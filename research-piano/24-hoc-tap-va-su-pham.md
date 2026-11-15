# 24 — Khoa học học tập & thiết kế sư phạm cho app

> Mục tiêu: tính năng luyện tập **phải dựa trên cơ chế học thật**, không chỉ là "đếm nốt đúng". File này biến các phát hiện từ nghiên cứu motor learning / cognitive science thành **quy tắc thiết kế cụ thể** cho app.

## 24.1. Bốn điều kiện của "deliberate practice" (Ericsson)

| Điều kiện | Nghĩa | App phải làm gì |
|---|---|---|
| **Mục tiêu cụ thể** | Không phải "luyện scale" mà "chơi đoạn này ở 120 BPM không căng ngón cái" | Cho người dùng đặt mục tiêu theo **đoạn + tempo + tiêu chí** (đúng nốt / đúng nhịp / không sai quá N) |
| **Ở mép khả năng** | Không quá dễ (chán), không quá khó (bỏ) | Tự đề xuất tempo/đoạn dựa trên kết quả gần nhất |
| **Phản hồi tức thì, cụ thể** | Biết sai ở đâu, sai gì | Chấm theo nốt + theo ô nhịp; hiện "bar 7 chậm 40 ms" thay vì chỉ "85%" |
| **Tập trung hoàn toàn** | Không chơi trong lúc lướt điện thoại | Phiên ngắn (10–15 phút), có nhịp nghỉ, không thông báo gây nhiễu |

## 24.2. Chunking — chia nhỏ rồi ghép lại

- Người chơi giỏi mã hoá bản nhạc thành **cấu trúc phân cấp**: câu → ô nhịp → đoạn → bài. Não coi mỗi "chunk" như một đơn vị.
- **App phải hỗ trợ chia nhỏ có ý thức**, không chỉ loop tuỳ ý:
  - Tự phát hiện **ranh giới câu/đoạn** từ MIDI (khoảng lặng, đổi hợp âm, đổi tay, kết câu) → đề xuất "chunk" 2–4 ô nhịp.
  - Cho người dùng **đặt tên chunk** ("câu 2 – tay trái"), lưu vào project.
  - Luyện chunk đến ngưỡng → **ghép** với chunk kề (chunk + 1 ô hai bên), rồi cả câu.
- Đây cũng là lý do **luyện tay riêng hiệu quả**: mỗi tay thành một chunk độc lập, sau đó tích hợp.

## 24.3. Spacing & nghỉ

- Hiệu ứng **spacing** (học cách quãng) có effect size trung bình ~0.54; **giấc ngủ** củng cố kỹ năng vận động (bằng chứng mạnh).
- Hệ quả thiết kế:
  - Khuyến khích **15–30 phút/ngày**, nhiều ngày, thay vì 2 giờ Chủ nhật. Thông điệp UI: *"15 phút mỗi ngày tốt hơn 2 giờ một lần."*
  - Nhắc nghỉ ngắn sau ~10–15 phút (không ép, chỉ gợi ý).
  - **Streak** (chuỗi ngày) là công cụ tốt — nhưng đừng phạt nặng khi mất chuỗi (gây bỏ luôn).
- **Không** dùng "daily cap" kiểu Yousician để ép trả tiền: gây khó chịu và phản tác dụng với người học nghiêm túc.

## 24.4. Slow practice + tempo ladder (thang tốc độ)

- Chơi chậm để **hình thành schema vận động đúng** trước khi tăng tốc; tăng dần từng bước nhỏ.
- Quy tắc cụ thể (đưa vào app):
  - Bắt đầu ở tempo mà người dùng đạt **≥90% nốt đúng và ≥70% đúng nhịp**.
  - Khi đạt **3 lần liên tiếp** ở tempo hiện tại → **+5 BPM** (không nhảy 20 BPM).
  - Nếu 2 lần liên tiếp < 80% → **−5 BPM**.
  - Hiển thị "thang tempo" trực quan, lưu lịch sử từng chunk.
