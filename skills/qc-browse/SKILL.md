---
name: qc-browse
description: "autonomous manual-testing via cmux browser: explore a URL to produce a requirement doc, run reviewed testcases step-by-step with evidence, generate e2e code, a11y checks"
---

# qc-browse

Use this skill for autonomous manual QA in a cmux browser surface. Inputs are natural-language prompt + URL, and for `test-run` also a reviewed testcase table with step/data/expected.

Always use verified `cmux browser` commands only. Do not invent Playwright MCP or cmux commands.

Before any browser interaction, use `cmux-browser-human` as the base layer. All mutation-capable actions in this skill must be performed through its human-paced helpers (`human_click`, `human_type`, `human_press`, `human_select`, or `human_fill_fallback` only when typing cannot work). Do not use instant `fill` + immediate `click` sequences.

## Modes

Infer the mode from the prompt. If ambiguous, choose the safest read-only mode (`explore`) unless testcases are supplied.

| Mode | Goal |
|---|---|
| `explore` | Open a URL, systematically browse screens/navigation, and produce a detailed requirement document. |
| `test-run` | Execute reviewed testcase steps and record actual visual results + PASS/FAIL. |
| `gen-e2e` | Generate Playwright test code from real actions already performed. Do not run Playwright MCP. |
| `a11y` | Use the cmux accessibility snapshot plus screenshots for accessibility review. |

## Required output location

Create one artifact folder per run:

```bash
RUN_DIR="artifacts/qc/$(date +%Y%m%d-%H%M)"
mkdir -p "$RUN_DIR"
```

Save:

- `report.md` as the final report.
- `snapshot-*.txt` for relevant text-only snapshots.
- `screenshot-*.png` for screenshot evidence.
- `playwright.spec.ts` only for `gen-e2e` mode.

Keep the main chat/context text-only. Do not paste full DOM, screenshots, or large snapshots into the main context unless strictly necessary.

**Screenshot command note (verified 2026-07-07):** `cmux browser <surface> screenshot` does NOT
print base64 to stdout on this CLI version — it always writes a real PNG file to disk and
prints `OK <path>` to stdout. Always pass `--out "$RUN_DIR/screenshot-name.png"` explicitly;
never redirect stdout to a `.b64` file (that captures only the one-line `OK <path>`
confirmation, not image data — confirmed by inspecting actual command output, not assumed
from older docs).

## Safety gate before mutation

Mutation means `fill`, `type`, `select`, `press`, `click`, `check`, `uncheck`, `scroll` when it can change state, storage/cookie writes, and any `eval` that changes page state.

Before mutation:

1. Check current URL:

   ```bash
   cmux browser "$SURFACE" get url
   ```

2. Build the safe URL keyword list:
   - Built-in low-risk keywords: `localhost`, `127.0.0.1`, `0.0.0.0`, `.local`, `dev`, `staging`, `stage`, `test`, `sandbox`, `preview`.
   - If `.clark/stack.yml` exists, read `qc.safe_url_keywords` and append those project-specific keywords.

3. Mutate only when the current URL matches the safe list.
4. If there is no `.clark/stack.yml` and the URL does not match the built-in safe list, ask the user before mutation on the unknown URL.
5. If blocked from asking, continue only with read-only actions: `open`, `goto`, `get url`, `get title`, `snapshot`, `get text`, `get html`, `get attr`, `get count`, `get box`, `get styles`, screenshots, and waits.

Never submit forms, make purchases, send messages, delete data, or trigger irreversible workflow actions unless the prompt explicitly authorizes that exact action and the URL passes the safety gate.

## Core browser loop

Open or reuse one surface for the task.

```bash
# Define the helper functions from `cmux-browser-human` in this same Bash invocation first.
OPEN_JSON=$(cmux --json browser open "$URL")
SURFACE=$(printf '%s' "$OPEN_JSON" | grep -o '"surface_ref"[^,}]*' | grep -o 'surface:[0-9]*')
[ -n "$SURFACE" ] || { echo "Could not open browser surface."; exit 1; }

cmux browser "$SURFACE" get url
human_after_load "$SURFACE"
human_snapshot "$SURFACE" > "$RUN_DIR/snapshot-home.txt"
cmux browser "$SURFACE" screenshot --out "$RUN_DIR/screenshot-home.png"
```

