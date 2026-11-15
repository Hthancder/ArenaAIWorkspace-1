# 14 — Thư viện, dependency và giấy phép (kiểm chứng 2026-11-14)

> File này trả lời: **dùng thư viện nào, giấy phép gì, nặng bao nhiêu, có được bê code không.**
> Số liệu lấy trực tiếp từ `registry.npmjs.org` (`/latest`) và `api.github.com` (license + contents), không phải từ blog.

## 14.1. Dependency của NoteFall — trạng thái & giấy phép

| Package | Bản NoteFall dùng | Bản mới nhất (14/11/2026) | License | Unpacked | Vai trò | Ghi chú khi fork |
|---|---|---|---|---|---|---|
| `react` | 18.3.1 | — | MIT | — | UI | R3F 9 cần React 19 → **giữ React 18 nếu không muốn nâng cấp lớn** |
| `@react-three/fiber` | 8.17 | **9.8.2** | MIT | 2.3 MB | render 3D | v9 yêu cầu React 19; v8 vẫn chạy React 18 |
| `@react-three/drei` | 9.114 | **10.7.9** | MIT | 1.7 MB | helper 3D | drei 10 đi với R3F 9 |
| `three` | 0.169 | **0.187** | MIT | 20.5 MB | WebGL | nâng version có thể vỡ shader/geometry tuỳ chỉnh |
| `@react-three/postprocessing` | 2.16 | **3.2.2** | MIT | 0.5 MB | Bloom | — |
| `postprocessing` | 6.39 | 6.39.6 | **Zlib** | 2.7 MB | hiệu ứng | Zlib license: giữ notice, OK thương mại |
| `smplr` | 0.20 | **1.2.0** | MIT | 1.1 MB | sampler | ⚠️ `stopId` mặc định = midi → phải truyền id riêng |
| `@tonejs/midi` | 2.0.28 | 2.0.28 | MIT | 281 KB | parse/serialize SMF | ổn định, không update từ 2023 |
| `tone` | 15.0 | **15.1.22** | MIT | **5.3 MB** | chỉ để quản lý AudioContext | **có thể bỏ** → dùng Web Audio thuần, giảm bundle đáng kể |
| `mediabunny` | 1.61 | **1.66** | **MPL-2.0** | **11.6 MB** | mux MP4/WebM | MPL là copyleft **theo file**: sửa file của họ thì phải công bố file đó; dùng nguyên thì OK |
| `fflate` | 0.8.2 | 0.8.3 | MIT | 778 KB | zip `.nfz` | — |
| `zustand` | 5.0.1 | 5.1.0 | MIT | 109 KB | state | — |
| `react-aria-components` | 1.4 | **1.22** | **Apache-2.0** | 6.8 MB | UI headless | Apache-2.0: giữ NOTICE, OK thương mại |
| `i18next` / `react-i18next` | 26 / 17 | 27 / — | MIT | 0.6 MB | i18N | — |
| `@fontsource-variable/geist` | 5.3 | 5.3 | **OFL-1.1** | 177 KB | font | OFL: được nhúng, không được bán font riêng |
| `posthog-js` | 1.374 | — | MIT (client) | — | analytics | **nên bỏ** (gửi dữ liệu sang server bên thứ ba) |
| `lil-gui` (dev) | 0.20 | — | MIT | — | panel debug | giữ cho dev |

### Thư viện **nên thêm** (cho các tính năng P1/P2)

| Package | Latest | License | Unpacked | Dùng cho | Ghi chú |
|---|---|---|---|---|---|
| `opensheetmusicdisplay` | 2.3.1 | **BSD-3-Clause** | 2.5 MB | render MusicXML + cursor | Lựa chọn chính cho sheet music; BSD-3 dễ dùng |
| `vexflow` | **5.0.0** | MIT (npm) | 20.8 MB | vẽ khuông nhạc / composer | Nặng; chỉ import phần cần. npm ghi MIT dù GitHub API báo "Other" |
| `soundfont-player` | 0.12.0 | MIT | 100 KB | phát `.sf2`/soundfont | Nhẹ, cũ (2023) nhưng ổn; thay thế: tự viết loader + smplr |
| `@spotify/basic-pitch` | 1.0.1 | **Apache-2.0** | 1.7 MB | audio → MIDI | Cần `onnxruntime-web` |
| `onnxruntime-web` | 1.31.1 | MIT | **147 MB** (unpacked, gồm nhiều build wasm) | inference | Chỉ ship bản wasm cần (~5–15 MB thực tế), không bundle hết |
| `lamejs` | 1.2.1 | **LGPL-3.0** ⚠️ | 6.3 MB | encode MP3 | LGPL: nên **dynamic import** hoặc tránh; WAV/FLAC an toàn hơn |
| `@breezystack/lamejs` | 1.2.7 | LGPL-3.0 ⚠️ | 460 KB | encode MP3 (fork gọn hơn) | Cùng vấn đề license |