- Cảnh báo: đừng cho luyện mãi ở tempo đích khi độ chính xác còn thấp (tạo thói quen sai).

## 24.5. Tay riêng, rồi ghép

- Thực hành tay riêng **lâu hơn người mới nghĩ** (nhiều tuần với bài trung cấp).
- Chu trình nên khuyến nghị: **tay phải → tay trái → ghép → tách lại từng tay** (quay lại tay riêng sau khi ghép giúp củng cố).
- App: nút "Tay P / Tay T / Hai tay" + tự phát tay còn lại + **ghi nhớ lựa chọn theo chunk**.

## 24.6. Mental rehearsal & nghe trước

- Tưởng tượng động tác kích hoạt nhiều vùng não giống thực hiện thật → có thể luyện không cần đàn.
- App: chế độ **"Nghe và hình dung"** — phát đoạn, hiện nốt + ngón tay, **không cho bấm** (hoặc bấm không tính điểm) trong 1–2 lần đầu.
- Với người không có đàn: đây là tính năng **rất giá trị** (nghe mẫu, nhìn nốt, tập gõ theo nhịp trên bàn).

## 24.7. Ghi âm & tự đánh giá

- Nghe lại bản ghi là cách tự phát hiện lỗi mạnh (và là cách giáo viên dạy).
- App: sau mỗi phiên, cho **nghe lại take** + **so sánh với bản gốc** (A/B), hiện timeline lỗi.
- Không cần AI: so sánh MIDI người chơi vs MIDI gốc đã đủ.

## 24.8. Động lực: cái gì hiệu quả, cái gì phản tác dụng

| Cơ chế | Hiệu quả khi | Phản tác dụng khi |
|---|---|---|
| **Streak** | Gắn với **ngày có luyện tập thực chất** (≥5 phút có tương tác) | Tính cả ngày mở app 5 giây |
| **XP/điểm** | Thưởng cho **chất lượng** (đúng, tăng tempo, hoàn thành chunk) | Thưởng cho "điểm danh" |
| **Huy hiệu** | Mốc kỹ năng cụ thể ("Chunk 1 ở 100 BPM, 95%") | Huy hiệu ngẫu nhiên/đăng nhập |
| **Bảng xếp hạng** | So với chính mình (tuần trước) | So với người khác (gây nản) |
| **Leaderboard online** | Chỉ khi cộng đồng đông và công bằng | Giai đoạn đầu: không |
| **Âm thanh phần thưởng** | Nhẹ, có thể tắt | Ồn ào, lặp lại |
| **Phạt** | Hầu như không bao giờ | Mất streak, trừ điểm, khoá bài |

Nguyên tắc: **thưởng hành vi dẫn tới học** (luyện chậm đúng, tăng dần tempo, sửa đoạn yếu) — không thưởng "mở app".

## 24.9. Cấu trúc một phiên luyện (template sinh tự động)

```
1. Khởi động (3–5 phút)   : scale/arpeggio hoặc chunk đã thành thạo, tempo thấp
2. Kỹ thuật (5–10 phút)   : 1 chunk khó nhất, tay riêng, tempo ladder
3. Tiết mục (10–15 phút)  : ghép chunk, chạy cả đoạn, chấm điểm
4. Củng cố (3–5 phút)     : chạy lại đoạn vừa sửa ở tempo chậm (kết thúc bằng thành công)
5. Ghi chú (1 phút)       : "hôm nay sửa được gì" (1 dòng, lưu vào lịch sử)
```

**Thuật toán chọn nội dung phiên** (đơn giản, hiệu quả):
```
score(chunk) = 0.5*(1 - accuracy_gần_nhất) + 0.3*(1 - tempo_đạt/tempo_đích) + 0.2*độ_lâu_chưa_luyện
→ chọn 2–3 chunk điểm cao nhất cho phần "kỹ thuật", 1 chunk đã tốt cho "khởi động"
```

