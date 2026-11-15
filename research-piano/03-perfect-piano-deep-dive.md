# 03 — Perfect Piano — Deep dive

> Nhà phát triển: Revontulet Soft Inc (Gamestar). Nền tảng: Android, iOS, Windows (Microsoft Store). Nguồn: Google Play listing, Microsoft Store, bài review.
> Đây là app người dùng nêu ví dụ đầu tiên ("perfect piano app trên điện thoại").

## 3.1. Định vị

"Intelligent piano simulator" — mô phỏng piano + dạy chơi + multiplayer, tất cả trong một app mobile. Timbre piano thật, học hàng nghìn bản nhạc, chơi online với người khắp thế giới.

## 3.2. Intelligent Keyboard (bàn phím thông minh)

- Bàn phím **88 phím** đầy đủ.
- Chế độ hiển thị: **Single-row** (1 hàng), **Double-row** (2 hàng), **Dual players** (2 người chơi), **Chords mode** (chế độ hợp âm).
- **Multitouch** (chạm nhiều điểm cùng lúc), **Force touch** (lực chạm 3D Touch), phát hiện **áp lực chạm** (touch pressure → velocity).
- **Chỉnh độ rộng phím** (keyboard width adjustment) — phù hợp ngón tay to / màn hình nhỏ.
- **OpenSL ES low latency** (beta) — giảm độ trễ âm thanh trên Android.
- Âm thanh tích hợp (9 loại theo các nguồn): Grand piano, Bright Piano, Music Box, Pipe Organ, Rhodes, Synthesiser, Synth bass, Steel string guitar, Strings Ensemble, Soprano Sax, Space Synth… (số lượng thay đổi theo phiên bản).
- **Timbre plug-ins** tải thêm miễn phí: bass, electric guitar, wooden guitar, flute, saxophone, electronic keyboard, violin, chord, xylophone, harp, cello, soprano sax, strings ensemble, electronic piano, clean electric guitar, high quality grand piano…
- **MIDI + AAC audio recording**, phát lại, chia sẻ file, đặt làm ringtone.
- **Metronome** tích hợp.
- Hỗ trợ **MusicXML notation** (bản mới hơn).

## 3.3. Learn to Play (học chơi)

- Thư viện **hàng nghìn bản nhạc** phổ biến, cập nhật hàng tuần.
- **3 kiểu hướng dẫn**: falling note (nốt rơi), waterfall (thác nước — biến thể nốt rơi), music sheet / stave (khuông nhạc).
- **3 chế độ chơi**: Auto play (tự phát), Semi-auto play (bán tự động — hỗ trợ một phần), Note pause (dừng chờ bấm đúng nốt — tương đương Wait Mode).
- **Tách tay trái/phải** (Left & right hand setup).
- **Loop A→B**, **chỉnh tốc độ**, **chỉnh độ khó** (difficulty — bản đơn giản/dễ của cùng một bài).
- Bài hát có nhiều mức độ; người mới bắt đầu từ bản dễ.

## 3.4. Multiplayer & Competition

- Chơi piano online với người chơi khắp thế giới, kết bạn, **chat realtime**.
- **Weekly new song challenge ranking** — thi đấu bài mới mỗi tuần, bảng xếp hạng.
- **Tạo guild** (hội nhóm), hệ thống bạn bè.
- Đây là tính năng **hiếm** trong các app piano — hầu hết app khác không có multiplayer piano thật.

## 3.5. USB MIDI Keyboard

- Hỗ trợ chuẩn **General MIDI** qua USB (Android 3.1+, USB Host / OTG): Yamaha P105, Roland F-120, Xkey…
- Điều khiển piano, ghi âm, thi đấu bằng bàn phím MIDI thật.
- Lưu ý: iOS dùng cách kết nối khác; Windows version cũng có.

## 3.6. Điểm mạnh / điểm yếu rút ra

**Mạnh:**
- Tất cả trong một: chơi tự do + học + multiplayer + MIDI + nhiều timbre.
- Chế độ bàn phím đa dạng (single/double/dual/chords) — rất hợp mobile.
- Force touch / pressure → velocity cảm ứng, điều mà web khó làm.
- Timbre plug-in mở rộng gần như không giới hạn nhạc cụ.

**Yếu (so với NoteFall / Synthesia):**
- Không có editor MIDI trên canvas, không export video 4K, không keyframe visual.
- Không có sheet music editor, không có chấm điểm chi tiết từng nốt (chủ yếu theo dõi tiến độ bài).
- Mobile-first; bản desktop là port, không tối ưu cho máy tính.
- Nội dung bài hát phụ thuộc thư viện của hãng (bản quyền), không tự mang MIDI tùy ý như Synthesia/NoteFall.
- Giấy phép đóng, không bê source được.

## 3.7. Tính năng nên "mượn ý tưởng" cho app mới

| Tính năng Perfect Piano | Áp dụng cho app mới |
|---|---|
| Single/Double/Dual/Chords mode | Thêm chế độ hiển thị bàn phím cho màn hình hẹp |
| Keyboard width adjustment | Tùy chỉnh độ rộng phím (NoteFall chưa có rõ) |
| Force touch / pressure velocity | Chỉ mobile; web dùng velocity curve thay thế |
| 9+ timbre + plug-in | Thêm SoundFont `.sf2` + nhiều instrument (P1) |
| 3 guidance: falling / waterfall / stave | Thêm waterfall + stave (P1) |
| Auto / Semi-auto / Note pause | Thêm 3 chế độ phát (P1) |
| Difficulty adjustment | Thêm bản dễ/khó cho cùng một MIDI (P1) |
| Multiplayer + guild + ranking | P2, cần backend — ngoài đợt đầu |
| Set ringtone | Không cần cho desktop |
| MusicXML | Import MusicXML (P1) |

## 3.8. So sánh nhanh Perfect Piano vs NoteFall

|  | Perfect Piano | NoteFall (ekkx) |
|---|---|---|
| Nền tảng | Mobile + Windows | Web desktop |
| Chơi tự do | ✅ 88 phím, multitouch | ✅ 88 phím 3D, Web MIDI |
| Học bài | ✅ Hàng nghìn bài, 3 guidance | ❌ Chỉ visualizer |
| Multiplayer | ✅ | ❌ |
| Editor MIDI | ❌ | ✅ Trên canvas |
| Export video | ❌ | ✅ 4K |
| Tùy chỉnh visual | Ít | Rất nhiều (hàng trăm thông số) |
| MIDI tự mang | Hạn chế | ✅ Tự do |
| Source | Đóng | Source-available (PolyForm Shield) |
