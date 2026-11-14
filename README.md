# Taskora 📝

**Ứng dụng quản lý công việc (to-do) cho Windows** – giao diện **liquid glass** chuẩn Apple, viết 100% bằng **Rust** (Tauri v2 + frontend web nhẹ, không framework).

![Build](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/workflows/ci.yml/badge.svg)

## ⬇️ Tải file .exe

1. Vào tab **[Releases](https://github.com/Hthancder/ArenaAIWorkspace-1/releases/latest)** → tải `Taskora.exe` (chạy ngay) hoặc `Taskora-Setup-x64.exe` (bản cài đặt NSIS) của bản mới nhất.
2. (Hoặc: tab **[Actions](https://github.com/Hthancder/ArenaAIWorkspace-1/actions)** → chọn bản build gần nhất → artifact `Taskora-Windows-x64`.)
3. Chạy thôi – không cần cài đặt. Windows 10/11 đã có sẵn **WebView2** qua Edge; bản cài NSIS sẽ tự tải WebView2 nếu thiếu.
4. Dữ liệu cũ từ v1.x được **giữ nguyên** (`data.json` cùng đường dẫn `%APPDATA%\Taskora`).

## ✨ Tính năng

**Việc & danh sách**
- Thêm việc nhanh bằng **ngôn ngữ tự nhiên** (Anh + Việt):
  `Trả báo cáo ngày mai #công-việc !p1 *hàng tuần`
  → hiểu `hôm nay / ngày mai / thứ 6 / chủ nhật / 15/11/2026 / next monday / in 3 days`, thẻ `#`, ưu tiên `!p1–!p4`, lặp lại `*daily/*weekly/*monthly` và `hàng ngày/tuần/tháng`.
- Nhiều **danh sách** với màu riêng; Hộp thư, view nhanh: **Hôm nay · Sắp tới · Đã ghim · Đã hoàn thành · Thùng rác · Thống kê**.
- **Việc nhỏ** (checklist) có tiến độ, **thẻ tag**, **ưu tiên P1–P4**, **ghim ★**, **lặp lại** (hàng ngày / ngày tuần / hàng tuần / hàng tháng – hết hạn tự tạo lần kế tiếp).
- **Lịch chọn ngày** ngay trong panel chi tiết.
- **Kéo thả** đổi thứ tự (chế độ Thủ công), **chuột phải** đầy đủ menu: hoàn thành, ghim, chuyển danh sách, nhân bản, xóa.
- **Chọn nhiều** (bulk mode): hoàn thành / ghim / xóa hàng loạt.

**Liquid glass (v2.0)**
- Nền aurora tím–lam–hồng sâu trên nền navy, phủ **hạt nhiễu SVG** chống banding.
- Panel kính thật **backdrop-filter blur + saturate**, viền sáng 1px, specular đỉnh, gloss chéo, bóng nổi — đúng tinh thần Glass-1/2/3 trong ảnh mẫu.
- Ô thêm nhanh có **tia sáng lướt** khi nhập; nút chủ đạo glow indigo; shimmer trên thẻ "Tổng thể".
- Chế độ **Tối / Sáng** đầy đủ (Ctrl+D).

**Cài đặt & cá nhân hóa (v2.1)**
- Tab **Cài đặt** (Ctrl+8): toàn bộ tùy chỉnh gom một chỗ — không cần sửa code hay file cấu hình.
- **Màu nhấn tùy chọn**: 8 swatches dựng sẵn + **chọn màu bất kỳ** + nhập **mã hex** (#rrggbb) — nút, tiến trình, biểu đồ, điểm nhấn khắp app đổi theo tức thì.
- **Cửa sổ trong suốt Acrylic thật** (Windows): thấy và làm mờ màn hình desktop phía sau cửa sổ như liquid glass thật sự, chỉnh **độ phủ màu** (40–170).
- **Giảm hiệu ứng chuyển động** (trợ năng), **xem trước phân tích** khi thêm nhanh, **nhắc việc hôm nay** khi mở app, **tự sao lưu khi thoát**.
- **Đặt lại cài đặt gốc** một chạm (giữ nguyên dữ liệu việc làm).
- **Thanh cuộn liquid glass tự ẩn** — chỉ hiện khi rê chuột vào lề phải hoặc khi lăn con lăn; mượt, viền kính, có đổ sáng.
- Chuyển **Tối/Sáng** và đổi **màu nhấn** giờ chuyển mượt toàn cục (kể cả gradient) — không giật, không nhấp nháy.
- Sửa menu ⋮ bị nội dung trang phủ lên (topbar luôn nằm trên vùng nội dung).

**Hiệu năng & nơi lưu dữ liệu (v2.2)**
- **Cuộn được ở mọi tab** — sửa triệt để layout chiều cao (hàng grid `100vh` + `min-height:0`) trước đây khiến nội dung Cài đặt/Thống kê bị cắt cụt.
- **Nhẹ hơn đáng kể**: task row chỉ render khi gần trong khung nhìn (`content-visibility`), và **Chế độ hiệu năng** (Cài đặt → Giao diện) tắt toàn bộ blur/animation/hạt nhiễu cho máy yếu.
- **Tuỳ chỉnh nơi lưu dữ liệu** (Cài đặt → Nơi lưu dữ liệu): mặc định `%APPDATA%\Taskora`, thư mục tuỳ chọn, hoặc **portable** (mọi thứ lưu cạnh file thực thi — hợp USB/đồng bộ đám mây).
- **Tự phát hiện di chuyển**: nếu Taskora.exe bị copy lẻ sang chỗ trống, app hỏi chuyển dữ liệu portable cũ sang. Nếu bạn chạy ở nơi khác mà `%APPDATA%` còn dữ liệu v1/v2.0 cũ, app hỏi **gộp** (id-union, không trùng lặp).
- **Khôi phục view đang mở** giữa các lần chạy; toast hành động kèm nút **Hoàn tác** sau mỗi thao tác.

**Vá v2.10.1 — dễ thấy & dễ chỉnh**
- Nút mở **cửa sổ Đồng hồ** trên overlay giờ là pill có chữ “↗ Đồng hồ” (trước là icon đơn độc, dễ bị bỏ lỡ).
- Ô phút trong Cài đặt → Tập trung **áp dụng ngay khi gõ** (không cần rời khỏi ô/Enter); chip bấm vẫn ăn ngay.
- Thêm dòng gợi ý trong Cài đặt: mở cửa sổ Đồng hồ từ overlay hoặc Ctrl+K → “Mở cửa sổ đồng hồ”; quyền `start-dragging` để kéo cửa sổ Đồng hồ chắc chắn hoạt động.
- Nếu cửa sổ Đồng hồ không mở được, toast hiện **lý do lỗi thật** (để báo lại dễ dàng).

**Vá v2.10.2 — cửa sổ Đồng hồ hoạt động thật & tự mở khi bắt đầu phiên**
- Sửa gốc lỗi “cửa sổ trắng, treo, không đóng được”: cửa sổ Đồng hồ giờ là **cửa sổ đục (opaque) có khung native** thay vì frameless trong suốt — tránh lỗi compositing của WebView2 trên Windows (cửa sổ trong suốt thứ hai không paint được). Khung native luôn có nút **Đóng** (Alt+F4 cũng hoạt động), `Escape` đóng đồng hồ (phiên vẫn chạy).
- **Mặc định tự mở cửa sổ Đồng hồ khi bạn bấm “Tập trung”** — always-on-top, tách riêng khỏi cửa sổ chính; tắt được trong Cài đặt → Tập trung → “Tự mở cửa sổ Đồng hồ khi bắt đầu phiên”.

**Vá v2.10.3 — FIX GỐC lỗi cửa sổ Đồng hồ trắng/treo**
- Nguyên nhân đúng (theo tài liệu WebView2/Tauri): tạo cửa sổ web mới bên trong **command đồng bộ** ⇒ deadlock vòng lặp thông điệp WebView2 trên Windows ⇒ cửa sổ trắng không vẽ được gì, ứng dụng đơ, khung đóng cũng vô hiệu.
- `focus_open_timer` giờ là **async command** (chạy trên thread riêng) — cửa sổ Đồng hồ được tạo như tài liệu Tauri khuyến nghị; vẫn là cửa sổ đục + khung native luôn đóng được.

**Vá v2.10.4 — đồng bộ cửa sổ Đồng hồ & rà logic**
- **Bấm “Dừng” → cửa sổ Đồng hồ đóng theo**, dù bấm từ overlay trong app chính hay từ ngay trong cửa sổ Đồng hồ.
- **“Bắt đầu lại” ngay trên màn “Xong” chạy lại phiên mới ngay** (trước bị kẹt ở trạng thái tạm dừng với đồng hồ đầy — bấm không thấy gì xảy ra).
- Đồng hồ trong app chính và cửa sổ Đồng hồ **không thể lệch bản ghi đè cũ**: mọi chuyển phase đọc lại trạng thái thật từ engine (wall-clock), kể cả khi bạn bấm Reset đúng khoảnh khắc đồng hồ về 0.
- **Nhắc mắt 20-20-20 cũng hiện trong cửa sổ Đồng hồ** (pill nổi, tự ẩn, tôn trọng tuỳ chọn chuông) — không chỉ trong overlay chính.

**v2.12.1 — Vá triệt để “bấm X xong còn tiến trình chạy” (lỗi từ trước v2.12.0)**
- Nguyên nhân gốc: mọi lần chạy đều **tạo sẵn một cửa sổ Thông báo ẩn** (luôn sống để gửi thông báo tức thì). Bản ≤ v2.11.x khi bấm X thì cửa sổ chính **bị đóng/destroy**, còn cửa sổ Thông báo ẩn giữ event-loop sống → `Taskora.exe` chạy ngầm, không cửa sổ, không icon. v2.12.0 đã đổi X sang hỏi/tray/thoát nhưng vẫn còn lỗ hổng: **tray hỏng/không tạo được mà vẫn hide cửa sổ** (kể cả khi tự khởi động ẩn).
- Bản vá: **mọi quyết định “ẩn vào khay” đều bắt buộc qua kiểm tra tray đã tạo thành công** — X (“Thu vào khay”), nút "Thu vào khay" trong modal hỏi, và “Mở ẩn trong khay khi tự khởi động”. Tray không sẵn sàng ⇒ **thoát hẳn thay vì ẩn**; tự khởi động ẩn không áp dụng ⇒ cửa sổ chính hiện ra bình thường. Không bao giờ còn tiến trình Taskora chạy vô hình.
- **Cài đặt gọn hơn**: tách **“Khay hệ thống & phím tắt”** thành nhóm accordion riêng (sau nhóm Giao diện) — Giao diện còn 8 dòng, nhóm Khay gom Đóng cửa sổ chính · Tự khởi động · Phím tắt toàn cục; “Chế độ ADHD” và “Âm thanh khi hết giờ phiên” chuyển sang nhóm **Tập trung**. Không đổi id/hành vi, badge “N dòng” tự tính lại.
- Chi tiết kỹ thuật & nghiệm thu: `specs/v2.12.1-hotfix-zombie.md`.

**v2.12.0 — Sống ở khay hệ thống, tự khởi động, phím tắt toàn cục**
- **Icon khay luôn hiện** (liquid glass, menu chuẩn): click trái bật/tắt cửa sổ chính; chuột phải mở menu — header `Taskora — N việc hôm nay[ · M quá hạn]`, **Việc hôm nay** (chuyển thẳng view Hôm nay), **Mở Taskora**, separator, **Thoát**.
- **Bấm nút X không còn thoát cứng**: lần đầu hỏi “Đóng Taskora?” (Thu vào khay / Thoát hẳn, **Ghi nhớ** mặc định tick, focus khởi đầu ở **Thu vào khay**; Esc/backdrop = đóng modal, không làm gì). Đổi lại bất cứ lúc nào: **Cài đặt → Giao diện → Khi đóng cửa sổ chính** (Hỏi · Thu vào khay · Thoát).
- **Tự khởi động cùng Windows** (mặc định TẮT) — tự chữa đường dẫn khi exe di chuyển; sub-toggle **“Mở ẩn trong khay khi tự khởi động”** (mặc định BẬT, chỉ hiện khi autostart bật).
- **Phím tắt toàn cục Ctrl + Alt + T** (đổi được, khớp mọi layout bàn phím): hiện/ẩn cửa sổ chính từ mọi ứng dụng. Tổ hợp hợp lệ = ít nhất 1 phím Ctrl/Alt/Shift/Win + một phím A–Z/0–9/F1–F12; Backspace/Delete khôi phục mặc định; Esc hủy; tổ hợp bị app khác chiếm sẽ tự quay về phím cũ và báo lỗi. Bật/tắt riêng qua toggle **Phím tắt toàn cục**.
- Thoát hẳn vẫn đảm bảo sao lưu (nếu bật “Tự sao lưu khi thoát”) trước khi đóng — mọi cổng thoát đều đi qua một đường duy nhất.

**v2.11.2 — Vá 4 lỗi trải nghiệm: focus treo, thông báo chồng & chậm, việc lặp nhảy hero**
- **Dừng Đồng hồ ở cửa sổ Đồng hồ giờ cập nhật ngay mọi nơi** — hero “Việc tiếp theo” không còn đông cứng ở giây bị dừng; chip trên topbar và overlay cũng đồng bộ theo engine (mọi thay đổi focus phát sự kiện `taskora:focus` cho cả app).
- **Thông báo không còn chồng/bóp lên nhau** — thẻ không cho co trong container đo lường và cửa sổ Thông báo tự đo lại chiều cao tức thì (không phụ thuộc vòng vẽ của cửa sổ ẩn) nên nhiều thẻ hiện cùng lúc luôn tách rõ, nội dung không bị cắt.
- **Thông báo đến gần như ngay** — cửa sổ Thông báo được tạo sẵn (ẩn) lúc khởi động; thẻ gắn hiệu ứng hiện bằng flush style đồng bộ và tự ẩn luôn có bộ đếm dự phòng — không còn cảnh đợi vài giây mới thấy.
- **Bấm “Xong” trên việc lặp hằng tháng trong Hộp thư không còn “nhảy thẳng sang tháng sau”** — hero bỏ qua việc hẹn tương lai (instance lặp kế tiếp nằm ở Sắp tới như đúng vị trí), hero tự chuyển sang việc khả dụng tiếp theo hoặc trạng thái trống.
- Chi tiết kỹ thuật & CI: commit vá trên nhánh `arena/07cb4854-arenaaiworkspace-1`.

**v2.11.1 — Thông báo tách khỏi cửa sổ app chính**
- **Cửa sổ THÔNG BÁO riêng** thay cho thẻ nằm trong cửa sổ app chính: cửa sổ frameless, trong suốt, luôn nổi ở góc dưới-phải màn hình — thông báo đến ngay cả khi cửa sổ Taskora đang thu nhỏ hoặc bị che. Không chiếm taskbar, không cướp focus; kích thước tự co giãn theo số thẻ và tự ẩn hẳn khi hết thông báo.
- Nút hành động trong thẻ (ví dụ **Hoàn tác**) vẫn chạy đúng lệnh ở cửa sổ chính — chỉ id đi qua IPC, closure không rời cửa sổ chính.
- Vá thêm: âm thanh tùy chỉnh (data URI) giờ thực sự phát được — CSP thiếu `media-src data:` ở bản v2.11.0 chặn im lặng loại âm này.
- Thanh trạng thái/tiến trình thẻ, hover tạm dừng, tự ẩn 3/5/8/10s, mọi cấu hình “Cài đặt → Thông báo” giữ nguyên — chỉ đổi *nơi hiển thị*.

**v2.11.0 — Thông báo của Taskora & tách mã nguồn**
- **Thông báo đẩy (push notification) kiểu Taskora** thay thế hoàn toàn toast cũ: thẻ nổi góc dưới-phải (tối đa 3 thẻ, dư thì xếp hàng), nền kính mờ đục, viền sáng, icon theo loại; **tự ẩn sau N giây** với thanh tiến trình — **rê chuột vào để giữ lại** (hết giờ tự ẩn trở lại sau khi rời chuột); tắt tự ẩn được để thông báo bám màn hình cho tới khi bạn đóng.
- **8 loại thông báo, tùy chỉnh từng loại** (Cài đặt → **Thông báo**): phiên tập trung xong · nghỉ xong · việc đến hạn hôm nay · việc quá hạn · lỗi lưu trữ · hợp nhất dữ liệu · thông tin · lỗi. Mỗi loại bật/tắt riêng và chọn âm thanh riêng: **3 nốt / Chuông gió / Không / Âm tự chọn** (tối đa 4 file âm thanh tuỳ chỉnh, mỗi file ≤ 256 KB, lưu trong data.json) — có nút *Nghe thử* cho từng loại và nút **Gửi thử thông báo** để kiểm tra toàn bộ.
- **Tắt/bật toàn cục**: “Bật thông báo” và “Bật âm thanh thông báo” — khi tắt âm vẫn hiện thẻ, khi tắt hẳn thì không hiện gì. Tôn trọng **Giảm chuyển động** và **Chế độ hiệu năng** của app.
- **Đồng hồ phiên tập trung giờ mặc định chỉ nằm ở cửa sổ Đồng hồ riêng** (luôn nổi, kéo được, đóng được nhưng phiên vẫn chạy) — chọn **Cài đặt → Tập trung → “Đồng hồ hiển thị ở đâu”**: *Cửa sổ Đồng hồ (mặc định)* · *Trên app chính (overlay)* · *Cả hai*. Khi phiên đang chạy, topbar hiện **chip đếm ngược** (chấm tím nhấp nháy, tạm dừng thì hổ phách, xong phiên thì xanh lá) — bấm chip để gọi lại cửa sổ Đồng hồ.
- **Cài đặt chia nhóm thu gọn (accordion)**: Giao diện · Tập trung · Thông báo · Việc & danh sách · Dữ liệu & sao lưu · Nơi lưu dữ liệu · Khác — mỗi nhóm mở/đóng độc lập, app nhớ trạng thái thu gọn giữa các lần mở.
- **Tách mã nguồn**: monolith `app.js` đã được tách thành 13 module ES (`js/`) + CSS theo từng phần (`styles/`) — mã nguồn dễ đọc, dễ bảo trì hơn nhiều; **không giữ shim** cho `app.js` cũ.
- Tương thích dữ liệu tuyệt đối: backup cũ mở bằng v2.11.0 không đổi gì (field mới có `serde(default)`); build cũ bỏ qua field lạ.
- Thiết kế đầy đủ: [specs/v2.11.0-notifications-and-architecture.md](specs/v2.11.0-notifications-and-architecture.md).

**Vá v2.10.5 — Đồng hồ phiên tập trung ra giữa cửa sổ & to hơn**
- Màn phiên toàn màn trong app chính (overlay) trước giờ bị **dính mép trái** do `.overlay` không căn giữa — giờ **căn giữa hoàn toàn** (ngang + dọc).
- Vòng đồng hồ **216 → 308px**, số phút **44 → 62px**, tên việc to hơn, vòng thở 138 → 172px — đúng như chế độ tập trung toàn màn phải có.

**Phiên tập trung của bạn — tuỳ biến tận gốc (v2.10.0)**
- **Mọi con số quanh phiên tập trung đều chỉnh được** (Cài đặt → **Tập trung**, nhóm mới): thời lượng phiên 5–180′ (chip nhanh 15/25/45/50/90 + gõ tự do, mặc định 25) · nghỉ ngắn 1–60′ · nghỉ dài 5–60′ · **chu kỳ pomodoro** “nghỉ dài sau mỗi N phiên” (mặc định 4, chọn Tắt nếu không muốn) · **tự bắt đầu nghỉ khi hết giờ** và **tự bắt đầu lại cùng việc sau khi nghỉ** (mặc định **TẮT** — không ép nhịp) · nhắc nghỉ mắt **20-20-20** tắt/bật được · kiểu chuông cuối phiên: **3 nốt / Chuông gió / Không** (có nút *Nghe thử*).
- **Nút “Bắt đầu lại” (Reset)** ngay trên đồng hồ — về đầy thời gian, giữ việc + chế độ + chu kỳ, không ghi nhận phiên; phím **R** làm y vậy. Không còn phải thoát hẳn khi lỡ nhịp.
- **Cửa sổ “Đồng hồ” riêng, luôn nổi** (mở từ nút ↗ trên overlay, hoặc Ctrl+K → “Mở cửa sổ đồng hồ”): đếm ngược sống ở góc màn hình trong khi bạn làm việc khác; có nút ghim always-on-top, nút đóng (phiên vẫn chạy), kéo cửa sổ bằng thanh tiêu đề. Overlay và cửa sổ đồng hồ **luôn khớp tuyệt đối** — thời gian do Rust tính theo đồng hồ thật (wall-clock), không phải đếm lùi bằng setInterval.
- **Đồng hồ không lệch khi máy ngủ/minimize**; cả hai cửa sổ nghe chung một state machine Rust (`focus:change`); hết giờ chỉ chuyển phase **một lần duy nhất** (cửa sổ bấm trước thắng — không chuông đúp, không ghi thống kê đúp).
- **“25 phút” không còn hard-code**: nút hero ADHD, overlay, dòng kết thúc phiên, cửa sổ đồng hồ đều lấy theo cấu hình; dòng tiến độ “Hôm nay đã xong N việc · M phiên”.
- Dữ liệu cũ hoàn toàn tương thích: backup v2.8.0/v2.9.0 mở bằng v2.10.0 không đổi gì (các field mới có `serde(default)`); build cũ bỏ qua field lạ, chỉ mất hiệu lực 8 tinh chỉnh mới.
- Thiết kế đầy đủ: [specs/v2.10.0-focus-customization.md](specs/v2.10.0-focus-customization.md).

**Việc lặp lại hạng nhất (v2.9.0 — đã phát hành)**
- **Quy tắc đầy đủ**: tần suất **Ngày / Tuần / Tháng / Năm** · khoảng lặp tuỳ ý (`*mỗi 3 ngày`, `*mỗi 2 tuần`, `*mỗi 6 tháng`, `*mỗi 2 năm`) · chọn thứ trong tuần (tuần) · ngày trong tháng gồm **“ngày cuối cùng”** · kết thúc: **Không bao giờ / Đến ngày / Sau N lần hoàn thành**.
- **Bảng lịch xem trước (ghost calendar)** ngay trong hộp thoại “Lặp lại” (Chi tiết → **Chỉnh…**): chấm tím ở mọi ngày việc sẽ xuất hiện; **bấm vào ngày để đặt ngày kết thúc**; chip nhanh **+1 / +3 / +6 tháng** và **Cuối năm**; đếm **“≈ N lần nữa”**; đầy đủ bằng bàn phím (lưới `role=grid`).
- **Câu tóm tắt tiếng Việt cập nhật trực tiếp**: *“Mỗi 2 tuần · T2 & T5 · đến 31/12/2026”* — preview lấy 100% từ cùng thuật toán với bản chạy thật (Rust), không mô phỏng bằng JS.
- **“Bỏ qua lần này”** một chạm (nghỉ ốm, bận việc) — dời lần lặp tới, hoàn tác được; **“Dừng lặp lại”** giữ nguyên như v2.8.0. Việc lặp đã hết hạn (đến ngày / đủ N lần) mà chưa xong sẽ tự thành việc thường.
- **Quick-add hiểu khoảng lặp**: `*mỗi 3 ngày`, `*mỗi 2 tuần`, `*mỗi 6 tháng`, `*mỗi 2 năm` (cũng hiểu *mỗi tuần, *every 3 days; thiếu số = 1).
- **Tương thích ngược**: việc lặp cũ (`*hàng ngày`…) tự nâng cấp sang rule mới khi mở file — giữ nguyên dữ liệu, mở bằng build cũ không sinh bản sao sai.
- Thiết kế đầy đủ: [specs/v2.9.0-recurring-tasks.md](specs/v2.9.0-recurring-tasks.md).

**Tuỳ chỉnh cao — seed không còn hành vi ẩn (v2.8.0)**
- **Sửa parser cho cú pháp lặp tiếng Việt**: `*hàng ngày` / `*hàng tuần` / `*hàng tháng` (kể cả `*hang tuan`) giờ được hiểu đúng — tiêu đề KHÔNG dính chữ rác `*hàng` nữa. (Đây là lý do bản v2.7.0 in hướng dẫn `*hàng ngày` mà gõ vào lại ra việc tên "Tập gym *hàng".)
- **Việc mẫu "Tập thể dục 30 phút" giờ là việc thường** — hoàn thành KHÔNG tự sinh việc mới; mọi việc mẫu xoá/sửa/nhân bản bình thường. Việc lặp chỉ xảy ra khi *bạn* chủ động gõ cú pháp lặp hoặc chọn trong ô **Lặp lại**.
- **Nút "Dừng lặp lại" một chạm** ngay dòng ghi chú dưới ô Lặp lại — dừng việc lặp không cần mò ô chọn.
- Trợ giúp thêm mục dọn các lần lặp cũ: tab **Đã hoàn thành** → **Chọn** → tick → **Xóa**.
- Chi tiết: [specs/v2.8.0-customizability.md](specs/v2.8.0-customizability.md).

**Việc lặp lại & Sắp tới — thiết kế chỉn chu (v2.7.0)**
- **Hiểu ngay việc lặp lại là gì**: hàng việc hiện chip *"Lặp: Hàng ngày"* (tông tím); panel chi tiết có cờ bấm được *"Lặp: …"* (bấm → focus ô **Lặp lại**).
- **Biết lần tiếp theo là ngày nào**: dòng ghi chú ngay dưới ô Lặp lại — *"Hoàn thành xong → lần tiếp theo: Thứ Hai, 17/11/2026 · dừng bằng cách chọn “Không lặp”"* (khớp đúng quy tắc của app; Ctrl+Z hủy cả hoàn thành lẫn lần vừa tạo).
- **Hoàn thành xong**: toast *"✓ Xong — lần tiếp theo: Thứ Hai, 17/11/2026"* — không còn ai phải đoán tại sao việc lại quay về.
- **View Sắp tới thành agenda theo ngày**: header gom nhóm ("Ngày mai · 12/11/2026", "T6 · 14/11/2026") kèm số việc mỗi nhóm (khi sắp xếp theo hạn chót).
- **Dòng chú thích** nhắc việc lặp lại chỉ hiện một lần (Hôm nay / Sắp tới).
- Sửa kèm: nút hành động trên hàng việc (nhân bản/xóa) giờ hiện cả khi **Tab tới bàn phím**; chip "quá hạn" viết rõ số ngày ("quá hạn 5 ngày"); việc mẫu "Tập thể dục 30 phút" tự giải thích là ví dụ việc lặp lại.
- Chi tiết: [specs/v2.7.0-recurring-upcoming.md](specs/v2.7.0-recurring-upcoming.md).

**Sửa lỗi theo phản hồi + mẫu riêng của bạn (v2.6.0)**
- **Mọi hộp thoại bấm được rồi**: nút trong Brain-dump / xác nhận xóa / đổi cài đặt… — trước đây click vào trong modal có thể bị lớp nền nuốt mất (modal đóng ngay, không lưu được). Sửa triệt để: panel nổi trên backdrop, chỉ bấm ra ngoài (backdrop) hoặc nút đóng mới đóng.
- **"Xóa vĩnh viễn" trong Thùng rác giờ luôn hoạt động**: bấm ở panel chi tiết (và ở nút hàng, menu chuột phải) → hộp xác nhận rõ ràng → xóa hẳn (vẫn hoàn tác Ctrl+Z được ngay sau đó). Việc thường vẫn đi vào Thùng rác như cũ.
- **Mẫu chia nhỏ tự tạo**: phần "Chia nhỏ: bước tiếp theo" giờ là **ô sửa được** — sửa từng bước, xóa dòng, thêm dòng (tối đa 12). Lưu bộ bước hiện tại thành **mẫu riêng** (ví dụ "Viết báo cáo tuần"), bấm chip để áp dụng lại bất cứ lúc nào, nút × để xóa mẫu (có **Hoàn tác**). Mẫu được lưu theo dữ liệu app, đi theo bản sao lưu/xuất. Không cần AI.
- Chi tiết: [specs/v2.6.0-fixes.md](specs/v2.6.0-fixes.md).

**Hoàn thiện app To-do (v2.5.0)**
- **Brain-dump**: nút bút chì cạnh ô thêm nhanh (hoặc **Ctrl+Shift+N**, hoặc palette "Brain-dump") — mở ô nhập lớn, **mỗi dòng một việc**, không cần sắp xếp. Ctrl+Enter để đổ vào Hộp thư: parser tự nhận diện ngày/#tag/!p1/lịch lặp cho từng dòng. **Một thao tác hoàn tác** xóa sạch cả mẻ đổ.
- **Bước nhỏ nhất tiếp theo** (không cần AI): trong panel chi tiết việc → **"Chia nhỏ: bước tiếp theo"** — từ điển tiếng Việt cục bộ tự gợi ý 3–6 micro-step (ví dụ "viết báo cáo" → mở file → dàn ý 3 mục → viết mục 1…). Thêm vào "việc nhỏ" bằng 1 bấm, một thao tác hoàn tác.
- **Thống kê phiên tập trung**: app đếm số phiên 25′ bạn hoàn thành mỗi ngày (lưu trong dữ liệu app); xem ở **Thống kê** ("Phiên tập trung hôm nay" / "7 ngày qua") và ở thẻ TIẾP THEO ADHD ("Hôm nay đã xong N việc · M phiên 25′").
- **Âm thanh khi hết giờ phiên**: chime 3 nốt nhẹ (Web Audio, offline). Bật/tắt trong **Cài đặt → Âm thanh khi hết giờ phiên** (mặc định bật).
- **Nhắc nghỉ mắt 20-20-20**: trong phiên tập trung, đúng mốc trôi 20 phút → pill nhắc *"nhìn xa ~6m · 20 giây"* hiện một lần (đếm ngược 20→0, không chặn gì, tôn trọng reduce-motion).
- Chi tiết: [specs/v2.5.0-features.md](specs/v2.5.0-features.md). Tầm nhìn Hub all-in-one (roadmap, **chưa làm**): [specs/hub-vision.md](specs/hub-vision.md).

**Giao diện ADHD thiết kế riêng (v2.4.0)**
- **Thẻ TIẾP THEO giờ là hero**: tiêu đề 22px, đồng **live HH:MM** ngay trong thẻ (mỏ neo thời gian — chống time blindness), nút **Tập trung 25 phút** to 50px chiếm chỗ chính, nút **Xong**; dòng tiến độ tích lũy *"Hôm nay đã xong N việc"* (chỉ cộng, không bao giờ trừ/về 0 — không streak, không quota).
- **Giao diện bớt lựa chọn**: ẩn hàng chip ví dụ "Thử ngay…", thanh công cụ mờ còn 55% (trở lại rõ khi rê chuột), chữ việc lớn hơn, nút menu to hơn dễ bấm.
- **Hai trạng thái phiên khác nhau hẳn**: phiên tập trung có dòng *"Bây giờ là HH:MM"*; khi nghỉ 5 phút, vòng đếm ngược **biến mất** và nhường chỗ cho **vòng thở** ("Hít vào… 4 giây / Thở ra… thật chậm 6 giây") — focus là làm, break là điều tiết thần kinh.
- **Empty-state dịu**: *"Xong hết rồi ✦ — Nghỉ thật sự, không còn gì chờ bạn"*.
- Chi tiết: [specs/adhd-mode.md](specs/adhd-mode.md) (mục 7).

**Chế độ ADHD — dành riêng cho não ADHD (v2.3.0)**
- **Một việc tại một thời điểm**: thẻ **TIẾP THEO** ghim đầu danh sách — chỉ hiện việc kế tiếp (tôn trọng sort/filter đang dùng), hai nút: **Tập trung 25′** và **Xong**. Hết việc → dòng dịu "Không còn việc nào — nghỉ xíu đi." Không bắt bạn chọn giữa 20 việc; triệt tiêu decision paralysis.
- **Phiên tập trung 25 phút** (Esc để dừng, Space = tạm dừng/tiếp tục): vòng tròn đếm ngược SVG trực quan (chống time blindness), chỉ 1 việc trên màn hình, copy luôn ấm — hết giờ có màn celebrate và lựa chọn **Nghỉ 5 phút** hoặc **Việc tiếp theo**. "Dừng lại — không sao" nghĩa là dừng lại thì chẳng sao cả.
- **Thưởng tức thì**: confetti nổ ngay khi hoàn thành việc (mọi đường: bấm checkbox, Space, thẻ TIẾP THEO) + câu cổ vũ ngẫu nhiên — phần thưởng đến đúng "now", không cần streak. Không có streak nào bị đứt, không có điểm nào bị trừ: **không thể gây shame**.
- **Ngôn ngữ không phán xét**: banner quá hạn chuyển hổ phách, "Chưa kịp lần này — N việc chờ tới lúc bạn sẵn sàng"; mọi copy mới đều ấm.
- **Giao diện dịu**: tắt hạt nhiễu nền, vùng bấm lớn hơn, focus ring rõ hơn. Quick-add placeholder xoay vòng gợi ý "chỉ cần 1 việc nhỏ nhất".
- Bật trong **Cài đặt → Giao diện → Chế độ ADHD**. Chi tiết thiết kế: [specs/adhd-mode.md](specs/adhd-mode.md).

**Trong suốt theo đúng điều kiện Windows (v2.2.4)**
- **Biết lý do trong suốt không hiện**: Taskora đọc công tắc **Transparency effects** của Windows (registry `HKCU\…\Personalize\EnableTransparency`). Thiếu điều kiện này thì Acrylic không thể hiển thị — trước đây app không nói gì, giờ thì nói rõ.
- **Bật trong suốt thì điều kiện phải được đảm bảo**: khi bạn gạt "Trong suốt Acrylic" mà Transparency effects đang TẮT, Taskora hiện hộp thoại hỏi bạn cho phép bật giúp (chỉ ảnh hưởng tài khoản Windows hiện tại). **Từ chối → Taskora tự chuyển về nền đặc**, không giữ "trong suốt" khi không dùng được. Từ chối/mất điều kiện ở mọi thời điểm (kể cả lúc khởi động) đều được ép về nền đặc.
- **Trong Cài đặt → Giao diện có dòng "Transparency effects (Windows)"** với pill BẬT/TẮT/Không rõ và nút **Bật/Tắt** toàn hệ thống — tắt tại đây thì Taskora tự rời nền trong suốt; bật lại thì acrylic được áp ngay.
- **Kéo cửa sổ hết khựng/delay**: trên Windows 11 22H2+ app dùng `DWMSBT_TRANSIENTWINDOW` (DWM tự xử lý, GPU-composited — không còn khựng); Windows cũ hơn tự fallback SWCA (có thể khựng — giới hạn của Windows). Trước đây v2.2.3 luôn dùng SWCA nên kéo bị lag.
- Trạng thái hiệu ứng hiển thị luôn tình trạng Transparency effects (BẬT/TẮT/không đọc được).

**Độ phủ Acrylic chỉnh được thật sự (v2.2.3)**
- **Thanh trượt "Độ phủ màu Acrylic" giờ có tác dụng trên mọi bản Windows** — app tự gọi `SetWindowCompositionAttribute(ACCENT_ENABLE_ACRYLICBLURBEHIND)` với tint lấy từ slider. Trước đây trên Windows 11 22H2+, DWM bỏ qua tint hoàn toàn nên kéo slider không thấy gì.
- Thanh trượt đồng thời điều khiển **độ đục của lớp nền và panel** (biến `--cov`): kéo là nền mờ dần ngay khi đang trong chế độ Trong suốt, không cần đợi DWM.
- Dọn DWMSBT cũ còn sót từ các bản trước khi tắt Trong suốt.

**Trong suốt & màu sắc (v2.2.2)**
- **Nền aurora đi theo màu nhấn**: đổi Màu nhấn là toàn bộ nền (gradient, aurora tối/sáng) đổi theo hue tương ứng — không chỉ nút bấm nữa.
- **Acrylic trong suốt thật sự trong hơn hẳn**: lớp nền và panel giảm alpha mạnh (nhìn xuyên qua desktop rõ rệt), thêm dòng **Trạng thái hiệu ứng** trong Cài đặt cho biết DWM trên máy bạn đã bật Acrylic/Blur thành công hay chưa (tiện tự chẩn đoán).
- Sửa triệt để hành vi IPC khi đang ở view Cài đặt/Thống kê (một số lệnh gửi `view` không hợp lệ khiến backend báo lỗi).

**Hoàn thiện (v2.2.1)**
- **Sửa triệt để card Cài đặt/Thống kê bị ép co & cắt cụt nội dung** (flex children mặc định `flex-shrink:1` trong container co giãn).
- **Hiệu ứng hoàn thành việc**: checkbox pop nảy lò xo + vòng xanh tỏa ra, gạch ngang chữ quét từ trái sang, flash xanh nhạt cả hàng; thả ghim ★ cũng bật pop.
- Font được **preload**, logo About lazy-load, edge-hover thanh cuộn được throttle bằng rAF.
- Hỗ trợ GPU sẵn có: WebView2 (Chromium) render bằng DirectComposition/ANGLE trên GPU, Acrylic do DWM Windows xử lý — không cần cờ gì thêm.

**Trải nghiệm**
- **Tìm kiếm** toàn bộ (Ctrl+K mở bảng lệnh nhanh: điều hướng + tìm việc), lọc theo **thẻ**, lọc Ưu tiên P1–P4, ẩn/hiện đã hoàn thành, 5 kiểu sắp xếp.
- **Hoàn tác / Làm lại** (Ctrl+Z / Ctrl+Y) tới 80 bước.
- **Thống kê**: việc đang làm, xong hôm nay, quá hạn, chuỗi ngày liên tiếp, biểu đồ cột 14 ngày, tiến độ theo danh sách, theo thẻ.
- **Lưu tự động** vào `%APPDATA%\Taskora\data.json`; **xuất / nhập bản sao lưu** một chạm; mở thẳng thư mục dữ liệu.
- Phím tắt: `Ctrl+N` thêm · `Space` đánh dấu xong · `↑↓` chọn · `Alt+↑↓` đổi thứ tự · `Esc` đóng · `Ctrl+1…8` chuyển view.
- **Icon Phosphor** (MIT), font **Be Vietnam Pro** (OFL) nhúng sẵn.

## 🛠️ Xây dựng từ nguồn

```bash
# Yêu cầu: Rust stable + Node 20 + Tauri CLI
cargo test --manifest-path src-tauri/Cargo.toml   # test parser + model + storage
npm i --no-save jsdom@24 && node scripts/smoke.mjs  # smoke frontend (jsdom, 26 assertion)
npm install -g @tauri-apps/cli@^2
tauri dev          # chạy thử (hot reload frontend)
tauri build        # → src-tauri/target/release/Taskora.exe (+ NSIS installer)
```

CI (**GitHub Actions**, `windows-latest`) chạy test + `tauri build` ở **mọi lần push** và tự upload artifact; push tag `v*` → tạo **GitHub Release** với cả `Taskora.exe` và `Taskora-Setup-x64.exe`.

## 🧱 Công nghệ

| Thành phần | Lựa chọn |
|---|---|
| Shell | [Tauri v2](https://v2.tauri.app) (WebView2 trên Windows) |
| Backend | Rust — core `models / parser / storage` (dùng lại nguyên từ v1, có unit-test) |
| Frontend | HTML + CSS + Vanilla JS (backdrop-filter liquid glass), không framework |
| Lưu dữ liệu | `serde` + `serde_json` (JSON trong `%APPDATA%\Taskora`) |
| Icon | [Phosphor Icons](https://phosphoricons.com) (MIT) — SVG sprite inline |
| Font | Be Vietnam Pro (OFL) |

## 📁 Cấu trúc

```
src-tauri/            ← backend Rust (Tauri)
  src/models.rs       ← Store / Task / List / View / Priority / Repeat (+ test)
  src/parser.rs       ← phân tích thêm việc nhanh (+ test)
  src/storage.rs      ← load/save JSON, sao lưu, khôi phục (+ test)
  src/commands.rs     ← toàn bộ lệnh IPC (snapshot / act / quick_add / stats / backup)
  src/state.rs        ← AppState: undo/redo + lưu tự động + flash
  src/stats.rs        ← thống kê (streak, 14 ngày, theo list/thẻ)
  tauri.conf.json     ← cửa sổ, CSP, bundle NSIS, icon
src-ui/               ← frontend (index.html, styles.css, app.js) — liquid glass
  assets/fonts/       ← Be Vietnam Pro
.github/workflows/    ← pipeline build Windows
```

## 🙏 Nguồn tài nguyên

- [**Be Vietnam Pro**](https://fonts.google.com/specimen/Be+Vietnam+Pro) – font tiếng Việt (SIL Open Font License).
- [**Phosphor Icons**](https://phosphoricons.com) – bộ icon (MIT).
- Thiết kế tham chiếu: Apple **Liquid Glass** (WWDC 2025) và các bản tái hiện CSS công khai.

## 📄 License

MIT
