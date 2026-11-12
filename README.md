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
