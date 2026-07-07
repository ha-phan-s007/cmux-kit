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

## Safety & ToS notes

- Chỉ thao tác trên URL an toàn và đúng phạm vi công việc.
- Với thao tác mutation như `type`, `fill`, `click`, `press`, `select`, `evaluate`, kiểm tra URL trước khi làm và áp dụng `cmux-browser-human` để thao tác giống người thật.
- Với Gemini/Google, chỉ dùng account của chính bạn; ToS automation là vùng xám, nên tránh spam, scraping hàng loạt, hoặc hành vi vượt tần suất người dùng thật.
- Giữ token hygiene: ưu tiên `snapshot --interactive`, trích text cần thiết, không đưa DOM dump/screenshot vào context nếu không cần.
- Cmux browser dùng WKWebView, nên một số khả năng Chrome/CDP như viewport emulation, offline emulation, trace/screencast, network interception có thể không hỗ trợ.

## Troubleshooting

Ưu tiên dùng skill `cmux-diagnostics` khi gặp lỗi.

| Lỗi | Ý nghĩa | Cách xử lý |
| --- | --- | --- |
| `Socket not found` | App Cmux chưa chạy hoặc socket chưa sẵn sàng. | Mở app Cmux, mở terminal pane, rồi chạy lại Claude Code trong pane đó. |
| `Access denied — only processes started inside cmux can connect` | Claude Code đang chạy ngoài pane Cmux. | Thoát Claude Code hiện tại, mở app Cmux → terminal pane → `cd` vào project → chạy `claude`. |
| Browser surface không phản hồi | Surface chưa load xong hoặc ref đã stale. | `get url`, `wait --load-state complete`, rồi `snapshot --interactive` lại để lấy ref mới. |
| `js_error` khi snapshot/eval | Trang JS-heavy chặn hoặc làm hỏng script snapshot. | Fallback `get text body` hoặc `get html body`; nếu cần, navigate qua trang đơn giản hơn rồi thử lại. |
