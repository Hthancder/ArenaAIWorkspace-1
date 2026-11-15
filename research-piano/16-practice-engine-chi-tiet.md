# 16 — Practice engine chi tiết: Wait Mode, chấm điểm, calibration, fingering

> Đây là phần **khó nhất về logic** của app mới và là thứ NoteFall hoàn toàn thiếu.
> Nội dung dưới đây là **thiết kế + pseudocode tự viết**, dựa trên việc đọc ý tưởng từ 3 nguồn (không copy code — các repo đó không có LICENSE, xem file 14.2):
> - `IbrahimKhan25/piano-app`: wait mode dựa trên cursor OSMD + DP fingering (204 dòng `fingering.ts`, 266 dòng `waitMode.ts`).
> - `Bewelge/MIDIano`: mic input + wait mode trên nền VexFlow, không license.
> - Bài viết "Grading piano timing in the browser with Web MIDI" (Keystair, 10/2026): công thức cửa sổ thời gian + calibration bằng 12 click.

## 16.1. Nguyên tắc nền: một đồng hồ, hai loại thời gian

Có **hai** trục thời gian và không được lẫn:

| Trục | Đơn vị | Dùng cho |
|---|---|---|
| `performance.now()` (ms) | ms, đơn điệu | Mọi mốc sự kiện: MIDI event `e.timeStamp`, thời điểm bấm phím, thời điểm chấm điểm |
| `AudioContext.currentTime` (s) | giây | Chỉ để **schedule** âm thanh phát ra loa |

Chuyển đổi chính xác (khi cần schedule):

```
function toCtxTime(ctx, tPerfMs):
    ts = ctx.getOutputTimestamp?.()
    if ts and ts.contextTime != null and ts.performanceTime:
        # neo hai đồng hồ tại thời điểm mẫu thực sự phát ra loa
        return ts.contextTime + (tPerfMs - ts.performanceTime) / 1000
    # fallback: trừ độ trễ browser báo
    lag = (ctx.outputLatency or 0) + (ctx.baseLatency or 0)
    return ctx.currentTime + (tPerfMs - performance.now()) / 1000 - lag
```

**Sai lầm kinh điển**: schedule click bằng `AudioContext`, chấm điểm bằng `performance.now()` mà không bù latency → mọi điểm số lệch đúng bằng độ trễ loa (10–40 ms), người chơi giỏi bị chấm "late" liên tục.

**Bẫy thứ hai**: `AudioContext` không tự chạy. Browser chỉ cho `resume()` sau **user gesture**; **sự kiện MIDI không tính là gesture**. Nếu người dùng chỉ cắm đàn và bấm phím, context vẫn `suspended`, không có lỗi, chỉ im lặng. Cách xử lý:
- Gắn `pointerdown` + `keydown` một lần để `resume()`.
- Trước mỗi phiên luyện: `await resume()` kèm timeout ~400 ms → nếu chưa `running` thì hiện thông báo "bấm vào màn hình để bật âm thanh".
- Nghe `statechange` để ẩn thông báo.

## 16.2. Calibration độ trễ (bắt buộc cho chấm điểm)

Mỗi setup (máy + tai nghe + loa + đàn) có offset khác nhau. Không đoán — **đo**:

```
Calibration:
  phát 12 click ở 80 BPM (750 ms/click)
  bỏ 4 click đầu (count-in), lấy 8 click sau
  với mỗi click, tìm lần bấm gần nhất của người dùng (trong ±375 ms)
  offset = median(t_note - t_click)     # median để 1 lần bấm trượt không phá kết quả
  lưu offset (ms) vào settings; mọi lần chấm trừ offset này
```

- Hiển thị offset hiện tại + nút đo lại. Giá trị điển hình: **+5 … +40 ms** (lớn hơn nếu dùng loa ngoài).
- Nếu |offset| > 120 ms → cảnh báo "kiểm tra tai nghe/loa, độ trễ quá cao để chấm điểm chính xác".

## 16.3. Wait Mode (chế độ "dừng chờ bấm đúng")

### 16.3.1. Bản không cần sheet music (thuần MIDI — làm trước, dễ nhất)

