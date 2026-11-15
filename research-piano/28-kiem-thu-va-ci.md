# 28 — Kiểm thử & CI/CD

> NoteFall gần như **không có test** — đó là rủi ro lớn nhất khi fork và sửa sâu. File này là kế hoạch test thực dụng cho app piano web.

## 28.1. Kim tự tháp test cho app piano

| Lớp | Cái gì | Công cụ | Tốc độ | Số lượng |
|---|---|---|---|---|
| **Unit (nhiều nhất)** | `midi/edit`, `speedMap`, `settingsKeyframes`, `practice/scoring`, `fingering`, `noteName`, `chord detect` | Vitest | ms | 100+ |
| **Audio snapshot** | Render 1 đoạn bằng `OfflineAudioContext` → so hash/peak/duration | Vitest + OfflineAudioContext | 1–2 s | 10–20 |
| **Integration** | `store` + `engine` + parse: mở MIDI → play → seek → loop | Vitest + jsdom (audio mock) | 1–3 s | 20–30 |
| **E2E** | Người dùng thật: kéo file, bấm phím, export | Playwright (Chromium) | 10–30 s | 8–15 |
| **Visual** | Canvas 3D không lệch sau refactor | Playwright screenshot + so sánh | 10 s | 5–10 |
| **Performance budget** | Bundle size, FPS, thời gian parse | size-limit, custom bench | 30 s | 5 |

## 28.2. Test những phần "không thể sai"

| Hàm/module | Test case quan trọng |
|---|---|
`midi/parse` → `ParsedSong` | tempo map, format 0/1, velocity 0 = note off, overlap cùng pitch, drum channel, note treo (file 19) |
`midi/edit` | add/move/resize/split/delete giữ nguyên bất biến (không overlap, id duy nhất, duration đúng) |
`speedMap` | tích phân nghịch đảo: `timeToSong(songToTime(t)) ≈ t` (sai số < 1 ms) |
`settingsKeyframes` | nội suy giữa 2 pin, giá trị ngoài khoảng, key không animate được |
`practice/scoring` | 10 ca ở file 16.7 (perfect, lệch đều, bỏ nốt, thêm nốt, nốt lặp, hợp âm, tempo đổi) |
`fingering` | gam C, hợp âm C-E-G, fixed fingers, >5 nốt, tay trái mirror |
`noteName` / solfège | C4↔Đô4, C#↔Đô thăng, transpose giữ đúng spelling |
`sanitize/midi limits` | file quá lớn bị từ chối, zip bomb bị chặn (file 27) |

**Nguyên tắc:** test **hành vi**, không test implementation. Một khi `midi/edit` có 30 test, bạn có thể refactor tự tin.

## 28.3. Mock Web MIDI & audio

**Web MIDI** (không có trong jsdom/Node):
```ts
// test/setup/midi.ts
class FakeInput extends EventTarget {
  onmidimessage: ((e: { data: Uint8Array }) => void) | null = null
  send(bytes: number[]) {
    const data = new Uint8Array(bytes)
    this.onmidimessage?.({ data })
  }
}
export function installFakeMidi() {
  const input = new FakeInput()
  const access = {
    inputs: new Map([['fake', input]]),
    outputs: new Map(),
    onstatechange: null,
  }
  ;(navigator as any).requestMIDIAccess = async () => access
  return { input, access }
}
```
- Test: note on/off, velocity 0 = off, CC64, cắm/rút thiết bị, không có quyền.

**Audio**:
- Unit/integration: **mock** `AudioContext` (chỉ ghi lại lệnh schedule) — nhanh.
- Audio snapshot: dùng **`OfflineAudioContext` thật** trong Chromium (Playwright) để render và so sánh:
  - `duration`, `peak`, `RMS`, hash của mẫu (với seed cố định).
  - Không so bit-exact giữa các máy (float/CPU khác nhau) → so với dung sai (peak ±0.5 dB).

**Thời gian**:
- Inject clock (NoteFall đã có `clock.ts`) → test dùng `VirtualClock`, không `waitForTimeout`.
- `performance.now`, `requestAnimationFrame`: tua bằng `page.clock` (Playwright) hoặc fake timer (Vitest).

## 28.4. Determinism — điều kiện để test ảnh/âm thanh

| Yếu tố ngẫu nhiên | Cách cố định |
|---|---|
| Màu random theo nốt | seed trong settings (`noteRandomSeed`) — NoteFall đã có |
| Particle | seed + virtual clock + `Math.random` được patch trong test |
| Camera auto | tắt trong test |
| Sample decode | chờ `engine.isReady()` trước khi chụp |
| Device pixel ratio | set `deviceScaleFactor: 1` |
| Font | chờ `document.fonts.ready` |

## 28.5. E2E Playwright — 10 kịch bản tối thiểu

