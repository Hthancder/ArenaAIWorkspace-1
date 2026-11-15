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

## Còn nợ (TODO)

- Wait mode + chấm điểm (research 16) — milestone M5, chưa làm.
- Remap từng phím PC-key + preset AZERTY/Dvorak (research 09/20.5) — xem `ideas.md`.
- Metronome theo tempo map của bài; loop A–B (research 15.4).
- SoundFont / đa timbre (research 09 P1); export video test tay; PWA/CSP (M6).