Ý tưởng: coi mỗi **"cụm nốt"** (các note có cùng `time`, làm tròn theo ngưỡng) là một bước. Bài dừng ở bước hiện tại cho tới khi người dùng bấm đủ tập pitch của bước đó.

```
State: currentStep (index trong steps), pressedSinceLastAdvance = Set<midi>

Khởi tạo: steps = groupNotesByOnset(song.notes, tolMs = 30)
          currentStep = 0

Khi vào bước i:
    required = steps[i].pitches           # có thể là hợp âm
    engine.seek(thời điểm bước i - prerollMs)   # lùi 1 chút để nghe "vào" tự nhiên
    engine.pause()                        # hoặc giữ playing rất chậm tuỳ chế độ
    pressedSinceLastAdvance.clear()
    highlight(required)

Khi nhận noteOn (từ addLiveListener):
    pressedSinceLastAdvance.add(midi)
    nếu required ⊆ pressedSinceLastAdvance:
        advance()

advance():
    currentStep += 1
    nếu hết bài → finish (hiện điểm)
    else → vào bước tiếp theo
```

**Các quyết định thiết kế quan trọng:**

| Vấn đề | Cách xử lý | Lý do |
|---|---|---|
| Nốt lặp lại cùng pitch | Theo dõi pitch **bấm từ lần advance gần nhất**, không theo "phím đang giữ" | Nếu theo phím đang giữ, nốt lặp tự động "đúng" dù không bấm lại |
| Hợp âm | Yêu cầu **đủ tập pitch**, thứ tự bất kỳ; chấp nhận bấm trong ±60–80 ms quanh nhau | Người mới không bao giờ bấm đồng thời tuyệt đối |
| Bấm sai | Bỏ qua (không phạt) hoặc phạt nhẹ (đếm "wrong") — tùy cấu hình | Wait mode là để học, không phải thi |
| Pedal | Không tính là "đúng"; pedal chỉ ghi nhận | Tránh người dùng giữ pedal để "qua bài" |
| Kẹt chờ mãi | Tùy chọn "tự đi sau X giây (2–10 s)" hoặc nút Skip | Có người không tìm ra phím |
| Nghe trước | Phát trước 0.5–1 s phần đệm (nếu có) hoặc nốt trước đó | Tạo ngữ cảnh nhịp |
| Loop | Hết đoạn loop → quay lại đầu loop, không phải đầu bài | Luyện đoạn khó |
| Tránh nhấp nháy audio | Không `play/pause` quá nhanh; nếu phát liên tục thì hạ `rate` xuống rất nhỏ thay vì pause | Pause/resume liên tục gây click và lệch clock |

**Biến thể "Semi-auto" (Perfect Piano)**: app tự phát tay đang không luyện (hoặc các nốt ngoài tầm tay), người dùng chỉ chơi phần được chọn → dùng `engine.triggerKey(midi, vel)` theo lịch, không cần pause.

**Biến thể "Auto"**: chỉ phát, không chờ; dùng để nghe mẫu (vẫn giữ highlight nốt).

### 16.3.2. Bản có sheet music (OSMD) — nếu muốn chờ theo *vị trí nhạc*

Ý tưởng: dùng cursor của OSMD làm "con trỏ vị trí"; mỗi vị trí cursor cần một tập pitch. Khi đủ thì `cursor.next()`.

Các **cạm bẫy đã gặp trong thực tế** (quan trọng, tiết kiệm vài ngày debug):