1. Mở app → thấy bàn phím → bấm phím máy tính → có âm thanh (kiểm tra trạng thái engine).
2. Kéo file `.mid` → tên bài hiện, số nốt hiện, phát được, pause được.
3. Seek scrubber → thời gian đúng, không lệch hình.
4. Loop A–B → phát vòng, hết loop quay lại.
5. Ghi âm (count-in tắt) → 3 nốt → dừng → take xuất hiện → export MIDI tải về.
6. Sửa nốt: chọn, dịch, xoá, undo, redo.
7. Wait Mode: giả lập MIDI đúng → tiến; sai → đứng; skip được.
8. Chấm điểm: chơi lệch → report hiện bar yếu.
9. Export WAV → file tải về, dung lượng > 0, header đúng (`RIFF`).
10. Export video 720p30 5 s → file mp4 tồn tại, mở được bằng `ffprobe` (nếu CI có ffmpeg).

Với Web MIDI: `page.addInitScript(installFakeMidi)` + expose hàm `window.__fakeMidi.send([...])`.

## 28.6. Visual regression cho canvas 3D

- Chụp **sau khi** engine ready + clock dừng ở một mốc (ví dụ `t = 5.000 s`).
- So sánh với ảnh chuẩn, **ngưỡng** cho phép (0.1–0.3% pixel khác) vì GPU khác nhau.
- Chạy visual test **chỉ trên 1 môi trường** (Chromium headless trên CI) để ổn định.
- Chụp 5 trạng thái: không bài (start card), đang phát, pause + chọn nốt, inspector mở, dialog export.
- Lưu ảnh vào artifact khi fail để xem.

## 28.7. CI (GitHub Actions) — workflow gợi ý

```yaml
name: ci
on: [pull_request, push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npm run typecheck
      - run: npm run test -- --run          # vitest
      - run: npm run build
      - run: npx size-limit                 # ngân sách bundle
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npx playwright install --with-deps chromium
      - run: npm run build
      - run: npx playwright test
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: playwright-report, path: playwright-report }
```

- **Vercel** tự tạo preview cho mỗi PR → thêm bước smoke test trên preview URL (tùy chọn).
- Cache: `~/.npm`, Playwright browsers.
- Thời gian mục tiêu: build+unit < 3 phút, e2e < 6 phút.

## 28.8. Ngân sách chất lượng (quality gates)

| Cổng | Ngưỡng | Ghi chú |
|---|---|---|
| TypeScript | 0 lỗi (`tsc -b --noEmit`) | bắt buộc |
| Unit test | pass 100%, coverage **≥ 60%** cho `midi/`, `practice/`, `audio/` | không cần 90% toàn repo |
| Bundle (gzip) chính | ≤ 1.2 MB | three + rAC nặng; tách chunk |
| Lighthouse Performance | ≥ 80 desktop | |
| Lighthouse Accessibility | ≥ 95 | |
| axe violations | 0 serious/critical | |
| FPS (bench) | ≥ 55 với 2.000 nốt @1080p | máy CI có thể thấp hơn → đo trên máy thật |
| Không `console.error` trong prod | bắt buộc | |

## 28.9. Bộ dữ liệu test

- **12 file MIDI** ở file 19.6 — commit vào `test/fixtures/midi/` (tự làm, public domain).
- **3 project `.nfz`**: tối giản, đầy đủ tính năng, file "bẩn" (settings lạ).
- **Session JSON** cho scoring (10 ca ở file 16.7).
- **Sample giả** (1–2 file OGG rất nhỏ) cho test audio, không commit 77 MB.
- **Zip bomb giả** (file nhỏ khai báo giải nén 4 GB) để test giới hạn.

## 28.10. Quy trình báo lỗi & điều tra

**Mẫu báo lỗi trong app** (thay cho feedback endpoint của NoteFall):
- Người dùng bấm "Báo lỗi" → app tạo **báo cáo đã điền sẵn**: phiên bản, trình duyệt, GPU, thiết bị MIDI, settings JSON (rút gọn), có/không WebGL2/WebCodecs.
- Hiện **toàn bộ nội dung** trước khi gửi (như NoteFall làm), cho phép bỏ tick từng mục.
- Gửi bằng: mở GitHub Issue với nội dung điền sẵn (không cần server) **hoặc** copy vào clipboard.
- Tuyệt đối không tự gửi file MIDI của người dùng.

**Triage:**
| Nhãn | Nghĩa |
|---|---|
| `bug/audio` | im tiếng, click, sai pedal |
| `bug/midi` | parse, note treo, tempo |
| `bug/perf` | FPS, RAM, tải chậm |
| `bug/export` | codec, hỏng file |
| `bug/ui` | layout, phím tắt |
| `license` | vấn đề giấy phép |

## 28.11. Trước mỗi release

- [ ] `npm ci && npm run typecheck && npm run test -- --run && npm run build` sạch.
- [ ] Chạy 10 kịch bản E2E trên Chromium; smoke test thủ công trên Safari/Firefox.
- [ ] Test trên 1 máy yếu (hoặc giả lập 4× CPU throttle).
- [ ] Kiểm tra 3 file MIDI "khó" (black MIDI, tempo đổi, pedal).
- [ ] Export thử 1080p30 và 9:16; mở bằng ffprobe/trình phát.
- [ ] Kiểm tra dung lượng bundle không tăng bất thường.
- [ ] Bump version + ghi changelog (tiếng Việt, ngắn).
- [ ] Kiểm tra service worker: người dùng cũ nhận bản mới.
