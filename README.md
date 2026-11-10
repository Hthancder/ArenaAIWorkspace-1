# Taskora 📝

**Ứng dụng quản lý công việc (to-do) cho Windows** – giao diện đẹp, mượt mà, đầy đủ tính năng, viết 100% bằng **Rust** (egui/eframe).

![Build](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/workflows/ci.yml/badge.svg)

## ⬇️ Tải file .exe

1. Vào tab **[Actions](https://github.com/Hthancder/ArenaAIWorkspace-1/actions)** → chọn bản build gần nhất (workflow **Build**).
2. Ở mục **Artifacts** tải `Taskora-Windows-x64` → giải nén ra `Taskora.exe`.
3. Chạy thôi – không cần cài đặt, không cần Internet.

> Mẹo: sau khi mở repo, thêm tag `v0.1.0` rồi push → CI tự tạo **GitHub Release** kèm sẵn `Taskora.exe`.

## ✨ Tính năng

**Việc & danh sách**
- Thêm việc nhanh bằng **ngôn ngữ tự nhiên** (Anh + Việt):
  `Trả báo cáo ngày mai #công-việc !p1 *weekly`
  → hiểu `hôm nay / ngày mai / thứ 6 / chủ nhật / 15/11/2026 / next monday / in 3 days`, thẻ `#`, ưu tiên `!p1–!p4`, lặp lại `*daily/*weekly/*monthly` và `hàng ngày/tuần/tháng`.
- Nhiều **danh sách** với màu riêng; Hộp thư, view nhanh: **Hôm nay · Sắp tới · Đã ghim · Đã hoàn thành · Thùng rác**.
- **Việc nhỏ** (checklist) có tiến độ, **thẻ tag**, **ưu tiên P1–P4**, **ghim ★**, **lặp lại** (hàng ngày / ngày tuần / hàng tuần / hàng tháng – hết hạn tự tạo lần kế tiếp).
- **Lịch chọn ngày** gọn ngay trong panel chi tiết.
- **Kéo thả** đổi thứ tự (chế độ sắp xếp Thủ công), menu chuột phải đầy đủ: hoàn thành, chuyển danh sách, nhân bản, xóa/có thùng rác.

**Trải nghiệm**
- **Liquid glass**: nền aurora gradient, panel kính mờ (viền phản quang + bóng dưới), thẻ "Tổng thể" & ô thêm việc nhanh có dải sáng lướt (shimmer), đường sáng trên đỉnh card khi hover.
- **Hiệu ứng mượt**: fade khi chuyển trang, thanh accent sidebar trượt, hover/chọn việc chuyển màu dần, pulse xanh lá khi đánh dấu xong, thanh tiến độ & cột biểu đồ.animate.
- **Bộ icon Phosphor** (MIT) nhúng sẵn: sidebar, toolbar, nút bút / sao / lịch… thay ký tự text.
- Giao diện **Tối/Sáng** tinh chỉnh riêng, font **Be Vietnam Pro** (chuẩn tiếng Việt, nhúng sẵn trong exe).
- **Tìm kiếm** toàn bộ (Ctrl+F), lọc theo **thẻ**, ẩn/hiện đã hoàn thành, 5 kiểu sắp xếp.
- **Hoàn tác / Làm lại** (Ctrl+Z / Ctrl+Y) tới 80 bước.
- **Thống kê**: việc đang làm, xong hôm nay, quá hạn, chuỗi ngày liên tiếp, biểu đồ cột 14 ngày, tiến độ theo danh sách.
- **Lưu tự động** vào `%APPDATA%\Taskora\data.json`; **xuất / nhập bản sao lưu** một chạm; mở thẳng thư mục dữ liệu.
- Phím tắt: `Ctrl+N` thêm · `Space` đánh dấu xong · `↑↓` chọn việc · `Alt+↑↓` đổi thứ tự · `Esc` đóng · `Ctrl+1…6` chuyển view.

## 🛠️ Xây dựng từ nguồn

```bash
cargo run --release     # chạy thử (cần Rust toolchain)
cargo build --release   # → target/release/Taskora.exe
cargo test              # test parser + model + storage
```

CI (**GitHub Actions**, `windows-latest`) chạy test + build release ở **mọi lần push** và tự upload artifact.

## 🧱 Công nghệ

| Thành phần | Lựa chọn |
|---|---|
| Ngôn ngữ | Rust (edition 2021) |
| UI | [`eframe/egui 0.31.1`](https://github.com/emilk/egui) – immediate mode, không webview |
| Ngày giờ | `chrono` |
| Lưu dữ liệu | `serde` + `serde_json` (JSON trong `%APPDATA%`) |
| Font | Be Vietnam Pro (OFL) + Phosphor Icons (MIT) – nhúng `include_bytes!` |
| CI | GitHub Actions → artifact + Release khi push tag `v*` |

## 📁 Cấu trúc

```
assets/fonts/         ← Be Vietnam Pro + Phosphor (Regular, Fill)
src/main.rs           ← điểm vào, tạo icon cửa sổ
src/app.rs            ← App, phím tắt, hành động (Act), lưu tự động
src/models.rs         ← Store / Task / List / View / Priority / Repeat
src/parser.rs         ← phân tích thêm việc nhanh (có unit-test)
src/storage.rs        ← load/save JSON, sao lưu, khôi phục
src/ui/               ← theme, icons (bảng glyph), sidebar, task_list, detail, stats
.github/workflows/    ← pipeline build Windows
```

## 🙏 Nguồn tài nguyên

- [**Be Vietnam Pro**](https://fonts.google.com/specimen/Be+Vietnam+Pro) – font tiếng Việt (SIL Open Font License).
- [**Phosphor Icons**](https://phosphoricons.com) – bộ icon (MIT), nhúng qua `assets/fonts/Phosphor*.ttf`.

## 📄 License

MIT
