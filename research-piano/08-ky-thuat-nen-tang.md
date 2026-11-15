# 08 — Kỹ thuật nền tảng (cho người sẽ build app)

> Mục đích: gom toàn bộ kiến thức kỹ thuật cần để làm app piano web chơi thật trên máy tính, tùy chỉnh MIDI tự do. Đọc file này trước khi code.

## 8.1. MIDI — Standard MIDI File (SMF)

### Cấu trúc file
- **Header chunk** `MThd`: format (0/1/2), số track, division (ticks per quarter note hoặc SMPTE).
  - **Format 0**: 1 track duy nhất chứa mọi channel.
  - **Format 1**: nhiều track song song, track 0 thường là conductor (tempo/time signature/key signature).
  - **Format 2**: nhiều pattern độc lập (hiếm).
- **Track chunk** `MTrk`: chuỗi delta-time + event.
  - **Note On** (0x9n), **Note Off** (0x8n) hoặc Note On velocity 0.
  - **Control Change** (0xBn): CC64 sustain (≥64 = pedal xuống), CC7 volume, CC10 pan, CC1 modulation, CC11 expression, CC66 sostenuto, CC67 soft.
  - **Program Change** (0xCn): đổi instrument GM.
  - **Pitch Bend** (0xEn): 14-bit.
  - **Meta**: tempo (0x51, µs/quarter), time signature (0x58), key signature (0x59), track name (0x03), end of track (0x2F).
- **GM channel 10 = drum kit** (lưu là channel 9 zero-based) — phải loại khỏi bàn phím piano hoặc render riêng.

### Điều cần xử lý khi parse (NoteFall đã làm — tham khảo `src/midi/parse.ts`)
- Ghép Note On/Off thành `NoteEvent { id, midi, time, duration, velocity, track }`.
- Note On trùng pitch khi note trước chưa off → **resolveOverlaps** (cắt note trước, đánh dấu retrigger) — nếu không, engine sẽ nuốt note.
- Tempo map: đổi tempo giữa bài → đổi tick → giây. Speed automation (speedMap) là lớp phụ.
- Track name + track có note hay không (giữ index khớp với `NoteEvent.track`).
- **Sustain pedal** thành mảng `{ time, value 0..1 }` (giữ half-pedal).
- Sostenuto/soft: giữ để round-trip, playback có thể bỏ qua.
- **Không** dựa vào tick khi phát: chuyển hết sang giây (float) lúc parse — đơn giản và chính xác khi speed thay đổi.

### Serialize (xuất MIDI)
- Ghi lại đúng format, tempo map, CC pedal, program change, track name.
- Hand/finger không có chỗ trong SMF → lưu sidecar (như NoteFall: `manifest.noteHands`).

### Thư viện
- `@tonejs/midi` — parse/serialize, đọc tempo, track, note; NoteFall dùng. Nhẹ, đủ tốt.
- `midi-file` (npm) — parse/serialize thấp cấp hơn, giữ mọi event.
- `mido`/`pretty_midi` (Python) — nếu làm tool offline.

## 8.2. Web MIDI API (input từ bàn phím MIDI)

```js
const access = await navigator.requestMIDIAccess({ sysex: false })
for (const input of access.inputs.values()) {
  input.onmidimessage = (e) => {
    const [status, d1, d2] = e.data
    const type = status & 0xf0, ch = status & 0x0f
    if (type === 0x90 && d2 > 0) noteOn(d1, d2 / 127)
    else if (type === 0x80 || (type === 0x90 && d2 === 0)) noteOff(d1)
    else if (type === 0xb0 && d1 === 64) pedal(d2 / 127)   // CC64 half-pedal
  }
}
```
- **Hỗ trợ trình duyệt** (kiểm chứng caniuse 2026-11-14 — xem bảng đầy đủ ở file 17.1): Chrome 43+, Edge 79+, Opera 30+, Samsung 4+ (desktop + Android); **Firefox 108+ desktop** nhưng cần cài **Site Permission Add-On** (Firefox Android: không); **Safari: KHÔNG hỗ trợ ở mọi phiên bản** (macOS/iOS/iPadOS) — chỉ có extension bên thứ ba "Web MIDI for Safari". Vì mọi browser trên iOS đều là WebKit → **iPhone/iPad không có Web MIDI**. → Bắt buộc có fallback: PC keyboard + chuột/touch cho Safari/Firefox/iOS.
- **Không được tin blog**: nhiều bài viết 2026 nói "Safari 18+ hỗ trợ Web MIDI" — **sai**. Xem file 17.6.
- HTTPS bắt buộc (localhost cũng OK).
- Cần **user gesture** để mở MIDI access trên một số trình duyệt.
- `access.onstatechange` để phát hiện cắm/rút thiết bị; lưu device id yêu thích.
- Gửi output (đèn phím, MIDI ra DAW): `output.send([0x90, note, vel])` — dùng cho lighted keyboard.