After every navigation or DOM-changing action:

```bash
human_snapshot "$SURFACE" > "$RUN_DIR/snapshot-after-action.txt"
```

For action steps, prefer fresh refs from the latest `snapshot --interactive`:

```bash
human_type "$SURFACE" e1 "value"
human_click "$SURFACE" e2 --snapshot-after
human_press "$SURFACE" Enter
human_snapshot "$SURFACE"
```

If `snapshot --interactive` returns `js_error`, recover with:

```bash
cmux browser "$SURFACE" get url
cmux browser "$SURFACE" get text body
cmux browser "$SURFACE" get html body
```

Use compact snapshots when context is large:

```bash
cmux browser "$SURFACE" snapshot --interactive --compact --max-depth 3
```

## Mode: explore

Goal: produce a detailed requirement document from observed behavior.

Process:

1. Open the URL and capture the landing screen.
2. Inventory visible navigation, primary CTAs, forms, filters, menus, tabs, modals, tables, and error/empty states.
3. Traverse systematically with the loop: navigate -> wait -> snapshot -> screenshot -> click -> wait -> re-snapshot.
4. For each main screen, capture one screenshot and one text snapshot.
5. Exercise safe, reversible UI paths: open menus/modals, change tabs, use filters with harmless values, inspect validation by focusing/leaving required fields empty only when safe.
6. Stop exploration when major screens and navigation paths are covered or further actions would require unsafe mutation.

Write `report.md` with:

```markdown
# Requirement Discovery Report

## Scope
- URL:
- Mode: explore
- Run directory:

## Screen Map
| Screen | URL/State | Purpose | Evidence |

## UI/UX Details by Screen
### Screen name
- Layout:
- Visible content:
- Controls:
- Form fields:
- States observed:
- Screenshot:

## User Flows
### Flow name
| Step | Action | Observed result | Evidence |

## Observed Business Rules
- Rule:
- Evidence:

## Validation and Error Behavior
- Scenario:
- Observed behavior:

## Unclear or Problematic Points / Improvement Suggestions
- Issue:
- Why it matters:
- Suggested improvement:

## Coverage Notes
- Covered:
- Not covered:
- Blocked by safety/auth/data:
```

## Mode: test-run

Goal: execute reviewed testcases step-by-step and record actual visual evidence.

Input testcase format can be markdown/CSV-like, but normalize it internally to:

| Case ID | Step | Data | Expected |
|---|---|---|---|

Process:

1. Create `RUN_DIR`.
2. Open URL and snapshot the initial state.
3. For each testcase, reset to the required start URL/state if specified.
4. Before each mutating step, apply the safety gate.
5. Execute exactly one step at a time with `fill`, `click`, `press`, `select`, etc.
6. After each step, capture a fresh snapshot.
7. Set `actual` to a detailed description of what is visible in the snapshot: labels, values, messages, enabled/disabled state, URL changes, modal/page changes, list/table content, validation errors.
8. Capture screenshot evidence for important steps: start state, each assertion point, failures, final state.
9. Verdict per step/case:
   - `PASS` when actual visible behavior matches expected.
   - `FAIL` when actual contradicts expected or required UI is missing.
   - `BLOCKED` when safety/auth/environment prevents execution.

Use commands like:

```bash
human_type "$SURFACE" e3 "qa@example.com"
human_press "$SURFACE" Tab
human_click "$SURFACE" e8 --snapshot-after
cmux browser "$SURFACE" snapshot --interactive > "$RUN_DIR/snapshot-TC01-step03.txt"
cmux browser "$SURFACE" screenshot --out "$RUN_DIR/screenshot-TC01-step03.png"
```

Write `report.md` with:

```markdown
# Manual Test Run Report

## Scope
- URL:
- Mode: test-run
- Run directory:

## Summary
| Total | PASS | FAIL | BLOCKED |

## Results
### TC01 - Title
| Step | Data | Expected | Actual observed from snapshot | Verdict | Evidence |

## Defects / Observations
| Case | Step | Severity | Finding | Evidence |

## Coverage Notes
- Not executed:
- Safety/auth/data blockers:
```

## Mode: gen-e2e

Goal: generate Playwright test code from real interactions already executed in cmux.

Rules:

- Do not use Playwright MCP.
- Do not treat cmux snapshot refs (`e1`, `e2`) as stable selectors in generated tests; refs are session-local and stale after DOM changes.
- Derive stable Playwright locators from observed accessibility names, labels, roles, placeholder text, visible text, URL changes, and stable attributes from `get html body` or `get attr`.
- Prefer locators in this order:
  1. `page.getByRole(role, { name })`
  2. `page.getByLabel(label)`
  3. `page.getByPlaceholder(text)`
  4. `page.getByText(text)`
  5. `page.locator('[data-testid="..."]')`
  6. CSS selector only when no semantic locator is available.
- Include assertions based on what was actually visible.
- Add TODO comments where only unstable selectors are available.

Useful inspection commands:

```bash
cmux browser "$SURFACE" snapshot --interactive
cmux browser "$SURFACE" get attr e3 --attr aria-label
cmux browser "$SURFACE" get attr e3 --attr placeholder
cmux browser "$SURFACE" get html body
```

Write:

- `artifacts/qc/<YYYYMMDD-HHmm>/playwright.spec.ts`
- `artifacts/qc/<YYYYMMDD-HHmm>/report.md`

`report.md` should list source flows, generated tests, locator assumptions, and any TODOs.

## Mode: a11y

Goal: accessibility review using cmux accessibility snapshots as the primary source, plus screenshots for best-effort visual checks.

Process:

1. Open URL and capture each major screen state.
2. Use `snapshot --interactive` as the accessibility tree.
3. Check:
   - Missing or vague accessible names for buttons, links, inputs, icons, and menu items.
   - Incorrect or missing roles for interactive controls.
   - Heading structure: one meaningful `h1`, no skipped levels where observable.
   - Form labels and error message association.
   - Image alt text or accessible names where images appear in the tree.
   - Keyboard path basics: focusable controls, visible focus behavior after `press Tab`, modal focus containment when safe.
   - Contrast from screenshots as best effort; use `get styles` for visible text/background when selectors are known.

Commands:

```bash
cmux browser "$SURFACE" snapshot --interactive > "$RUN_DIR/snapshot-a11y-home.txt"
cmux browser "$SURFACE" screenshot --out "$RUN_DIR/screenshot-a11y-home.png"
human_press "$SURFACE" Tab
cmux browser "$SURFACE" snapshot --interactive
cmux browser "$SURFACE" get styles e5 --property color
cmux browser "$SURFACE" get styles e5 --property background-color
```

Write `report.md` with:

```markdown
# Accessibility Review Report

## Scope
- URL:
- Mode: a11y
- Run directory:

## Summary
| Category | Status | Notes |

## Findings
| Severity | Screen | Element | Issue | Evidence | Recommendation |

## Heading Structure

## Keyboard / Focus Notes

## Contrast Notes (Best Effort)

## Not Verified
```

## Final report and integrations

At the end, report only:

- `report.md` path.
- Key PASS/FAIL/BLOCKED counts or top findings.
- Artifact folder path.

If `.clark/stack.yml` exists, inspect project notification settings and `dry_run` flags. Do not invent ClickUp/Slack commands. If `dry_run` is enabled or no known integration command exists, add a final section in `report.md`:

```markdown
## Suggested ClickUp / Slack Update

Dry run: true
Target:
Message:
```

Only send to ClickUp/Slack when the project has an existing documented command/config for it, `dry_run` is false, and the user asked for sending.
