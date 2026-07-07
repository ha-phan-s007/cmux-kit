# cmux-kit

`cmux-kit` là bộ hướng dẫn + installer để trao cho Claude Code khả năng điều khiển browser qua Cmux. Thay vì dùng Claude-in-Chrome hoặc Playwright MCP, Claude Code chạy trực tiếp trong terminal pane của app Cmux và điều khiển browser nhúng WKWebView thông qua `cmux browser ...`.

## Yêu cầu

- macOS 14+
- Homebrew
- Claude Code
- App Cmux. Installer sẽ cài nếu chưa có bằng Homebrew Cask.

## Cài đặt

Chạy từ thư mục `cmux-kit`:

```bash
./install.sh
```

Installer sẽ:

1. kiểm tra macOS, Homebrew, và app Cmux;
2. cài app Cmux nếu chưa có, sau khi bạn xác nhận;
3. cài 4 skill chính chủ từ `manaflow-ai/cmux`;
4. copy 3 skill kit `cmux-browser-human`, `ask-gemini` và `qc-browse` vào `~/.claude/skills/`, backup bản cũ nếu có;
5. thêm rule `Bash(cmux:*)` vào allow-list của **`~/.claude/settings.json` của chính bạn** (merge an toàn, backup file cũ, theo symlink nếu settings.json của bạn là symlink — ví dụ do dotfiles quản lý) — để mọi lệnh `cmux` chạy không bị hỏi permission mỗi lần. Nếu không có `jq`, bước này bị skip và installer in ra rule để bạn tự thêm tay;
6. **tuỳ chọn** (hỏi xác nhận, không tự động): nếu `~/.config/ghostty/config` chưa có, đề nghị tạo theme cho Cmux khớp với theme/font hiện tại của Terminal.app — xem mục Theme dưới đây.

> Kit này tự chứa (self-contained): mọi cấu hình cần thiết (skill + permission) đều do chính `install.sh` thiết lập trên máy bạn, không phụ thuộc dotfiles hay settings cá nhân của người đóng gói.

## Quan trọng: socket policy

**Claude Code PHẢI chạy trong pane của app Cmux.**

Cmux mặc định dùng socket policy `cmuxOnly`: chỉ process được khởi động bên trong pane Cmux mới được phép kết nối tới Unix socket điều khiển browser. Nếu chạy Claude Code trong Terminal/iTerm/Ghostty bên ngoài app Cmux, các lệnh `cmux browser ...` sẽ bị từ chối.

Workflow đúng:

1. Mở app Cmux.
2. Mở terminal pane trong Cmux.
3. `cd` vào project cần làm.
4. Chạy `claude` trong pane đó.

Trong pane Cmux, process sẽ có các env như `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, `CMUX_SOCKET_PATH`.

## Login Google/Gemini lần đầu

Với Gemini, lần đầu hãy mở `https://gemini.google.com` trong browser surface của Cmux và dùng chuột login Google thủ công. Webview của Cmux có cookie store riêng, nên không nhất thiết kế thừa session từ Safari/Chrome; thường chỉ cần login một lần trong chính webview đó. Sau khi login ổn định, có thể dùng `state save` để backup auth state nếu skill yêu cầu.

Chỉ dùng account của chính bạn và thao tác với tần suất giống người thật.

## Theme — Cmux khớp với Terminal.app

Cmux dùng libghostty làm engine terminal, và đọc **chung file config** với một bản
Ghostty độc lập: `~/.config/ghostty/config`. `cmux reload-config` áp dụng ngay, không
cần khởi động lại app.

`theme/extract-terminal-theme.py` đọc profile Terminal.app đang là mặc định của bạn
(font + palette 16 màu ANSI + màu nền/chữ) và in ra đúng cú pháp Ghostty config:

```bash
python3 theme/extract-terminal-theme.py > ~/.config/ghostty/config
cmux reload-config
```

Script tự phát hiện profile mặc định (`Default Window Settings` trong Terminal.app);
truyền tên profile khác làm argument nếu muốn (`extract-terminal-theme.py "Pro"`).

Lưu ý: field font trong Terminal.app lưu **PostScript name** (ví dụ `FiraCodeNF-Reg`),
không hẳn là **family name** Ghostty cần (`FiraCode Nerd Font`). Script sẽ in cảnh báo
kèm gợi ý `fc-list | grep -i <name>` để bạn xác nhận đúng family trước khi dùng.

`theme/ghostty-config.example` là 1 ví dụ tham khảo đã verify (từ profile "Clear Dark"),
không phải default chung cho mọi người — theme/font là lựa chọn cá nhân.