1. **Quy đổi cao độ**: OSMD trả `halfTone` tính từ C0 = 0 lệch một octave → MIDI = `halfTone + 12`. Nếu quên, mọi nốt lệch 1 octave.
2. **Dấu nối (tie)**: tie được lưu trên **cả hai** nốt; chỉ nốt đầu được đánh → phải bỏ qua "tie continuation" (`note.NoteTie.StartNote !== note`).
3. **Cursor bị tạo lại** mỗi lần OSMD redraw (resize, đổi zoom) → **luôn lấy cursor qua getter**, không cache tham chiếu.
4. **Nốt lặng (rest)** không yêu cầu bấm, nhưng cursor vẫn đi qua → phải skip tới vị trí kế tiếp có nốt.
5. **Fingering trong MusicXML** nằm ở `ParentVoiceEntry.TechnicalInstructions` (type = Fingering, `sourceNote` trỏ tới nốt) — đọc ở đây để hiển thị số ngón có sẵn trong file.
6. **Tô màu nốt trên sheet**: mỗi nốt có nhiều notehead SVG trong cùng một `<g>` của hợp âm → phải **xếp theo cao độ** để biết notehead nào của nốt nào; tô cả group + con bên trong, rồi trả lại sau ~500 ms (transition 0.25 s).
7. **Nhảy vị trí / loop theo ô nhịp**: `reset()` rồi `moveToNext()` tới `CurrentMeasureIndex` mong muốn; nhớ `update()` sau khi nhảy.
8. **MusicXML có giới hạn**: repeat / D.C. / D.S. **không được expand**, fermata và ritardando **không ảnh hưởng playback**, chỉ hỗ trợ `score-partwise` (đã kiểm chứng từ README của một dự án dùng OSMD). → Nếu cần chính xác tuyệt đối, **MIDI là nguồn thời gian**, MusicXML chỉ là hình ảnh.

**Khuyến nghị cho app mới**: dựng **một engine wait-mode duy nhất trên MIDI** (16.3.1), rồi *map* vị trí MIDI ↔ vị trí sheet để tô màu/di cursor. Như vậy không phụ thuộc OSMD cho logic, và wait mode vẫn chạy khi bài không có MusicXML.

## 16.4. Chấm điểm (3 chế độ)

### 16.4.1. Cửa sổ thời gian — phải co giãn theo tempo

Công thức tham khảo (từ Keystair), diễn giải lại:

```
timingWindows(msPerBeat, stepBeats):
    step        = min(1, stepBeats)              # stepBeats = khoảng ngắn nhất giữa 2 nốt, tính theo beat
    windowMs    = min(400, msPerBeat * 0.5 * step)   # trễ tối đa còn được tính "có đánh"
    goodMs      = min(140, max(70, msPerBeat * 0.18), windowMs * 0.6)  # "đúng nhịp"
    return { goodMs, windowMs }
```

| Tempo / mật độ | windowMs | goodMs |
|---|---|---|
| 60 BPM, nốt đen | 400 ms | 140 ms |
| 120 BPM, nốt móc đơn (8th) | 125 ms | 75 ms |

- Nốt chỉ được tính nếu nằm trong `windowMs` của nốt **cùng cao độ gần nhất chưa khớp**.
- Nốt dư (không khớp nốt nào) = "extra note" (tha thứ ~1 nốt / 10 nốt).

### 16.4.2. Ba chế độ

| Chế độ | Cách chạy | Chấm |
|---|---|---|
| **Wait / Melody** | Dừng chờ đúng nốt (16.3) | số nốt đúng, số lần phải thử, thời gian hoàn thành |
| **Rhythm** | Chạy đúng nhịp, không chặn | accuracy (pitch) + timing |
| **Recital** | Chạy full tốc độ, như biểu diễn | accuracy + timing + **độ dài nốt** (staccato/legato) |

### 16.4.3. Thuật toán so khớp (một lượt chơi)

```
Input: expected[] = {onMs, offMs, pitch, hand}, played[] = {onMs, offMs, pitch}
B1. Với mỗi expected, tìm played chưa dùng, cùng pitch, |Δon| ≤ windowMs, chọn Δ nhỏ nhất.
B2. Phân loại:
      khớp & |Δ| ≤ goodMs           → perfect/good
      khớp & |Δ| >  goodMs          → early/late
      không khớp nhưng có pitch đó  → miss (sai thời điểm quá xa)
      không có pitch đó             → miss (bỏ nốt)
B3. played còn lại                   → extra
B4. (Recital) so |Δduration| với ngưỡng: ngắn quá = staccato quá, dài quá = giữ phím
B5. Tổng hợp theo ô nhịp (bar) → % đúng / % đúng nhịp / early-late trung bình
B6. Kết luận "qua đoạn": ví dụ ≥90% nốt được đánh VÀ ≥70% đúng nhịp VÀ extra ≤ 10%
```

