# Decisions — app Piano (fork NoteFall)

Mỗi quyết định 1 dòng, mới nhất trước. Tham chiếu tài liệu: `research-piano/`.

## 2026-11-15 — phiên build đầu tiên

- **Nền tảng**: fork nguyên `ekkx/notefall` vào `app/`, giữ `LICENSE.md` (PolyForm Shield 1.0.0) + Required Notice; ghi công trong `ATTRIBUTIONS.md`. *Không thương mại hoá sản phẩm cạnh tranh nếu chưa xin phép tác giả* (research 02.1).
- **Sample**: tự host Salamander V3 (480 file OGG, 150 MB) trong `public/samples/` từ mirror `d-buckner/salamander-piano` (CC BY 3.0, Alexander Holm) — KHÔNG dùng `samples.notefall.app` (CORS khoá, research 41.1.6). Script tái tạo: `scripts/fetch-samples.sh`. `SAMPLES_BASE_URL` mặc định `/samples/salamander-v3-close` cả dev lẫn prod.
- **PC input**: `pcVelocity` (mặc định 0.78 theo research 20.4), `pcKeymapBase` (mặc định 48 = C3), `pcOctaveShift` (±4). Map 2 hàng giữ nguyên của NoteFall (`pcInput.ts`).
- **CONFLICT (research 20.5 vs 20.4/principle)**: 20.5 đề xuất `Z`/`X` đổi quãng tám, `M` metronome, `L` loop — nhưng trong map của NoteFall đó là phím ĐÀN, và nguyên tắc của chính 20.5 cấm gán shortcut không-modifier lên phím đàn. **Quyết**: octave shift = `PgUp`/`PgDn`; metronome = `Ctrl/Cmd+M`; bỏ `L` (chưa có loop A–B). Ghi vào `research-piano/46`.
- **Pedal giữ âm PC**: `pcSustainKeyCode` mặc định `ShiftLeft` (cả 2 phím Shift), theo convention "sustain = Space/Shift" của web piano (research 06). Phím Shift vẫn dùng được cho Shift+R / Shift+K (không phát nốt).
- **Velocity chuột**: `mouseVelocityFromPosition` (tắt mặc định) — vị trí nhấn dọc phím: trước = nhẹ, sau = mạnh (research 09 "vị trí click (Y trên phím)"). TODO(spec): khoảng 0.35–1.0 tự chọn vì tài liệu không nêu số.
- **Nhãn phím máy tính**: `pcKeyLabelsEnabled` + cỡ/độ mờ/khoảng cách — atlas glyph tái dùng hệ `pitchLabels` (research 06: tuneonmusic có nhãn PC-key).
- **Metronome**: `metronomeEnabled/Bpm/BeatsPerBar` (40–240 BPM theo research 06, mặc định 100/4 — số liệu count-in của NoteFall). Chưa đồng bộ tempo map bài — TODO(spec).
- **i18n**: thêm locale `vi` (đầy đủ 7 namespace, sinh từ `scripts/make-vi-locales.py`), `fallbackLng: 'vi'` — tiếng Việt là ngôn ngữ mặc định (research 41.1.12). Branding hiển thị: "Piano" (research 41.9); en/ja giữ nguyên của upstream.
- **Vite**: `server.allowedHosts: true` để chạy qua preview proxy của Arena.

## 2026-11-15 — deploy Vercel (web sample set)

