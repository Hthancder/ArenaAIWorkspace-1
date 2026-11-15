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

## Còn nợ (TODO)

- Wait mode + chấm điểm (research 16) — milestone M5, chưa làm.
- Remap từng phím PC-key + preset AZERTY/Dvorak (research 09/20.5) — xem `ideas.md`.
- Metronome theo tempo map của bài; loop A–B (research 15.4).
- SoundFont / đa timbre (research 09 P1); export video test tay; PWA/CSP (M6).