**Vì sao greedy là đủ**: với một bài piano, mỗi pitch tại một thời điểm gần như chỉ có một nốt khớp; greedy theo Δ nhỏ nhất cho kết quả thực tế trùng khớp với matching tối ưu, rẻ hơn nhiều. (Nếu làm nghiêm ngặt, dùng Hungarian cho từng cửa sổ nhỏ — không cần.)

### 16.4.4. Hiển thị kết quả (theo bài học từ app thương mại)

- **Không chỉ hiện điểm tổng** → hiện **theo bar**: "bar 3: chậm 40 ms", "bar 7: 2 nốt sai" — người dùng biết sửa gì.
- Màu: xanh = đúng, vàng = lệch nhịp, đỏ = sai/bỏ.
- Cho replay phần sai (loop đúng các bar yếu) — nút "luyện lại bar 7–8".
- Lưu lịch sử để thấy tiến bộ (biểu đồ % theo ngày).
- Ngưỡng "qua" nên cấu hình được (dễ / chuẩn / khắt khe) — người mới không nên bị chặn.

## 16.5. Gợi ý ngón tay tự động (DP / Viterbi)

### 16.5.1. Phát biểu bài toán

- Mỗi **cụm nốt** (một vị trí thời gian) là một "layer"; mỗi cách gán 5 ngón cho các nốt của cụm (tăng dần) là một "state".
- Số state cho cụm k nốt = `C(5,k)`; k = 1..5 → 5, 10, 10, 5, 1. Cụm > 5 nốt: bỏ qua (không thể một tay).
- **Cost** = Σ cost(state) + Σ cost(chuyển state trước → state này). Tìm đường rẻ nhất qua toàn bài (Viterbi + truy hồi).

Độ phức tạp: `O(n × 10 × 10)` ≈ tuyến tính — chạy tức thì cho bài 10.000 nốt.

### 16.5.2. Mô hình cost (theo tinh thần Parncutt 1997, đơn giản hoá)

**(a) Cost một state** (cùng lúc):
- **Ngón yếu / phím đen**: ngón cái (1) hoặc út (5) trên phím đen bị phạt; ngón 4 phạt nhẹ (yếu).
- **Độ căng (stretch)**: mỗi cặp ngón kề nhau có khoảng "thoải mái" và "tối đa":

| Cặp ngón | Thoải mái (semitone) | Tối đa thực tế |
|---|---|---|
| 1–2 | 5 | 8 |
| 1–3 | 7 | 10 |
| 1–4 | 9 | 12 |
| 1–5 | 10 | 13 |
| 2–3 | 3 | 5 |
| 2–4 | 5 | 7 |
| 2–5 | 7 | 9 |
| 3–4 | 2 | 4 |
| 3–5 | 4 | 6 |
| 4–5 | 2 | 3 |

  Vượt "thoải mái" → phạt tuyến tính; vượt "tối đa" → phạt rất nặng (gần như cấm).
- **Ngón không kề bị ép vào quãng hẹp** (vd 2 và 5 chơi một quãng 3) → phạt.
- **Hợp âm**: ưu tiên bàn tay mở (1-3-5 hơn 1-2-3) bằng một bonus nhỏ.

**(b) Cost chuyển state** (giữa 2 cụm):
- Cùng ngón, khác phím → phạt (phải nhảy tay).
- Ngón đi cùng chiều cao độ → cost = stretch (bàn tay mở/gập tự nhiên).
- Ngón đi ngược chiều cao độ → **crossing**: ngón cái luồn qua (thumb under) rẻ hơn nhiều so với ngón khác vắt qua; crossing không có ngón cái bị phạt rất nặng.
- Luôn có "lối thoát": **đổi vị trí tay** (reposition) với cost = hằng số nhỏ + 0.1 × số semitone — nhờ vậy thuật toán không bị kẹt khi khoảng cách quá lớn.
- `cost = min(các cách trên, reposition)` → bảo đảm luôn tìm được đường.