### Latency thực tế (đo bởi MIDI-Scenes)
| Kết nối | Latency |
|---|---|
| USB wired MIDI → Web Audio | ~15–30 ms (Chrome), tốt nhất <20 ms |
| Bluetooth MIDI | +100–250 ms → **không chơi được** (chỉ dùng để ghi/duyệt) |
| Web Audio `latencyHint: 'interactive'` | Chrome tôn trọng; Firefox/Safari một phần |
| Tổng mục tiêu | ≤30 ms tốt, ≤50 ms chấp nhận được |

→ Trong UI phải **cảnh báo** khi phát hiện Bluetooth MIDI (không cho chọn làm input chính, hoặc hiện badge "độ trễ cao").

## 8.3. Web Audio API — engine âm thanh

### Kiến trúc tối thiểu
```
AudioContext (latencyHint: 'interactive', sampleRate 48k)
 └─ masterGain
     ├─ reverbSend → ConvolverNode (impulse) → wetGain ┐
     └─ dryGain ────────────────────────────────────────┴→ destination
```

### Phát sample piano
- Mỗi note = nhiều buffer theo velocity layer (Salamander: 16 layer) + round-robin.
- **Không** new AudioBufferSourceNode mỗi note nếu latency quan trọng? Thực tế vẫn ổn (tạo node rẻ), nhưng phải **preload decode** trước.
- Schedule bằng `AudioContext.currentTime`, **không** dùng `setTimeout` để canh nhịp.
- Attack: `gain.setValueAtTime`, release: `exponentialRampToValueAtTime` về 0.0001 rồi `stop()`.
- **Ngưỡng an toàn**: lookahead ~15 ms, stop buffer ~20 ms (NoteFall dùng đúng số này).

### Lỗi kinh điển cần tránh
1. **Hai note cùng pitch**: smplr mặc định `stopId = midi number` → note sau stop note trước. Phải truyền `stopId` duy nhất (`s${noteId}`).
2. **Click/pop** khi release đột ngột → dùng ramp, không `stop()` ngay.
3. **Tab nền bị throttle** `requestAnimationFrame` → cần Worker `setInterval(25ms)` làm tick driver thứ hai (NoteFall làm).
4. **iOS/Safari**: AudioContext phải `resume()` trong user gesture. ⚠️ **Sự kiện MIDI KHÔNG tính là user gesture** → nếu người dùng chỉ cắm đàn và bấm phím, context vẫn `suspended`, không có lỗi, chỉ im lặng. Phải gắn `pointerdown`/`keydown` để `resume()`, và trước mỗi phiên luyện thì `await resume()` kèm timeout ~400 ms để hiện thông báo "bấm vào màn hình để bật âm thanh".
5. **Chấm điểm sai vì lẫn hai đồng hồ**: schedule bằng `AudioContext.currentTime` nhưng chấm bằng `performance.now()` mà không bù latency → lệch đúng bằng độ trễ loa. Dùng `ctx.getOutputTimestamp()` để neo hai đồng hồ (chi tiết + code ở file 16.1).
5. **Polyphony**: 88 note × nhiều layer có thể nổ RAM nếu decode hết. Decode lazy theo pitch/velocity thực dùng, cache LRU.
6. **Reverb convolution dài** tốn CPU → dùng impulse ngắn hoặc Freeverb đơn giản.

