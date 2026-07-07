#!/usr/bin/env bash
# guard-cmux.sh — PreToolUse(Bash) hook: mechanical backstop for `cmux browser` mutations.
#
# `cmux browser` subcommands run through the plain Bash tool (there is no MCP tool
# boundary to gate them), and cmux-kit's install.sh grants a broad `Bash(cmux:*)`
# permission for DX. This hook is the safety rail that permission grant relies on:
# it lets read-only/navigation subcommands through untouched, but for anything that
# mutates a page (click, type, fill, press, select, check/uncheck, drag, upload,
# eval, addinitscript, cookies/storage writes, state load) it resolves the live
# surface URL and only allows the action on a URL that looks safe (local/dev/
# staging/test-shaped hostname, or explicitly approved).
#
# Claude Code calls this script with JSON on stdin:
#   {"tool_name": "Bash", "tool_input": {"command": "<the bash command>"}}
# Exit 2  = BLOCK the command (reason on stderr).
# Exit 0  = ALLOW.
#
# HONEST LIMITATIONS (documented, not airtight):
#   * This hook only understands a single `cmux browser <surface> <subcommand> ...`
#     invocation per command string. Chained/piped commands with `&&`/`;`/`|` that
#     bundle multiple cmux calls are matched on the WHOLE string, so if the FIRST
#     cmux invocation found is a gated mutation, the whole line is checked against
#     that surface's URL; other invocations later in the chain are not individually
#     re-checked. Keep gated actions to one `cmux browser` call per command when
#     possible (this matches the human_* helper convention already in use).
#   * Fail-closed: if the surface's URL cannot be resolved (surface dead, cmux CLI
#     missing, timeout, empty output), the command is BLOCKED — this is a safety
#     backstop, not a convenience.
#   * Approval-record cross-check mirrors clark's guard-browser.sh format
#     (.clark/.qc-browser-approval.json: approved / classification / human_approved
#     / url / expires_at, ISO-8601 UTC). It does not re-verify the approval's own
#     url_safety classification logic — only that record shape, freshness, and URL
#     match are trusted here.

set -euo pipefail

input=$(cat)

command -v jq >/dev/null 2>&1 || { echo "BLOCKED by clark cmux-guard: jq unavailable -- cannot parse tool input (fail-closed)." >&2; exit 2; }

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

if [[ "$tool" != "Bash" || -z "$cmd" ]]; then
  exit 0
fi

# Only look at commands that actually invoke `cmux browser`.
if ! echo "$cmd" | grep -Eq '(^|[;&|[:space:]])cmux[[:space:]]+(--json[[:space:]]+)?browser[[:space:]]'; then
  exit 0
fi

# --- Extract the surface ref and subcommand from the first `cmux browser` call ---
# Shape: cmux [--json] browser [--surface <ref>|<surface>] <subcommand> [args...]
read -r surface subcmd <<<"$(printf '%s' "$cmd" | sed -nE 's/.*cmux[[:space:]]+(--json[[:space:]]+)?browser[[:space:]]+(--surface[[:space:]]+)?([^[:space:]]+)[[:space:]]+([a-zA-Z_-]+).*/\3 \4/p' | head -n1)"

if [[ -z "$subcmd" ]]; then
  # Could not parse a subcommand (e.g. `cmux browser open ...`, `status`, `disable`,
  # `enable`, or an unparseable form) -> not a surface-scoped mutation, allow.
  exit 0
fi

# --- Mutation subcommand set -------------------------------------------------
mutation_re='^(click|dblclick|type|fill|press|key|keydown|keyup|select|check|uncheck|drag|drop|upload_file|upload-file|eval|addinitscript|addscript|addstyle)$'

if ! echo "$subcmd" | grep -Eq "$mutation_re"; then
  # Handle the multi-word gated forms separately (cookies set / storage set|clear / state load).
  case "$subcmd" in
    cookies)
      echo "$cmd" | grep -Eq 'cookies[[:space:]]+(set|clear)' || exit 0
      ;;
    storage)
      echo "$cmd" | grep -Eq 'storage[[:space:]]+(local|session)[[:space:]]+(set|clear)' || exit 0
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

# --- Resolve the surface's live URL ------------------------------------------
[[ -n "$surface" ]] || { echo "BLOCKED by clark cmux-guard: could not determine surface for mutation subcommand '$subcmd' (fail-closed)." >&2; exit 2; }