## Skill được cài

| Skill | Nguồn | Mục đích |
| --- | --- | --- |
| `cmux` | chính chủ | Hướng dẫn tổng quát để dùng CLI Cmux, workspace, pane, browser surface, và socket context. |
| `cmux-browser` | chính chủ | Browser automation: open URL, wait, snapshot interactive, click/fill/press/select, đọc text/html/value. |
| `cmux-workspace` | chính chủ | Quản lý workspace/window/pane/surface, target đúng context khi có nhiều cửa sổ hoặc workspace. |
| `cmux-diagnostics` | chính chủ | Chẩn đoán lỗi Cmux, socket, permission, app state, và browser surface. |
| `cmux-browser-human` | kit | Base overlay cho mọi thao tác browser qua Cmux: hover trước khi click/type, gõ từng ký tự, pause jitter, re-snapshot sau mutation, tránh chuỗi thao tác instant. |
| `ask-gemini` | kit | Dùng Gemini web qua Cmux để hỏi/phản biện, ưu tiên text-only và snapshot compact. Trigger: `ask Gemini: <câu hỏi>` (tiếng Anh, để match skill ổn định). |
| `qc-browse` | kit | Dùng browser surface để QC nhanh UI/web app, đọc console/page state và ghi nhận vấn đề. |

4 skill chính chủ lấy từ upstream `manaflow-ai/cmux`. Xem LICENSE tại upstream repository để biết điều khoản sử dụng. Kit này được đóng gói với tham chiếu Cmux version `0.64.17`.

`install.sh` fetch `skills.sh` bằng URL raw.githubusercontent.com **pin theo commit SHA**
của tag `v0.64.17` upstream (`9ed29d81a39de3ba44e0654bbcf6bf67ca86d1fb` — verify bằng
`git ls-remote --tags https://github.com/manaflow-ai/cmux.git`, và khớp với build hash
`cmux --version` in ra), KHÔNG fetch từ branch `main` đang trôi. Điều này đảm bảo nội
dung `skills.sh` không đổi ngầm giữa các lần cài trên các máy khác nhau. Nếu cần bump
version kit, cập nhật cả `CMUX_VERSION` và `UPSTREAM_CMUX_REF` trong `install.sh` cùng
lúc sau khi verify lại bằng `git ls-remote --tags`.

## Safety & ToS notes

- Chỉ thao tác trên URL an toàn và đúng phạm vi công việc.
- Với thao tác mutation như `type`, `fill`, `click`, `press`, `select`, `evaluate`, kiểm tra URL trước khi làm và áp dụng `cmux-browser-human` để thao tác giống người thật.
- Với Gemini/Google, chỉ dùng account của chính bạn; ToS automation là vùng xám, nên tránh spam, scraping hàng loạt, hoặc hành vi vượt tần suất người dùng thật.
- Giữ token hygiene: ưu tiên `snapshot --interactive`, trích text cần thiết, không đưa DOM dump/screenshot vào context nếu không cần.
- Cmux browser dùng WKWebView, nên một số khả năng Chrome/CDP như viewport emulation, offline emulation, trace/screencast, network interception có thể không hỗ trợ.

### Mechanical backstop: guard-cmux.sh

`cmux browser` chạy qua Bash tool thường (không có ranh giới MCP tool để chặn), và
installer cấp permission rộng `Bash(cmux:*)` cho DX — nghĩa là không có prompt xin
phép trước mỗi lệnh `cmux`. Rule "chỉ thao tác trên URL an toàn" ở trên chỉ là hướng
dẫn cho agent tự giác tuân theo; nó không tự chặn được gì nếu agent phán đoán sai.

Kit đóng gói `hooks/guard-cmux.sh` làm backstop cơ học cho đúng khoảng trống đó, theo
**mô hình approval-record** (giống hệt `guard-browser.sh` phía hey-clark cho MCP
browser tools) — KHÔNG phải mô hình cũ "hook tự resolve URL rồi so khớp hostname" (mô
hình cũ đã bị bỏ: một PreToolUse hook chỉ nhận được command dưới dạng chuỗi literal,
trước khi shell expand biến, nên với DX thật của skill — dùng biến shell như
`cmux browser "$S" click ...` hay định nghĩa helper function có body chứa literal
`cmux browser "$1" press ...` — hook không thể resolve ref thành URL và fail-closed
chặn nhầm mọi mutation hợp lệ, kể cả trên localhost):

