# Taskora Hub — Tầm nhìn all-in-one (Ý TƯỞNG — Ghi lại 2026-11-11, CHƯA LÀM)

> **Trạng thái: Ý TƯỞNG / ROADMAP — không nằm trong bất kỳ bản phát hành nào hiện tại.**
> File này ghi lại để không mất. Khi quyết định làm, tách thành spec chi tiết từng phase
> (v3.0, v3.1…) theo đúng quy trình: spec trước → implement → CI → Release.
> Người dùng xác nhận (2026-11-11): *"tạm ghi vào ý tưởng đi, sau này lấy ra làm sau,
> mình còn định hoàn thiện app todo."*

## 1. Định hướng sản phẩm mới

**Taskora = bộ app hiệu suất all-in-one cho Windows** (thay vì chỉ là to-do list).
Khi mở app: **không vào thẳng todo** — vào **Dashboard**: lưới "app" kiểu iOS/Windows Start
(chọn app muốn vào: To-do, Calendar, Pomodoro, …). Nhấn vào app nào → **cửa sổ riêng, mở đúng
app đó, không lẫn**. Mục tiêu: gom mọi app hiệu suất phổ biến về một chỗ mà **vẫn gọn** —
không dồn tất cả vào một UI.

Nguyên tắc bất di bất dịch:
- **Không lẫn**: mỗi app = cửa sổ WebView riêng, state riêng.
- **Gọn**: mọi thứ chung (settings, giao diện, thông báo) chỉ xây một lần, dùng chung.
- **Dễ bảo trì & mở rộng**: workspace thư mục rõ ràng; mỗi app tự chứa; thêm app mới = thêm 1 thư mục, không sửa app khác.
- **Đẹp và hiện đại**: một design system thống nhất; mỗi app có "da" riêng (accent/icon/tint) hoặc theo theme chung.

## 2. Kiến trúc đề xuất

```
src-ui/
  hub/               # Dashboard + launcher — entry point mặc định khi mở app
  apps/todo/         # App To-do (chính là v2.x hiện tại, tách lại)
  apps/calendar/     # (phase sau)
  apps/focus/        # (phase sau) Pomodoro / bộ đếm
  shared/            # design tokens, component chung (btn, card, toast), icons, i18n, api helper
src-tauri/src/
  apps/todo/         # command module theo app: todo_*
  hub/               # đăng ký app, điều hướng, notification service, tray badge
  shared/            # settings chung, dữ liệu chung
specs/               # mỗi app 1 spec — giữ quy trình hiện tại
```

- **Cửa sổ riêng**: Tauri multi-window — spawn `WebviewWindow` theo yêu cầu app
  (`todo.html`, `calendar.html`…). Dữ liệu app nào dùng namespace lệnh riêng (`todo_*`,
  `calendar_*`).
- **Design system chung**: tokens (màu/radius/shadow/typography) + components (nút, card,
  toggle, toast) trong `shared/` — app nào dùng gì import đó; không copy-paste.
- **Thông báo tại Dashboard**: tray chạy nền luôn bật; mọi app phát sự kiện
  `notify({app, title, body})` → toast chung hiển thị **trong dashboard** (badge số chưa đọc
  trên tile app tương ứng + tổng trên tray icon). Không app nào tự vẽ toast riêng.
- **Style thông báo**: mặc định theo accent chung; mỗi app có thể đăng ký màu/icon riêng
  (settings có mục "Thông báo: Theo chung / Theo từng app").
- **Tùy chỉnh sâu nhưng gọn**: settings chia 2 tầng — *Chung* (Theme, accent, ngôn ngữ,
  thông báo) và *Theo app* (notification style, vị trí phím tắt…). Mỗi app chỉ hiển thị
  đúng phần của nó; "đầy đủ cài đặt mà không thừa" áp dụng cho từng app.
- **Push notification native**: dùng Tauri notification plugin (native Windows toast) cho
  nhắc hạn/đầu ngày — dashboard vẫn là nơi "tổng hợp".

