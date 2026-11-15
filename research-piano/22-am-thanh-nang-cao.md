# 22 — Âm thanh nâng cao: sample, mô hình vật lý, pedal, reverb, độ to

> Mục tiêu: hiểu **vì sao tiếng đàn của app nghe "thật" hay "giả"**, và làm gì trong web app để tối đa hoá chất lượng trong giới hạn trình duyệt.

## 22.1. Hai công nghệ: sample và physical modeling

| | **Sample** (NoteFall, Salamander) | **Physical modeling** (Pianoteq) |
|---|---|---|
| Bản chất | Ghi âm từng nốt ở nhiều mức lực, phát lại + biến đổi | Tính toán dao động dây, búa, soundboard theo thời gian thực |
| Số mức lực | Hữu hạn: **16 layer** là chuẩn tốt (Salamander V3); nhiều thư viện chỉ 8 | **127 mức liên tục** (mọi velocity MIDI) |
| Sympathetic resonance | Xấp xỉ bằng layer ghi sẵn / reverb | **Tính thật** từ tương tác dây |
| Half-pedal | Xấp xỉ (fade) | Mô phỏng như đàn thật |
| Dung lượng | ~77 MB (Salamander nén) → hàng trăm GB (thư viện lớn) | Vài chục MB |
| Điểm yếu | Chuyển layer có thể nghe "nấc"; lặp lại cùng nốt nghe y hệt | Attack đôi khi bị coi là "hơi tổng hợp"; release tail khó |
| Trong browser | ✅ Khả thi (Salamander + smplr) | ❌ Không có engine mã nguồn mở đủ tốt; tự viết = dự án nhiều năm |

**Kết luận thực dụng:** dùng **sample** (đã có), và **xấp xỉ** các hành vi của modeling bằng kỹ thuật rẻ (22.3). Đừng cố tự viết physical modeling.

## 22.2. Những gì tạo nên "cảm giác thật" — xếp theo mức ảnh hưởng

1. **Velocity layers + đường cong velocity** (lực bấm → âm lượng **và** màu âm).
2. **Release / key-off noise** (tiếng tắt phím, tiếng búa trả về) — thiếu thì nghe "MIDI".
3. **Sympathetic resonance** (dây không gõ vang theo) — đặc biệt khi giữ pedal.
4. **Pedal noise + half-pedal** (âm thanh cơ học + thay đổi độ dài đuôi).
5. **Stereo image** (đàn rộng, âm trầm bên trái, cao bên phải).
6. **Room/reverb** phù hợp (quá nhiều = muddy; quá ít = khô, giả).
7. **Round-robin** (cùng nốt lặp lại không y hệt).
8. **Detune nhẹ giữa các dây unison** (đàn thật không bao giờ hoàn hảo).
9. **Dynamic range & limiter** (dày cụm hợp âm không bị vỡ tiếng).

## 22.3. Xấp xỉ trong Web Audio (rẻ, hiệu quả)

### (a) Velocity → âm lượng + màu âm
- Chọn layer gần nhất (16 layer = ~8 đơn vị velocity/layer) + **crossfade** giữa 2 layer kề khi velocity nằm giữa (2 voice cùng lúc, gain theo khoảng cách) → giảm "nấc".
- Thêm **low-pass filter** mở dần theo velocity (velocity thấp → bớt bổng) — bù cho việc layer không hoàn hảo.
- Áp **velocity curve** người dùng chỉnh (đã có) + **velocity compensation** (NoteFall có `velocityCompensation`).

### (b) Release noise
- Bộ Salamander có `rel*` (release) — NoteFall **bỏ qua**. Thêm: khi note off, phát sample release tương ứng ở mức rất nhỏ (−20…−26 dB).
- Nếu không có sample release: dùng envelope release ngắn + một "thump" lọc thấp rất nhỏ.

### (c) Sympathetic resonance (khi pedal xuống)
Ba mức, chọn theo công:
1. **Rẻ nhất**: gửi tín hiệu piano vào reverb dài hơn khi pedal xuống (wet +, decay +) → cảm giác "vang theo". Đây là cách nhiều web piano làm.
2. **Trung bình**: khi pedal xuống, với mỗi note mới, phát thêm **rất nhỏ** các nốt thuộc chuỗi hài của nó (quãng 8, 5, 3) ở mức −30 dB, dùng cùng sample nhưng detune nhẹ. Cần giới hạn số voice.
3. **Tốt nhất (khó)**: impulse response riêng cho "resonance bus" (thu từ đàn thật với pedal), convolve. Đây là cách thư viện lớn làm.
- Bộ Salamander có `harm*` — có thể dùng làm layer resonance **rất nhỏ** dưới tín hiệu chính.

