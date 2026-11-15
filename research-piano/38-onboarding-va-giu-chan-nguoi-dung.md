# 38 — Onboarding, giữ chân & tâm lý người dùng

> Kỹ thuật tốt không đủ: người dùng mở app, phải **nghe được tiếng đàn trong 10 giây** và **hiểu mình làm được gì trong 60 giây**. File này là thiết kế cụ thể.

## 38.1. Khoảnh khắc "aha" phải xảy ra trước 30 giây

Đường đi tối ưu:

```
0s    Mở app → thấy bàn phím 3D, một nốt mẫu rơi
+2s   Chữ lớn: "Bấm phím A" (hoặc chạm vào phím Đô)
+3s   Người dùng bấm → nghe tiếng đàn thật, phím sáng
+8s   "Hay! Giờ thử cả câu: A S D F G H J"
+20s  Hết đoạn mẫu → "Mở file MIDI của bạn" / "Thử một bản demo"
+30s  Người dùng đã chơi, đã thấy nốt rơi, đã nghe đàn
```

**Nguyên tắc:**
- **Không** bắt đăng ký, không chọn cài đặt trước, không tour 8 bước.
- **Không** chặn bằng dialog. Mọi thứ có thể bỏ qua bằng 1 phím.
- Sample phải sẵn sàng (hoặc synth tạm) trước khi người dùng bấm phím đầu.

## 38.2. Ba nhóm người dùng & đường đi riêng

| Nhóm | Họ muốn gì | Onboarding nên đưa |
|---|---|---|
| **Người chơi đàn thật** (có MIDI keyboard) | xem nốt rơi, luyện bài, quay video | "Cắm đàn MIDI → chọn bài → phát" |
| **Người mới, không có đàn** | học chơi bằng máy tính | "Bắt đầu với 5 nốt" + bài học ngắn |
| **Người làm nội dung** (TikTok/YouTube) | video piano đẹp | "Chọn bài → chỉnh màu → xuất video" |

Hỏi **một câu duy nhất** ở lần đầu: *"Bạn muốn làm gì?"* với 3 nút. Kết quả này đổi màn hình mặc định và bộ preset.

## 38.3. Kiểm tra "sẵn sàng chơi" (playability gate)

Trước khi người dùng bấm, app phải trả lời được:
- AudioContext đã `running`? (nếu chưa: hiện nút "Bật âm thanh")
- Sample tầng mid đã giải mã? (nếu chưa: "Đang chuẩn bị đàn… 60%")
- Có cắm MIDI? (nếu có: "Đã kết nối: Yamaha P-45")
- Thiết bị yếu? (đã hạ cấp đồ hoạ chưa)

Hiển thị dưới dạng **1 dòng trạng thái nhỏ**, không phải modal: `● Sẵn sàng · Yamaha P-45 · 12 ms`.

## 38.4. Vòng lặp giữ chân (không gamification rẻ tiền)

File 24 đã nói về sư phạm. Ở đây là **cơ chế quay lại**:

| Cơ chế | Tốt | Xấu (tránh) |
|---|---|---|
| **Chuỗi ngày luyện** (streak) | nhẹ nhàng, có thể bỏ qua, không phạt | mất streak là mất hết, thông báo gây ác cảm |
| **Tiến bộ đo được** ("đoạn này từ 60% → 85%") | trung thực, khích lệ | điểm số ảo, so sánh với người khác |
| **Bài đang dang dở** ("tiếp tục Für Elise, ô nhịp 24") | đúng nhu cầu | mở app là bắt đầu lại |
| **Bản ghi cũ để so** | nghe thấy tiến bộ | quá nhiều bản ghi rối |
| **Mục tiêu tuần** (3 phiên × 15 phút) | linh hoạt | ép 60 phút/ngày |

**Không làm:** leaderboard toàn cầu, tiền ảo, loot box, thông báo "bạn đang thua bạn bè".

## 38.5. Phiên dùng đầu tiên → phiên thứ hai

Điều quyết định người dùng quay lại **không phải** tính năng, mà là **công sức bỏ ra lần đầu**:
- Nếu họ phải tìm file MIDI, tải sample 77 MB, cấu hình 5 thứ → phần lớn không quay lại.
- Giải pháp: **3 bài demo có sẵn trong app** (bản tự soạn/PD), nhỏ, mở tức thì; nút "Tiếp tục bài gần nhất" ở đầu; sample tải nền **sau** khi họ đã chơi.

**Chỉ số cần tự đo (local, không gửi đi):**
- Thời gian từ mở app → phím đầu tiên (mục tiêu < 15 s)
- Số phiên/tuần (mục tiêu > 2 với người dùng thật)
- Tỉ lệ mở file thành công ở lần đầu
- Số lần export (dấu hiệu tạo giá trị thật)

Hiển thị cho người dùng trong "Thống kê của tôi" — vừa minh bạch, vừa tạo động lực.

## 38.6. Thông báo & nhắc nhở

- **Trong app** (banner nhỏ): "Đã 4 ngày kể từ lần lưu cuối — xuất bản sao lưu?" quan trọng hơn mọi nhắc luyện tập.
- **Web Push**: chỉ dùng nếu thật cần; xin quyền **sau** khi người dùng đã dùng 2–3 lần, không phải lúc mở.
- **Email**: không có (không có tài khoản).
- Tần suất tối đa: 1 nhắc/ngày, tắt được bằng 1 click.

## 38.7. Xử lý lỗi như một phần onboarding

| Lỗi | Thông điệp (tiếng Việt, cụ thể) | Hành động |
|---|---|---|
| Không có Web MIDI | "Trình duyệt này không hỗ trợ đàn MIDI. Chơi bằng bàn phím vẫn tốt." | Gợi ý Chrome/Edge |
| MIDI không mở được | "File này có 1.2 triệu nốt — quá lớn. Thử file nhỏ hơn?" | Nút chọn file khác |
| Hết bộ nhớ | "Trình duyệt hết bộ nhớ. Đã tắt hiệu ứng và giảm số nốt." | Tự hạ cấp |
| Safari xoá dữ liệu | "Safari xoá dữ liệu trang sau 7 ngày. Xuất `.nfz` để giữ bài." | Nút xuất |
| Sample lỗi | "Không tải được sample. Đang dùng synth tạm." | Thử lại |

**Không bao giờ** hiện `Error: undefined` hay stack trace cho người dùng.

## 38.8. Bản địa hoá giọng điệu

- Xưng "bạn" – "mình"/"chúng mình"; tránh "quý khách".
- Câu ngắn, động từ rõ: "Mở file MIDI", không "Tiến hành mở tệp tin MIDI".
- Thuật ngữ: dùng bảng ở file 25; lần đầu xuất hiện thì có tooltip.
- **Không dịch** tên phím/tên hợp âm nếu gây nhầm (C4 giữ là C4, chú thích Đô4).

## 38.9. Checklist onboarding

- [ ] Từ mở app → nghe tiếng đàn < 15 s trên máy 4G.
- [ ] Không có modal nào chặn ở lần mở đầu.
- [ ] Có 3 bài demo mở tức thì, không cần tải.
- [ ] Có nút "Bật âm thanh" rõ nếu context bị treo.
- [ ] Trạng thái sẵn sàng hiển thị liên tục (thiết bị, latency).
- [ ] Tất cả thông báo lỗi đã được viết lại bằng tiếng Việt dễ hiểu.
- [ ] Người dùng mới có thể bỏ qua mọi thứ bằng Esc.
- [ ] Đo được 4 chỉ số ở 38.5 (local).