### Sample libraries
| Nguồn | Chi tiết | Giấy phép |
|---|---|---|
| **Salamander Grand Piano V3** | Yamaha C5, 48kHz 24-bit, 16 velocity layer, SFZ FLAC 707 MiB / SF2 296 MiB | **CC BY 3.0** (ghi công Alexander Holm) |
| GeneralUser GS `.sf2` | 128 GM instrument | Free (kiểm tra điều khoản) |
| `gleitz/midi-js-soundfonts` | Soundfont MIDI.js mp3, dùng ngay trong browser | MIT-ish, xem repo |
| FluidR3_GM | GM đầy đủ | MIT-like |
| SoundFont player | `danigb/soundfont-player` hoặc `smplr` | MIT |

→ App mới: giữ Salamander cho grand piano + thêm SoundFont loader cho đa instrument (P1).

## 8.4. Lịch phát (scheduling) & transport

- **Một nguồn thời gian duy nhất** (`audio/clock.ts` kiểu NoteFall): `now()` đọc wall clock hoặc virtual clock khi export offline.
- **Transport state**: playing, position (giây), rate, loopStart/loopEnd.
- **Scheduler**: mỗi tick (Worker 25 ms) lấy note trong cửa sổ `[pos, pos + lookahead]` chưa schedule → schedule với `audioTime = ctx.currentTime + (noteTime - pos) + latencyComp`.
- **Seek/loop**: cancel tất cả scheduled node, reset con trỏ, resume.
- **Speed automation**: map thời gian bài ↔ thời gian thực (NoteFall `speedMap.ts` — tích phân nghịch đảo).
- **Latency compensation**: offset nhỏ để note nghe đúng lúc hình ảnh chạm hit line.

## 8.5. Sheet music / notation trong browser

| Thư viện | Khả năng | Dùng cho |
|---|---|---|
| **VexFlow** | Vẽ khuông nhạc SVG/canvas từ dữ liệu tự do, cursor dễ làm | Tự sinh sheet từ MIDI (Midiano), composer |
| **OpenSheetMusicDisplay (OSMD)** | Render MusicXML chuẩn, đổi màu note theo index, ẩn part, export SVG/PNG, chạy headless Node | Hiển thị MusicXML, cursor sync (piano-app) |
| **abcjs** | ABC notation → sheet + playback | Nhập bài nhanh bằng text |
| **Verovio** | MEI/MusicXML → SVG, mạnh nhưng nặng | Không khuyến nghị |

- **Đồng bộ cursor với playback**: OSMD có `cursor` API; hoặc với VexFlow phải tự map note→vị trí.
- **Tự sinh sheet từ MIDI** khó hơn render MusicXML: cần ước lượng nhịp, tách giọng, xử lý beaming — Midiano làm được ở mức cơ bản. Khuyến nghị: **MusicXML là nguồn chính cho sheet**, MIDI chỉ để luyện falling notes.

## 8.6. Đồ họa nốt rơi (falling notes)

Hai hướng:
1. **2D Canvas/WebGL** (đơn giản, nhẹ, chạy mobile tốt): mỗi note là rect, màu theo track/tay, scroll theo trục thời gian. Midiano, Perfect Piano, Synthesia dùng hướng này.
2. **3D Three.js/R3F** (NoteFall): nốt là mesh 3D, shader SDF cho bevel/gradient, reflections, particles, bloom.

Cho app mới (ưu tiên máy tính + "đẹp như NoteFall"): giữ **3D của NoteFall**, nhưng thêm **fallback 2D** khi máy yếu / mobile (P2).

Điểm kỹ thuật NoteFall cần nhớ khi sửa:
- Hit line = `KEYBOARD_Y + WHITE_KEY_LENGTH`; clip nốt bằng SDF per-fragment chứ không phải z-occlusion (nếu đổi z sẽ bị parallax).
- Nốt dùng **1 InstancedMesh** với shader chung → đổi material chỉ là uniform.
- `keyboardViewShift` là **lens shift** (`camera.view.offsetY`), không phải move keyboard — đừng "sửa" bằng cách đổi Y world.

## 8.7. Export video/audio