### (d) Half-pedal
- NoteFall đã làm đúng: CC64 giữ 0..1 → damper lift → fade hàm mũ với time constant; re-target khi pedal di chuyển.
- Bổ sung: **pedal noise** (sample `pedal*`) khi CC64 vượt ngưỡng, âm lượng theo velocity của lần đạp.

### (e) Stereo & detune
- Sample Salamander đã stereo (close mic). Nếu cần rộng hơn: **không** dùng stereo widener mạnh (làm pha, mất tự nhiên). Detune ±2–4 cent cho 2 voice unison (nếu có) hoặc ±1–2 cent khi layer trùng.
- Trầm → pan trái nhẹ, cao → phải nhẹ (mô phỏng vị trí dây) nếu muốn "nghe như đang ngồi trước đàn".

### (f) Reverb
- Tham số NoteFall đã expose: size, decay time, decay, pre-delay, damping, hi-cut, low-cut, dry/wet.
- Gợi ý preset: **"Close"** (dry 1.0, wet 0.15, decay 1.2 s, hi-cut 8 kHz) · **"Studio"** (wet 0.35, 2.2 s) · **"Hall"** (wet 0.5, 3.5 s, pre-delay 40 ms).
- Tránh: wet > 0.6 với nhạc nhanh (nhòe), low-cut < 60 Hz (ù), hi-cut > 12 kHz (chói).
- Convolver với impulse dài tốn CPU → dùng impulse 1.5–3 s, hoặc Freeverb/`Reverb` của Tone (nhưng đang muốn bỏ Tone).

### (g) Limiter & headroom
- Cụm hợp âm dày (10+ nốt) dễ clipping. Đặt **master gain −6 dB headroom** + `DynamicsCompressorNode` làm limiter (threshold −3 dB, ratio 20:1, attack 3 ms, release 100 ms) → không vỡ.
- Đo: render 1 hợp âm 10 nốt fortissimo ở 48 kHz, kiểm tra peak ≤ −1 dBFS.

## 22.4. SoundFont / đa nhạc cụ (P1)

| Định dạng | Cách dùng trong web | Ghi chú |
|---|---|---|
| **`.sf2`** (SoundFont 2) | Parse bằng JS (tự viết hoặc `soundfont-player` hỗ trợ) → decode sample → phát | 1 file chứa 128 GM instrument; dung lượng 30–300 MB |
| **`.sfz`** | Text + file sample rời | Linh hoạt, nhưng web phải tự host hàng nghìn file |
| **MIDI.js soundfonts** | mp3/ogg theo từng nốt, tải theo instrument | Nhẹ, nhanh, chất lượng trung bình; tốt cho bản demo |
| **Sample pack tự chọn** | Người dùng chọn thư mục | Cần File System Access / zip |

**Gợi ý triển khai:** ưu tiên **8 timbre đóng gói sẵn** (grand, bright, electric piano, organ, music box, synth pad, harpsichord, strings) + **load `.sf2` người dùng** ở mức "nâng cao". Mỗi track chọn instrument theo program change.

## 22.5. Độ to, loudness và mastering (quan trọng cho video)

| Ngữ cảnh | Mục tiêu | Ghi chú |
|---|---|---|
| Export video cho YouTube | **−14 LUFS integrated**, true peak **−1 dBTP** | YouTube normalize về ~−14 LUFS (desktop), ~−13 (mobile); **chỉ giảm, không tăng** → làm to hơn vô ích, chỉ mất dynamic |
| TikTok / Reels / Shorts | −14 … −11 LUFS (nền tảng thường to hơn) | Kiểm tra sau khi upload |
| File WAV để dùng lại | Peak ≤ −1 dBFS, không normalize | Để người dùng tự master |
| Nghe trên web | Không cần chuẩn hoá, nhưng đừng clipping | Volume mặc định ~0.8 như NoteFall |

**Không nên**: nén/limiter mạnh để "to" — piano cần dynamic. Chỉ limiter bảo vệ.

