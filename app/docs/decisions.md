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

## 2026-11-15 — hands overlay v2: rigid motion + adaptive hands (user feedback)

Two user complaints about the live hands (v1, 879dc5c): fingers looked
stretched ("kéo dãn, force"), and the hands were not adaptive — with only
the right hand on stage, playing left-side keys stretched the right hand
across ("nhìn giả quá") instead of bringing the LEFT hand up. Plus: a key
pressed many times must visibly tap every time.

- **Rigid only (no bone stretching).** v1's per-joint tip-lerp (tip moved
  ~1.1 while DIP ~0.5 → +150% bone) and shear drift (wrist x1.0 vs bases
  x0.18) are GONE. Every transform is now rigid: `shiftHand` translates
  ALL joints incl. elbow and thumbRef; `bobFinger` moves joints 1..3 by
  the SAME dz (proximal change ~dz²/2L ≈ 1%, invisible). No joint is ever
  moved alone toward a target. The assigned finger's tip lands on the key
  purely by rigid drift (`keyX − tipX`); the press read comes from the
  `press` flag + the strike bob. Test asserts bone lengths preserved <5%.
- **Adaptive hands.** A hand that is off stage (runtime poseAt → null:
  "rests in the lap") COMES UP when the user plays its side: it is
  synthesised from a mid-run pose sample (`opts.sampleHand`), fades in
  from above (ENTER_Z/Y, τ 0.14) and lowers away after playing (τ 0.28,
  poses[hand] → null). Cost claim: plan fingering first, else reach cost
  with off-stage bias `1.6+|keyX−side·2.2|·0.35`; on-stage hands clamp at
  REACH_X=1.2 (a synth hand travels freely — it entered for exactly that).
- **Fingering from the song plan.** `opts.resolvePlan` maps a live key to
  the motion plan's (hand, finger) for the song note nearest the playhead
  (≤2.5 s) — press seen, plan used (2026-11-15 decision). Plan finger
  takes over early-freed neighbours for a clean hand-off.
- **Every key-down taps.** `strikeT` resets on each key-down (even
  repeats) → strike envelope STRIKE_Z·(1−u)² over 0.13 s on joints 1..3,
  scaled by `handsKeystrike` (new setting, default 0.6). Demand hover
  (Wait Mode) preserved.
- The update() contract: input poses are fresh per frame (humanize does
  this); `update` treats its OWN buffer as "not on stage" so the synth
  hand keeps fading (poses identity check).
- Tests (`scripts/test-livehands.ts`, 23 checks): bone lengths, tip lands
  on key, repeat taps, left hand enters/leaves for left keys, plan
  fingering, demand hover — ALL PASSED alongside the existing suites.

## 2026-11-15 — free-play hands: "đánh tự do vẫn có tay"

User: hand motion only existed when song notes were falling. Playing
freely (no song / no falling notes) must still show the hands, pressing
the keys the user plays.

- **Neutral pose, baked from the real pipeline.** `scripts/extract-
  neutral-pose.ts` drives `hands-worker.js` + `hands.wasm` + the vendored
  motion DB in-process under node (deflate-raw via DecompressionStream;
  the worker accepts a `file` buffer — no browser needed), synthesises one
  held note per hand at the keyboard centre, and FKs a mid-hold frame
  exactly like the client's `handAt`. The t=2.5 s frame is rigid-shifted
  to wrist x = ±1.5 and lifted 8 mm (fingers hover, not press) and baked
  into `src/hands/neutralPose.ts` (read-only; 502,458 DB entries load in
  ~5 s in node — the script stays as the provenance/regen path).
- **Free-play render path** (`Hands.tsx`): when `motionRef` is null the
  frame no longer bails out — poses = `{L: null, R: null}` and the live
  overlay synthesises hands from `sampleHand` on demand. `sampleHand`
  falls back to `neutralHandPose(hand)` when there is no motion, or the
  motion has no runs for that hand (a right-hand-only song now still gets
  a left hand for left keys).