command -v cmux >/dev/null 2>&1 || { echo "BLOCKED by clark cmux-guard: cmux CLI not found -- cannot resolve surface URL (fail-closed)." >&2; exit 2; }

# Portable 5s timeout: neither `timeout` nor `gtimeout` (GNU coreutils) is
# guaranteed present on a member's macOS install, so poll a background job
# instead of depending on either.
url=""
tmpfile=$(mktemp)
cmux browser "$surface" get url >"$tmpfile" 2>/dev/null &
bgpid=$!
waited=0
while kill -0 "$bgpid" 2>/dev/null && [[ "$waited" -lt 50 ]]; do
  sleep 0.1
  waited=$((waited + 1))
done
if kill -0 "$bgpid" 2>/dev/null; then
  kill "$bgpid" 2>/dev/null || true
  wait "$bgpid" 2>/dev/null || true
else
  wait "$bgpid" 2>/dev/null || true
  url=$(tr -d '\r\n' <"$tmpfile")
fi
rm -f "$tmpfile"

if [[ -z "$url" ]]; then
  echo "BLOCKED by clark cmux-guard: could not resolve URL for surface '$surface' (dead surface, timeout, or cmux error). Run 'cmux browser $surface get url' manually to check surface health, then retry." >&2
  exit 2
fi

# --- Hostname classification --------------------------------------------------
# ALLOW iff:
#   - hostname equals a safe keyword, OR
#   - any dot-separated label of hostname equals a safe keyword
#     (dev.foo.com ALLOWS; devices.foo.com and protest.com do NOT), OR
#   - hostname ends with ".local", OR
#   - hostname is exactly gemini.google.com (ask-gemini whitelist), OR
#   - a fresh .clark/.qc-browser-approval.json covers this URL.
classification=$(python3 - "$url" <<'PYEOF'
import sys
from urllib.parse import urlparse

url = sys.argv[1]
parsed = urlparse(url if "://" in url else "http://" + url)
host = (parsed.hostname or "").lower()

safe_keywords = {"localhost", "127.0.0.1", "0.0.0.0", "dev", "staging", "stage", "test", "sandbox", "preview"}

if not host:
    print("unresolvable")
    sys.exit(0)

if host in safe_keywords:
    print("safe")
    sys.exit(0)

labels = host.split(".")
if any(label in safe_keywords for label in labels):
    print("safe")
    sys.exit(0)

if host.endswith(".local"):
    print("safe")
    sys.exit(0)

if host == "gemini.google.com":
    print("safe")
    sys.exit(0)

print("unsafe")
PYEOF
)

if [[ "$classification" == "safe" ]]; then
  exit 0
fi

if [[ "$classification" == "unresolvable" ]]; then
  echo "BLOCKED by clark cmux-guard: could not parse hostname from surface URL '$url' (fail-closed)." >&2
  exit 2
fi

# --- Fall back to a fresh QC browser-approval record --------------------------
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
approval="$proj/.clark/.qc-browser-approval.json"

if [[ -f "$approval" ]] && command -v jq >/dev/null 2>&1; then
  rec=$(cat "$approval" 2>/dev/null || true)
  if printf '%s' "$rec" | jq -e . >/dev/null 2>&1; then
    approved=$(printf '%s' "$rec" | jq -r '.approved // false')
    human_approved=$(printf '%s' "$rec" | jq -r '.human_approved // false')
    rec_url=$(printf '%s' "$rec" | jq -r '.url // ""')
    expires=$(printf '%s' "$rec" | jq -r '.expires_at // ""')
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [[ "$approved" == "true" && ( "$human_approved" == "true" || -n "$rec_url" ) \
          && -n "$expires" && "$expires" =~ Z$ && ! "$now" > "$expires" \
          && "$rec_url" == "$url" ]]; then
      exit 0
    fi
  fi
fi

echo "BLOCKED by clark cmux-guard: mutation '$subcmd' on non-dev-shaped URL '$url' (surface $surface). Allowed hosts: localhost/127.0.0.1/0.0.0.0, a dev/staging/stage/test/sandbox/preview label, *.local, or gemini.google.com. For any other URL, get explicit human approval and record it at .clark/.qc-browser-approval.json (approved:true, url matching exactly, expires_at as an unexpired ISO-8601 UTC timestamp, human_approved:true for production-like targets) before retrying." >&2
exit 2
