---
name: cmux-browser-human
description: Base rules and command wrappers for human-like cmux browser automation. Use whenever a task controls a web page with `cmux browser`, especially before click/type/fill/select/press/scroll actions.
---

# Human-like Cmux Browser Automation

Use this skill as the base layer for any `cmux browser` workflow. The goal is to make browser actions look like deliberate human interaction: cursor arrives first, text is typed character by character, pauses are natural, and page state is re-read after changes.

This skill does not replace the official `cmux-browser` skill. It constrains how to use it safely and humanly.

`qc-browse` sources `check_for_server_errors` directly from this skill; `ask-gemini` carries its own ported copy of `check_for_server_errors` plus the fingerprint fix below (it runs standalone, so it inlines rather than sources). This file remains the source of truth for both — its documented behavior and limitations here.

## Core rule

Every browser action must follow a human rhythm unless it is purely read-only evidence collection.

- Prefer `type` over `fill` for text entry. `fill` is an instant JS-level value write and should be reserved for controls where `type` cannot work.
- Hover before `click`, `type`, `select`, `check`, `uncheck`, or any action that a human would target with the pointer.
- Focus before typing or key presses when the target element is known.
- Add randomized pauses at natural decision points: after load, before acting, after typing, before submit, after navigation, and between polling checks.
- Execute flows in one batched Bash invocation when practical, so the whole sequence keeps pacing state and avoids one permission prompt per small action.
- Re-read page state after navigation or DOM-changing actions: `get url`, `wait --load-state complete`, then `snapshot --interactive` or a scoped text read.
- If a surface disappears or stops being a browser, stop and report it. Do not return stale snapshots as current evidence.
- **Stop immediately if a 5xx-shaped or explicit error message shows up via `check_for_server_errors`** (see helper below) — do not continue mutating or polling past that point. See the honest limitation note under that helper before relying on it as a full safety net.

## Baseline helper functions

Copy these helpers into the same Bash invocation as the task flow. Keep them near the top so all later browser commands go through them.

