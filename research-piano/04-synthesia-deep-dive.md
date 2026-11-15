# 04 — Synthesia — Deep dive

> Nhà phát triển: Synthesia LLC (Nicholas Piegdon). Ra mắt 2006 với tên "Piano Hero". Nền tảng: Windows, macOS, iPad, Android, Chromebook. Giá: miễn phí thử (20+ bài full, 20 giây đầu của bài khác), unlock **một lần $29** (giá thường $39) cho mọi thiết bị, không subscription.
> Synthesia là "ông tổ" của thể loại falling-notes piano game.

## 4.1. Cơ chế cốt lõi: Falling Notes

- Đọc file **MIDI** (và **MusicXML** từ v10.8), biến mỗi note thành khối màu rơi xuống bàn phím.
- Màu phân biệt **tay trái / tay phải** (và track).
- Không cần đọc nhạc vẫn chơi được ngay; có thể bật sheet music song song để học đọc nhạc dần.

## 4.2. Ba chế độ luyện tập (Practice Modes)

| Chế độ | Cách hoạt động |
|---|---|
| **Melody Practice** | Synthesia **đợi** người chơi bấm đúng nốt mới đi tiếp ("Play at Your Own Speed"). Chấm trên phím hiển thị chấm màu nốt cần bấm. Nơi bắt đầu mọi bài. |
| **Rhythm Practice** | Chạy theo nhịp, có thể chậm tempo, nhưng **timing tính điểm** theo beat. |
| **Recital** | Chạy full tốc độ như biểu diễn, chấm **notes + rhythm + note lengths**. |

- Mỗi bài tối đa **100 điểm**. Muốn 100 phải chơi cả hai tay, gần như hoàn hảo, nhiều lần, ở cả 3 chế độ.
- Điểm melody + rhythm + recital hiển thị cùng nhau; có thể gửi điểm lên website để xem đồ thị tiến độ (tài khoản Synthesia Online).

## 4.3. Công cụ luyện tập

- **Hands separately**: chọn tay trái/phải, app tự chơi phần còn lại.
- **Speed control**: nút +/− chậm/nhanh tempo bất kỳ lúc nào.
- **Jump & Loop**: click timeline nhảy tới bar bất kỳ, loop đoạn khó; "See the next loop before it starts" (thấy trước loop sắp tới, không bị nhảy đột ngột).
- **Bookmarks / markers**: đánh dấu vị trí trong bài.
- **Labels**: số ngón tay (finger numbers), tên nốt (C D E), solfège fixed-do / movable-do, scale degrees — hiển thị trên phím và nốt.
- **Sheet music**: hiển thị notation phía trên falling notes, hoặc tắt falling notes chỉ đọc sheet music. Page-flip mode.
- **Key lights**: bàn phím có đèn (lighted keyboard) tự sáng nốt sắp tới trong Melody Practice.
- **Metronome** tích hợp.
- **Free Play**: khu vực chơi tự do, thử nốt/nhạc cụ/hợp âm, xem tên hợp âm, **multi-track recorder** (ghi tới 6 track, bản unlock).
- **Finger hints**: gợi ý ngón tay cho mọi bài có sẵn; thêm bằng 1 click cho MIDI tự mang.
- **Easy hand splitting**: tự tách tay cho bài chỉ có 1 piano part.
- **Ash's Exercises**: scale + arpeggio có finger hints.
- **Key binding**: gán phím chuột/MIDI (note, CC, program change, pitch bend) cho mọi chức năng game, có thể kết hợp Ctrl.
- **Song flags**: đánh dấu bài trong thư viện, sắp xếp theo cột.
- **Recently played** trên màn hình chính.
- **Config tool** với hàng chục tùy chọn nâng cao (MIDI device check interval, volume reset, loop max errors…).

## 4.4. Thư viện & MIDI

- **150+ bài** có sẵn (kể cả Megalovania, FNaF… theo changelog), + **Music Store** bán arrangement $0.99–$2.99.
- **Bất kỳ MIDI/MusicXML nào** cũng chơi được — thư viện thực tế không giới hạn. Bản free chỉ phát 20 giây đầu của bài ngoài; unlock mới full.
- Hỗ trợ MIDI input/output: USB, Bluetooth, adapter; nhớ device yêu thích giữa các phiên; xử lý bàn phím "exotic" chỉ gửi All Notes Off; tự nhận diện instrument theo track.
- Hỗ trợ **lighted keyboard** (đèn phím), shift đúng khi đổi octave Z/X.

## 4.5. Điểm mạnh / điểm yếu

**Mạnh:**
- Wait Mode + chấm điểm 100 là cơ chế học hiệu quả nhất trong nhóm falling-notes.
- Một lần mua, mọi thiết bị, mọi update — giá trị tốt nhất nhóm app học.
- MIDI/MusicXML tự do, không khóa thư viện.
- Sheet music + finger hints + labels đầy đủ.

**Yếu:**
- **Chỉ nghe MIDI** — đàn piano cơ không có feedback (không có mic detection).
- Falling notes có thể thành "gậy chống" — người chơi quen nhìn nốt rơi mà không học đọc nhạc (chính Synthesia cũng thừa nhận).
- Không có editor MIDI, không export video, không tùy chỉnh visual sâu như NoteFall.
- Không có curriculum bài bản (chủ yếu là thư viện bài + luyện theo bài).
- Source đóng.

## 4.6. Tính năng nên mượn cho app mới (ưu tiên cao)

| Tính năng Synthesia | Ưu tiên | Ghi chú |
|---|---|---|
| Melody Practice (Wait Mode) | **P0/P1** | Cơ chế luyện cốt lõi còn thiếu của NoteFall |
| Rhythm Practice + Recital + điểm 100 | P1 | Chấm timing + note length |
| Hands separately + auto hand split | P1 | Tách tay tự động theo pitch/track |
| Speed + Jump/Loop + Bookmarks | **P0** | NoteFall có speedMap/trim, cần thêm loop/bookmark rõ ràng |
| Labels (finger, note name, solfège, scale degree) | P1 | NoteFall có pitch labels cơ bản |
| Sheet music song song | P1 | Cần MusicXML + VexFlow/OSMD (file 08) |
| Key lights (MIDI lighted keyboard) | P2 | Gửi MIDI note → đèn phím |
| Free Play + multi-track record | P1 | NoteFall có record 1 take; mở rộng multi-track |
| Finger hints tự động | P1 | Thuật toán gợi ý ngón (xem piano-app DP ở file 06) |
| Song flags / recently played | P1 | Quản lý thư viện cá nhân |
| MusicXML import | P1 | Mở rộng nguồn bài |
