# Taskora 📝

**Ứng dụng quản lý công việc (to-do) cho Windows** – giao diện **liquid glass** chuẩn Apple, viết 100% bằng **Rust** (Tauri v2 + frontend web nhẹ, không framework).

![Build](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/workflows/ci.yml/badge.svg)

## ⬇️ Tải file .exe

1. Vào tab **[Actions](https://github.com/Hthancder/ArenaAIWorkspace-1/actions)** → chọn bản build gần nhất (workflow **Build**).
2. Tải `Taskora-Windows-x64` → có cả `Taskora.exe` (chạy ngay) lẫn `Taskora-Setup-x64.exe` (bản cài đặt NSIS).
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