- **Bộ sample web** (research 40, phương án B): 30 phím × **8 tầng** (lấy tầng lẻ v1..v15 → đánh số lại v1..v8), **cắt đuôi 10 s** + fade 250 ms, OGG Vorbis ~100 kbps (`compression_level=0.55` — lưu ý libsndfile ĐẢO NGƯỢC: 0.9 = nén mạnh nhất). Kết quả **27.1 MB / 240 file**, tracked trong git để deploy tự chứa. Full set (156 MB) ở `_local/salamander-full/` (gitignored).
- Lệch công thức `40.3.4`: **không** chuẩn hoá peak từng file về −3 dBFS — Salamander đã ghi nhất quán, biên độ giữa các tầng LÀ động học velocity (upstream cũng không chuẩn hoá). Chống clip nếu cần làm sau.
- Lệch `40.3.3`: giữ đuôi tới **10 s** thay vì 2–3 s (đây là one-shot, không có release sample; 2–3 s sẽ cắt vụn tiếng khi giữ pedal).
- `VELOCITY_LAYERS` đọc từ env `VITE_SAMPLE_LAYERS` (mặc định 8) trong `salamanderDescriptor.ts` — dùng full set thì đặt `16` + `VITE_SAMPLES_BASE_URL`.
- **Vercel**: project `piano-app`, root `app/`, framework vite, build `npm run build` → `dist/`. `vercel.json` theo research 26.3 (SPA rewrite, immutable cho `/assets/` + `/samples/`, `Permissions-Policy: midi=(self)`), thêm header `Content-Type: audio/ogg` cho `/samples/`. Gói Hobby = **chỉ phi thương mại** (research 26.2); băng thông 100 GB/tháng ≈ 3.700 lượt tải bộ sample mới.
- **Đã deploy production 2026-11-15** (dpl_FtrRt4FTjbU9zfz4XbZVmp4wYmx2, build 58s, PROMOTED): **https://piano-app-peach.vercel.app** (cùng `piano-app-hthancders-projects.vercel.app`). Lưu ý: project setting `gitProviderOptions.createDeployments = disabled` (chưa cài GitHub App của Vercel cho repo) → **push không tự deploy**; gọi `create_deployment` thủ công hoặc cài Vercel GitHub App sau.

## Còn nợ (TODO)

- ~~Wait mode + chấm điểm (research 16)~~ ✅ M5 đã làm (2026-11-15) — xem mục dưới.
- Remap tự do từng phím PC-key (preset AZERTY/Dvorak ✅ có sẵn; remap từng phím còn thiếu) — xem `ideas.md`.
- Metronome theo tempo map của bài; handle A–B trên timeline (nút A/B ✅ có).
- SoundFont / đa timbre (research 09 P1); export video test tay; PWA/CSP (M6).

## Hands motion DB — tự host (fix 2026-11-15)

- Bug user báo: **"không tải được chuyển động tay"** — `hands/motion.ts` vẫn tải
  `motion.82cbd97028.bin` (~22 MB) từ `samples.notefall.app` (vi phạm rule 41
  "không dùng CDN", + bucket CORS chỉ cho phép notefall.app → fetch từ
  domain khác luôn fail).
- Fix: DB_URL → `/hands/${DB_FILE}` (self-host, `VITE_HANDS_DB_URL` override);
  file vendored vào `app/public/hands/` qua **GitHub Actions** (`.github/workflows/
  fetch-hands-db.yml` — runner GitHub với tới CDN, sandbox thì không; trigger
  `push` theo path filter + `workflow_dispatch`); vercel.json + immutable cache
  `/hands/`; xoá proxy `/samples-cdn` vô dụng trong vite.config.
- Workflow chạy **13s**, commit bot `230e50e` (file 21.744.038 bytes, magic "NFMD");
  deploy production `dpl_6MEWwDAkLPVWEZWkLEdgYZPauq4f` (PROMOTED, alias
  piano-app-peach.vercel.app vẫn giữ).

## M5 — Practice engine (Wait Mode + chấm điểm + Calibration + Loop A–B), 2026-11-15

- **Hai chế độ** theo research 16.4.2: `wait` (dừng chờ đúng nốt — 16.3.1, steps =
  cụm onset 30ms, bấm sai chỉ đếm) và `rhythm` (chấm điểm khi chạy — 16.4, matching
  greedy). Recital (chấm độ dài nốt) CHƯA làm vì 16.4.3 B4 không có ngưỡng số — TODO(spec).
- **Cửa sổ thời gian** dùng nguyên công thức 16.4.1 (kiểm chứng đúng bảng 60BPM→400/140,
  120BPM-eighth→125/75 trong test). Mức chia perfect/good = 50% goodMs — 16.4.3 B2
  không định nghĩa → **TODO(spec)**. Ngưỡng tối thiểu tap cho calibration = 3/8 — TODO(spec).
- **Đồng hồ** theo 16.1: điểm bấm quy về "đang nghe" = playhead − (baseLatency +
  outputLatency); offset calibration (median 16.2) trừ tiếp vào mọi delta. Click
  calibration tính wall-time qua `getOutputTimestamp` (không lặp "classic mistake").