**Nếu muốn đo LUFS trong web**: dùng `AudioWorklet` + thư viện đo loudness (BS.1770) hoặc ước lượng bằng RMS; đơn giản hơn: hiện **peak meter** + cảnh báo clipping, và để người dùng tự chọn mức.

## 22.6. Chất lượng khi export

| Hạng mục | Khuyến nghị |
|---|---|
| Sample rate | **48 kHz** (chuẩn video); 44.1 kHz nếu chỉ audio |
| Bit depth | **24-bit WAV** khi export audio (nếu tự ghi header), hoặc float32 → 24-bit |
| Dither | Chỉ khi xuống 16-bit; với 24-bit không cần |
| AAC | 320 kbps stereo cho MP4 (YouTube nhận tới 384) |
| Opus | 128–192 kbps cho WebM |
| Render engine | `OfflineAudioContext` (nhanh hơn realtime nhiều lần) — NoteFall đã làm |
| Tail | Giữ **5 s** sau nốt cuối (NoteFall `TAIL_SECONDS = 5`) để reverb không bị cắt |

## 22.7. Voice management (polyphony)

| Vấn đề | Cách xử lý |
|---|---|
| 88 nốt cùng lúc + pedal | Giới hạn **~96–128 voice**; voice stealing theo "quietest + oldest" |
| Pedal giữ nhiều voice | Ưu tiên giữ voice đang nghe; giải phóng voice đã fade gần hết |
| Layer crossfade | 2 voice/nốt → giảm giới hạn note còn ~48–64 |
| Release sample | Voice riêng, ngắn, ưu tiên giải phóng |
| Đo | Log số voice trung bình/peak trong dev panel; mục tiêu peak < 80% giới hạn |

## 22.8. Kiểm thử âm thanh (không cần tai nghe tốt)

1. **Null test**: render cùng 1 MIDI 2 lần với cùng settings → phải **bit-identical** (kiểm tra tính deterministic của engine offline).
2. **Peak test**: hợp âm 10 nốt fortissimo → peak ≤ −1 dBFS, không clip.
3. **Click test**: chuỗi nốt ngắn liên tiếp + pedal → nghe/soi waveform không có spike.
4. **Release test**: note off giữa chừng → không tắt đột ngột (soi envelope).
5. **Pedal test**: cùng hợp âm với pedal up/down → thời lượng đuôi khác rõ rệt.
6. **Layer test**: quét velocity 1→127 trên 1 nốt → không có "nấc" lớn (>3 dB) giữa các layer.
7. **Latency test**: đo `baseLatency + outputLatency` và ghi lại theo máy.
8. **Loudness test**: export → đo integrated LUFS (dùng ffmpeg `loudnorm` ngoài app hoặc script) → mục tiêu −14 ± 1 nếu xuất cho YouTube.

## 22.9. Những cải thiện âm thanh rẻ nhất, hiệu quả nhất (thứ tự làm)

1. Cho người dùng chỉnh **velocity curve** (đã có) + hiển thị đồ thị rõ.
2. Thêm **release samples** (bộ Salamander có sẵn — chỉ chưa dùng).
3. **Pedal noise** rất nhỏ khi đạp/nhả.
4. **Crossfade giữa velocity layer** (giảm nấc).
5. **Limiter** bảo vệ + headroom −6 dB.
6. Preset reverb (Close/Studio/Hall).
7. **Stereo/pan theo vùng phím** nhẹ.
8. Resonance xấp xỉ khi pedal xuống.
9. Detune rất nhẹ cho nốt lặp (round-robin).
10. Load `.sf2` cho đa nhạc cụ.

## 22.10. Giới hạn cần biết (đừng hứa quá)

- Không thể đạt chất lượng Pianoteq/Garritan bằng sample 77 MB trong web — và **không cần**: phần lớn người nghe trên laptop/điện thoại.
- Bluetooth audio làm hỏng trải nghiệm chơi (60–120 ms) — không có phần mềm nào sửa được.
- Sample 96 kbps OGG có artifact ở âm rất cao; nếu muốn chất lượng hơn: 128–160 kbps hoặc FLAC (nặng hơn 3–4×).
- Reverb convolution + 88 nốt + 4K render cùng lúc = nặng; export dùng engine offline riêng (NoteFall đã tách `export/synth/`).
