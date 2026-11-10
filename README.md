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
