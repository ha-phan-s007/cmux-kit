#!/bin/bash
# guard-cmux.sh — PreToolUse(Bash) hook: approval-record backstop for `cmux browser` mutations.
#
# `cmux browser` subcommands run through the plain Bash tool (there is no MCP tool
# boundary to gate them), and cmux-kit's install.sh grants a broad `Bash(cmux:*)`
# permission for DX. This hook is the safety rail that permission grant relies on:
# it lets read-only/navigation subcommands through untouched, but for anything that
# mutates a page (click, type, fill, press, select, check/uncheck, drag, upload,
# eval, addinitscript, cookies/storage writes, state load, network route) it
# requires a fresh QC browser-approval record to already exist.
#
# Claude Code calls this script with JSON on stdin:
#   {"tool_name": "Bash", "tool_input": {"command": "<the bash command>"}}
# Exit 2  = BLOCK the command (reason on stderr).
# Exit 0  = ALLOW.
#
# REDESIGN (2026-07-07): the previous version of this hook tried to resolve the
# live surface URL itself by extracting the surface ref from the command string
# and shelling out to `cmux browser <ref> get url`. A PreToolUse hook receives the
# command as a LITERAL STRING before shell expansion, so real skill usage — which
# uses shell variables (`cmux browser "$S" click ...`) and defines helper
# functions whose BODIES contain literal `cmux browser "$1" press ...` — made the
# hook extract an unexpanded token (`"$S"`, `"$1"`), fail to resolve any URL, and
# fail-closed on every real mutation call (even safe localhost ones), including
# commands that merely DEFINE a helper function and never call it. Reproduced
# live before this rewrite.
#
# This version mirrors hey-clark's guard-browser.sh (MCP browser-tool guard) and
# does NOT resolve URLs itself. It only checks that a fresh, valid QC
# browser-approval record already exists at .clark/.qc-browser-approval.json,
# written by the calling skill (qc-browse, ask-gemini) AFTER the skill's own
# is_safe_url / domain-check gate. This makes the guard immune to how the ref is
# spelled in the command string (literal, variable, or inside a helper
# definition) since it never needs to parse the ref at all.
#
# DIFFERENCE from guard-browser.sh: this hook does NOT require qc.enabled==true
# in .clark/stack.yml. guard-browser.sh gates hey-clark's QC pipeline, which is
# opt-in per project; cmux-kit runs standalone in arbitrary projects that may not
# have a QC pipeline or stack.yml at all. The approval record's own existence,
# validity, and freshness is the sole gate here.
#
# HONEST LIMITATIONS (documented, not airtight — same trust model as
# guard-browser.sh):
#   * This hook is defense-in-depth, not an independent oracle. It does not
#     itself classify any URL as safe/production-like — it trusts that the
#     record was written by a skill that already ran its own URL-safety check
#     (qc-browse's is_safe_url, ask-gemini's gemini.google.com domain check).
#     A totally rogue mutation with no record is still blocked; the freshness
#     window (30 min) bounds how long a stale approval stays valid.
#   * Stateless per-call: this hook does not confirm which URL the command's
#     surface is actually on right now, nor that the record's `url` field
#     matches the surface being acted on in THIS command. It only checks that
#     *some* fresh, approved record exists.
#   * Fail-closed: if jq is missing, or the record is missing/invalid/expired,
#     a matched mutation subcommand is BLOCKED — this is a safety backstop, not
#     a convenience.

set -euo pipefail

input=$(cat)

command -v jq >/dev/null 2>&1 || { echo "BLOCKED by clark cmux-guard: jq unavailable -- cannot verify QC browser-approval (fail-closed on mutation subcommands). Install jq." >&2; exit 2; }

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

if [[ "$tool" != "Bash" || -z "$cmd" ]]; then
  exit 0
fi

# Only look at commands that actually invoke `cmux browser`.
if ! echo "$cmd" | grep -Eq '(^|[;&|[:space:]])cmux[[:space:]]+(--json[[:space:]]+)?browser[[:space:]]'; then
  exit 0
fi

# --- Extract the subcommand following `browser [ref]` ------------------------
# Shape: cmux [--json] browser [--surface] <ref> <subcommand> [args...]
# The ref may be a literal surface id OR an unexpanded shell token ($S, "$1",
# etc.) -- we deliberately do NOT care which, and never try to resolve it. We
# only need the subcommand word that follows it, so this still matches inside
# a helper FUNCTION DEFINITION body (e.g. `human_press() { cmux browser "$1"
# press "$2"; }`), not just a direct call with a literal ref.
subcmd=$(printf '%s' "$cmd" | sed -nE 's/.*cmux[[:space:]]+(--json[[:space:]]+)?browser[[:space:]]+(--surface[[:space:]]+)?[^[:space:]]+[[:space:]]+([a-zA-Z_-]+).*/\3/p' | head -n1)