### Kết luận dependency
- **Giữ**: React 18 + R3F 8 + three 0.169 + drei 9 + postprocessing (đã ổn định, đẹp).
- **Cân nhắc bỏ**: `tone` (5.3 MB chỉ để giữ AudioContext → thay bằng Web Audio thuần), `posthog-js`.
- **Thêm P1**: OSMD (BSD-3), soundfont-player (MIT).
- **Thêm P2**: `@spotify/basic-pitch` + `onnxruntime-web` (chỉ khi làm audio→MIDI).
- **Tránh nếu được**: lamejs (LGPL) — ưu tiên WAV/FLAC/Opus; nếu cần MP3 thì load động.
- **MPL-2.0 (mediabunny)**: dùng nguyên thì ổn; nếu sửa file của họ phải công bố phần sửa đó.

## 14.2. Giấy phép các repo tham khảo — ⚠️ nhiều repo **KHÔNG có LICENSE**

Kiểm tra trực tiếp `api.github.com/repos/<owner>/<repo>` + danh sách file gốc (14/11/2026):

| Repo | License GitHub báo | Có file LICENSE? | Dùng code được? |
|---|---|---|---|
| `ekkx/notefall` | NOASSERTION ("Other") | ✅ `LICENSE.md` = **PolyForm Shield 1.0.0** | Có điều kiện — **Noncompete**, xem file 10.1 |
| `PolyMeilex/Neothesia` | **GPL-3.0** | ✅ | Được, nhưng **copyleft mạnh** (phân phối bản sửa phải mở source) |
| `danigb/soundfont-player` | **MIT** | ✅ | ✅ Thoải mái |
| `isc/opensheetmusicdisplay` | **BSD-3-Clause** | ✅ | ✅ Giữ copyright notice |
| `0xfe/vexflow` | NOASSERTION | ✅ (npm: MIT) | ✅ Thực tế MIT |
| `RenCheng0525/WebGL-Piano` | **None** | ❌ **KHÔNG có file LICENSE** (README *nói* MIT) | ⚠️ **Rủi ro** — README tuyên bố MIT nhưng thiếu văn bản; muốn dùng phải xin xác nhận tác giả |
| `worldwiderad/pianoroll` | **None** | ❌ | ❌ Không có giấy phép = **giữ toàn quyền**; chỉ đọc để học ý tưởng |
| `Bewelge/MIDIano` | **None** | ❌ | ❌ Không được copy code (dù public) — chỉ học ý tưởng |
| `IbrahimKhan25/piano-app` | **None** | ❌ | ❌ Như trên |
| `pirozhki/piano-visualizer-classic` | (repo không trả metadata) | ❌ | ❌ Coi như không có |

> **Nguyên tắc pháp lý quan trọng**: public GitHub **không** đồng nghĩa dùng được. Không có LICENSE = mặc định "all rights reserved". Chỉ **đọc để hiểu thuật toán** rồi tự viết lại, không copy mã.

**Hệ quả thực tế:** các ý tưởng hay nhất (DP fingering của `piano-app`, wait-mode + VexFlow của MIDIano) **không được copy code**. Nhưng **thuật toán/ý tưởng không bị bảo hộ bản quyền** (chỉ biểu hiện cụ thể của code mới bị) → viết lại từ mô tả là hợp pháp. File 16 mô tả thuật toán bằng lời + pseudocode tự viết.

## 14.3. Giấy phép tài nguyên âm thanh / hình ảnh

