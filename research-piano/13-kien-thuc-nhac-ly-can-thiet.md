# 13 — Kiến thức nhạc lý / piano cần thiết khi làm app

> Không phải để dạy nhạc, mà để **code đúng**: mọi tính năng (chia tay, gợi ý ngón, hợp âm, scale, chấm điểm, sheet music) đều dựa trên các khái niệm dưới đây. Ghi kèm "áp dụng vào đâu".

## 13.1. Bàn phím & cao độ

- Piano chuẩn **88 phím**: A0 (MIDI 21) → C8 (MIDI 108). 52 phím trắng, 36 phím đen.
- Mẫu 12 phím lặp lại: C C# D D# E F F# G G# A A# B. Khoảng cách giữa 2 phím liền = **1 semitone** (nửa cung).
- **Middle C = C4 = MIDI 60**. Quy ước octave: C4 ở giữa; A4 = 440 Hz.
- Tần số: `f = 440 × 2^((midi − 69) / 12)` — dùng khi làm synth hoặc pitch detection.
- Phím đen nằm giữa: C#/Db, D#/Eb, F#/Gb, G#/Ab, A#/Bb — **enharmonic** (2 tên, 1 phím). App phải có setting `accidental: sharp | flat`.
- **Áp dụng:** layout bàn phím, nhãn nốt, transpose, solfège, chấm điểm theo pitch, vẽ sheet.

## 13.2. Quãng (intervals)

| Semitone | Tên | Ký hiệu |
|---|---|---|
| 0 | unison | P1 |
| 1 | minor 2nd | m2 |
| 2 | major 2nd | M2 |
| 3 | minor 3rd | m3 |
| 4 | major 3rd | M3 |
| 5 | perfect 4th | P4 |
| 6 | tritone | A4/d5 |
| 7 | perfect 5th | P5 |
| 8 | minor 6th | m6 |
| 9 | major 6th | M6 |
| 10 | minor 7th | m7 |
| 11 | major 7th | M7 |
| 12 | octave | P8 |

- **Áp dụng:** chord detection, hiển thị khoảng cách trong bài, gợi ý ngón (khoảng cách lớn → ngón dài/ngón cái luồn).

## 13.3. Hợp âm (chords) — cho tính năng chord detection

- **Triad**: major (0,4,7), minor (0,3,7), diminished (0,3,6), augmented (0,4,8).
- **7th**: maj7 (0,4,7,11), m7 (0,3,7,10), dom7 (0,4,7,10), m7b5 (0,3,6,10), dim7 (0,3,6,9), mMaj7 (0,3,7,11).
- **Sus**: sus2 (0,2,7), sus4 (0,5,7). **6th**: 6 (0,4,7,9), m6 (0,3,7,9). **Add9**: (0,4,7,14).
- **Inversion**: cùng tập pitch, bass khác → tên `/E`, `/G`… Nhận dạng: so tập pitch class (bỏ octave), rồi xác định root theo bass + khoảng cách.
- **Áp dụng:** `learn/chords.ts` — nhận hợp âm từ tập note đang giữ, hiển thị tên; hiển thị trên timeline khi phát MIDI.

## 13.4. Scale & key

