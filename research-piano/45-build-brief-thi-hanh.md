# 45 — Build brief thi hành (dành cho AI coding agent)

> Đây là file **duy nhất** cần mở khi bắt đầu một phiên làm việc, cùng `41` và `spec/*`. Nó nói: xây gì, theo thứ tự nào, xong khi nào.

## 45.1. Sản phẩm (một đoạn)

Web app **piano 3D** chạy hoàn toàn trên trình duyệt: mở file MIDI bất kỳ, phát nốt rơi đẹp mắt, chơi thật bằng bàn phím máy tính hoặc đàn MIDI USB với độ trễ thấp, chỉnh gần như mọi tham số hiển thị/âm thanh, sửa nốt trên piano roll, luyện tập có chấm điểm, lưu project vào một file `.nfz`, xuất WAV/video. **Không backend, không tài khoản, không upload.** Tiếng Việt mặc định.

**Stack CHỐT:** Vite + React 19 + TypeScript (strict) + three.js (qua @react-three/fiber + drei) + zustand + Tailwind (chỉ layout/spacing; token trong CSS var) + Vitest + Playwright. Không Next.js, không Redux, không UI kit ngoài.

## 45.2. Trạng thái milestone (AI cập nhật sau mỗi lần)

| M | Tên | Trạng thái | Ghi chú |
|---|---|---|---|
| M0 | Khung dự án | ☑ | Fork `ekkx/notefall` vào `app/` (2026-11-15); tự host Salamander; vi i18n |
| M1 | Chơi được | ☑ | Upstream có sẵn + `pcVelocity`, `pcOctaveShift`, pedal Shift, nhãn phím PC, velocity theo vị trí nhấn |
| M2 | Tuỳ biến & lưu | ☑ | Upstream: ~300 settings, search, `.nfz`, preset… (đủ yêu cầu 45.5) |
| M3 | Nhập MIDI + timeline | ☑ | Upstream: parse worker, transport, speedMap, keyframes |
| M4 | Sửa & xuất | ☑ | Upstream: editor trên canvas, undo/50, export WAV/video/MIDI |
| M5 | Luyện tập | ☐ | Wait mode, chấm điểm, tempo ladder — CHƯA làm |
| M6 | Đánh bóng & phát hành | ◐ | vi i18n + metronome ✅; PWA/CSP/deploy/video test còn nợ |

Ký hiệu: ☐ chưa · ◐ đang · ☑ xong · ⚠ có nợ kỹ thuật (ghi rõ).

## 45.3. M0 — Khung dự án (0.5–1 ngày)

**Làm:** Vite + TS strict + ESLint + Prettier; `src/` theo `44.1`; `tokens.css` sinh từ `spec/design-tokens.json`; layout S1 tĩnh với canvas three.js trống + bàn phím 88 phím + transport pill; i18n `vi` với 20 key đầu; Vitest + Playwright chạy được.

**Xong khi:**
- [ ] `npm run dev` mở app: canvas đen, bàn phím 3D hiện, pill ở dưới.
- [ ] `npm run typecheck` + `npm run test` + `npm run build` sạch.
- [ ] Không có mã màu ngoài token (grep).
- [ ] Ảnh chụp màn hình khớp bố cục `42 S1`.

## 45.4. M1 — Chơi được (P0, 2–3 ngày)

**Làm:** `audio/engine.ts` với sample (dùng 8 tầng trước), `sampler` tải theo lô + decode; `pcInput` (mapping 2 hàng + octave shift + velocity theo độ dài phím); đàn on-screen bấm/kéo được; `triggerKey/releaseKey/panic`; trạng thái sẵn sàng; S0 start card; banner lỗi audio.

**Xong khi:**
- [ ] Bấm `A` → nghe tiếng đàn, phím lún, không trễ cảm nhận (< 30 ms trên máy thật).
- [ ] Giữ phím rồi thả: không có tiếng "cụt" bất thường; không nốt treo khi đổi tab.
- [ ] 88 phím bấm được bằng chuột; kéo ngang = glissando.
- [ ] Mở app lạnh → tiếng đầu tiên < 15 s trên 4G (hoặc synth tạm).
- [ ] `panic()` tắt hết (test unit).

## 45.5. M2 — Tuỳ biến & lưu (2–3 ngày)

**Làm:** `Settings` đầy đủ theo `44.3` (P0 subset: keyboard, notes, colors, camera, scene cơ bản, audio volume/velocity); S2 Customize với search + tabs; áp dụng ngay; undo cho settings; lưu `localStorage` + preset; S9 Settings 2 tab đầu.

**Xong khi:**
- [ ] 25 thông số P0 trong `09` Phần B chỉnh được và thấy ngay.
- [ ] Search tiếng Việt không dấu tìm đúng (`mau not` → "Màu nốt").
- [ ] Reset về mặc định hoạt động; reload giữ settings.
- [ ] Không panel nào che pill; 768 px dùng được.

## 45.6. M3 — Nhập MIDI + timeline (3–4 ngày)

**Làm:** `midi/parse` (worker) + giới hạn; kéo-thả file; `ParsedSong` → nốt rơi; transport (play/pause/seek/loop/tốc độ); S8 open dialog; `speedMap`; S3 Timeline cơ bản; S4 inspector chọn nốt (chưa sửa).

**Xong khi:**
- [ ] 12 file test `19.6` mở được, không treo > 1 s.
- [ ] Tempo đổi giữa bài: nốt không nhảy sai vị trí.
- [ ] Loop A–B chạy đúng, không lệch sau 10 vòng.
- [ ] Seek khi đang phát: không nốt treo, pedal reset.

