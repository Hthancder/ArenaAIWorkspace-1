# 19 — MIDI thực tế: các ca biên & độ bền dữ liệu

> File này để app **không chết** khi người dùng kéo vào một file MIDI "bẩn". Mọi ca dưới đây đều gặp trong thực tế khi mở MIDI tải trên mạng.
> Cách xử lý ghi theo hướng "app phải làm gì", kèm mức ưu tiên.

## 19.1. Cấu trúc & định dạng

| Ca | Triệu chứng | Cách xử lý | Ưu tiên |
|---|---|---|---|
| **Format 0** (1 track, nhiều channel) | Mọi track gộp làm một, tô màu track vô nghĩa | Tách hiển thị theo **channel** ± heuristic tay trái/phải; vẫn giữ 1 track logic | P0 |
| **Format 1** nhiều track | Track 0 thường không có note (tempo/meta) | Giữ index track đồng bộ, ẩn track không có note khỏi danh sách màu | P0 |
| **Format 2** (pattern độc lập) | Không có nghĩa "phát tuần tự" | Cảnh báo, chỉ phát track đầu hoặc hỏi người dùng | P1 |
| **SMPTE division** (thay vì ticks/quarter) | Tempo map không áp dụng được theo cách thường | Chuyển trực tiếp sang giây bằng timecode; bỏ tempo | P1 |
| **Tempo change giữa bài** | Nếu bỏ qua, cả bài lệch dần | Xây **tempo map** đầy đủ (tick → giây theo từng đoạn); test bằng bài có ritardando | **P0** |
| **Running status** | Parser tự viết dễ lỗi | Dùng `@tonejs/midi` (đã xử lý) hoặc test kỹ parser | P0 |
| **SysEx / meta lạ** | Parser crash | Bỏ qua an toàn, không throw | P0 |
| **Tên track không UTF-8** (Big5, GBK, Shift_JIS, CP1252) | Hiện ký tự rác | Thử decode: UTF-8 → Shift_JIS/GBK/Big5 → CP1252; fallback "Track N" | P1 |

## 19.2. Note & channel

| Ca | Triệu chứng | Cách xử lý | Ưu tiên |
|---|---|---|---|
| **Note On velocity 0** thay cho Note Off | Note treo vĩnh viễn | Coi `0x90 vel 0` = note off (bắt buộc) | **P0** |
| **Note Off thiếu** (file hỏng, hết track đột ngột) | Note kêu mãi, đếm sai | Khi gặp End of Track hoặc hết file: đóng mọi note đang mở | **P0** |
| **Note chồng cùng pitch** (note mới khi note cũ chưa off) | Note trước bị "nuốt", hiển thị sai | `resolveOverlaps`: cắt note trước tại điểm note mới (NoteFall đã có) | **P0** |
| **Channel 10 = drum** | Trống bị vẽ lên bàn phím piano, gây rối | Mặc định **bỏ** khỏi bàn phím; tùy chọn "hiện như track riêng" (không phát bằng piano) | **P0** |
| **Program change khác nhau mỗi track** | Piano phát tất cả như piano | Ghi nhận instrument mỗi track; khi có SoundFont → phát đúng; không có → cảnh báo nhẹ | P1 |
| **Pitch bend / modulation** | Bỏ qua thì phần synth mất biểu cảm | Ghi nhận và áp dụng cho track dùng synth; piano sample bỏ qua | P2 |
| **Note ngoài 21–108** | Vẽ ra ngoài bàn phím | Kẹp vào range, ẩn cột, hoặc báo "bài có nốt ngoài 88 phím" | P1 |

## 19.3. Pedal

| Ca | Triệu chứng | Cách xử lý | Ưu tiên |
|---|---|---|---|
| CC64 chỉ có 0/127 | Ổn | Vẫn xử lý như half-pedal threshold | P0 |
| CC64 **giá trị trung gian** (half-pedal) | Nếu chỉ so `>=64` thì mất sắc thái | Lưu dạng 0..1, map sang damper lift (NoteFall đã làm) | P1 |
| **Pedal down khi hết bài** (không có CC64 = 0 cuối) | Âm đuôi bị cắt đột ngột khi stop | Khi stop/seek: nhả pedal + fade ra | P0 |
| **Pedal xuống trước note đầu** | Note đầu không được giữ | Áp dụng trạng thái pedal tại thời điểm note bắt đầu | P0 |
| CC66/67 (sostenuto/soft) | NoteFall giữ để round-trip, không phát | Giữ nguyên; nếu muốn chính xác cao thì model riêng (P2) | P2 |

## 19.4. File "khủng" và black MIDI