- **Practice state NGOÀI Settings** — Settings bị hash vào content hash của project
  (store.ts `hashSettings`); đưa session vào Settings sẽ đánh dấu project "unsaved"
  mỗi lần chơi. Prefs (mode, offset, auto-advance) lưu localStorage (browser-local,
  không backend — hợp rule 41).
- **Loop A–B**: điểm A/B lưu TL_audio (trục transport), tự bật loop khi đặt B;
  wait-mode wrap về bước đầu đoạn loop (đổi đơn vị qua speed map).
- **Per-bar** (16.4.4) cần tempo/TS map — `parse.ts` giờ capture `tempos` + `barTimes`;
  file không có map → chỉ hiện tổng (không bịa bar).
- **Giới hạn đã biết**: rhythm + loop → mỗi expected chỉ khớp 1 lần/vòng (TODO(spec)
  reset matcher khi wrap); preview nốt của wait mode cũng đi vào recorder nếu đang ghi;
  hợp âm wait-mode chấp nhận bấm bất kỳ thứ tự nào (16.3.1 "thứ tự bất kỳ").
- **Test**: `npx tsx scripts/test-practice.ts` — 8 case theo 16.7, ALL PASSED; test
  bắt thật 1 bug (`onsetStepBeats` sập window khi onset trùng) — đã fix.

## Hands motion — humanize (2026-11-15)
Làm chuyển động bàn tay "người" hơn (`src/hands/humanize.ts`, slider ở Inspector › Hands):
- **Ràng buộc cứng**: bộ lọc PHẢI là hàm thuần của `t` — exporter render frame-step bằng virtual clock, còn preview dùng clock thật; hai đường chỉ khớp nếu cùng `t` cho ra cùng pose. => cấm mọi filter có state (EMA/spring/bộ nhớ) — đã cân nhắc và loại.
- Thiết kế: 3 mẫu `src(t), src(t−τ), src(t−2τ)` (τ = `handsSmoothness`·55ms); lag theo nhóm khớp (ngón nhẹ → cổ tay → khuỷu nặng nhất) + term "settle" `β·(vB−vC)` cho độ nảy khi move nhanh rồi ease-in; micro-tremor tất định ~0.3Hz (drift) + ~8.2Hz (physiological tremor), phase từ hash số nguyên của (joint, tay) — không RNG state.
- `press` copy RAW từ mẫu t: key light/kẹp nốt không được trễ tiếng đàn.
- Amplitude hằng số mang tính nghệ thuật (TODO(spec)): AMP_FINGER 0.011 / AMP_WRIST 0.007 / AMP_ELBOW 0.004 world units tại microMotion = 1.
- Test: `npx tsx scripts/test-humanize.ts` (purity, lag, bounded tremor, pass-through).

## Wait Mode — flow-and-pause redesign (2026-11-15)
User: mô hình cũ "dịch chuyển" nốt (seek teleport từng bước) cho trải nghiệm sai + rất lag. Thay bằng:
- **Trôi + dừng**: flow loop (RAF trong usePracticeEngine) đẩy playhead tới onset của bước hiện tại rồi DỪNG đúng trên đường chạm; chơi xong → trôi tiếp tới nốt kế. Nốt rơi liên tục, không teleport (ngoại trừ nhảy lùi khi wrap loop A–B — giống hành vi loop bình thường).
- **Cửa sổ chơi** mở 0.75s (TL) trước onset — bấm sớm tự nhiên vẫn tính; sớm hơn bị bỏ qua (không tính sai). Bấm trễ = chờ tới khi bấm. `press` đúng full bộ pitches → sang bước; lặp pitch = retry; sai pitch = wrong (đếm, không chặn) — giữ nguyên bộ đếm M5.
- **Lag fix**: nguyên nhân = `audioEngine.seek()` mỗi bước (quét note ×2 + re-trigger mọi voice đang vang + ghi store) + auto-advance 5s seek định kỳ cả khi rảnh. Mới: `engine.flowSet(t)` = 2 phép ghi field/th frame — không quét note, không audio, không re-render (zustand chỉ ghi khi đổi bước).
- **Auto-advance mặc định TẮT (0)** — "dừng chờ đánh" thuần; slider giữ (0 = Không bao giờ); migration: persisted 5000 (default cũ) → 0. Skip button vẫn có.
- Điểm bắt đầu = playhead hiện tại (bước kế tiếp; hết bài → wrap loop hoặc bước 0). Seek-bar kéo giữa phiên = re-anchor tự động. `engine.flowSet` no-op khi export (virtual clock giữ quyền).
- Preview pitch ("nghe trước") phát lúc DỪNG (không phải lúc sang bước) — phím sáng lúc chờ.
- Test: `resolveStepIndex` 7 case trong test-practice.ts — ALL TESTS PASSED.