- **Major**: 0,2,4,5,7,9,11. **Natural minor**: 0,2,3,5,7,8,10. **Harmonic minor**: 0,2,3,5,7,8,11. **Melodic minor (up)**: 0,2,3,5,7,9,11.
- **Mode** (trên major): Ionian, Dorian (0,2,3,5,7,9,10), Phrygian, Lydian, Mixolydian, Aeolian, Locrian.
- **Pentatonic** major (0,2,4,7,9), minor (0,3,5,7,10); **blues** (0,3,5,6,7,10).
- **Key signature**: số dấu thăng/giáng; vòng quãng 5 (C, G, D, A, E, B, F#, C# / F, Bb, Eb, Ab, Db, Gb).
- **Áp dụng:** `learn/scales.ts` — highlight phím thuộc scale, mờ phím ngoài; gợi ý key khi import MIDI (đếm pitch class + phân bố); hiển thị key signature trên sheet.

## 13.5. Nhịp & tiết tấu

- **Time signature**: 4/4, 3/4, 6/8, 2/4, 12/8… `beats per bar` + `beat unit`.
- **Note value**: whole (4 beat), half (2), quarter (1), 8th (0.5), 16th (0.25), dotted (×1.5), triplet (×2/3).
- **Tempo**: BPM = quarter notes per minute. Thuật ngữ: Largo 40–60, Adagio 66–76, Andante 76–108, Moderato 108–120, Allegro 120–156, Presto 168–200, Prestissimo >200.
- **Swing / shuffle**: chia 8th không đều — cần setting riêng nếu làm jazz.
- **Áp dụng:** metronome, grid/snap của editor, vẽ bar lines, chấm timing, tự sinh bar từ MIDI, tempo map khi parse.

## 13.6. Cường độ & sắc thái

- **Velocity** (MIDI 1–127) ↔ dynamic markings: pp (≈16–32), p (≈32–48), mp (≈48–64), mf (≈64–80), f (≈80–96), ff (≈96–112), fff (≈112–127). Không tuyến tính tuyệt đối — dùng để map hiển thị.
- **Articulation**: staccato (ngắn), legato (liền), tenuto, accent, marcato, fermata.
- **Áp dụng:** hiển thị dynamic trên sheet; chấm "note length" trong scoring; velocity curve; hiển thị velocity trong editor (màu/độ đậm nốt).

## 13.7. Pedal

- **Sustain (damper, CC64)**: nhấn giữ → mọi note ngừng kêu khi pedal nhả. Kỹ thuật: legato pedaling (nhấn ngay sau khi đổi hợp âm), half-pedal, flutter pedal.
- **Sostenuto (CC66)**: chỉ giữ các note đang nhấn tại thời điểm pedal → dùng cho note dài.
- **Soft / una corda (CC67)**: giảm âm lượng + đổi màu âm.
- **Áp dụng:** engine (đã có CC64 chuẩn), hiển thị pedal trên timeline, chấm điểm pedal (nâng cao), phân tích MIDI để suy ra pedal khi transcription.

## 13.8. Ngón tay (fingering) — cho gợi ý ngón tự động

- Quy ước: **1 = ngón cái, 2 = trỏ, 3 = giữa, 4 = áp út, 5 = út**. Tay trái dùng cùng số nhưng mirror.
- Nguyên tắc cơ bản:
  - Không dùng ngón cái/út trên phím đen trong chuỗi liền (trừ trường hợp đặc biệt).
  - **Ngón cái luồn (thumb under)** khi đi lên, **vắt chéo (cross over)** khi đi xuống.
  - Tránh ngón 4 và 5 trên phím đen ở vị trí quan trọng; ưu tiên 1-2-3 cho phím đen.
  - Nhảy xa (>5 semitone) → đổi vị trí tay (position shift), thường qua ngón 1 hoặc 5.
  - Hợp âm: 3 note → 1-3-5 hoặc 1-2-5; 4 note → 1-2-3-5.
- **Thuật toán DP** (như `IbrahimKhan25/piano-app`): state = (note index, finger), cost = khoảng cách ngón + phạt ngón cái/út trên phím đen + phạt nhảy + phạt lặp ngón; truy hồi để lấy chuỗi tối ưu.
- **Áp dụng:** `learn/fingering.ts`; lưu vào `NoteEvent.finger`; cho phép sửa tay; export/import.

## 13.9. Kỹ thuật luyện tập (để thiết kế tính năng practice đúng)

| Phương pháp | Cách app hỗ trợ |
|---|---|
| **Chia nhỏ (chunking)** | Loop A–B theo bar/phrase, đánh dấu đoạn khó |
| **Chậm rồi nhanh dần** | Speed 50% → tăng 5–10% khi đạt ngưỡng; "metronome ladder" |
| **Tay riêng** | Hands separate + tự phát tay kia |
| **Nghe trước – chơi sau** | Chế độ nghe demo (app tự phát), rồi luyện |
| **Không dừng khi sai (rhythm first)** | Rhythm Mode chấm timing, không chặn |
| **Dừng khi sai (accuracy first)** | Wait Mode, chặn tới khi đúng |
| **Sight-reading** | Test 20 giây nhìn trước, chấm %; ẩn nốt rơi |
| **Ghi âm & nghe lại** | Record take, so sánh với bản gốc |
| **Mục tiêu đo được** | Điểm theo bar, % đúng, streak |

- Nguyên tắc sư phạm: **luôn cho người học thấy tiến bộ** (điểm, streak, biểu đồ), **không phạt nặng** (tránh làm người mới bỏ cuộc), **không để falling notes thành gậy chống** (khuyến khích chuyển sang sheet sau khi quen).

## 13.10. Đọc nhạc (notation) — mức cần cho sheet music

- **Staff 5 dòng**, treble (G clef) cho tay phải, bass (F clef) cho tay trái; **grand staff** nối bằng brace.
- **Ledger lines** trên/dưới staff; **accidental** (♯ ♭ ♮) trong ô nhịp; **key signature** đầu dòng; **time signature** sau key.
- **Note values** (whole/half/quarter/8th/16th) + **rest**; **beam** cho 8th/16th; **dot**; **tie** (nối 2 nốt cùng cao độ); **slur** (legato); **tuplet** (triplet).
- **Dynamics** (p, f, crescendo), **tempo marking**, **articulation** (staccato dot, accent), **pedal marking** (Ped. ✱).
- **Áp dụng:** khi render MusicXML (OSMD lo phần lớn); khi tự sinh sheet từ MIDI (VexFlow) phải tự quyết định beam/tie/voice — đây là lý do khuyến nghị **MusicXML là nguồn chính**.

## 13.11. Điều KHÔNG nên tự làm (để tránh sai kiến thức)

- Không tự "đoán" key signature từ MIDI rồi hiển thị như sự thật — chỉ gợi ý, cho sửa.
- Không tự sinh fingering mà không cho sửa — luôn cho override.
- Không chấm "đúng/sai" theo pitch mà bỏ qua thời gian — luôn tách accuracy và timing.
- Không coi MIDI velocity là "độ to tuyệt đối" — nó phụ thuộc nhạc cụ và velocity curve.
- Không hiển thị hợp âm khi tập pitch không khớp mẫu nào — im lặng thay vì đoán bừa.