**(c) Tay trái**: gương hoá — đảo dấu pitch (p → −p) và đảo thứ tự để bài toán trở thành "tay phải", nhưng luật phím đen vẫn dùng pitch thật. Kết quả map ngược lại.

### 16.5.3. Ràng buộc & UX

- **Fingering có sẵn** (từ MusicXML hoặc người dùng sửa) là `fixed`: state không tôn trọng → loại bỏ; nếu xung đột toàn bộ → bỏ ràng buộc cho cụm đó và vẫn dùng fixed khi lưu.
- Khoá lưu: `(hand, vị trí trong bài, pitch)` → finger. Nhờ vậy người dùng sửa 1 nốt không làm hỏng phần còn lại.
- Cho phép: bật/tắt gợi ý, sửa từng nốt bằng phím 1–5, xoá gợi ý của cả tay, export/import bản sửa.
- Không hiển thị số ngón khi cụm > 5 nốt (không hợp lệ).
- **Không bao giờ ghi đè sửa tay của người dùng** khi tính lại.

## 16.6. Dữ liệu phiên luyện tập

```ts
type Verdict = 'perfect' | 'good' | 'early' | 'late' | 'miss' | 'extra'

type NoteResult = {
  expectedId?: number; pitch: number; hand?: 'L'|'R'
  expectedOnMs?: number; playedOnMs?: number; deltaMs?: number
  durationDeltaMs?: number; verdict: Verdict
}

type SessionResult = {
  id: string; songHash: string; mode: 'wait'|'rhythm'|'recital'
  startedAt: number; durationMs: number
  range?: { startBar: number; endBar: number }
  offsetMs: number                     // calibration đã dùng
  windows: { goodMs: number; windowMs: number }
  totals: { expected: number; perfect: number; good: number; early: number; late: number; miss: number; extra: number }
  perBar: Array<{ bar: number; expected: number; correct: number; onTime: number; avgDeltaMs: number }>
  notes: NoteResult[]                  // có thể cắt bớt nếu bài quá dài
}
```

Lưu ở IndexedDB (như NoteFall lưu takes), không nhét vào `.nfz`. Có thể export JSON nếu muốn chia sẻ.

## 16.7. Kiểm thử practice engine (không cần đàn)

Viết test thuần (Vitest) với dữ liệu tổng hợp — đây là cách duy nhất để tin được điểm số:

1. **Session hoàn hảo**: played = expected với Δ = 0 → 100%, 0 extra.
2. **Lệch đều +30 ms** (sau khi trừ offset 30) → 100% good, không late.
3. **Bỏ 1 nốt giữa bài** → 1 miss, perBar chỉ đúng bar đó.
4. **Thêm 1 nốt lạ** → 1 extra, không ảnh hưởng nốt khác.
5. **Nốt lặp cùng pitch** (C4 C4 liền nhau) → phải bấm 2 lần; bấm 1 lần = 1 miss.
6. **Hợp âm 3 nốt** bấm đủ nhưng lệch 50 ms → đúng (nếu ngưỡng chord ≥ 60 ms), lệch 200 ms → sai.
7. **Tempo thay đổi giữa bài** → cửa sổ phải co theo tempo tại chỗ đó.
8. **Wait mode**: giả lập input sai pitch → không advance; đúng → advance đúng 1 bước; loop → quay lại đầu loop.
9. **Fingering DP**: gam C trưởng đi lên 1 quãng tám → phải cho 1-2-3-1-2-3-4-5 (hoặc tương đương hợp lý); hợp âm C-E-G → 1-3-5; có fixed finger → giữ nguyên.
10. **Regression**: lưu 5–10 session mẫu (JSON) và so kết quả sau mỗi lần sửa thuật toán.

## 16.8. Tóm tắt thứ tự làm

1. Calibration + đồng hồ (`toCtxTime`, xử lý gesture) — **nền của mọi thứ**.
2. Wait mode thuần MIDI + highlight phím.
3. Scoring Rhythmic + per-bar report.
4. Recital + note length.
5. Sheet music (OSMD) + cursor + tô màu.
6. Fingering DP + UI sửa.
7. Lịch sử + biểu đồ + "luyện lại bar yếu".
