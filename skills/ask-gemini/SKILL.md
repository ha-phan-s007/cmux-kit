---
name: ask-gemini
description: Use when you need to offload a question to Google Gemini web UI via cmux browser and return the answer text.
---

# Ask Gemini via cmux Browser

Use this skill from Claude Code running inside a Cmux pane to ask Gemini in the web UI and return only Gemini's answer text.

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

## Open or Reuse Gemini

First, look for a known Gemini surface. Use the current surface from Cmux context if available, plus any `surface:N` refs already visible in recent command output:

```bash
cmux identify --json
cmux browser surface:7 get url
```

If a known surface URL is on `gemini.google.com`, reuse it:

```bash
SURFACE=surface:7
cmux browser "$SURFACE" get url
cmux browser "$SURFACE" wait --load-state complete --timeout-ms 15000
```

If no known Gemini surface exists, open Gemini and copy the returned `surface:N` ref:

```bash
cmux --json browser open https://gemini.google.com
SURFACE=surface:7
cmux browser "$SURFACE" get url
cmux browser "$SURFACE" wait --load-state complete --timeout-ms 15000
cmux browser "$SURFACE" get url
```

## Login Handling

If the URL or page text shows Google login, pause browser automation and ask the human to click through login once in the Cmux webview. Note (verified 2026-07-07): the Cmux webview (WKWebView) has its OWN cookie store — it does NOT inherit the system/Safari/Chrome Google session. The one-time manual login in the webview persists for future runs within the webview.

After the human finishes login and Gemini chat is visible, save a backup auth state without exposing its contents:

```bash
mkdir -p ~/.local/state/cmux
cmux browser "$SURFACE" state save ~/.local/state/cmux/gemini-state.json
```

Never load the state file into context. Never run `cat`, `sed`, `grep`, `jq`, or similar commands on `~/.local/state/cmux/gemini-state.json`.

## Ask the Question — ONE batched Bash call (DX rule)

Run the whole ask→send→wait→extract loop as a SINGLE Bash invocation. Do NOT issue one
`cmux` call per Bash tool-call — that triggers a permission prompt per command and ruins DX.

Verified selectors (2026-07-07, Gemini web — locale-independent, tested against a Vietnamese-locale UI):
- Prompt input: `div.ql-editor` (Quill contenteditable — NOT exposed in a11y snapshot, so don't hunt refs; use the CSS selector directly)
- Send button: `button:has([data-mat-icon-name="arrow_upward"])`. `data-mat-icon-name` is Angular Material's internal icon identifier — it does NOT change with UI language, unlike `aria-label` text (which is `"Gửi tin nhắn"` in VN, `"Send message"` in EN, etc.). Do NOT match on `aria-label` for this button — pick the icon-name selector so the skill works regardless of the Gemini UI locale.
- `press Enter` returns OK but does NOT submit — always click the send button.
- The send button only renders/enables after the input has non-empty text — fill first, then query for the button.

```bash
S=surface:4   # reuse known Gemini surface; else: cmux --json browser open https://gemini.google.com
Q='Replace with the exact question.'
cmux browser $S wait --load-state complete --timeout-ms 20000
cmux browser $S fill 'div.ql-editor' "$Q"
cmux browser $S click 'button:has([data-mat-icon-name="arrow_upward"])'
prev=0
for i in $(seq 1 20); do
  sleep 5
  cur=$(cmux browser $S get text body 2>/dev/null | wc -c)
  if [ "$cur" -gt 200 ] && [ "$cur" -eq "$prev" ]; then break; fi
  prev=$cur
done
cmux browser $S get text body
```

Answer stabilization = body text length stops growing across two polls. Extract only the
newest Gemini response from the body text; a11y snapshot may be near-empty on this page.

Final response format to the user must be text-only: Gemini's answer, plus no extra metadata unless fallback was used.

## Error Handling and Fallback

If `snapshot --interactive` or wait/evaluate behavior returns `js_error`, inspect the page body instead:

```bash
cmux browser "$SURFACE" get url
cmux browser "$SURFACE" get text body
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
