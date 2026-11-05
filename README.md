# LUMEN — Nối những vì sao

Game giải đố xoay ô, đồ hoạ tối giản nhưng đẹp, cực kỳ nhiều màn chơi (600 màn).
Không đồng hồ, không thất bại, không áp lực — thiết kế thân thiện, đặc biệt phù hợp người dễ bị phân tâm / ADHD.

## Cơ chế chơi
- Mỗi màn là một chòm sao gồm các ô nối di chạm.
- Nhấn vào một ô để xoay 90° (chọn chiều xoay bằng nút ↻ / ↺, hoặc phím **Q**).
- Đưa ánh sáng từ **ngôi sao nguồn** đến **mọi ngôi sao đích**.
- Ô có khoanh tròn nhỏ đã được khoá, không cần xoay.

## Điểm nhấn thiết kế
- **600 màn**, chia 10 chương, độ khó tăng dần (3×3 → 8×8, xuất hiện ô khoá, ô trống, nhiều sao đích hơn).
- Từng màn được sinh từ cây khuếm trải (spanning tree) → **luôn có lời giải**, vô sinh ngẫu nhiên xác định.
- Mục tiêu tối ưu (par) chỉ tính các ô trên đường sáng tới sao đích — công bằng, khuyến khích khám phá.
- **3 sao** nếu đi đúng hoặc chỉ hơn 1 nước so với tối ưu.
- **Gợi ý (H)**, **hoàn tác (U)**, **chơi lại (R)**, **chuyển chiều xoay (Q)**, **thoát về (Esc)**.
- **Chế độ Zen**: ẩn bộ đếm nước đi và mức tối ưu (trong Cài đặt).
- Tự động lưu tiến trình và số sao vào trình duyệt (localStorage).

## Công nghệ
HTML5 + CSS3 + JavaScript (ES module), không cần build, không cần thư viện ngoài. Âm thanh tổng hợp bằng Web Audio API (không cần file media).

## Cách chạy
Mở file `index.html` trực tiếp trong trình duyệt, hoặc phục vụ qua một HTTP server cục bộ:

```bash
python3 -m http.server 8000
# rồi mở http://localhost:8000
```

## Cấu trúc
- `index.html` — khung màn hình (trang chủ, chọn màn, chơi)
- `styles.css` — đồ hoạ tối giản, neon tinh tế, starfield, hiệu ứng
- `js/levels.js` — sinh 600 màn + kiểm tra ánh sáng
- `js/board.js` — vẽ bàn chơi SVG + xoay ô
- `js/main.js` — luồng game,進 trình, modal, phím tắt
- `js/audio.js` — synthesize âm thanh
- `js/storage.js` — lưu tiến trình
- `js/fx.js` — hiệu ứng sao, confetti
- `tools/validate.mjs` — kiểm tra toàn bộ 600 màn có giải

Tác giả: ArenaAIWorkspace · Giấy phép: dùng tự do