if [[ -z "$subcmd" ]]; then
  # Could not parse a subcommand (e.g. `cmux browser open ...`, `status`,
  # `disable`, `enable`, or an unparseable form) -> not a surface-scoped
  # mutation, allow.
  exit 0
fi

# --- Mutation subcommand set ---------------------------------------------------
mutation_re='^(click|dblclick|type|fill|press|key|keydown|keyup|select|check|uncheck|drag|drop|upload_file|upload-file|eval|evaluate|addinitscript|addscript|addstyle)$'

if ! echo "$subcmd" | grep -Eq "$mutation_re"; then
  # Handle the multi-word gated forms separately (cookies set|clear /
  # storage set|clear / state load / network route).
  case "$subcmd" in
    cookies)
      echo "$cmd" | grep -Eq 'cookies[[:space:]]+(set|clear)' || exit 0
      ;;
    storage)
      echo "$cmd" | grep -Eq 'storage[[:space:]]+(local|session)?[[:space:]]*(set|clear)' || exit 0
      ;;
    state)
      echo "$cmd" | grep -Eq 'state[[:space:]]+load' || exit 0
      ;;
    network)
      echo "$cmd" | grep -Eq 'network[[:space:]]+route' || exit 0
      ;;
    *)
      exit 0
      ;;
  esac
fi

# --- Approval record must exist & be valid (mirrors guard-browser.sh) --------
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
stack="$proj/.clark/stack.yml"
approval="$proj/.clark/.qc-browser-approval.json"

if [[ ! -f "$approval" ]]; then
  echo "BLOCKED by clark cmux-guard: no QC browser-approval record (.clark/.qc-browser-approval.json) for mutation subcommand '$subcmd'. The calling skill must run its own URL-safety gate (is_safe_url / domain check) and write the approval record first; production_like/unknown URLs additionally need human_approved:true." >&2
  exit 2
fi

rec=$(cat "$approval")
if ! printf '%s' "$rec" | jq -e . >/dev/null 2>&1; then
  echo "BLOCKED by clark cmux-guard: .clark/.qc-browser-approval.json is not valid JSON." >&2
  exit 2
fi

approved=$(printf '%s' "$rec" | jq -r '.approved // false')
classification=$(printf '%s' "$rec" | jq -r '.classification // "unknown"')
human_approved=$(printf '%s' "$rec" | jq -r '.human_approved // false')
url=$(printf '%s' "$rec" | jq -r '.url // ""')
expires=$(printf '%s' "$rec" | jq -r '.expires_at // ""')

if [[ "$approved" != "true" ]]; then
  echo "BLOCKED by clark cmux-guard: approval record present but approved != true." >&2
  exit 2
fi

# --- Freshness (ISO-8601 UTC lexical compare; requires ...Z form) ----------
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [[ -z "$expires" || ! "$expires" =~ Z$ ]]; then
  echo "BLOCKED by clark cmux-guard: approval record missing/non-UTC expires_at (want YYYY-MM-DDTHH:MM:SSZ)." >&2
  exit 2
fi
if [[ "$now" > "$expires" ]]; then
  echo "BLOCKED by clark cmux-guard: QC browser-approval expired at $expires (now $now). Re-run the URL-safety gate and rewrite the approval record." >&2
  exit 2
fi

# --- URL classification cross-check ----------------------------------------
# Read safe keywords from stack.yml qc.safe_url_keywords; fall back to defaults.
default_keywords="localhost 127.0.0.1 staging stage demo dev preview sandbox test"
keywords=""
if [[ -f "$stack" ]]; then
  keywords=$(awk '/safe_url_keywords:/{f=1;next} f&&/^[[:space:]]*-[[:space:]]*/{gsub(/[",-]/,"");gsub(/^[[:space:]]+|[[:space:]]+$/,"");print} f&&/^[[:space:]]*[a-zA-Z_]+:/{f=0}' "$stack" 2>/dev/null | tr '\n' ' ')
fi
[[ -z "${keywords// /}" ]] && keywords="$default_keywords"

url_is_safe="false"
for kw in $keywords; do
  [[ -n "$kw" ]] || continue
  if printf '%s' "$url" | grep -qiF "$kw"; then
    url_is_safe="true"; break
  fi
done

if [[ "$url_is_safe" == "true" ]]; then
  # Safe non-prod URL with a fresh approved record -> allow.
  exit 0
fi

# Production-like / unknown URL -> require explicit human approval.
if [[ "$human_approved" == "true" ]]; then
  exit 0
fi

echo "BLOCKED by clark cmux-guard: mutation '$subcmd' with approval record classifying URL '$url' as '$classification' (production-like/unknown) but human_approved != true. Passive inspection is allowed; interaction on a non-safe URL needs explicit human approval recorded in the approval file." >&2
exit 2
