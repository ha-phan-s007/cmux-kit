---
name: cmux-browser-human
description: Base rules and command wrappers for human-like cmux browser automation. Use whenever a task controls a web page with `cmux browser`, especially before click/type/fill/select/press/scroll actions.
---

# Human-like Cmux Browser Automation

Use this skill as the base layer for any `cmux browser` workflow. The goal is to make browser actions look like deliberate human interaction: cursor arrives first, text is typed character by character, pauses are natural, and page state is re-read after changes.

This skill does not replace the official `cmux-browser` skill. It constrains how to use it safely and humanly.

## Core rule

Every browser action must follow a human rhythm unless it is purely read-only evidence collection.

- Prefer `type` over `fill` for text entry. `fill` is an instant JS-level value write and should be reserved for controls where `type` cannot work.
- Hover before `click`, `type`, `select`, `check`, `uncheck`, or any action that a human would target with the pointer.
- Focus before typing or key presses when the target element is known.
- Add randomized pauses at natural decision points: after load, before acting, after typing, before submit, after navigation, and between polling checks.
- Execute flows in one batched Bash invocation when practical, so the whole sequence keeps pacing state and avoids one permission prompt per small action.
- Re-read page state after navigation or DOM-changing actions: `get url`, `wait --load-state complete`, then `snapshot --interactive` or a scoped text read.
- If a surface disappears or stops being a browser, stop and report it. Do not return stale snapshots as current evidence.

## Baseline helper functions

Copy these helpers into the same Bash invocation as the task flow. Keep them near the top so all later browser commands go through them.

> **Positional-arg tokens ($1/$2/$3...) — write them via `args=("$@")` + array index, never bare.**
> Observed 2026-07-07 (see `ask-gemini` skill's Known Failure Modes): when a skill is invoked
> with multi-word `args`, the rendered content handed to the agent had literal `$1`/`$2` tokens
> silently replaced with words from those args — the file on disk was unaffected, only what
> gets displayed at invocation time. Root cause is upstream in the skill-loading layer, not
> fixable in this repo. Every helper below reads its parameters through `local args=("$@")`
> then `"${args[0]}"`, `"${args[1]}"`, etc. instead of bare `$1`/`$2`/`$3`, specifically to avoid
> that token shape. Keep this pattern for any new helper added here.

```bash
jitter() { python3 -c "import random,sys; lo,hi=float(sys.argv[1]),float(sys.argv[2]); print(round(random.uniform(lo,hi),1))" "$@"; }

human_pause() {
  local args=("$@")
  local min="${args[0]:-0.4}"
  local max="${args[1]:-1.2}"
  sleep "$(jitter "$min" "$max")"
}

ensure_surface_alive() {
  local args=("$@")
  local surface="${args[0]}"
  cmux browser "$surface" get url >/dev/null 2>&1
}

human_after_load() {
  local args=("$@")
  local surface="${args[0]}"
  cmux browser "$surface" wait --load-state complete --timeout-ms 15000
  human_pause 1.0 2.5
}

human_snapshot() {
  local args=("$@")
  local surface="${args[0]}"
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" get url
  cmux browser "$surface" wait --load-state complete --timeout-ms 15000
  human_pause 0.5 1.2
  cmux browser "$surface" snapshot --interactive
}

human_click() {
  local args=("$@")
  local surface="${args[0]}"
  local target="${args[1]}"
  local extra=("${args[@]:2}")
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" hover "$target"
  human_pause 0.2 0.8
  cmux browser "$surface" click "$target" "${extra[@]}"
  human_pause 0.7 1.8
}

human_type() {
  local args=("$@")
  local surface="${args[0]}"
  local target="${args[1]}"
  local text="${args[2]}"
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" hover "$target"
  human_pause 0.2 0.7
  cmux browser "$surface" focus "$target"
  human_pause 0.1 0.4
  cmux browser "$surface" type "$target" "$text"
  human_pause 0.8 2.2
}

human_fill_fallback() {
  local args=("$@")
  local surface="${args[0]}"
  local target="${args[1]}"
  local text="${args[2]}"
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" hover "$target"
  human_pause 0.2 0.7
  cmux browser "$surface" focus "$target"
  human_pause 0.4 1.0
  cmux browser "$surface" fill "$target" "$text"
  human_pause 0.8 2.2
}

human_press() {
  local args=("$@")
  local surface="${args[0]}"
  local key="${args[1]}"
  ensure_surface_alive "$surface" || return 1
  human_pause 0.2 0.8
  cmux browser "$surface" press "$key"
  human_pause 0.4 1.3
}

human_select() {
  local args=("$@")
  local surface="${args[0]}"
  local target="${args[1]}"
  local value="${args[2]}"
  ensure_surface_alive "$surface" || return 1
  cmux browser "$surface" hover "$target"
  human_pause 0.3 0.9
  cmux browser "$surface" select "$target" "$value"
  human_pause 0.7 1.8
}
```

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
cmux browser "$SURFACE" screenshot > "$RUN_DIR/screenshot-home.b64"
cmux browser "$SURFACE" get text body
```

Do not paste full DOM, full page HTML, cookies, localStorage, sessionStorage, or browser state files into chat.

## Failure handling

- If `ensure_surface_alive` fails, mark the step `BLOCKED` or report the pane died/stale. Clear any saved stale surface ref owned by the task before retrying later.
- If a click silently does nothing, inspect the target state and current URL before trying again.
- If `snapshot --interactive` returns `js_error`, fall back to `get url`, scoped `get text`, and only then `get html` for the smallest useful container.
- If the URL is production-like or outside the user's authorized scope, do not mutate. Use read-only inspection unless the user explicitly approves the exact action.