| Tài nguyên | Dùng cho | License | Điều kiện |
|---|---|---|---|
| **Salamander Grand Piano V3** (Alexander Holm) | piano sample chính | **CC BY 3.0** | Phải ghi công tác giả + link license ở đâu đó người dùng thấy (About/Credits) |
| Sample "rel*" (release noise), "harm*" (sympathetic), "pedal*" (pedal noise) trong cùng bộ Salamander | tăng chân thực (P2) | CC BY 3.0 | NoteFall **bỏ qua** các file này — cơ hội cải thiện |
| Hand models (NoteFall `hands/`) | tay ảo | CC0 (theo repo) | Không cần ghi công |
| **GeneralUser GS** `.sf2` | đa nhạc cụ | Free nhưng **đọc điều kiện của tác giả** (thường cấm bán sample set) | Kiểm tra `LICENSE` trong bản tải |
| **FluidR3_GM** | GM soundfont | Thường MIT-like — **kiểm tra lại** | MIDIano dùng bản này |
| **MIDI.js soundfonts** (`gleitz/midi-js-soundfonts`) | GM nhanh cho web | Xem repo (thường MIT cho script, sample theo từng nguồn) | Kiểm tra từng instrument |
| Nhạc demo (`.mid`) | demo | Bản quyền **bản phối** thuộc người làm MIDI, không thuộc nhà soạn nhạc cổ điển | Chỉ dùng bài public domain + MIDI tự làm |
| MusicXML (Mutopia, OpenScore, IMSLP) | sheet music | Tùy nguồn: Mutopia CC BY-SA, OpenScore CC0, IMSLP tùy bản | Ghi nguồn, kiểm tra từng file |

**Việc phải làm trước khi publish:**
1. Thêm màn hình **Credits/Licenses** liệt kê: Salamander (CC BY 3.0 + link), font OFL, các thư viện MIT/BSD/Apache/MPL.
2. Giữ nguyên file LICENSE của NoteFall (nếu fork) + `Required Notice: Copyright (c) 2026 ekkx`.
3. Không đóng gói sample CC BY vào sản phẩm bán mà không ghi công.
4. Nếu dùng GeneralUser/FluidR3 → đọc license gốc, ghi rõ.

## 14.4. Chi tiết bộ sample Salamander (từ script của NoteFall)

| Thông số | Giá trị |
|---|---|
| Nguồn | `https://archive.org/download/SalamanderGrandPianoV3/SalamanderGrandPianoV3_OggVorbis.tar.bz2` (~78 MB) |
| Số sample dùng | **30 phím** (A0, C1, D#1, F#1, A1, C2 … A7, C8) × **16 velocity layer** = **480 file OGG** |
| Codec | OGG Vorbis 96 kbps (chuyển từ WAV 24-bit bằng ffmpeg) |
| Tổng dung lượng | ~**77 MB** (tải 1 lần, cache bằng Cache Storage) |
| Tên file | `<note>v<layer>.ogg`, `#` đổi thành `s` (Ds, Fs) để không bị hiểu là URL fragment |
| CDN của NoteFall | `https://samples.notefall.app/salamander-v3-close`, **CORS chỉ cho `https://notefall.app`** |
| Dev proxy | `/samples-cdn/*` (vite proxy) để tránh CORS khi chạy localhost |
| Sample bị bỏ | `rel*`, `harm*`, `pedal*` (release/sympathetic/pedal noise) |

→ **Khi fork bắt buộc**: tự host 480 OGG này (hoặc tự transcode từ WAV gốc) và bật CORS cho domain của mình, nếu không app sẽ không có tiếng.

## 14.5. Bảng quyết định nhanh "dùng cái gì"

| Nhu cầu | Chọn | Lý do |
|---|---|---|
| Piano sample | Salamander V3 tự host (CC BY) | Chất lượng cao, license rõ, NoteFall đã tích hợp sẵn |
| Đa nhạc cụ | GeneralUser GS `.sf2` + `soundfont-player` (MIT) | Không tự viết parser SF2 |
| MIDI parse | `@tonejs/midi` | Đã dùng, đủ tốt; nếu cần giữ mọi event → `midi-file` |
| Sheet music | `opensheetmusicdisplay` (BSD-3) | Render MusicXML chuẩn + cursor có sẵn |
| Sheet từ MIDI | `vexflow` (MIT) hoặc tự quantize + VexFlow | Chỉ làm ở mức cơ bản, cảnh báo độ chính xác |
| Audio → MIDI | `@spotify/basic-pitch` (Apache-2.0) | Nhẹ hơn ByteDance 154 MB; chất lượng đủ cho demo |
| MP4/WebM | `mediabunny` (MPL-2.0) + WebCodecs | Đã tích hợp; thay thế: `mp4-muxer`/`webm-muxer` (MIT) nếu muốn tránh MPL |
| Zip project | `fflate` (MIT) | Nhẹ |
| State | `zustand` (MIT) | Nhẹ, NoteFall đã dùng |
| UI | `react-aria-components` (Apache-2.0) + Tailwind | Accessible, đã dùng |
| MP3 export | **tránh**; dùng WAV/FLAC, hoặc `lamejs` load động (LGPL) | License + chất lượng |