| Ca | Số liệu thực tế | Cách xử lý |
|---|---|---|
| **Black MIDI** (hàng trăm nghìn nốt) | 100k–1M note; 10k note/giây | Giới hạn hiển thị theo cửa sổ thời gian; **không** tạo mesh cho mọi note; parse trong Web Worker; cảnh báo "file rất lớn, có thể giật" |
| **Nhiều note cùng lúc** (>20) | Vẽ chồng, particle nổ | Cap particle theo frame; gộp note cùng pitch trong 10 ms |
| **Bài rất dài** (>30 phút) | RAM, timeline | Stream theo cửa sổ; timeline dùng mipmap/giảm mẫu |
| **File > 20 MB** | Parse chậm, tab treo | Parse worker + progress; từ chối > 100 MB kèm thông báo |
| **Số track > 32** | UI rối | Nhóm, ẩn mặc định, chỉ hiện track có note |
| **Tempo cực cao** (>300 BPM) hoặc cực thấp | Nốt dồn/lệch | Clamp speed hiển thị; test bằng file cực đoan |

## 19.5. Thời gian & đồng bộ

| Ca | Triệu chứng | Cách xử lý |
|---|---|---|
| **Nốt đầu không ở 0** | Im lặng đầu bài, timeline trống | Tự trim im lặng đầu (tùy chọn), hoặc giữ và hiển thị rõ |
| **Khoảng lặng dài giữa bài** | Người dùng tưởng treo | Giữ nguyên (đúng nhạc) nhưng hiện "silence 12s" trên timeline |
| **Note duration = 0** (note on/off cùng tick) | Vô hình | Đặt `noteMinLength` khi hiển thị (NoteFall đã có) |
| **Note kéo dài tới hết file** | Không có off | Cắt tại `song.duration` |
| **Pedal + note dài + speed automation** | Sai thời điểm nhả | Test kỹ nhánh `speedMap` × pedal |
| **Seek giữa lúc pedal đang xuống** | Note mới bị giữ oan | Khi seek: reset pedal state = trạng thái CC64 tại vị trí seek |

## 19.6. Kiểm thử: bộ file MIDI mẫu nên có

Tạo thư mục `test-midi/` với ít nhất 12 file (tự làm hoặc CC0):

1. `format0-simple.mid` — 1 track, 1 channel, 100 nốt.
2. `format1-3tracks.mid` — 3 track, tempo cố định.
3. `tempo-changes.mid` — 5 lần đổi tempo, có ritardando.
4. `pedal-half.mid` — CC64 giá trị 0..127 liên tục.
5. `pedal-stuck.mid` — pedal down, không có CC64=0 cuối.
6. `overlap-same-pitch.mid` — C4 chồng C4 nhiều lần.
7. `missing-noteoff.mid` — vài note không có off.
8. `drum-channel.mid` — channel 10 có note.
9. `black-midi.mid` — 50k note, dồn dập (test hiệu năng).
10. `cjk-tracknames.mid` — tên track Big5/Shift_JIS.
11. `out-of-range.mid` — note 10 và 120.
12. `long-silence.mid` — 30 s im lặng ở giữa.

**Tiêu chí pass cho từng file**: mở < 500 ms (trừ black), không crash, thời lượng hiển thị đúng ±10 ms, phát không treo note, export MIDI round-trip cho ra file mở được ở MuseScore.

## 19.7. Xuất MIDI ngược (round-trip)

Khi export, phải giữ được:
- Tempo map (không chỉ 1 tempo).
- Time signature.
- Track name (UTF-8) + instrument (program change).
- **Pedal CC64** dạng continuous (không chỉ on/off) nếu gốc là continuous.
- Channel đúng (không dồn hết về channel 0).
- Note on/off đúng thứ tự, không có note treo.

**Test round-trip**: `parse → serialize → parse` phải cho cùng số note, cùng thời lượng ±1 ms, cùng số pedal event. Đây là test rẻ nhất và bắt được nhiều bug nhất.

## 19.8. Thông báo lỗi cho người dùng (đừng để app "im lặng sai")

| Tình huống | Thông báo |
|---|---|
| File không phải MIDI | "File này không phải MIDI. Hỗ trợ .mid / .midi / .mxl (MusicXML nén)." |
| MIDI không có note | "File MIDI này không có nốt nào (chỉ có meta/tempo)." |
| Chỉ có channel 10 | "File chỉ có trống (channel 10) — không hiển thị trên bàn phím piano." |
| Có nốt ngoài 88 phím | "Có N nốt ngoài phạm vi 88 phím (A0–C8) — đã ẩn." |
| File quá lớn | "File lớn (X MB, Y nốt) — có thể giật. Vẫn mở?" |
| Note treo được sửa | (im lặng, chỉ log nội bộ) |
| Tempo không hợp lệ (0 hoặc âm) | "Tempo không hợp lệ — dùng 120 BPM." |
| MusicXML có repeat/D.C. | "Bản nhạc có dấu lặp/DC/DS — hiển thị đúng nhưng phát một lượt." |