## 3. Lộ trình đề xuất

| Phase | Nội dung | Ghi chú |
|---|---|---|
| v2.5.0 | Hoàn thiện app To-do hiện tại (Brain-dump, bước nhỏ nhất, thống kê phiên, âm thanh hết giờ, 20-20-20) | Đang làm |
| v3.0 | **Taskora Hub shell**: dashboard + launcher mặc định; migrate To-do thành app đầu tiên (giữ nguyên dữ liệu); notification service + tray badge; settings 2 tầng | Bản nâng cấp lớn nhất |
| v3.1 | **Calendar** mini-app (week/month view; đọc due_date todo qua IPC chung, không duplicate data) | App thứ 2 |
| v3.2 | **Pomodoro / Focus timer** thành app riêng (nâng từ overlay trong todo) | App thứ 3 |
| v3.3+ | Theo nhu cầu: Habit/streaks, Notes nhanh, Stats tổng hợp, … | |

Mỗi phase là một release độc lập, luôn ship được. Không đập đi xây lại một lần.

## 4. Ứng viên tính năng tương lai (roadmap apps)

- **Body doubling / accountability rooms** (Focusmate-style): phòng tập trung trực tuyến,
  ghép cặp, webcam/presence, check-in. **Cần server + tài khoản** — là một app riêng,
  không bao giờ nhét vào To-do. Bản offline trung thực thay thế: "Đăng check-in" tạo
  mailto/copy gửi cho bạn.
- **Ước lượng thời gian** (planning fallacy): mỗi task có `estimate_min`; app so với thời
  gian focus thực tế → gợi ý "bạn thường hết gấp đôi". Dùng lại focus engine.
- **Chặn xao lãng OS-level**: mức 1 (taskkill danh sách app xao lãng user tự chọn khi phiên
  focus bắt đầu + Windows Focus Assist hint) và mức 3 (kiosk fullscreen). **Không** tự sửa
  hosts/firewall (quyền admin, rủi ro).
- **Gợi ý AI (opt-in)**: "Chia nhỏ việc này", gợi ý lịch… — chỉ khi user tự bật + tự nhập
  API key (OpenAI-compatible), mặc định TẮT, có nhãn rõ dữ liệu gửi đi đâu. Lớp 2 sau lớp
  1 (template cục bộ, không AI). Dùng chung cho mọi app qua 1 service chung.
- **Thư viện phím tắt / lệnh nhanh (Ctrl+K) dùng chung** toàn Hub.

## 5. Quyết định cần người dùng chốt khi đến lúc

1. Hub là **cửa sổ mặc định khi mở app**, hay chỉ mở bằng phím tắt (và mở thẳng app cuối cùng)?
2. App thứ 2 là **Calendar** hay **Focus timer**? (đề xuất Calendar — ăn trực tiếp dữ liệu due-date của todo)
3. Có làm **native push notifications** (cần Tauri plugin + quyền Windows) từ v3.0 ngay?
4. Settings 2 tầng: tên nhóm hiển thị tiếng Việt như hiện tại?
5. Giữ bundle như hiện tại (không tách workspace crates) hay tách thành cargo workspace nhiều crate khi app ≥ 4?

## 6. Rủi ro & cách tránh

| Rủi ro | Tránh |
|---|---|
| Big-bang rewrite → vỡ ổn định | Từng phase ship được; v3.0 migrate To-do bằng cách **di chuyển file, không viết lại** |
| Dữ liệu người dùng gãy khi đổi cấu trúc | Store giữ nguyên schema; Hub chỉ thêm lớp điều hướng |
| Settings 2 tầng rối | Chỉ 2 tầng; app mới chỉ thấy phần mình |
| Design system phình | Chỉ token + 10 component chung; không "thư viện component" tổng quát hóa sớm |
| Scope creep | Mỗi app mới = 1 spec duyệt riêng trước khi code |