## 45.7. M4 — Sửa & xuất (4–5 ngày)

**Làm:** `midi/edit` command + undo/redo; S5 piano roll (chọn/kéo/xoá/vẽ/snap/velocity lane); quantize/transpose; `.nfz` save/load + migrate + autosave IDB; S7 export WAV (OfflineAudioContext) + MIDI; S10 credits.

**Xong khi:**
- [ ] Sửa → undo 100 bước → redo đúng.
- [ ] Round-trip MIDI: số nốt/pitch/thời lượng/velocity bằng nhau.
- [ ] `.nfz` mở lại đúng settings + keyframes; file zip đọc được bằng `unzip`.
- [ ] WAV xuất ra mở được, không clip; MIDI xuất ra mở được ở app khác.

## 45.8. M5 — Luyện tập (3–4 ngày)

**Làm:** `practice/scoring` theo `16.3`; wait mode; đếm vào; metronome; S6 HUD + card kết quả; lưu session vào IDB + hiển thị tiến bộ; tempo ladder đơn giản.

**Xong khi:**
- [ ] 10 ca test `16.7` cho kết quả đúng công thức.
- [ ] Wait mode: sai → đứng, đúng → tiến ≤ 50 ms, Tab bỏ qua.
- [ ] Kết quả chỉ ra ô nhịp yếu; "luyện lại ô yếu" đúng phạm vi.
- [ ] Calibration lưu và áp dụng vào điểm số.

## 45.9. M6 — Đánh bóng & phát hành (3–4 ngày)

**Làm:** S11 đủ trạng thái lỗi; accessibility (focus, aria-live, contrast); export video 720p30 (nếu kịp); PWA; header/CSP; trang credits/license; README; deploy.

**Xong khi:**
- [ ] Checklist `41.7` đạt 10/10 (trừ mục video nếu bỏ).
- [ ] Lighthouse A11y ≥ 95, 0 axe serious.
- [ ] Không request mạng ngoài CDN sample.
- [ ] Deploy chạy; preview nhúng iframe được (`Permissions-Policy: midi=(self)`).

## 45.10. Thứ tự ưu tiên khi thiếu thời gian

Cắt theo thứ tự **từ dưới lên**: video export → practice nâng cao → piano roll vẽ nốt → export MIDI → timeline keyframe → credit page.
**Không bao giờ cắt:** engine âm thanh đúng, mở MIDI đúng, settings lưu được, không nốt treo.

## 45.11. Cổng chất lượng (chạy trước mỗi lần bàn giao)

```bash
npm ci
npm run typecheck        # 0 lỗi
npm run lint             # 0 error
npm run test -- --run    # 100% pass; coverage midi/, audio/, practice/ >= 60%
npm run build            # không cảnh báo bundle > 1.2 MB gz (chính)
npx playwright test      # 8 kịch bản chính
```
Ghi kết quả vào `docs/build-log/M{n}.md` (5 dòng: làm gì, test, số đo, nợ, bước sau).

## 45.12. Những gì AI **không** được làm trong M0–M6

- Không thêm backend, không auth, không analytics.
- Không thêm thư viện UI (MUI/Chakra/shadcn full kit) — tự viết theo `43`.
- Không dùng CSS-in-JS runtime; Tailwind + CSS var.
- Không refactor sang Next.js/SSR.
- Không đổi tên type trong `44`.
- Không "cải tiến" chuỗi UI tiếng Việt.
- Không bật `COOP/COEP` toàn app.
- Không dùng CDN của NoteFall.
- Không copy code từ repo không license.
- Không mở rộng phạm vi ngoài milestone đang làm (ghi ý tưởng vào `docs/ideas.md`).

## 45.13. Câu lệnh giao việc (mẫu, dùng được ngay)

```
Dự án: piano-app (web, Vite+React+TS+three, local-first, tiếng Việt).
Đọc: research-piano/41 → research-piano/45 → research-piano/spec/design-tokens.json
     → file chủ đề của milestone (xem 41.2).
Nhiệm vụ: {M2 — Tuỳ biến & lưu}.
Ràng buộc: 41.1 (12 luật), 45.12 (10 điều cấm), token từ spec, chuỗi từ 42.
Bàn giao: code + test + ảnh chụp + cập nhật 45.2 + docs/build-log/M2.md.
Thiếu thông tin → TODO(spec), liệt kê ở cuối; không tự bịa số liệu.
```

## 45.14. Định nghĩa "clone đủ tính năng"

Một bản được coi là **đủ** khi có:

| Nhóm | Yêu cầu tối thiểu |
|---|---|
| Chơi | bàn phím máy tính, MIDI USB, đàn on-screen, velocity, pedal, panic, latency hiển thị |
| Phát | play/pause/seek/loop/speed/count-in/metronome, mute theo track, tay trái/phải |
| Hình | nốt 3D, camera, màu theo 5 chế độ, nhãn nốt 3 hệ, phím đàn, nền ảnh/video, particle, bloom |
| Sửa | piano roll đầy đủ (chọn/kéo/xoá/vẽ/snap/velocity), quantize, transpose, undo 100 |
| Học | wait mode, chấm điểm, kết quả theo ô nhịp, tempo ladder, log phiên |
| Dữ liệu | `.nfz` save/load/migrate, autosave, export MIDI, import MusicXML (tùy chọn) |
| Xuất | WAV, video 720p30 (tùy chọn), ảnh chụp |
| Khác | tiếng Việt + Anh, PWA, credits/license, không telemetry |

Nếu thiếu bất kỳ dòng nào ở cột "Yêu cầu tối thiểu" → **chưa đủ**, trừ khi người dùng chấp thuận cắt.