- **Audio**: `OfflineAudioContext` render nhanh hơn realtime → encode WAV thủ công (write header) hoặc `AudioEncoder` (AAC/Opus).
- **Video**: **không** dùng `MediaRecorder` (realtime, rơi frame). Dùng **WebCodecs `VideoEncoder`** + render từng frame bằng R3F (`advance` → `gl.finish` → `readPixels` → VideoFrame) rồi **mux** bằng `mediabunny` (MP4/WebM).
- Render theo frame cho phép 4K60 trên máy không đủ nhanh realtime; cần xử lý **virtual clock** để engine/particles chạy theo frame time chứ không phải wall clock (NoteFall `clock.ts`).
- Hỗ trợ codec (**kiểm chứng 2026-11**): WebCodecs có ở Chrome/Edge 94+, **Firefox 130+ desktop** (không có trên Firefox Android), **Safari 26+** (Safari 16.4–18.7 chỉ có phần **video**, `AudioEncoder` chưa có). Encode: H.264 gần như mọi nơi; **AAC có ở Chrome + Safari nhưng KHÔNG ở Firefox**; **Opus có ở mọi nơi**; **MP3 encode gần như không hỗ trợ ở đâu** (muốn MP3 phải dùng lamejs — LGPL). Bảng đầy đủ: file 17.2.
- Luôn **probe** `VideoEncoder.isConfigSupported` + `AudioEncoder.isConfigSupported` trước khi render (NoteFall làm đúng trong `export/codec/preflight.ts`).
- Canvas cần `preserveDrawingBuffer` hoặc đọc ngay sau render.

## 8.8. Lưu trữ & project file

- **File-based** (`.nfz` zip: manifest + assets) tốt hơn IndexedDB cho công việc sáng tạo — người dùng kiểm soát file, không mất khi clear site data.
- IndexedDB chỉ dùng cho **takes ghi âm tạm**, recent files handle, cache sample.
- File System Access API (Chrome/Edge) cho Save tại chỗ; fallback `<input type=file>` + download (Safari/Firefox).
- **Không autosave** nhưng phải có `beforeunload` cảnh báo + chỉ báo dirty rõ.
- Versioning: có `appVersion` trong manifest; trước 1.0 dùng lenient merge settings.

## 8.9. Âm thanh → MIDI (transcription) — P2

- **Basic Pitch** (Spotify, ONNX) — nhẹ, chạy browser/Node, đa nhạc cụ.
- **ByteDance piano transcription** (ONNX, ~154 MB) — chất lượng cao cho piano, Suma-Udd NoteFall dùng.
- **Piano transcription** cho polyphonic piano khó (pedal, overtone) → cần hậu xử lý (onset merge, pedal CC64 suy ra).
- Trong browser: `onnxruntime-web` + WASM/WebGPU.

## 8.10. Mic detection (nghe đàn cơ) — P2, rất khó

- Pipeline: getUserMedia → AudioWorklet → FFT/CQT → onset detection → pitch estimation đa âm (multi-pitch) → so khớp note mong đợi.
- Đa âm piano (nhiều note cùng lúc + pedal) là bài toán khó; Simply Piano dùng model riêng ("MusicSense").
- Thực tế: chỉ nên chấm "có đúng nốt giai điệu không" thay vì polyphonic đầy đủ; hoặc dùng model transcription như 8.9 rồi so sánh.
- Không nên đưa vào P0/P1 — chi phí cao, độ chính xác thấp trong phòng ồn.

## 8.11. Hiệu năng & chất lượng

| Vấn đề | Cách xử lý |
|---|---|
| 1000+ note trên màn hình | InstancedMesh / batch, chỉ render note trong cửa sổ thời gian |
| MIDI lớn (100k note) | Parse trong Web Worker, typed arrays |
| Máy yếu / không WebGL2 | Fallback 2D canvas, giảm particle/bloom |
| Màn hình nhỏ | Layout responsive, ẩn timeline/inspector |
| Pin / tab nền | Pause visual, Worker vẫn chạy audio |
| Sample tải chậm | Preload layer phổ biến trước (velocity trung bình), lazy layer khác |
| Cache | Cache Storage cho sample + hands data, versioned |

## 8.12. Tiếp cận (accessibility) & i18n

- Keyboard-only navigation (react-aria có sẵn trong NoteFall).
- Screen reader cho transport, không cho canvas.
- i18n: NoteFall có en/ja → thêm `vi` (ưu tiên người dùng Việt).
- Màu: đảm bảo contrast, có preset cho người mù màu (note color theo pattern, không chỉ màu).