> **Positional params ($1/$2/$3) are correct and portable here — the earlier "fix" to this
> section was wrong and has been reverted.** Two distinct issues got conflated on 2026-07-07:
> (1) a display-only bug where the Skill-loading layer can silently replace literal `$1`/`$2`
> text with words from a skill's invocation `args` in what gets RENDERED to the agent (the file
> on disk is never affected — verify by reading the file directly if a rendered `$N` looks
> wrong); (2) a real execution bug introduced by "fixing" (1) via `local args=("$@")` +
> `"${args[0]}"`: this machine's Bash tool runs through **zsh**, and zsh arrays are **1-indexed
> by default** — `${args[0]}` is always empty there, so every helper silently received an empty
> surface/target/text and no-op'd (confirmed live: `human_type`/`human_click`/`human_select` all
> failed against a real local test page after that rewrite, while the original plain-`$1` form
> passed). Plain `$1`/`$2`/`$3` on function positional parameters is unaffected by that
> bash/zsh indexing difference (it's not a named array), so it is both correct and the safer
> choice. `jitter()` below still takes its bounds via `"$@"`/`sys.argv` (delegated to Python, so
> no shell array indexing is involved) — that part of the original fix was sound and is kept.

```bash
jitter() { python3 -c "import random,sys; lo,hi=float(sys.argv[1]),float(sys.argv[2]); print(round(random.uniform(lo,hi),1))" "$@"; }

human_pause() {
  local min="${1:-0.4}"
  local max="${2:-1.2}"
  sleep "$(jitter "$min" "$max")"
}

ensure_surface_alive() {
  local surface="$1"
  cmux browser "$surface" get url >/dev/null 2>&1
}

human_after_load() {
  local surface="$1"
  cmux browser "$surface" wait --load-state complete --timeout-ms 15000
  human_pause 1.0 2.5
}

human_snapshot() {
  local surface="$1"
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" get url
  cmux browser "$surface" wait --load-state complete --timeout-ms 15000
  human_pause 0.5 1.2
  cmux browser "$surface" snapshot --interactive
}

human_click() {
  local surface="$1"
  local target="$2"
  shift 2
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" hover "$target"
  human_pause 0.2 0.8
  cmux browser "$surface" click "$target" "$@"
  human_pause 0.7 1.8
}

human_type() {
  local surface="$1"
  local target="$2"
  local text="$3"
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" hover "$target"
  human_pause 0.2 0.7
  cmux browser "$surface" focus "$target"
  human_pause 0.1 0.4
  cmux browser "$surface" type "$target" "$text"
  human_pause 0.8 2.2
}

human_fill_fallback() {
  local surface="$1"
  local target="$2"
  local text="$3"
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" hover "$target"
  human_pause 0.2 0.7
  cmux browser "$surface" focus "$target"
  human_pause 0.4 1.0
  cmux browser "$surface" fill "$target" "$text"
  human_pause 0.8 2.2
}

human_press() {
  local surface="$1"
  local key="$2"
  ensure_surface_alive "$surface" || return 1
  human_pause 0.2 0.8
  cmux browser "$surface" press "$key"
  human_pause 0.4 1.3
}

human_select() {
  local surface="$1"
  local target="$2"
  local value="$3"
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" hover "$target"
  human_pause 0.3 0.9
  cmux browser "$surface" select "$target" "$value"
  human_pause 0.7 1.8
}

check_for_server_errors() {
  local surface="$1"
  local hits
  hits=$(cmux browser "$surface" console list 2>/dev/null | grep -iE '5[0-9]{2}|server error|network error|failed to load resource')
  local err_hits
  err_hits=$(cmux browser "$surface" errors list 2>/dev/null | grep -iE '5[0-9]{2}|server error|network error|failed to load resource')
  if [ -n "$hits" ] || [ -n "$err_hits" ]; then
    echo "STOP: possible server/network error found in console or errors:" >&2
    [ -n "$hits" ] && printf '%s\n' "$hits" >&2
    [ -n "$err_hits" ] && printf '%s\n' "$err_hits" >&2
    return 1
  fi
  return 0
}
```

> **Honest limitation of `check_for_server_errors` (verified 2026-07-07 — read before relying on it):**
> `cmux browser <surface> network requests` is explicitly `not_supported` on WKWebView (confirmed
> live: `Error: not_supported: browser.network.requests is not supported on WKWebView`) — there is
> no way to read real HTTP status codes for network requests through this tool at all.
> `console list`/`errors list` DO capture explicit `console.log`/`console.error` calls made by a
> page's own JavaScript (verified live), but they do **NOT** capture the browser's own
> auto-generated "Failed to load resource: the server responded with a status of ..." messages for
> failed subresource loads — verified with a controlled test (a real 404 confirmed in the local
> HTTP server's access log produced zero entries in either `console list` or `errors list`). The
> real CSP incident this project hit earlier ("Failed to load resource: Blocked by Content
> Security Policy") is exactly this unreachable message shape. So `check_for_server_errors` is a
> real but **partial** safety net — it only catches errors an app's own code explicitly logs, not
> browser-native resource-load failures. **The human visually watching the browser remains the
> more reliable backstop for CSP/resource-block-style errors specifically** — this has already
> caught two real incidents in this project when the automated checks did not.

## Opening and navigating

Opening a URL is allowed without hover, but still wait and pause before inspecting or acting.

```bash
OPEN_JSON=$(cmux --json browser open "$URL")
SURFACE=$(printf '%s' "$OPEN_JSON" | grep -o '"surface_ref"[^,}]*' | grep -o 'surface:[0-9]*')
[ -n "$SURFACE" ] || { echo "Could not open browser surface."; exit 1; }
human_after_load "$SURFACE"
human_snapshot "$SURFACE"
```

For SPA pages, `wait --load-state complete` is not enough by itself. Also wait for a known selector from the screen before acting:

```bash
cmux browser "$SURFACE" wait --selector '<stable-selector>' --timeout-ms 15000
human_pause 0.8 1.8
```

## Fingerprint / header check (verified 2026-07-07)

The humanization layer above covers interaction *timing*. It says nothing about whether the
browser's own HTTP headers and JS-visible properties look automated at the network/fingerprint
level — checked this directly since WKWebView is a different engine from Chrome/Chromium, which
a detector could plausibly key on.

**What's actually fine (verified against a local echo server + live `eval`, not assumed):**
- `User-Agent` sent over the wire is a completely standard, unmodified Safari string
  (`Mozilla/5.0 (Macintosh; Intel Mac OS X ...) AppleWebKit/605.1.15 ... Safari/605.1.15`) — no
  "WebView"/"Cmux"/framework name leaks into it.
- Request headers (`Sec-Fetch-*`, `Accept`, `Accept-Language`, `Accept-Encoding`) match genuine
  Safari shape. No `sec-ch-ua` client-hint headers — that is CORRECT for Safari (only Chromium
  sends those), not a gap to "fix."
- `navigator.webdriver` is `false`, `window.chrome` is `undefined` — both consistent with a
  genuine, unpatched Safari engine (no Selenium/Playwright-style automation flag leaking).

**Real gap found and fixed — `window.outerWidth`/`outerHeight` report `0`:** a classic
headless/embedded-browser tell (real user windows report outer dimensions larger than inner, to
account for chrome/toolbar). Confirmed via `eval` on a fresh surface. Fix (verified working —
before: `{"outerW":0,"outerH":0}`, after: `{"outerW":851,"outerH":1064}` matching real
`innerWidth`/`innerHeight` plus a plausible chrome offset):

```bash
cmux browser "$SURFACE" addinitscript "Object.defineProperty(window, 'outerWidth', {get: () => window.innerWidth}); Object.defineProperty(window, 'outerHeight', {get: () => window.innerHeight + 74});"
cmux browser "$SURFACE" reload
```

`addinitscript` only applies to the NEXT navigation, not retroactively to an already-loaded
document — call it once right after `open`, then `reload` (or navigate) before doing anything
else, if this hardening matters for the target site. This costs one extra round-trip; skip it
for low-stakes/local targets where it doesn't matter.

**Real gap found, NOT fixed — the webview never has real OS-level keyboard focus during
automation:** `document.hasFocus()` returns `false` while `document.visibilityState` is
`"visible"` — an inconsistent combination a detector could check. `cmux browser <surface>
focus-webview` (the command that should fix this) itself fails with `internal_error: Focus did
not move into web view` when tried. Checking *why* (e.g. is the Cmux app frontmost) requires
macOS Accessibility/Apple Events permissions this environment does not have
(`osascript ... System Events` → `Not authorized to send Apple events to System Events`). This is
an open, currently-unresolved gap — spoofing `document.hasFocus()` to return `true` via
`addinitscript` would be worse than leaving it, since real focus/blur event firing would still be
absent and could be cross-checked. No fix is claimed here; flagging it honestly instead.

## Action guidance

- **Click:** `human_click "$SURFACE" e2 --snapshot-after` when a snapshot-after option is useful. Then save or inspect the returned snapshot.
- **Type:** `human_type "$SURFACE" e3 "qa@example.com"`. Use `human_fill_fallback` only after `type` fails or for controls that reject typed key events.
- **Keyboard:** focus the relevant field first when possible, then `human_press "$SURFACE" Tab` or `human_press "$SURFACE" Enter`. Add a separate pause for each repeated key.
- **Select:** `human_select "$SURFACE" e4 "Option value"`. For custom dropdowns, use `human_click` to open, pause, then `human_click` the option.
- **Submit:** pause after typing so the value can be visually reviewed, hover the submit control, click once, then verify the page changed or the form cleared. Retry only after checking the first click was a no-op.
- **Polling:** never poll at fixed intervals. Use `human_pause 4 8` between checks and require multiple stable observations for generated/streamed content.

## Read-only actions

Evidence commands can run directly, but keep them scoped and paced after page changes:

```bash
cmux browser "$SURFACE" get url
cmux browser "$SURFACE" snapshot --interactive --compact --max-depth 3
cmux browser "$SURFACE" screenshot --out "$RUN_DIR/screenshot-home.png"
cmux browser "$SURFACE" get text body
```

Do not paste full DOM, full page HTML, cookies, localStorage, sessionStorage, or browser state files into chat.

## Failure handling

- If `ensure_surface_alive` fails, mark the step `BLOCKED` or report the pane died/stale. Clear any saved stale surface ref owned by the task before retrying later.
- If a click silently does nothing, inspect the target state and current URL before trying again.
- If `snapshot --interactive` returns `js_error`, fall back to `get url`, scoped `get text`, and only then `get html` for the smallest useful container.
- If the URL is production-like or outside the user's authorized scope, do not mutate. Use read-only inspection unless the user explicitly approves the exact action.
- **Run `check_for_server_errors "$SURFACE"` after any action that triggers a backend call** (send/submit, navigation, generation) — if it returns non-zero, STOP the flow immediately: do not send another action, do not retry, do not poll further. Report the captured console/error lines to the human and let them decide. Remember its limitation above — a human-observed CSP/resource error with no console entry is just as much a stop signal as one this function catches.
