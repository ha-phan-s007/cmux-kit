# cmux-kit

`cmux-kit` is a set of guides and an installer that gives Claude Code browser-control
capabilities through Cmux. Instead of Claude-in-Chrome or Playwright MCP, Claude Code
runs directly inside a terminal pane of the Cmux app and drives the embedded WKWebView
browser via `cmux browser ...`.

## Requirements

- macOS 14+
- Homebrew
- Claude Code
- The Cmux app. The installer will install it via Homebrew Cask if missing.

## Installation

Run from the `cmux-kit` directory:

```bash
./install.sh
```

The installer will:

1. check macOS, Homebrew, and the Cmux app;
2. install the Cmux app if missing, after your confirmation;
3. install the 4 official skills from `manaflow-ai/cmux`;
4. copy the 3 kit skills `cmux-browser-human`, `ask-gemini`, and `qc-browse` into
   `~/.claude/skills/`, backing up any existing versions;
5. add a `Bash(cmux:*)` rule to the allow-list of **your own `~/.claude/settings.json`**
   (safe merge, backs up the old file, follows the symlink if your settings.json is a
   symlink — e.g. managed by dotfiles) — so every `cmux` command runs without a
   permission prompt each time. If `jq` is missing, this step is skipped and the
   installer prints the rule for you to add manually;
6. **optional** (asks for confirmation, not automatic): if `~/.config/ghostty/config`
   doesn't exist yet, offers to create a Cmux theme matching Terminal.app's current
   theme/font — see the Theme section below.

> This kit is self-contained: all necessary configuration (skills + permissions) is set
> up by `install.sh` itself on your machine, with no dependency on the packager's
> dotfiles or personal settings.

## Important: socket policy

**Claude Code MUST run inside a Cmux app pane.**

Cmux defaults to the `cmuxOnly` socket policy: only a process started inside a Cmux pane
is allowed to connect to the browser-control Unix socket. If you run Claude Code in
Terminal/iTerm/Ghostty outside the Cmux app, `cmux browser ...` commands will be
rejected.

Correct workflow:

1. Open the Cmux app.
2. Open a terminal pane inside Cmux.
3. `cd` into the project you're working on.
4. Run `claude` in that pane.

Inside a Cmux pane, the process will have env vars such as `CMUX_WORKSPACE_ID`,
`CMUX_SURFACE_ID`, `CMUX_SOCKET_PATH`.

## First-time Google/Gemini login

For Gemini, the first time, open `https://gemini.google.com` in a Cmux browser surface
and log in to Google manually with the mouse. Cmux's webview has its own cookie store,
so it does not necessarily inherit a session from Safari/Chrome; you typically only need
to log in once inside that webview. Once logged in, you can use `state save` to back up
the auth state if a skill requires it.

Only use your own account, and interact at a pace consistent with a real human.

## Theme — matching Cmux to Terminal.app

Cmux uses libghostty as its terminal engine, and reads the **same config file** as a
standalone Ghostty install: `~/.config/ghostty/config`. `cmux reload-config` applies
changes immediately, no app restart needed.

`theme/extract-terminal-theme.py` reads your current default Terminal.app profile
(font + 16-color ANSI palette + background/foreground colors) and prints it in the
correct Ghostty config syntax:

```bash
python3 theme/extract-terminal-theme.py > ~/.config/ghostty/config
cmux reload-config
```

The script auto-detects the default profile (`Default Window Settings` in
Terminal.app); pass a different profile name as an argument if you want
(`extract-terminal-theme.py "Pro"`).

Note: Terminal.app's font field stores the **PostScript name** (e.g.
`FiraCodeNF-Reg`), which isn't necessarily the **family name** Ghostty expects
(`FiraCode Nerd Font`). The script prints a warning with a `fc-list | grep -i <name>`
suggestion so you can confirm the right family before using it.

`theme/ghostty-config.example` is a verified reference example (from the "Clear Dark"
profile), not a shared default for everyone — theme/font is a personal choice.

## Installed skills

| Skill | Source | Purpose |
| --- | --- | --- |
| `cmux` | official | General guide to the Cmux CLI, workspace, pane, browser surface, and socket context. |
| `cmux-browser` | official | Browser automation: open URL, wait, interactive snapshot, click/fill/press/select, read text/html/value. |
| `cmux-workspace` | official | Manage workspace/window/pane/surface, target the right context with multiple windows or workspaces. |
| `cmux-diagnostics` | official | Diagnose Cmux, socket, permission, app-state, and browser-surface errors. |
| `cmux-browser-human` | kit | Base overlay for every browser action via Cmux: hover before click/type, type character by character, jittered pauses, re-snapshot after mutation, avoid instant action sequences. |
| `ask-gemini` | kit | Use the Gemini web UI via Cmux to ask/discuss, preferring text-only output and compact snapshots. Trigger: `ask Gemini: <question>` (in English, for stable skill matching). |
| `qc-browse` | kit | Use a browser surface for quick UI/web app QC — read console/page state and record issues. |

The 4 official skills come from the upstream `manaflow-ai/cmux`. See the LICENSE in the
upstream repository for terms of use. This kit is packaged against Cmux version
`0.64.17`.

`install.sh` fetches `skills.sh` from raw.githubusercontent.com **pinned to the commit
SHA** of the upstream tag `v0.64.17` (`9ed29d81a39de3ba44e0654bbcf6bf67ca86d1fb` —
verified via `git ls-remote --tags https://github.com/manaflow-ai/cmux.git`, and matched
against the build hash printed by `cmux --version`), NOT fetched from the moving `main`
branch. This ensures `skills.sh`'s content doesn't silently change across installs on
different machines. If you need to bump the kit version, update both `CMUX_VERSION` and
`UPSTREAM_CMUX_REF` in `install.sh` together, after re-verifying with
`git ls-remote --tags`.

