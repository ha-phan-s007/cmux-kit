---
name: ask-gemini
description: Use when you need to offload a question to Google Gemini web UI via cmux browser and return the answer text.
---

# Ask Gemini via cmux Browser

Use this skill from Claude Code running inside a Cmux pane to ask Gemini in the web UI and return only Gemini's answer text.

This skill carries a local, Gemini-specific version of the same humanization policy that is reusable in `cmux-browser-human`. When changing browser pacing or action rules here, keep the base skill aligned too.

## Preconditions

1. Confirm Claude Code is running inside Cmux:

```bash
if [ -z "${CMUX_SOCKET_PATH:-}" ]; then
  echo "CMUX_SOCKET_PATH is not set. Run Claude Code inside a Cmux pane, then retry."
  exit 1
fi
```

2. Only automate `https://gemini.google.com`. Do not use this skill on other domains.
3. Never read, print, paste, summarize, or commit browser state files, cookies, localStorage, or sessionStorage.

## Known failure modes (observed 2026-07-07 — read before automating)

Real incidents hit while building this skill, and why each matters:

1. **Surface refs go stale silently.** A previously-working `surface:N` (from your own memory,
   a prior command's output, or a human closing the pane) can stop being a browser at all.
   `cmux browser <ref> get url` then fails with `invalid_params: Surface is not a browser` or
   `not_found`. Never hardcode a surface number from a past run — resolve it fresh every time
   (see Surface Resolution below).
2. **The pane can die or be closed mid-generation** (a human closing it to be safe, an app
   crash, a CSP-triggered webview reload). If this happens while Gemini is still generating,
   `get text body` keeps returning the LAST GOOD SNAPSHOT — a sentence cut off mid-word, with
   no error and no visual cue that generation didn't finish. Silently treating that as "the
   answer" produces a confidently wrong result. Always re-check the surface is still alive
   immediately after the wait loop (see Ask the Question below) and say so explicitly if it
   died instead of returning partial text as if it were complete.
3. **Google/Gemini automation carries real account-block risk perceived by the human.** Even
   though this skill does no more than a human would (type + click), avoid looking bot-like:
   space out consecutive asks, and treat any close/crash as a signal to slow down, not to
   retry immediately in a loop.
4. **Don't write literal `$1`/`$2` in this file's bash blocks.** Observed 2026-07-07: when this
   skill is invoked with multi-word `args`, the rendered content handed to the agent had every
   literal `$1`/`$2` token silently replaced with a word from the args (e.g. asking "Hôm nay ăn
   gì" turned `random.uniform($1, $2)` into `random.uniform(nay, ăn)`) — the file on disk was
   unaffected, only what gets displayed at invocation time. Root cause is upstream in how the
   skill-loading layer handles positional-arg-shaped tokens, not something fixable in this repo,
   so the defensive fix here is to simply never use bare `$1`/`$2` in example code — see
   `jitter()` below, which takes its bounds via `"$@"` + `sys.argv` instead. If you add new bash
   here, verify by reading the file straight off disk (not via the Skill tool output) before
   trusting any `$<digit>` you see rendered.

## Surface Resolution (state-tracked, self-healing)

Persist the last-known-good surface ref to a state file and re-validate it before every ask,
instead of trusting a ref from memory or a past command. If it's gone, open a fresh one and
record the new ref — this makes the skill self-healing after a pane closes/crashes.

```bash
STATE_DIR="$HOME/.local/state/cmux"
mkdir -p "$STATE_DIR"
SURFACE_FILE="$STATE_DIR/gemini-surface"

S=""
if [ -f "$SURFACE_FILE" ]; then
  CANDIDATE=$(cat "$SURFACE_FILE")
  if cmux browser "$CANDIDATE" get url >/dev/null 2>&1; then
    S="$CANDIDATE"
  fi
fi
if [ -z "$S" ]; then
  OPEN_JSON=$(cmux --json browser open https://gemini.google.com)
  S=$(printf '%s' "$OPEN_JSON" | grep -o '"surface_ref"[^,}]*' | grep -o 'surface:[0-9]*')
  [ -n "$S" ] || { echo "Could not open a Gemini surface."; exit 1; }
  echo "$S" > "$SURFACE_FILE"
fi
cmux browser "$S" wait --selector 'div.ql-editor' --timeout-ms 15000
cmux browser "$S" get url
```

Do NOT also call `wait --load-state complete` here — observed 2026-07-07: on this page it
throws `js_error: Wait condition could not be evaluated: JavaScript execution returned a
result of an unsupported type` (a `cmux-browser` quirk evaluating load-state on Gemini's SPA
shell), and it adds nothing `wait --selector` doesn't already cover. `wait --selector
'div.ql-editor'` alone is both necessary AND sufficient: Gemini is a client-side-routed SPA,
so `load-state complete` (even if it worked) could report `complete` while still on
`gemini.google.com/` and not yet routed to `/app` with the chat editor mounted — waiting on
the editor selector directly is the correct readiness signal either way.

If this prints a Google login URL instead of `gemini.google.com/app`, go to Login Handling below.

## Model Selection (optional — `MODEL` argument)

Gemini web lets you pick a model via the mode picker button (labelled "Mở công cụ chọn chế độ,
hiện tại là <model>" in VN, "Open mode picker, currently <model>" in EN — the model NAME
itself, e.g. `3.5 Flash`, `3.5 Thinking`, `3.1 Pro`, is NOT translated, so matching on it is
locale-independent). Default when the caller doesn't specify one: `3.5 Flash`.

Each option in the menu (`[role="menu"] gem-menu-item`) carries a stable `data-mode-id` hash
attribute — click that attribute selector, not a positional `:nth-of-type` (menu items ARE
true siblings so `:nth-of-type` would actually work here, unlike `model-response` below, but
matching by the visible label is more robust if Google reorders or adds models).

Only open the picker if the current model differs from the requested one — skip it entirely
when already on the right model (fewer actions = less bot-like, and faster):

```bash
MODEL="${MODEL:-3.5 Flash}"
jitter() { python3 -c "import random,sys; lo,hi=float(sys.argv[1]),float(sys.argv[2]); print(round(random.uniform(lo,hi),1))" "$@"; }

current_label=$(cmux browser $S get text 'button[aria-label*="chọn chế độ"]' 2>/dev/null)
if [ -n "$MODEL" ] && ! printf '%s' "$current_label" | grep -qF "$MODEL"; then
  cmux browser $S hover 'button[aria-label*="chọn chế độ"]'
  sleep "$(jitter 0.3 0.8)"
  cmux browser $S click 'button[aria-label*="chọn chế độ"]'
  sleep "$(jitter 0.8 1.5)"                            # menu open + reading the options
  menu_html=$(cmux browser $S get html '[role="menu"]' 2>/dev/null)
  mode_id=$(printf '%s' "$menu_html" | python3 -c "
import sys, re
html = sys.stdin.read()
target = '''$MODEL'''
for mid, label in re.findall(r'data-mode-id=\"([a-f0-9]+)\".*?class=\"label\">\s*([^<]+?)\s*</span>', html, re.DOTALL):
    if label.strip() == target:
        print(mid); break
")
  if [ -n "$mode_id" ]; then
    cmux browser $S hover "gem-menu-item[data-mode-id=\"$mode_id\"]"
    sleep "$(jitter 0.2 0.5)"
    cmux browser $S click "gem-menu-item[data-mode-id=\"$mode_id\"]"
    sleep 1
  else
    echo "WARNING: model '$MODEL' not found in the mode picker (available options may have changed) — continuing with current model." >&2
    cmux browser $S press Escape 2>/dev/null
  fi
fi
```

Verified end-to-end 2026-07-07: switching `3.1 Pro` → `3.5 Flash` this way, confirmed by
re-reading the mode-picker button's label afterward.

## Login Handling

If the URL or page text shows Google login, pause browser automation and ask the human to click through login once in the Cmux webview. Note (verified 2026-07-07): the Cmux webview (WKWebView) has its OWN cookie store — it does NOT inherit the system/Safari/Chrome Google session. The one-time manual login in the webview persists for future runs within the webview.

After the human finishes login and Gemini chat is visible, save a backup auth state without exposing its contents:

```bash
mkdir -p ~/.local/state/cmux
cmux browser "$SURFACE" state save ~/.local/state/cmux/gemini-state.json
```

Never load the state file into context. Never run `cat`, `sed`, `grep`, `jq`, or similar commands on `~/.local/state/cmux/gemini-state.json`.

## Ask the Question — ONE batched Bash call (DX rule)

Run the whole pacing→ask→send→wait→extract loop as a SINGLE Bash invocation. Do NOT issue
one `cmux` call per Bash tool-call — that triggers a permission prompt per command and ruins
DX. `$S` here is the surface resolved in Surface Resolution above (resolve it in the SAME
invocation, don't split across two Bash calls — a pane can die between calls).

Verified selectors (2026-07-07, Gemini web — locale-independent, tested against a Vietnamese-locale UI):
- Prompt input: `div.ql-editor` (Quill contenteditable — NOT exposed in a11y snapshot, so don't hunt refs; use the CSS selector directly)
- Send button: `button:has([data-mat-icon-name="arrow_upward"])`. `data-mat-icon-name` is Angular Material's internal icon identifier — it does NOT change with UI language, unlike `aria-label` text (which is `"Gửi tin nhắn"` in VN, `"Send message"` in EN, etc.). Do NOT match on `aria-label` for this button — pick the icon-name selector so the skill works regardless of the Gemini UI locale.
- `press Enter` returns OK but does NOT submit — always click the send button.
- The send button only renders/enables after the input has non-empty text — fill first, then query for the button.

Pacing (account-safety): enforce a minimum gap since the last ask so requests don't look
scripted. Track it in the same state dir as the surface ref.

### Humanization layer (do not skip — this is why panes have been closing)

Repeated real incidents traced back to the SAME root cause: `fill` (instant bulk value-set)
immediately followed by `click` with near-zero delay is a textbook automation fingerprint —
no human reads-then-types-then-reviews-then-clicks in under 100ms with zero mouse movement.
Every action below exists to break that pattern:

- **`type`, not `fill`**, for the question — `fill` sets the whole value in one JS-level write;
  `type` dispatches per-character key events, closer to real typing.
- **`hover` before every `type`/`click`** — a human's cursor arrives at an element before
  interacting with it; jumping straight to `click` with no prior pointer movement is itself
  a signal.
- **Randomized pauses** (`jitter`) at each natural human decision point: after the page is
  ready (reading it), after typing (reviewing before sending), and between poll checks (never
  poll at a metronomically exact interval).
- **Fewer, more deliberate actions** — this is also why Model Selection above skips the picker
  entirely when already on the right model, and why pacing between asks exists at the outer
  loop, not just within one ask.

This does not guarantee Google's detection won't act — no client-side automation guarantee
ever does — but a flow with zero human-timing signals is the easiest possible thing to flag,
and this closes that gap with what `cmux browser` actually exposes.

```bash
STATE_DIR="$HOME/.local/state/cmux"
LASTASK_FILE="$STATE_DIR/gemini-last-ask"
MIN_INTERVAL=20   # seconds; raise this if asking many questions in a session

jitter() { python3 -c "import random,sys; lo,hi=float(sys.argv[1]),float(sys.argv[2]); print(round(random.uniform(lo,hi),1))" "$@"; }

if [ -f "$LASTASK_FILE" ]; then
  now=$(date +%s)
  elapsed=$((now - $(cat "$LASTASK_FILE")))
  [ "$elapsed" -lt "$MIN_INTERVAL" ] && sleep $((MIN_INTERVAL - elapsed))
fi
date +%s > "$LASTASK_FILE"

Q='Replace with the exact question.'
cmux browser $S wait --selector 'div.ql-editor' --timeout-ms 15000
sleep "$(jitter 1.0 2.5)"                              # reading the page before acting
cmux browser $S hover 'div.ql-editor'
cmux browser $S focus 'div.ql-editor'
cmux browser $S type 'div.ql-editor' "$Q"
sleep "$(jitter 0.8 2.2)"                              # reviewing before sending
cmux browser $S wait --selector 'button:has([data-mat-icon-name="arrow_upward"])' --timeout-ms 5000
cmux browser $S hover 'button:has([data-mat-icon-name="arrow_upward"])'
sleep "$(jitter 0.2 0.6)"
cmux browser $S click 'button:has([data-mat-icon-name="arrow_upward"])'

# Verify the send actually registered — Gemini clears the editor on send. A silent no-op
# click (button not yet interactive, overlay covering it, etc.) leaves the text sitting in
# the box with no error from `click`. Observed 2026-07-07: a click right after fill/type can
# no-op this way — confirmed by the editor still containing the question afterward.
sleep 1
leftover=$(cmux browser $S get text 'div.ql-editor' 2>/dev/null)
if [ -n "$leftover" ]; then
  cmux browser $S hover 'button:has([data-mat-icon-name="arrow_upward"])'
  sleep "$(jitter 0.3 0.8)"
  cmux browser $S click 'button:has([data-mat-icon-name="arrow_upward"])'
  sleep 1
  leftover=$(cmux browser $S get text 'div.ql-editor' 2>/dev/null)
  [ -n "$leftover" ] && { echo "__ASK_GEMINI_SEND_FAILED__ (question still in the input box after two send attempts)"; exit 1; }
fi

prev=0
stable=0
died=0
for i in $(seq 1 40); do
  sleep "$(jitter 5 8)"                                # jittered poll interval, not a fixed beat
  if ! cmux browser $S get url >/dev/null 2>&1; then
    died=1
    break
  fi
  cur=$(cmux browser $S get text 'chat-window' 2>/dev/null | wc -c)
  if [ "$cur" -eq "$prev" ] && [ "$cur" -gt 300 ]; then
    stable=$((stable+1))
    [ "$stable" -ge 4 ] && break
  else
    stable=0
  fi
  prev=$cur
done

if [ "$died" -eq 1 ]; then
  rm -f "$STATE_DIR/gemini-surface"
  echo "__ASK_GEMINI_PANE_DIED__ (browser pane closed or crashed mid-generation — any text below is INCOMPLETE, do not treat as the final answer)"
else
  cmux browser $S get text 'chat-window'
fi
```

Answer stabilization = `chat-window` text length stops growing across 4 consecutive polls (not
2 — a single stable poll can be a mid-stream pause on long structured answers, not completion).
`chat-window` is a single scoped container for the whole conversation (no header/footer chrome
noise like plain `body`) — but it's still the FULL conversation history, so extract only the
text after the LAST "Bạn đã nói" / "Gemini đã nói" pair. a11y snapshot may be near-empty on
this page, so don't rely on `snapshot --interactive` for extraction.

Dead end already tried, don't repeat it: targeting only the latest answer via
`model-response:last-of-type` / `div.response-container:last-of-type` looks like it should
work (there are 2+ matching elements) but always returns the FIRST turn's text — each
conversation turn is wrapped in its own single-child parent, so `:last-of-type` is trivially
true for every one of them and the tool returns the first document-order match, not the last.
No `:nth-of-type(N)` workaround either, for the same per-parent-scoping reason. Extracting from
the full `chat-window` text and taking the last block is the practical approach here — contrast
with Model Selection above, where `[role="menu"] gem-menu-item` ARE true siblings and
positional/attribute selectors do work correctly.

**If the output starts with `__ASK_GEMINI_PANE_DIED__`:** do NOT present partial text to the
user as if it were the complete answer. Report plainly that the browser pane closed during
generation, and ask the user whether to retry (a fresh surface will be opened automatically
on the next ask since the stale ref was cleared) — don't auto-retry in a loop, since repeated
immediate retries after a failure is exactly the bot-like pattern to avoid.

Final response format to the user must be text-only: Gemini's answer, plus no extra metadata unless fallback was used.

## Error Handling and Fallback

If `snapshot --interactive` or wait/evaluate behavior returns `js_error`, inspect the page body instead:

```bash
cmux browser "$SURFACE" get url
cmux browser "$SURFACE" get text 'chat-window'
```

If Gemini web is blocked by bot detection, CAPTCHA, unresolved login, or repeated JS errors, fall back to Gemini CLI in the current pane and tell the user fallback was used:

```bash
gemini -p "$QUESTION"
```

Return the CLI output text. Prefix only a short note such as: `Fallback used: Gemini web UI was blocked, so I used Gemini CLI.`

## Token Hygiene and Safety

- Use `snapshot --interactive`; avoid DOM or HTML dumps unless recovering from `js_error`.
- Bring back only the final answer text into the main context.
- Do not paste cookies, state files, screenshots, full page HTML, or unrelated page text.
- Automate only `gemini.google.com`; verify with `get url` before fill/click/press.
- Google/Gemini web automation can be ToS-gray. Use only the user's own account and keep frequency human-like.
