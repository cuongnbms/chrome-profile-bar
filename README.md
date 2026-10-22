# Chrome Profile Bar

App macOS nhỏ (AppKit thuần, không Dock icon) hiện một thanh nổi gồm các nút profile Chrome
để nhảy nhanh tới window của từng profile. Thay cho một Hammerspoon
script, nhưng chỉ tốn khoảng 13 MB footprint thay vì cả một Hammerspoon.

| Thao tác | Kết quả |
|---|---|
| Click nút | Focus window của profile (tìm theo given name); không có thì mở window mới bằng `--profile-directory` và đặt tên cho window đó sau 2.5 giây |
| Alt + Click | Đặt given name cho window Chrome đang ở trước = `window` của profile (xoá tên đó khỏi các window khác) |
| Kéo nền / ⋮ | Di chuyển thanh, vị trí được nhớ |
| Chuột phải | Launch at Login, Match Window Titles (Accessibility), Open/Reload Config, Quit |
| Ctrl+Alt+P | Ẩn/hiện thanh |
| Ctrl+Alt+1…9 | Nhảy tới profile 1…9 |

Nút của profile đang active (window Chrome đang focus) được tô đậm hơn. App bỏ qua mọi instance
Chrome chạy với `--enable-automation` (ví dụ chrome-devtools-mcp) và luôn gửi Apple Event theo
pid tới Chrome của bạn.

## Build & cài đặt

Cần Swift 6 (Command Line Tools là đủ, không cần Xcode).

```sh
./scripts/make-signing-cert.sh   # chỉ cần chạy một lần: tạo identity "ChromeProfileBar Dev" trong login keychain
./build.sh                       # -> build/ChromeProfileBar.app
./build.sh install               # build, chép vào /Applications rồi khởi động lại app
./scripts/test.sh                # unit test (config, so khớp tiêu đề, vị trí, đọc argv)
```

### Vì sao cần chứng chỉ ký riêng

Quyền Automation/Accessibility mà TCC lưu được gắn với *designated requirement* của chữ ký.
Ký ad-hoc thì requirement là cdhash, đổi sau mỗi lần build, nên macOS sẽ hỏi lại quyền. Ký
bằng một identity cố định thì requirement là
`identifier "dev.cuongnb.ChromeProfileBar" and certificate leaf = H"…"`, giữ nguyên qua các
lần rebuild. Chứng chỉ self-signed không cần được trust để `codesign` dùng (nó hiện
`CSSMERR_TP_NOT_TRUSTED` trong `security find-identity`, không sao). Kiểm tra:

```sh
codesign -dr - /Applications/ChromeProfileBar.app
```

Muốn dùng identity khác thì đặt `CODESIGN_IDENTITY="…" ./build.sh`. Nếu không tìm thấy
identity, `build.sh` ký ad-hoc và in cảnh báo.

## Cấp quyền

- **Automation → Google Chrome** (bắt buộc): macOS tự hỏi ở lần đầu app điều khiển Chrome. Nếu
  lỡ từ chối: System Settings → Privacy & Security → Automation → Chrome Profile Bar → bật
  Google Chrome. Có thể reset bằng `tccutil reset AppleEvents dev.cuongnb.ChromeProfileBar`.
- **Accessibility** (tuỳ chọn): Chrome scripting chỉ trả về tiêu đề tab, không có đuôi
  `(<profile>)`. Vì vậy nếu muốn tìm/highlight cả những window *chưa đặt tên* theo tiêu đề như
  bản Hammerspoon, hãy chọn chuột phải → *Match Window Titles (Accessibility)…* rồi bật app
  trong System Settings. Không cấp thì app chỉ dựa vào given name: click vào profile chưa có
  window được đặt tên sẽ mở window mới; dùng Alt+Click để đặt tên cho window có sẵn.
- Hotkey dùng Carbon `RegisterEventHotKey` nên không cần quyền gì thêm.

Luôn mở app qua `open`/Finder (không chạy thẳng binary) để macOS gán quyền đúng cho app.

## Cấu hình

`~/.config/chrome-profile-bar/profiles.json` (nếu chưa có, app tạo một file mẫu):

```json
[
  { "label": "Main", "window": "Main", "profile": "Main",        "dir": "Default",   "color": "#4285F4" },
  { "label": "Work", "window": "work", "profile": "example.com", "dir": "Profile 2", "color": "#0F9D58" }
]
```

| Khoá | Ý nghĩa | Mặc định |
|---|---|---|
| `label` | Chữ trên nút | bắt buộc |
| `window` | Given name của window ("Name window…") dùng để tìm window | `label` |
| `profile` | Tên hiển thị của profile, dùng để so với đuôi tiêu đề window (cần Accessibility) | `label` |
| `dir` | Phần cuối của "Profile Path" trong `chrome://version` | bắt buộc |
| `color` | Màu nút `#RRGGBB` | `#4285F4` |

Sửa xong thì chọn chuột phải → *Reload Config* (hoặc quit rồi mở lại app). Vị trí thanh được
lưu trong `defaults read dev.cuongnb.ChromeProfileBar`.

## Chạy khi đăng nhập

Chuột phải → *Launch at Login* (dùng `SMAppService.mainApp`, nên app phải nằm ở
`/Applications`). App sẽ hiện trong System Settings → General → Login Items.

## Chuyển từ Hammerspoon

Nếu đang dùng một script Hammerspoon tương tự, hãy quit Hammerspoon (hoặc gỡ script đó khỏi
`~/.hammerspoon/init.lua`) trước khi mở app. Nếu không, hotkey Ctrl+Alt+P/1…9 sẽ bị trùng và
một trong hai bên không nhận được phím.

## Bộ nhớ

Đo trên macOS 26, arm64 với 4 profile:

```sh
pid=$(pgrep -x ChromeProfileBar)
footprint $pid | grep phys_footprint   # ~13 MB, cũng là cột "Memory" trong Activity Monitor
ps -o rss= -p $pid                     # ~45 MB, gồm cả các trang framework hệ thống dùng chung
```

RSS của một app AppKit không làm gì (chỉ một NSPanel) đã khoảng 38 MB, vì RSS đếm cả các
trang của framework dùng chung với process khác. Footprint mới là phần bộ nhớ riêng của app.

## Cách hoạt động

- `Chrome.swift` + `AppleEvent.swift`: Apple Event thô (`NSAppleEventDescriptor`) gửi theo pid
  với các mã trong `scripting.sdef` của Chrome (`GNam` given name, `pidx` index, `pmnd`
  minimized, `misc/actv`). Không nạp OSAKit/JavaScriptCore. Instance automation được nhận ra
  bằng cách đọc argv qua `sysctl(KERN_PROCARGS2)`.
- `ActiveTracker.swift`: refresh khi Chrome được activate (`NSWorkspace`). Chỉ trong lúc
  Chrome đang ở trước, mỗi giây đọc số hiệu window trên cùng của Chrome qua
  `CGWindowListCopyWindowInfo` (không cần quyền nào) và chỉ gửi Apple Event khi số này đổi.
- `Panel.swift`: `NSPanel` dạng `.nonactivatingPanel`, level `.floating`, `.canJoinAllSpaces`
  + `.stationary`. Click không cướp focus của Chrome.
- `HotKeys.swift`: Carbon hotkeys. `WindowTitles.swift`: phần dùng Accessibility (tuỳ chọn).

Log: `log stream --info --predicate 'subsystem == "dev.cuongnb.ChromeProfileBar"'`.