- Chỉ xét các lệnh `cmux browser ...`; các lệnh Bash khác đi qua ngay (exit 0).
- Chỉ gate các subcommand có tính **mutation**: `click`, `dblclick`, `type`, `fill`,
  `press`/`key`, `select`, `check`/`uncheck`, `drag`/`drop`, `upload_file`, `eval`,
  `addinitscript`/`addscript`/`addstyle`, `cookies set|clear`, `storage set|clear`,
  `state load`, `network route`. Các subcommand đọc (`get`, `snapshot`, `wait`,
  `screenshot`, `console`, `errors`, `hover`, `focus`, `tab close`, `state save`,
  `reload`...) luôn được allow. Subcommand được match theo TỪ đứng sau `browser [ref]`,
  bất kể ref là literal hay biến shell (`"$S"`, `"$1"`) — hook không cần resolve ref
  thành URL nữa nên không quan tâm ref được viết dưới dạng gì, kể cả bên trong body của
  một helper function định nghĩa inline.
- Khi gate: hook KHÔNG tự resolve hay phân loại URL. Nó chỉ kiểm tra một bản ghi phê
  duyệt còn hiệu lực tại `.clark/.qc-browser-approval.json`, do chính skill gọi lệnh
  (`qc-browse`, `ask-gemini`) ghi ra SAU KHI skill tự chạy gate an toàn URL của nó
  (`is_safe_url` hoặc domain check riêng của `ask-gemini`). Bản ghi gồm: `approved`
  (bool), `classification` (`"safe"` / `"production_like"` / `"unknown"`),
  `human_approved` (bool), `url`, `expires_at` (ISO-8601 UTC, mặc định fresh 30 phút).
  Allow nếu bản ghi `approved:true`, chưa hết hạn, và (URL khớp keyword an toàn HOẶC
  `human_approved:true` cho URL production-like/unknown).
- **Khác với `guard-browser.sh`**: hook này KHÔNG yêu cầu `qc.enabled: true` trong
  `.clark/stack.yml` — `cmux-kit` chạy độc lập ở bất kỳ project nào, không chỉ trong
  pipeline QC của hey-clark, nên riêng bản ghi phê duyệt đã đủ để gate.
- **Đây là defense-in-depth, không phải oracle độc lập**: skill mới là bên phân loại
  URL (an toàn hay không); hook chỉ đảm bảo một bản ghi FRESH tồn tại, đã approved, và
  URL production-like có `human_approved:true`. Một mutation hoàn toàn "rogue" không có
  bản ghi vẫn bị chặn; cửa sổ 30 phút giới hạn thời gian một approval cũ còn hiệu lực.
- **Fail-closed**: nếu thiếu `jq`, không có bản ghi, bản ghi không hợp lệ/hết hạn, lệnh
  mutation bị BLOCK — đây là an toàn, không phải tiện lợi.

Installer sẽ hỏi xác nhận trước khi copy hook vào `~/.claude/hooks/guard-cmux.sh` và
đăng ký nó vào `~/.claude/settings.json` (`hooks.PreToolUse`, matcher `"Bash"`, merge an
toàn qua `jq`, backup file cũ, idempotent — chạy lại install không tạo bản đăng ký trùng).
Nếu máy không có `jq`, bước đăng ký tự động bị skip và installer in ra đoạn JSON để bạn
tự thêm tay. Việc cấp `Bash(cmux:*)` rộng vẫn hợp lý cho DX chính vì hook này đứng làm
lưới an toàn cơ học phía sau nó.

## Troubleshooting

Ưu tiên dùng skill `cmux-diagnostics` khi gặp lỗi.

| Lỗi | Ý nghĩa | Cách xử lý |
| --- | --- | --- |
| `Socket not found` | App Cmux chưa chạy hoặc socket chưa sẵn sàng. | Mở app Cmux, mở terminal pane, rồi chạy lại Claude Code trong pane đó. |
| `Access denied — only processes started inside cmux can connect` | Claude Code đang chạy ngoài pane Cmux. | Thoát Claude Code hiện tại, mở app Cmux → terminal pane → `cd` vào project → chạy `claude`. |
| Browser surface không phản hồi | Surface chưa load xong hoặc ref đã stale. | `get url`, `wait --load-state complete`, rồi `snapshot --interactive` lại để lấy ref mới. |
| `js_error` khi snapshot/eval | Trang JS-heavy chặn hoặc làm hỏng script snapshot. | Fallback `get text body` hoặc `get html body`; nếu cần, navigate qua trang đơn giản hơn rồi thử lại. |