**Kết thúc bằng thành công**: luôn kết phiên bằng đoạn người dùng chơi tốt (tạo cảm giác tiến bộ — yếu tố giữ chân mạnh nhất).

## 24.10. Lộ trình (curriculum) tối thiểu nếu muốn làm

| Level | Nội dung | Tiêu chí đạt (đo được) |
|---|---|---|
| 1 | 5 ngón, C position, nốt đen | 8 ô nhịp, 90% đúng, 60 BPM |
| 2 | Đọc nốt khóa Sol, quãng 2–5 | 12 ô, 90%, 70 BPM |
| 3 | Khóa Fa (tay trái), hợp âm rải | 2 tay, 85%, 70 BPM |
| 4 | Scale C/G/F 2 octave, ngón chuẩn | chạy đều, 80 BPM móc đơn |
| 5 | Pedal cơ bản, legato | đoạn 8 ô có pedal, 85% |
| 6 | Đọc nốt nhanh (sight-reading) | 20 s nhìn, 80% đúng |
| 7 | Độc lập hai tay | bài 2 tay 16 ô, 85% |
| 8 | Biểu cảm (dynamic, tempo) | đạt dynamic pp→ff theo yêu cầu |
| 9 | Tự học bài mới | hoàn thành 1 bài chưa từng chơi, 80% |

> Không cần nội dung bản quyền: mỗi level dùng bài **public domain** + bài người dùng tự mang.

## 24.11. Chống "nghiện nốt rơi" (falling-notes dependency)

- Nốt rơi dạy **vị trí phím**, không dạy **đọc nhạc**. Người chỉ nhìn nốt rơi sẽ không đọc được sheet.
- Giải pháp trong app:
  - Chế độ "**mờ dần**": sau N lần đạt, giảm độ sáng nốt rơi / ẩn nhãn, buộc nhìn sheet.
  - Chế độ "**chỉ sheet**" cho bài có MusicXML.
  - Nhắc nhẹ: "Bạn đã đạt 3 lần — thử tắt nốt rơi?"
- Không ép; chỉ khuyến khích.

## 24.12. Đo hiệu quả học (nếu muốn nghiêm túc)

| Chỉ số | Cách đo | Kỳ vọng |
|---|---|---|
| **Tốc độ đạt tempo đích** | Số phiên để chunk đạt tempo | giảm dần |
| **Số lỗi/ô nhịp** | Từ scoring | giảm |
| **Thời gian tới lần chơi đúng đầu tiên** | Từ scoring | giảm |
| **Retention**: chơi lại chunk sau 3 ngày | Session history | ≥70% độ chính xác giữ nguyên |
| **Tự nguyện luyện thêm** | Số phiên/tuần | tăng |
| **Chuyển sang đọc sheet** | Tỉ lệ tắt nốt rơi | tăng nhẹ |

Thử nghiệm A/B có thể làm **cục bộ** (bật/tắt 1 cơ chế bằng settings, so sánh trong dữ liệu của chính người dùng) — không cần server.

## 24.13. Tóm tắt: 10 tính năng sư phạm nên có (theo thứ tự giá trị)

1. **Wait Mode** (dừng chờ đúng nốt) — nền tảng.
2. **Chấm điểm theo ô nhịp** + chỉ ra đoạn yếu.
3. **Loop A–B + chunk có tên**.
4. **Tay riêng + tự phát tay kia**.
5. **Tempo ladder tự động** (+5 BPM sau 3 lần đạt).
6. **Sheet music đồng bộ** (và chế độ chỉ sheet).
7. **Gợi ý ngón tay** (DP) + cho sửa.
8. **Ghi âm & so sánh A/B**.
9. **Lịch sử phiên + biểu đồ tiến bộ** (so với chính mình).
10. **Chế độ nghe/hình dung** (không bấm) cho người chưa quen.