- Export contract kept: a motionless timeline exports no hands
  (`isExporting()` guard + free-play path disabled while exporting).
- Tests: 7 new checks (neutral pose finite, hands appear/leave with NO
  motion, per-side entry) — 30 checks ALL PASSED; humanize/practice
  suites, tsc, build green.

## 2026-11-15 — hands v3: real key-press articulation, bone-exact everywhere

User feedback on v2 + free play: hands freeze ("đơ ra"), fingers don't
press INTO the keys like when a MIDI plays; complex notes / repeated
presses with fingers close together look deformed ("méo mó, mềm oặt,
ảo"); repeats must look like REAL repeated presses ("3D trên mặt phẳng
2D"), never frozen as if holding. Fix properly ("chỉn chu, không chắp
vá"), with human joint limits.

Root causes found and fixed at the source:

1. **humanize blended JOINT POSITIONS across time taps** (`mixLagged`)
   plus per-joint micro noise and per-joint settle — on fast passages
   (complex notes, fingers close together) the position average WARPS
   bone chains (a chain's joints move differently → stretch/soften) and
   per-joint noise shimmered lengths by up to ~10 %. Rebuilt as a
   per-BONE blend: bone LENGTHS from the centre tap, DIRECTIONS blended
   (weighted unit vectors + settle overshoot), thumbRef blended on the
   sphere. Micro-motion = one whole-hand tremor translation + tiny
   per-finger rotations around their bases + forearm breath — all
   length-preserving. Regression test: 18 Hz curl flicker keeps every
   bone within 1 mm of source length (the old blend fails this hard).
2. **thumbRef are twist DIRECTIONS (unit vectors), not positions** —
   v2's shiftHand translated them, corrupting thumb orientation on
   every drift/entrance. `shiftPose` no longer touches them; they
   rotate (Rodrigues) with the thumb.
3. **v2's strike bob went UP (+z) and was a 6 mm nudge** — reads as a
   twitch, never as pressing. v3: a press is an MCP swing around the
   knuckle (hinge axis from the finger's own geometry): windup lift
   (PECK_LIFT 0.06 rad) → strike down INTO the key (SWING_PRESS −0.075·
   keystrike) over PECK_SEC 0.09 s → stays pressed while held → lifts
   back on release. Every key-down sweeps windup → press, so even
   millisecond repeats show a full peck ("không được im 1 chỗ"). The
   whole hand dips 1.4 mm on presses (weight cue), press flags fire at
   contact.
4. **Human joint limits**: swing clamped [-0.30, 0.25] rad, MCP
   abduction ±0.12 rad (fingers fan toward nearby keys — chords, tight
   repeats — instead of reaching); the claim picks the finger whose TIP
   is naturally closest to the key; the whole-hand drift serves the
   centroid. Nothing stretches — motion is translations of whole chains
   or rotations at real joints only (new shared `src/hands/geom.ts`).
5. **Free-play hands breathe**: synthised hands get a slow sway (±0.8 mm)
   + per-finger flutter (±0.012 rad) — never frozen ("tay đơ ra").

Tests: livehands 34 checks (tip dips BELOW rest while held; repeat peck
lifts before striking and travels ≥3 mm; bones exact <1 %) and humanize
(bone safety + existing purity/lag/contract) ALL PASSED; practice suite,
tsc, build green.

## 2026-11-15 — hands v3.1: the press must READ (user: "tay có di chuyển gì đâu, ngón không bấm")

Two real bugs behind "hands don't move, fingers don't press" in manual
playing, despite green unit tests:

1. **Drift half-travel (v3 regression).** The drift accumulator fed
   `keyX − (tipX + drift)` — a RESIDUAL — into a VALUE smoother → the
   equilibrium travelled only D/2. Near keys barely moved the hand. The
   unit test hid it (C5 is near the test pose's rest tips, and abduction
   absorbed the remainder). Fixed back to value semantics (`keyX − tipX`
   = the total offset; the pose is fresh per frame). The free-play
   landing test tightened 0.6 → 0.25 so it cannot hide again.
2. **Press amplitude ~4× too small.** swing −0.075 rad = 4° ≈ 4 px of
   fingertip travel on screen — invisible next to the model's own motion
   (wrist alone dips ~14 mm). Now: SWING_HOVER 0.12, SWING_PRESS −0.34·
   keystrike (≈16 mm dip at default 0.6), PECK_LIFT 0.16 windup,
   HOVER_EXTRA 0.14, WRIST_DIP 0.03, clamps [-0.55, 0.35] rad (well
   under a fist). Every press now reads like the MIDI-driven hands.

## 2026-11-15 — tay có hồn (expression layer có kiểm soát)

- Người chơi: chuyển động tay đã tự nhiên, yêu cầu tiếp theo là "có hồn",
  cảm xúc — nhưng **cân thận, có kiểm soát, không quá đà** (chữ của người
  chơi). Phối hợp tay–ngón hợp lý, đặt ngón phù hợp, thích nghi nốt đang
  rơi + nốt đánh thủ công, hành động như pianist thật (bấm mạnh nốt cảm
  xúc), kèm công tắc/tùy chỉnh.
- Thiết kế — 5 tín hiệu nhỏ, cộng dồn thành "hồn", tổng được kiểm soát
  (mọi thành phần tỉ lệ với `expression`, 0 = tắt hoàn toàn = hành vi cũ):
  1. **Velocity depth**: độ sâu nhát bấm tỉ lệ velocity của nốt đó
     (live: velocity từ `triggerKey`; playback: velocity của note trong
     plan) — nốt nhấn chìm sâu hơn, nhẹ nhàng hơn.
  2. **Accent arm roll**: nốt mạnh (velocity > 0.72) lăn bàn tay quanh
     trục cẳng tay (xoay quanh wrist, hướng elbow→wrist) — "arm weight",
     biên ±0.05 rad, đậm dần theo độ mạnh, tay thuận lăn đúng hướng.
  3. **Rolled chords**: 2 key-down trong cùng ~60 ms → ngón sau bấm trễ
     hơn ngón trước ~20 ms — hợp âm lướt như pianist, không bấm chùm.
  4. **Playback dip**: khi phát MIDI, model tự nhấn — nốt mạnh chìm sâu
     hơn chút (τ vào 0.06 s / ra 0.22 s) — cảm xúc khi nghe.
  5. **Register posture**: quãng cao tay nhỉnh lên, quãng thấp trầm xuống
     (chỉ tay synthesised, model hands tự có posture thật).
- Thích nghi: `resolvePlan` **ưu tiên nốt sắp tới** (on ∈ [t−0.35, t+1.4],
  chọn gần nhất) thay vì nốt vừa qua — ngón chuẩn bị cho nốt đang rơi;
  cost claim thêm +0.25 cho ngón cái trên phím đen (đặt ngón hợp lý).
- **Công tắc/tùy chỉnh**: setting `handsExpression` (mặc định **0.65**,
  slider "Biểu cảm" trong Hands, 0..1, step 0.01) — tắt = 0. Toàn bộ
  smoothing/rotation là rigid (bone lengths exact — có test).
- Test mới (42 checks total): velocity depth (hard < soft −0.02 z),
  accent roll (palm hướng đổi, lengths giữ), rolled chord stagger,
  playback dip, expression-off = hành vi cũ (34 test cũ còn xanh).

## 2026-11-15 — hands v3.3: nguyên nhân gốc "ngón không bấm" + 4 lỗi người chơi báo

- Người chơi báo 4 vấn đề: (1) hai tay TRANH nốt (tay phải giành nốt gần tay
  trái → nốt của chính nó trễ → giật); (2) tay giật/co rúm; (3) ngón rảnh
  quặp vào trong, cần cách ra; (4) **đánh thủ công ngón KHÔNG BẤM, KHÔNG DI
  CHUYỂN — "tìm nguyên nhân gốc vì mấy lần rồi chưa fix được"**.
- **Nguyên nhân gốc của (4)+(2) — tìm bằng repro chạy CHUỖI THẬT của app
  (humanize + pose trung lập + opts đúng Hands.tsx), scripts/test-livebrowser.ts:
  MỘT GIÁ TRỊ VELOCITY KHÔNG HỮU HẠN (NaN) đầu vào (mapping MIDI/pointer
  lỗi, persisted setting hỏng) lan qua `press/swing` và **ở lại vĩnh viễn**
  trong smoothing (`s.swing += (target − s.swing)·…` với s.swing=NaN không
  bao giờ hồi) → khớp biến NaN → mesh "co rúm", ngón đứng im đến khi tải lại
  trang. Các lần "fix" trước sửa biên độ/drift nên không chạm nguyên nhân này.
  Repro bắt được chính xác: triggerKey(60, NaN) → poses NaN vĩnh viễn.
- **Fix gốc (phòng thủ nhiều lớp)**: (a) guard velocity tại ingest
  (addLiveListener + onKeyDown: không hữu hạn → 0.75, clamp 0..1); (b) tự
  phục hồi mọi trạng thái slot/state mỗi frame (swing/abduct/dip/tap/vel/
  strikeT/keyX/drift/roll/posture); (c) guard resid/target/mvel không hữu
  hạn; (d) `expressAt` trong Hands.tsx guard plan + velocity; (e) **fallback
  của try/catch trong useFrame giờ VẪN chạy liveHands overlay trên pose gốc**
  — một lỗi lạ không bao giờ đóng băng ngón tay nữa.
- **(1) Không tranh — tay gần nhất xử lý**: `claim()` tính `palmOf(hand)` =
  wrist + drift (fallback anchor ±1.5 khi chưa có pose thật), tay XA hơn bị
  phạt CROSS_PENALTY 2.2; plan bị veto khi tay kia gần hơn > PLAN_HAND_SLACK
  2.0 VÀ còn ngón trống (kế hoạch fingering vượt tay chỉ khi thực cần).
  Tránh cascade "tay phải lấn sang nửa trái rồi bỏ quên nốt phải".
- **(2) Không giật**: drift bị giới hạn tốc độ DRIFT_RATE 10 units/s (glide,
  không snap) + các guard NaN ở trên (co rúm = triệu chứng NaN).
- **(3) Ngón rảnh mở ra**: ngón không giữ nốt, khi ngón khác đang bấm
  (tap > 0.3) sẽ FAN ra ngoài RELAX_FAN 0.09 rad (≤ ABDUCT_MAX 0.14 — "trong
  biên độ hợp lý"): ngón cái mở ra ngoài, các ngón tản theo hướng giải phẫu
  (R: −sign(f−2), L: +sign(f−2)), tỉ lệ theo mức bấm, mượt τ 0.08.
- **(4) Bấm thấy rõ**: đo trên hình học THẬT (pose trung lập + humanize):
  swing travel 0.168 units (~1.7 cm) mỗi nhát, lặp nào cũng peck đủ biên —
  vấn đề không phải biên độ mà là NaN; test mới chốt chặn mọi đường về lại.
- Test mới `scripts/test-livebrowser.ts` (17 checks — chuỗi trình duyệt thật):
  press travel, repeats, free play, NaN tự phục hồi, hợp âm, không tranh,
  relax fan, chia tay theo vùng, drift rate-limit. Suite cũ (34+18+M5) xanh.

## v3.4 — chuyển động tự nhiên hơn & ổn định hơn (S1–S6, N1–N5), 2026-11-15

Kế hoạch user duyệt trước khi code ("dành thời gian nghĩ là chính"): 5 mục ổn định +
6 mục tự nhiên, mỗi mục có ngưỡng đo. Đã làm 11/11 mục, mọi ngưỡng đều có test
(`scripts/test-livebrowser.ts` +16 checks → 33; `scripts/test-notequery.ts` mới, 10 checks).

**Ổn định**
- **S1 tách vòng lặp (chống wobble đáp phím)**: `update` có pre-pass trên pose tươi —
  drift = mean(`keyX − tipRaw`) như cũ, nhưng abduction chỉ nhận **độ lệch của ngón so với
  mean** (`dev = dResid[f] − rawDrift`) thay vì residual đầy đủ → hai vòng lặp không còn
  đuổi cùng một sai số. `tapNow` là snapshot (không phụ thuộc thứ tự duyệt ngón).
  Ngưỡng: độ biến thiên tip-rel-wrist khi giữ ổn định ≤ 1 mm (đo 30 frame sau hội tụ) ✓.
- **S2 deadzone**: drift bỏ qua |err| ≤ 0.002 (2 mm — humanizer rung ±0.7 mm không bị đuổi);
  abduct bỏ qua |dev| ≤ 0.004. Giảm rung vi mô khi giữ phím.
- **S3 trục bấm đóng băng**: `swingFinger` nhận `axis` tùy chọn; từ key-down đến hết
  `held || strikeT < PECK_SEC` trục `cross(tip−knuckle, up)` được **chốt 1 lần**
  (`fingerAxis`), trả `null` khi idle → mỗi nhát bấm quay quanh **một mặt phẳng**,
  hết lắc trục theo nhiễu humanizer. Test: `slotDebug().axis` không đổi trong suốt nhát
  bấm (turn < 1e-6 rad) + đường đi đầu ngón không gãy khúc (max segment ≤ 3.2× median).
- **S4 truy vấn nốt O(log n)** (`motion.ts`): `makeNoteQuery(notes, plan)` —
  `planFor` (thay `resolvePlan` scan O(n)/claim), `activeAt` (thay `expressAt` scan
  O(n)/ngón/frame — memo 1 pass/frame chia sẻ 10 ngón), `nextOn` (cửa sổ 0.4 s cho N4);
  `notes` sort theo `on` + binary search. `pooledPoseAt` vòng 4: runtime sinh ~30 mảng
  mới mỗi `poseAt` call × ~18 call/frame khi bật motion blur → giờ reuse. Test:
  khớp brute-force 200/200 + 1000 `planFor` trên 20k nốt < 80 ms; `activeAt` 600 call < 250 ms.
- **S5 giữ tay khi lặp**: `recent: Map<midi,{hand,t}>` (1.5 s, prune khi > 48 mục) —
  `claim` cộng `RECENT_HAND_PENALTY 0.8` nếu tay khác vừa chơi nốt đó → nốt lặp ranh
  giữa hai tay không đảo tay. Test: 3 lần bấm D4 liên tiếp luôn cùng một tay.
- **S6 hết pop vào/ra**: `meshHand.update(..., vis?)` — opacity của `MeshPhysicalMaterial`
  mỗi tay theo `liveHands.visOf(hand)` (tay synth đang vào/ra), `transparent=true` **chỉ**
  khi opacity < 1 → artifact sorting chỉ xuất hiện trong vài frame chuyển.

**Tự nhiên**
- **N1 lặp nhanh nhẹ tay**: `s.lift = PECK_LIFT·clamp((now − lastStrikeT)/REPEAT_REF_SEC 0.25,
  0.25, 1)` thay cho PECK_LIFT cố định trong pha windup → phím gõ 10 Hz nâng tay ≤ 40%
  biên độ gõ 2.5 Hz (giống ngón thật đánh điệp: phím chưa hồi phục thì ngón chưa nhấc).
  Test: `slotDebug().lift` của chu kỳ 0.1 s ≤ 0.42× chu kỳ 0.4 s; travel pose ≤ 0.75×.
- **N2 cung bay khi rê tay**: `st.driftVel` (smoothed τ 0.12) điều khiển `ARC_LIFT 0.04·
  clamp(|driftVel|/10)` dịch cả bàn tay lên +y trong `applyTo` → tay rê xa đi theo cung
  3–5 mm rồi hạ xuống, hết "trượt trên ray". Test: cổ tay nhấc 1–7 mm khi tới nốt xa,
  hội tụ lại ≤ 1.2 mm sau khi tới.
- **N3 bật ngược khi nhả**: `bind` release đặt `s.rebound = REBOUND_RAD 0.02` (rad swing),
  decay `exp(−dt/0.35)`; target swing += rebound khi `!held`, và pha rebound dùng
  `TAU_PRESS` (nhả nhanh như lúc đánh, không lê 0.5 s) → đầu ngón vút lên quá mức nghỉ
  0.2–1.5 mm rồi lắc về — "ngón bật ngược tự nhiên". Test đo overshoot tip-rel-wrist.
- **N4 dự báo nốt kế (chỉ khi KHÔNG phát theo)**: `opts.nextKey(hand) → {keyX, in}` từ
  `query.nextOn` (cửa sổ 0.4 s); drift target pha `ANTICIPATE_W 0.25·(1 − in/0.4)` về
  phía nốt kế — **≤ 25–28% khoảng cách** (giới hạn trên của plan, test đo cả `gap`);
  khi `playing` thì motion runtime đã dẫn trước → không lean thêm (test xác nhận).
- **N5 liên thông ngón**: ngón rảnh (`midi === null`) nhận `couple = −COUPLE_AMP 0.009·
  max(tapNow[ngón khác])`, smooth τ 0.06 → ngón hàng xóm **hơi chìm theo nhát gõ**
  (~0.2–0.9 mm, transient) — bàn tay có tính đàn hồi, không còn "mỗi ngón một cục".

Sai lệch trong quá trình làm (đã sửa, xem test): băng ngưỡng mm viết nhầm theo unit
(1 mm = 0.01 unit trong pose space); `REBOUND_TAU 0.05` decay trước khi ngón kịp lên
(→ 0.35 + rise nhanh); `COUPLE_AMP 0.02` cho cú chìm 1.7 mm vượt băng plan (→ 0.009);
test N1 đo max qua mọi chu kỳ nên chu kỳ đầu luôn full lift (→ đo chu kỳ cuối).

Biên độ mọi chuyển động mới ≤ hằng số cũ (arc ≤ 0.04 shift, couple ≤ 0.009 rad,
rebound ≤ 0.02 rad, lean ≤ 25% gap); không thêm UI; không đổi hành vi khi phát MIDI.

## hands v3.5 — GĐ 0 chẩn đoán + fix gốc 2 triệu chứng playback (2026-11-15)

**Triệu chứng (user, context=playback)**: (1a) nốt liền nhau — đầu ngón hụt về nốt vừa qua;
(1b) thân ngón/cổ tay/bàn tay hơi nghiêng, ngón chụm khi 1 ngón đánh; (2) nhấn chưa rõ:
lặp nhanh ít thấy nhấn, chưa lún sâu, pha nhấc–gõ chưa rõ, "tay bay cao" khi nhấn.

**GĐ 0 — đo bằng harness thật** (`scripts/diag-geometry.ts` dump 120 frame DB thật
→ `scripts/.diag-frames.json`; `scripts/diag-overlay.ts` chạy full chain humanize+liveHands
trên frames đó, 3 config). **DB source TỰ NHIÊN** (wristZ 0.31–0.62, tipX err ≤26mm,
approach 13–41°) → lỗi ở OVERLAY. Hai root cause định lượng:

1. **Double-curl** (triệu chứng 2): swing layer thêm −0.215 rad @hold → tip lún THÊM
   12–19mm qua mặt phím dù DB đã press (pose.press=1). Config keystrike=0 → hết.
   "Tay bay cao" là cảm nhận sai từ lún kép + ngón chụm (wristZ thật 3–6cm = bình thường).
2. **Lệch điểm chạm** (triệu chứng 1a): tipX−keyX @strike tới **−24mm** (hướng nốt trước).
   NGUỒN = **drift stale**: residual luôn tính theo phím CŨ đang giữ trong khi ngón đã di
   chuyển sang phím kế (kể cả khi nguồn đứng yên tại phím mới → −27mm; tắt humanize vẫn lệch
   → KHÔNG phải humanize lag). Kèm: swing arc có thành phần ngang ~6mm, humanize render lag.

**Fix (liveHands.ts + humanize.ts)**:
- **(a) Anti double-curl**: `press = SWING_PRESS·k·velTerm·(1 − share·pose.press[f])`,
  share = PRESS_SHARE·(1 − express·0.5·(vel−0.55)) — DB press=1 chỉ cộng thêm ~15–26%
  (velocity vẫn đọc được: share co giãn theo độ mạnh); peck lift cycle GIỮ NGUYÊN.
- **(b) Drift semantics (GĐ 3)**: residual = keyX − RENDER tip (tự hốt phần render lag);
  khi chơi, nếu ngón ĐANG DI CHUYỂN tới nốt kế (source velocity, lấy từ `opts.sampleHand`
  — KHÔNG dùng render velocity: ghost catch-up) → target = lead cỡ lag (≤6mm, chặn);
  residual >6mm và quá 0.3s không keydown = ngón đã rời phím → drop (stale);
  τ: 0.02 trong 0.15s sau keydown, 0.045 khi playing. N4 lean giữ nguyên khi !playing.
- **(c) Swing lat-cancel (GĐ 1)**: đền bù thành phần ngang của swing arc (θ·a.y·r.z) —
  bấm thẳng xuống, không trượt ngang 6mm. ABDUCT_MAX 0.14→0.06; abduct τ 0.02 sau keydown.
- **(d) GĐ 4**: REPEAT_MIN 0.25→0.55 (floor 55% windup); down-stroke τ 0.022;
  wrist attack dip ~2mm/nhát (ATTACK_DIP, envelope e^{−(t−0.04)/0.12}) + REBOUND giữ.
- **(e) Couple proximity** [1, 0.55, 0.22, 0.08] theo |Δf| (enslaving proximity hypothesis).
- **(f) humanize**: tách lag ngón/cổ tay (wFinger = wA + (1−wA)·0.6 — ngón chính xác,
  cổ tay giữ độ mềm); SETTLE_CAP 3mm (overshoot là "nảy", không phải nhảy).
  N2 arc y→z đã sửa ở v3.4.

**Đo sau fix (cùng harness)**: double-curl −12..−19mm → **−5..−8mm** ("lún" đúng nghĩa);
strike err: 4/6 chuyển tiếp ≤2.5mm (cũ 11–32mm), 2 outlier 7.6/14mm nằm đúng frame DB
nhiễu (65: srcTipZ +0.103 bay cao; 67: wristZ rơi 0.36) — không phải cơ chế.
Stress test tổng hợp (3cm/200ms, decelerate vào phím, có release thật): worst 3.2mm,
trung bình <2mm.

**Test**: test-livebrowser 33→**39 checks** (N1 ngưỡng mới 55–62% + travel ≥5mm; no-lean
dùng source dẫn trước; thêm GĐ1 double-curl ≤8mm, GĐ3 strike ≤3.5mm/mean ≤2mm, GĐ4 dip
0.8–4.5mm + rebound, GĐ2 couple theo proximity). test-livehands/humanize: 3 ngưỡng đổi
theo fixture/SETTLE_CAP. **Lỗi test bắt buộc phải sửa**: test cũ giữ phím vĩnh viễn
(setTimeout không chạy) → slot misallocation; source test teleport (segment kích hoạt muộn).