## Safety & ToS notes

- Only operate on URLs that are safe and within the scope of the work.
- For mutating actions like `type`, `fill`, `click`, `press`, `select`, `evaluate`,
  check the URL first and apply `cmux-browser-human` to behave like a real human.
- For Gemini/Google, only use your own account; automation is a ToS gray area, so avoid
  spamming, bulk scraping, or interaction rates beyond a real user's.
- Maintain token hygiene: prefer `snapshot --interactive`, extract only the text you
  need, and don't dump DOM/screenshots into context unless necessary.
- Cmux's browser uses WKWebView, so some Chrome/CDP capabilities such as viewport
  emulation, offline emulation, trace/screencast, and network interception may not be
  supported.

### Mechanical backstop: guard-cmux.sh

`cmux browser` runs through the regular Bash tool (there's no MCP tool boundary to gate
it), and the installer grants the broad `Bash(cmux:*)` permission for DX — meaning
there's no permission prompt before every `cmux` command. The "only operate on safe
URLs" rule above is only guidance the agent is expected to follow on its own; it doesn't
block anything by itself if the agent judges wrong.

The kit ships `hooks/guard-cmux.sh` as the mechanical backstop for exactly that gap,
using the **approval-record model** (identical to hey-clark's `guard-browser.sh` for MCP
browser tools) — NOT the old "hook resolves the URL itself and matches the hostname"
model (that model was abandoned: a PreToolUse hook only receives the command as a
literal string, before the shell expands variables, so with the skill's real DX — using
shell variables like `cmux browser "$S" click ...`, or defining a helper function whose
body contains the literal `cmux browser "$1" press ...` — the hook cannot resolve the
ref into a URL and fails closed, blocking every legitimate mutation, including on
localhost):

- Only `cmux browser ...` commands are inspected; every other Bash command passes
  straight through (exit 0).
- Only **mutating** subcommands are gated: `click`, `dblclick`, `type`, `fill`,
  `press`/`key`, `select`, `check`/`uncheck`, `drag`/`drop`, `upload_file`, `eval`,
  `addinitscript`/`addscript`/`addstyle`, `cookies set|clear`, `storage set|clear`,
  `state load`, `network route`. Read-only subcommands (`get`, `snapshot`, `wait`,
  `screenshot`, `console`, `errors`, `hover`, `focus`, `tab close`, `state save`,
  `reload`...) are always allowed. The subcommand is matched by the WORD right after
  `browser [ref]`, regardless of whether ref is a literal or a shell variable (`"$S"`,
  `"$1"`) — the hook no longer needs to resolve the ref into a URL, so it doesn't care
  how the ref is written, even inside the body of an inline-defined helper function.
- When gating: the hook does NOT resolve or classify the URL itself. It only checks for
  a still-valid approval record at `.clark/.qc-browser-approval.json`, written by the
  calling skill itself (`qc-browse`, `ask-gemini`) AFTER that skill runs its own URL
  safety gate (`is_safe_url`, or `ask-gemini`'s own domain check). The record contains:
  `approved` (bool), `classification` (`"safe"` / `"production_like"` / `"unknown"`),
  `human_approved` (bool), `url`, `expires_at` (ISO-8601 UTC, fresh for 30 minutes by
  default). Allowed if the record is `approved:true`, not expired, and (the URL matches
  a safe keyword OR `human_approved:true` for a production-like/unknown URL).
- **Difference from `guard-browser.sh`**: this hook does NOT require `qc.enabled: true`
  in `.clark/stack.yml` — `cmux-kit` runs standalone in any project, not just inside
  hey-clark's QC pipeline, so the approval record alone is enough to gate.
- **This is defense-in-depth, not an independent oracle**: the skill is the one that
  classifies the URL (safe or not); the hook only ensures a FRESH, approved record
  exists, and that a production-like URL has `human_approved:true`. A completely "rogue"
  mutation with no record is still blocked; the 30-minute window limits how long an old
  approval stays valid.
- **Fail-closed**: if `jq` is missing, there's no record, or the record is invalid or
  expired, the mutating command is BLOCKED — this is a safety property, not a
  convenience.

The installer will ask for confirmation before copying the hook to
`~/.claude/hooks/guard-cmux.sh` and registering it in `~/.claude/settings.json`
(`hooks.PreToolUse`, matcher `"Bash"`, safe merge via `jq`, backs up the old file,
idempotent — re-running install doesn't create a duplicate registration). If `jq` is
missing, the registration step is automatically skipped and the installer prints the
JSON snippet for you to add by hand. Granting the broad `Bash(cmux:*)` permission still
makes sense for DX precisely because this hook stands as the mechanical safety net
behind it.

## Troubleshooting

Prefer using the `cmux-diagnostics` skill when you hit an error.

| Error | Meaning | Fix |
| --- | --- | --- |
| `Socket not found` | The Cmux app isn't running or the socket isn't ready yet. | Open the Cmux app, open a terminal pane, then re-run Claude Code inside that pane. |
| `Access denied — only processes started inside cmux can connect` | Claude Code is running outside a Cmux pane. | Quit the current Claude Code, open the Cmux app → terminal pane → `cd` into the project → run `claude`. |
| Browser surface isn't responding | The surface hasn't finished loading, or the ref is stale. | `get url`, `wait --load-state complete`, then `snapshot --interactive` again to get a fresh ref. |
| `js_error` on snapshot/eval | A JS-heavy page is blocking or breaking the snapshot script. | Fall back to `get text body` or `get html body`; if needed, navigate to a simpler page and retry. |