## BUG FIX — hands crash (2026-11-15, regression do humanize)
Triệu chứng: bật bàn tay → tay không hiện, nốt ngừng rơi, phím mất glow, nhưng nhạc vẫn phát.
- **Nguyên nhân**: pose thật của runtime có `thumbRef` = **3** Vec3 (`hands.js` handAt: `thumbRef:[i(75),i(78),i(81)]` = fkThumbRefs 9 float; `meshHand.ts:565` đọc `thumbRef[Math.min(ci,2)]` → index 2). Scratch của humanize chỉ tạo 2 → `r=undefined` → `r[0]` THROW trong `mesh.update` MỖI frame → mọi useFrame đăng ký sau Hands chết (nốt đứng hình, glow chết); audio sống nhờ background worker ticker (25ms) → đúng triệu chứng.
- **Sửa**: allocHand/copyPose/blendHand = 3 thumbRef (fallback `?? bases`), press `?? 0`; sanitize params (NaN → 0.5) chống persisted-settings cũ; **try/catch cuối trong useFrame** của Hands — lỗi thì degrade về pose gốc + console.warn, KHÔNG được để frame loop chết nữa.
- **Phòng ngừa**: test-humanize mock shape theo runtime thật (thumbRef 3) + contract test `thumbRef[2]` readable trên cả 2 path — ALL TESTS PASSED.
- Bài học: HAND POSE SHAPE là contract với meshHand — đổi/mới cấp phát buffer phải khớp runtime (`hands.js` handAt) chứ không phải d.ts (d.ts để `Vec3[]` không nêu độ dài).

## Hands follow live input + wait-mode held-key fix (2026-11-15)
- **Bug "phím tự giữ / vệt note dài / lag" ở Chờ nốt**: preview mỗi bước gọi `triggerKey` KHÔNG bao giờ release → live note vĩnh viễn (key glow giữ, thanh nốt live dài ra vô hạn, voice tích tụ). Sửa: dùng `triggerPreview(midi, 0.12, 220)` (tự nhả, không vào liveNotes, không emit bus).
- **Tính năng "tay bám theo người dùng"** (`src/hands/liveHands.ts`, toggle `handsFollowInput` mặc định BẬT): mọi thao tác thủ công (chuột trên bàn phím ảo, PC keyboard, MIDI) đi qua `triggerKey` → live bus → overlay:
  - phím bấm claim (tay, ngón) dính khi giữ; ngón TAP xuống khi bấm, nhấc lên khi nhả;
  - cổ tay trôi tới trọng tâm các phím đang bấm (clamp ±1.1), khuỷu bám 0.35×;
  - `press[]`: khi đang phát = song || live; khi KHÔNG phát (Chờ nốt/tạm dừng) = thuần live → ngón "được yêu cầu" (pose frozen có press=1) **lơ lửng trên phím tới khi người dùng bấm thật**;
  - smoothing frame-rate-independent (1−exp(−dt/τ)) — attack 55ms/release 140ms/wrist 90ms — không nhảy biên (lift cũng smooth, binding chỉ giải phóng khi tap < 0.02);
  - **EXPORT LUÔN thuần**: update/applyTo no-op + reset khi `isExporting()` (state live là history-dependent — không được vào render pipeline export).
- Blur sub-poses cũng apply overlay (vệt khớp pose chính).
- Test: `scripts/test-livehands.ts` (vite-node + shim Web Audio tối giản + fake clock) — 15 checks ALL PASSED; test-practice/test-humanize vẫn ALL PASSED.
