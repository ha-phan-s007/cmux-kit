# cmux-kit Cookbook

Các recipe dưới đây là prompt mẫu cho use-case browser phổ biến **không cần viết skill riêng**. Copy-paste prompt vào Claude Code đang chạy trong pane Cmux. Mỗi recipe đang được đánh dấu **⚠ chưa verify** và sẽ được verify dần.

## Humanization baseline

Mọi recipe dùng browser đều giả định agent đọc và áp dụng `cmux-browser-human` trước khi thao tác trên trang: hover trước khi click/type/select, dùng `type` thay cho `fill` khi có thể, thêm pause jitter ở các điểm tự nhiên, và snapshot lại sau navigation hoặc mutation. Không dùng chuỗi `fill` rồi `click` tức thì.

## Auto-healing UI — ⚠ chưa verify

**Mục tiêu:** Mở app local, đọc lỗi console/UI, sửa code, reload và lặp đến khi trang sạch lỗi.

**Prompt mẫu:**

```text
Use cmux-browser to open http://localhost:3000.
Workflow: get url → wait load complete → snapshot interactive → inspect visible errors and console/page errors if available.
If there are UI/runtime errors, fix the source code, reload the page, and repeat until the page renders cleanly.
Keep evidence text-only: summarize errors, changed files, and final clean state. Do not paste full DOM.
```

**Lưu ý:** Chỉ sửa lỗi liên quan trực tiếp đến màn đang kiểm tra. Sau mỗi navigation hoặc reload, snapshot lại để tránh stale refs.

## Swagger UI → TypeScript interface — ⚠ chưa verify

**Mục tiêu:** Điền param trong Swagger UI, bấm Execute, đọc response JSON, rồi sinh TypeScript interface.

**Prompt mẫu:**

```text
Use cmux-browser to open the Swagger UI at <SWAGGER_URL>.
Find endpoint <METHOD> <PATH>, fill required parameters with these values: <PARAMS>.
Click Execute, wait for the response, extract the response JSON, and generate TypeScript interfaces from the actual response shape.
Return only: endpoint called, status code, compact response sample, and TypeScript interfaces.
```

**Lưu ý:** Verify đúng endpoint trước khi Execute. Không gửi request mutation tới môi trường production nếu chưa được phép.

## Storybook component states — ⚠ chưa verify

**Mục tiêu:** Check các states của component trong Storybook.

**Prompt mẫu:**

```text
Use cmux-browser to open Storybook at <STORYBOOK_URL>.
Navigate to component <COMPONENT_NAME>.
Inspect these states: <STATE_LIST>.
For each state, wait until rendered, take an interactive snapshot, and report visible issues in layout, content, disabled/loading/error behavior, and obvious a11y problems.
Keep output concise and text-only.
```

**Lưu ý:** Storybook thường thay đổi iframe/canvas; sau khi đổi story hoặc control, luôn wait rồi snapshot lại.

## Prisma Studio/phpMyAdmin data verification — ⚠ chưa verify

**Mục tiêu:** Verify data sau khi chạy script hoặc migration.

**Prompt mẫu:**

```text
Use cmux-browser to open <PRISMA_STUDIO_OR_PHPMYADMIN_URL>.
Verify that data created by <SCRIPT_OR_FLOW> exists in table/model <TABLE_OR_MODEL>.
Filter/search by <IDENTIFIER>.
Report the matching rows and whether the expected fields match: <EXPECTED_FIELDS>.
Do not modify data unless explicitly needed for verification.
```

**Lưu ý:** Đây là read-only verification mặc định. Nếu cần edit/delete data, yêu cầu prompt phải nói rõ.

## Đọc docs mới trên trang JS-heavy — ✅ verified 2026-07-07

**Mục tiêu:** Mở docs cần JS render, snapshot, rồi trích code example hữu ích.

**Prompt mẫu:**

```text
Use cmux-browser to open <DOCS_URL>.
Wait for the page to load, confirm the final URL, then snapshot interactive.
Extract the relevant documentation for <TOPIC>, especially code examples and option names.
If snapshot fails with js_error, fall back to get text body or get html body.
Return a concise summary plus the minimal code examples needed for implementation.
```

**Lưu ý:** Không paste toàn bộ docs. Chỉ trích phần cần thiết, giữ token hygiene.

## E2E qua login — ⚠ chưa verify

**Mục tiêu:** Login một lần, save state, rồi test màn sau login.

**Prompt mẫu:**

```text
Use cmux-browser for an authenticated E2E flow on <APP_URL>.
Open the login page. If already authenticated, continue. If not, guide me to complete login manually in the Cmux browser surface.
After login succeeds, save authentication state to <STATE_FILE>.
Then navigate to <POST_LOGIN_URL>, verify the expected page state <EXPECTED_STATE>, and perform these checks: <CHECKS>.
Return text-only evidence and note where auth state was saved.
```

**Lưu ý:** Với OAuth/2FA, để human thao tác bằng chuột/bàn phím trong browser surface. Không đưa credential vào prompt.

## A11y audit nhanh 1 trang — ⚠ chưa verify

**Mục tiêu:** Audit nhanh accessibility cho một trang.

**Prompt mẫu:**

```text
Use cmux-browser to open <PAGE_URL>.
Wait for load complete and take an interactive snapshot.
Perform a quick accessibility audit from the accessibility tree and visible content:
- heading structure
- button/link accessible names
- form labels and error messages
- keyboard focus blockers if obvious
- color/contrast issues if visually apparent
Return prioritized findings with selector/ref when available and suggest minimal fixes.
```

**Lưu ý:** Đây là quick audit, không thay thế full automated a11y suite. Nếu page thay đổi state khi click/tab, snapshot lại sau mỗi bước.
