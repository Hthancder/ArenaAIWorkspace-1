# 01 — Tổng quan và phạm vi

## 1.1. "App piano không cần đàn piano" là gì?

Là phần mềm mô phỏng / dạy chơi piano chạy trên máy tính hoặc điện thoại, trong đó:

- Âm thanh piano được tạo bằng **sample** (bản ghi âm đàn thật) hoặc **tổng hợp** (synthesis), phát qua loa/tai nghe.
- Người chơi dùng **chuột, cảm ứng, phím máy tính, hoặc bàn phím MIDI** (nếu có) thay cho phím đàn thật.
- Phần mềm hiển thị bàn phím ảo, nốt nhạc rơi (falling notes), bản nhạc (sheet music), hoặc cả hai.
- Có thể **phát MIDI có sẵn**, **ghi lại** phần mình chơi, **chấm điểm** khi luyện, **export video/audio**.

Không yêu cầu đàn piano cơ. Đàn piano thật / digital piano chỉ là **tùy chọn** (kết nối MIDI hoặc để mic nghe).

## 1.2. Phân loại theo mục đích

| Nhóm | Mục đích chính | Ví dụ tiêu biểu |
|---|---|---|
| **A. Virtual piano / chơi tự do** | Chơi đàn như một nhạc cụ, thử âm thanh, ghi lại | Perfect Piano (chế độ Free Play), virtual piano web, RoxyPiano, Synthio |
| **B. Falling-notes visualizer** | Xem MIDI thành nốt rơi 2D/3D, làm video | NoteFall (ekkx), NoteFall (Suma-Udd, Python), Synthesia |
| **C. Học piano theo bài (song-based)** | Học từng bài hát với hướng dẫn, chấm điểm | Synthesia, Flowkey, Simply Piano, Skoove, Yousician, OnlinePianist |
| **D. Curriculum / method** | Lộ trình bài bản từ số 0: đọc nhạc, kỹ thuật, sight-reading | Simply Piano, Piano Marvel, Playground Sessions, Pianote, Hoffman Academy |
| **E. Sight-reading / luyện kỹ thuật** | Đọc nhạc nhanh, scale, arpeggio, ear training | Piano Marvel (SASR), PianoBooster, Melodics |
| **F. DAW / sáng tác** | Soạn nhạc, ghi MIDI, phối khí | MuseScore, DAW trình duyệt (LA Studio…), NoteFall editor |
| **G. Multiplayer / social** | Chơi cùng người khác, thi đấu, chat | Perfect Piano (multiplayer, guild, ranking) |

Một app tốt thường gộp nhiều nhóm. NoteFall thuộc **A+B+F** (chơi tự do + visualizer + editor + export). Perfect Piano thuộc **A+C+G**. Synthesia thuộc **B+C**. Simply Piano/Flowkey thuộc **C+D**.

## 1.3. Phân loại theo cách "nghe" người chơi

| Cách nhận input | Độ chính xác | Cần phần cứng | App dùng |
|---|---|---|---|
| Chuột / cảm ứng / phím máy tính | Thấp (không có velocity thật, không polyphony đầy đủ) | Không | Mọi app đều có |
| **Web MIDI / USB MIDI / Bluetooth MIDI** | Rất cao (note + velocity + pedal chính xác) | Digital piano / MIDI controller | Synthesia, NoteFall, Piano Marvel, Playground Sessions, Perfect Piano (USB) |
| **Microphone (audio detection)** | Trung bình, phụ thuộc phòng ồn, đàn, mic | Không (dùng mic của máy) | Simply Piano, Flowkey, Skoove, Yousician |
| Không nghe — chỉ phát | — | Không | NoteFall visualizer, Suma-Udd NoteFall |

> Kết luận kỹ thuật: MIDI là đường chính xác nhất và rẻ nhất để làm trước. Mic detection là tính năng khó, tốn công, để sau (P2). Xem file 08.

## 1.4. Phạm vi của dự án app mới (theo yêu cầu)

**Ưu tiên 1 — Chơi đàn thật sự trên máy tính:**
- Bàn phím ảo 88 phím, chơi bằng chuột + phím máy tính + Web MIDI.
- Âm thanh piano chất lượng cao, độ trễ thấp, sustain pedal, velocity.
- Tùy chỉnh hầu hết thông số (âm thanh, hiển thị, phím tắt…).

**Ưu tiên 2 — MIDI tùy chỉnh tự do:**
- Mở bất kỳ file `.mid` nào, phát, dừng, tua, đổi tốc độ, loop đoạn, transpose, tách tay, đổi màu theo track…
- Ghi lại phần chơi thành MIDI, sửa MIDI, lưu/xuất MIDI.
- Import MusicXML / sheet music (P1).

**Ưu tiên 3 — Luyện tập / học (sau khi chơi ngon):**
- Wait Mode, chấm điểm, loop A-B, chậm tốc độ, luyện từng tay.
- Sheet music đồng bộ, gợi ý ngón tay, tên nốt, hợp âm.

**Ngoài phạm vi đợt đầu:**
- Đàn piano thật (chỉ cần hỗ trợ MIDI controller nếu có, không bắt buộc).
- Mobile app native (web responsive trước; mobile sau).
- Multiplayer online, tài khoản, thanh toán, thư viện bài hát có bản quyền (cần giấy phép nội dung riêng).
- Mic detection cho đàn cơ (P2, nghiên cứu sau).

## 1.5. Đối tượng người dùng mục tiêu

- Người muốn **chơi piano ngay trên máy tính**, không có đàn, không muốn học lý thuyết nặng.
- Người có file MIDI muốn **xem / luyện / làm video**.
- Người mới học piano muốn **hướng dẫn trực quan** (nốt rơi, sheet music).
- Người chơi nâng cao muốn **tùy chỉnh sâu** (velocity curve, pedal, soundfont, camera, màu sắc…).

## 1.6. Nguyên tắc thiết kế rút ra từ các app thành công

1. **Mở app là chơi được trong 5 giây** — không đăng ký, không cài đặt (web), không cấu hình dài.
2. **Mọi thứ đều tùy chỉnh được** — tốc độ, màu, phím, âm thanh, góc nhìn. Đây là yêu cầu trọng tâm của dự án này.
3. **Không khóa nội dung bằng paywall** — người dùng tự mang MIDI của mình vào.
4. **Độ trễ âm thanh thấp** — cảm giác "chạm là kêu" quyết định trải nghiệm chơi.
5. **Dữ liệu nằm trên máy người dùng** — file MIDI/project lưu local, không upload (NoteFall làm đúng nguyên tắc này).
6. **Học theo tốc độ của mình** — Wait Mode + chậm tốc độ + loop là bộ ba không thể thiếu.
