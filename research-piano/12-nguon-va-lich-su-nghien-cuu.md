# 12 — Nguồn tham khảo & nhật ký nghiên cứu

> Ngày: 2026-11-14. Mọi kết luận trong bộ tài liệu này đều truy được về một trong các nguồn dưới đây.
> Lưu ý: tính năng app thương mại thay đổi theo phiên bản; số liệu giá là tại thời điểm tra cứu.

## 12.1. Nguồn trực tiếp từ source code (độ tin cậy cao nhất)

| Nguồn | Lấy được gì |
|---|---|
| `git clone https://github.com/ekkx/notefall` (shallow, 2026-11-14) | Toàn bộ cấu trúc `src/` (201 file), `package.json`, `CLAUDE.md` (kiến trúc chi tiết), `LICENSE.md` (PolyForm Shield 1.0.0), `src/store.ts` (`Settings` + `defaultSettings` ~300 key), `src/midi/types.ts` (NoteEvent/PedalEvent/TrackInfo/ParsedSong), `src/audio/engine.ts` (public API: triggerKey, addKeyListener, addLiveListener, setLoop, seek, pause, tick, speed automation, pedal), `src/audio/playback.ts`, `src/audio/clock.ts` (pluggable clock + epoch), `src/audio/pedalDepth.ts`, `src/export/*`, `src/projects/*` |
| `https://github.com/ekkx/notefall` | Mô tả sản phẩm, tính năng, ảnh, 248 commits, commit mới nhất 9b6368b (2026-11-09) |

> Ghi chú: `curl` raw.githubusercontent.com cho repo này trả về rỗng — dùng `git clone` thay thế (đã làm).

## 12.2. Repo & dự án open source

| URL | Nội dung |
|---|---|
| https://github.com/Suma-Udd/notefall | Python desktop, app tkinter, Synthesia video, Basic Pitch ONNX + ByteDance transcription, sustain CC64, 5 themes, hands, PyInstaller |
| https://github.com/fonghtdev/NoteFall | Electron, falling notes từ PDF/MIDI/MP3/WAV/FLAC, composer 2 staff (VexFlow), modelled grand + SF2, metronome, export MP4 720/1080, iPad |
| https://github.com/austinrsands/notefall | Web, học bài từ MIDI + MIDI keyboard, wait mode, keys/transpose/tempo |
| https://github.com/micooz/notefall, https://github.com/Wesley-AlvesRolim/notefall, https://github.com/mjahangiralam/notefall | Fork của ekkx/notefall |
| https://github.com/Bewelge/MIDIano | MIDI player/learning web, falling bars + VexFlow sheet, wait mode, MIDI in/out, track color/particles/instrument, 3 soundfont |
| https://github.com/IbrahimKhan25/piano-app | Wait mode Web MIDI, OSMD MusicXML, fingering DP, loop/jump, hand switch, dev keyboard |
| https://github.com/isc/opensheetmusicdisplay | OSMD — render MusicXML trong browser, note coloring, export SVG/PNG |
| https://github.com/PolyMeilex/Neothesia | Rust + wgpu, GPL-3.0, MIDI visualizer cross-platform, SoundFont, free-play recording, ffmpeg encoder, workspace `neothesia-ai`/`-cli`/`-image`/`piano-layout` |
| https://github.com/worldwiderad/pianoroll | TS + Three.js web visualizer: theme JSON, timeline keyframes, background media, SoundFont sampler đa nhạc cụ, export MP4 WebCodecs, IndexedDB library |
| https://github.com/pirozhki/piano-visualizer-classic | Canvas 2D visualizer, hit effects (smoke/spark/hybrid), effect quality, export WebM, không CDN |
| https://github.com/RenCheng0525/WebGL-Piano | **MIT** — Three.js + Tone.js + @tonejs/midi + abcjs, 30 sample Salamander, pedal + re-strike, Tone.Transport scheduling, bỏ channel 10, decode tên track CJK, InstancedMesh, resize panel |
| https://github.com/danigb/soundfont-player | SoundFont loader WebAudio, polyphony không giới hạn, schedule list, kết nối Web MIDI |
| https://github.com/gleitz/midi-js-soundfonts | Soundfont MIDI.js cho browser |
| https://github.com/javiert01/MIDI-Scenes | Đo latency Web MIDI → Web Audio |

## 12.3. App thương mại — trang chính thức / store

| URL | Nội dung |
|---|---|
| https://play.google.com/store/apps/details?id=com.gamestar.perfectpiano | Perfect Piano: 88 phím, single/double/dual/chords, force touch, key width, 9+ timbre + plugin, MIDI+AAC record, metronome, learn hàng nghìn bài, 3 guidance, 3 play mode, L/R hand, A-B loop, speed/difficulty, multiplayer/chat/guild/weekly challenge, USB MIDI, MusicXML |
| https://www.seemusicapp.com/ (+ App Store, Google Play listing) | SeeMusic: record MIDI+audio+camera, auto align keyboard footage, isolate hands/keys, pitch detection audio→MIDI, MusicXML + sheet đồng bộ, MIDI editor, chroma 12 pitch color, textures/materials, background image/video, style presets, 4K/60 export, vertical video, Free w/ watermark, Pro $8.99/mo hoặc $79.99/yr |
| https://www.pianoviz.app/ (+ blog AI transcription) | PianoViz: AI transcription solo piano từ audio (MP3/WAV/FLAC/M4A/OGG ≤50 MB), WebGL2 realtime, export MP4 Full HD 30/60fps trên máy, hand separation beta, project lưu local; **không** export MusicXML, không sửa note, không loop/đổi camera |
| https://lumakeys.app/piano-app-comparisons | Bảng so sánh Synthesia alternatives 2026: SeeMusic, Embers, LumaKeys (Mac/Win, free + Pro $79), Flowkey, Anything Piano, Falling Note, Neothesia, Piano From Above, Pianotify |
| https://www.pianote.com/, https://www.hoffmanacademy.com/ | App học qua video, teacher-led |

## 12.4. Bài review / so sánh (dùng cho tính năng app học)

| URL | Nội dung |
|---|---|
| https://pianoers.com/synthesia-piano-review/ | Synthesia: Melody/Rhythm/Recital practice, 100 điểm, hands separately, speed, jump/loop, labels (finger/note/solfege/scale degree), sheet music, lighted keyboard, Free Play 6-track recorder, $29 one-time, MIDI only |
| https://www.songscription.ai/blog/best-piano-learning-apps | So sánh Simply Piano / Flowkey / Skoove / Yousician / Synthesia / Piano Marvel / Playground Sessions / Pianote |
| https://www.artmaster.com/articles/the-best-piano-learning-apps-i-tried-them-so-you-don-t-have-to | Trải nghiệm thực tế từng app, ưu/nhược, giá |
| https://playsheet.app/blog/comparing-piano-apps | Bảng: Playsheet/PianoML/Sightread/PianoBooster free BYO music; Piano Marvel static sheet; Simply/flowkey/Yousician/Skoove scrolling sheet; Synthesia falling notes; Playground strict grading |
| https://midisheetmusic.com/ (và các trang sheet) | Nhận xét: Synthesia/falling-note apps có ích cho người mới nhưng dễ thành "gậy chống", không học đọc nhạc |

## 12.5. Virtual piano / web piano

| URL | Nội dung |
|---|---|
| https://virtualpianokeyboard.com/ | Web piano: Web Audio zero-latency, 88 phím, multi-touch, USB MIDI, 4 engine, virtual sheet, lesson |
| https://tembrica.com/en/online-piano | 88 phím, 5 voice, MIDI, PC keymap, sustain Space, transpose/octave, chord detection, scale highlight, record WAV+MIDI, learn mode, drop .mid ≤2MB, synth 16-partial |
| https://toolv.com/en/app/online-piano | 4 instrument, glissando, record MP3 (10 local), preset songs, metronome 40–240 BPM, MIDI velocity |
| https://tuneonmusic.com/virtual-piano | 88 phím sampled grand 2 velocity layer, game mode echo, note labels, metronome |
| https://screenpiano.com/ | 88 phím, PC keyboard 61 phím, glide, MIDI từ settings, letter-note songs |
| https://roxypiano.web.id/ | 128 GM instrument, Salamander 16 layer, falling notes, Wait Mode, accuracy stats, metronome time signature, chord detection, transpose/speed, PWA, 8 ngôn ngữ, Web MIDI CC64 |
| https://synthio.io/ | Pitch bend ±2 semitone (wheel/arrow/MIDI 14-bit), MIDI CC14–17 → cutoff/resonance/detune/low-cut, record audio+video |
| https://playvirtualinstruments.com/ | 17 nhạc cụ ảo, recorder WebM, mark mode, chord chart, metronome, tuner |

## 12.6. Tài liệu kỹ thuật

| URL | Nội dung |
|---|---|
| https://indipiano.com/what-is-midi/ | SMF header/tracks, Format 0/1/2, tempo/time sig/key trong conductor track, CC64/7/10/1, velocity 1–127, pitch bend 14-bit, GM channel 10 drums (lưu 9) |
| https://midee.app/blog/playing-your-midi-keyboard-in-the-browser/ | Web MIDI trong browser, độ trễ, lưu ý thực tế |
| https://www.testmuai.com/learning-hub/web-midi-api-browser-support/ | Web MIDI: Chrome/Edge/Opera; Firefox sau flag; Safari không hỗ trợ |
| https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html | Salamander Grand Piano V3 — Yamaha C5, 48kHz 24-bit, 16 velocity layer, SFZ FLAC 707 MiB / SF2 296 MiB, CC BY 3.0 |
| https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API, /Web_MIDI_API, /WebCodecs_API | Tài liệu chuẩn (tham chiếu khi code) |
| https://polyformproject.org/licenses/shield/1.0.0 | Toàn văn PolyForm Shield 1.0.0 (Noncompete) |
| https://vexflow.com/, https://opensheetmusicdisplay.org/ | Thư viện notation |

## 12.6b. Nguồn kiểm chứng giấy phép & support (đợt 2 — 14/11/2026)

| Nguồn | Lấy được gì |
|---|---|
| `https://api.github.com/repos/<owner>/<repo>` | Trường `license.spdx_id`, `pushed_at`, `language`, stars cho 11 repo → phát hiện **NOASSERTION / null license** ở nhiều repo |
| `https://api.github.com/repos/<owner>/<repo>/contents/` | Danh sách file gốc → xác nhận **không có LICENSE** ở WebGL-Piano, pianoroll, MIDIano, piano-app; `ekkx/notefall` có `LICENSE.md` |
| `https://registry.npmjs.org/<pkg>/latest` | Version, license, `unpackedSize`, số dependency cho 20+ package (bảng đầy đủ ở file 14.1) |
| `https://caniuse.com/midi` | Bảng support Web MIDI thật: Safari **không hỗ trợ** mọi phiên bản (kể cả 27.3 TP); Firefox 108+ desktop; iOS Safari không; extension "Web MIDI for Safari" là userland |
| https://www.testmuai.com/learning-hub/webcodecs-browser-support/ + https://www.stormstreaming.com/blog/webcodecs-low-level-media-encoding-and-decoding-in-the-browser/ | WebCodecs: Chrome 94+, Firefox 130+ desktop (không Android), Safari 26+ (16.4–18.7 chỉ video); encode: AAC không có trên Firefox, **MP3 encode gần như không hỗ trợ** |
| https://antmedia.io/best-audio-codec/ | Ma trận codec audio/container thực tế 2026 |
| https://midee.app/blog/playing-your-midi-keyboard-in-the-browser/ | Ngân sách latency chi tiết (USB <1ms, BT 15–40ms, scheduling 0–20ms, tổng 5–25ms / 60–120ms BT); khuyến nghị preload sample trước khi người dùng bấm |
| https://www.epiano.org/midi-piano | iOS/iPadOS: mọi browser đều WebKit → không Web MIDI |
| https://dev.to/tiltedlunar123/grading-piano-timing-in-the-browser-with-web-midi-90g | **Công thức cửa sổ timing** (0.18 beat, min 70/max 140 ms; window 0.5 beat, max 400 ms), **calibration 12 click @80 BPM lấy median**, cách neo `performance.now()` ↔ `AudioContext` bằng `getOutputTimestamp()`, bẫy "MIDI không phải user gesture", tiêu chí qua đoạn (90% nốt / 70% đúng nhịp), transpose giữ đúng spelling (E→F# không thành Gb) |
| Bản clone `Bewelge/MIDIano`, `IbrahimKhan25/piano-app` | Đọc để hiểu thuật toán (wait mode trên cursor OSMD, DP fingering, mic autocorrelation đơn âm) — **không copy code vì không có license** |
| `docs/design-system.md`, `src/ui/kit/tokens.css`, `src/ui/useGlobalShortcuts.ts`, `src/keyboard/pcInput.ts` (NoteFall) | Design system, token màu/typo/bo góc, phím tắt toàn cục, mapping phím đàn |
| https://www.artmaster.com/articles/what-piano-apps-actually-cost-in-2026 · https://www.pianostartguide.com/best-piano-learning-apps/ · https://cooperpiano.com/best-piano-apps-adults/ · https://www.masterpiano.com/simply-piano-review | Giá & mô hình subscription 2026 |
| https://ffmpeg-cookbook.com/en/articles/youtube-ffmpeg-settings/ · https://www.kometmedia.com/tutorials/youtube-video-format-and-spec-guide · https://compresto.app/blog/best-video-format-for-youtube · https://audioutils.com/guide/audio-for-youtube-creators · https://www.yttowav.org/blogs/youtube-audio-quality/ | Thông số YouTube: bitrate theo res/fps, −14 LUFS, −1 dBTP, AAC-LC 48 kHz |
| https://www.modartt.com/user_manual?product=pianoteq · https://www.soundonsound.com/reviews/modartt-pianoteq-4 · https://modwheel.net/reviews/modartt-pianoteq-8-review · https://www.kvraudio.com/forum/viewtopic.php?p=9269527 | Modeling vs sampling: 127 mức velocity, sympathetic resonance, half-pedal, mic, release tail |
| https://github.com/astraedus/piano/blob/main/docs/research/motor-learning.md · https://fundamentals-of-piano-practice.readthedocs.io/ · https://corinneplayspiano.com/the-complete-guide-to-piano-practice-for-adult-learners/ | Deliberate practice, chunking, spacing, tempo ladder, tay riêng |
| https://vntre.vn/... · https://mcma.training/nhac-ly-la-gi-hoc-nhac-ly-de-lam-gi/ · https://pianoductri.com/blog/nhac-ly-piano/ | Thuật ngữ nhạc lý tiếng Việt |
| https://crescendopiano.app/support/accessibility-features · https://www.applevis.com/apps/ios/education/flowkey-learn-piano · https://pianoeducationjournal.org/accessibility.html | Mẫu accessibility cho app nhạc: high contrast, screen reader, touch target 48dp, keyboard nav |

| https://fencode.dev/en/blog/vercel-free-vs-pro-2026-official-limits-pricing · https://shipai.today/vibe-coding/vercel-pricing · https://xiaozha.org/en/article/vercel-vs-cloudflare/ | **Giới hạn Vercel Hobby 2026**: 100 GB băng thông/tháng, 1M edge request, 1M function invocation, 4 CPU-giờ, 1 GB Blob, **chỉ phi thương mại**; vượt → **tạm dừng deploy**; Pro $20/seat, 1 TB, $0.15/GB vượt |
| https://developers.cloudflare.com/pages/platform/limits/ (qua bài tổng hợp) · https://www.cloudflare.com/developer-platform/r2/ | Cloudflare Pages: **băng thông không giới hạn**, **20.000 file/site**, **25 MiB/file**, 500 build/tháng, 100k function request/ngày; **R2 egress $0**, 10 GB lưu trữ miễn phí, $0.015/GB-tháng |
| https://pianoranked.com/sustain-pedals/ · https://pract.is/blog/best-sustain-pedals-digital-piano-2026 · https://www.roland.com/global/products/dp-10/ · https://forum.pianoworld.com/ubbthreads.php/topics/3057332/new-piano-sustain-pedal-question.html | Pedal: **M-Audio SP-2** = công tắc + có nút đảo cực (dùng được mọi hãng); **Yamaha FC3A** = biến trở liên tục, **không** có nút đảo cực, dành riêng Yamaha; **Roland DP-10** = liên tục **hoặc** công tắc; **Korg DS-1H** liên tục, cực âm cố định; FC3A và DP-10 **không đấu dây giống nhau** → half-pedal phụ thuộc host |

| https://github.com/AThevon/basic-pitch-rs · https://huggingface.co/ericfithian/piano-duet-recording-transcription-onnx · https://github.com/FabienCouprie/attic/pull/309 | **Transcription trong browser có số đo thật**: basic-pitch-rs module WASM **2.3 MB gzip**, 1 cửa sổ 2 s = 31 ms (tract) / 9.8 ms (ort), 60 s audio = 0.19–1.15 s, "nhanh gấp ~22× thời gian thực"; Transkun 2.0 ONNX khớp 960/960 onset trong 30 ms trên WASM; **`session.run` chạy trên thread gọi → phải đưa vào Worker** (đóng băng 35 ms → 2–3 ms) |
| https://www.reddit.com/r/webdev/comments/1ldjqa1/ · https://github.com/Larront/grimoire/issues/244 · https://www.testmuai.com/learning-hub/web-audio-api-browser-support/ · https://waveplayer.info/kb/the-audio-is-distorted-in-safari-and-ios/ | **Safari/iOS audio**: context "running nhưng câm" sau khi tab idle (liên quan sample rate lúc tạo context) → suspend khi hidden + kiểm tra bằng `currentTime`; silent switch tắt Web Audio mặc định, `audioSession.type="playback"` (iPadOS 17.5+) bỏ qua nhưng dừng nhạc app khác; **1 phút stereo = ~23 MB** giải mã, tab bị kill >1.5 GB; rè khi resample giữa sample rate file và thiết bị |
| https://qnotepad.com/blog/indexeddb-storage-limits-safari-firefox-chrome · https://github.com/unmango/scm/issues/324 · https://rxdb.info/articles/indexeddb-max-storage-limit.html | **Quota & eviction**: Chrome ~60% đĩa, Firefox 10% (50% với `persist()`), Safari **~1 GB/origin**; **Safari ITP xoá toàn bộ storage script-ghi sau 7 ngày không tương tác** (PWA home-screen được miễn); OPFS `createWritable` có trên Safari từ **26**; quota dùng chung giữa IDB/OPFS/Cache |
| https://github.com/opensheetmusicdisplay/opensheetmusicdisplay (CHANGELOG 2.0→2.3, PR #1786, #1970) | OSMD: 2.0 nhanh 2×, 2.1.2 +40%, 2.3.0 +13% và **bộ nhớ giảm 8–19%**, `clear()` 10 MB thay vì 344 MB; phân bổ thời gian render (vẽ 52%, skyline 12%, …); load() có **22.5% là XML parser của trình duyệt** |
| https://sfzinstruments.github.io/pianos/ · https://simplesoundbank.com/guides/best-free-soundfonts/ · https://www.purgatorycreek.com/index.php/acoustic-piano-collection/ · https://rekkerd.org/ivy-audio-releases-piano-162-sample-library/ | Thư viện piano miễn phí: **Salamander (CC BY 3.0, 394 MB SFZ / 1.27 GB SF2, 16 tầng, 48 kHz)**; **Piano in 162** (Ivy Audio, 4.9 GB, 5 tầng, 2 round robin, pedal up/down — nhưng **cấm đóng gói lại**); **Upright Piano KW CC0 27 MB**; **Splendid Grand Piano (AKAI) PD 77 MB**; **VCSL Keys CC0 680 MB**; Accurate-Salamander 1.6 GB CC-BY |
| https://playmarblemusic.com/blog/where-to-find-free-midi-files · https://musescore.org/en/node/355266 · https://av.tib.eu/media/42235 · https://github.com/Luminous-Dynamics/symthaea/issues/9509 | Nguồn MIDI/sheet & quyền: **Mutopia** (license từng bản), **OpenScore CC0** (chép lại bản PD), **IMSLP** (PD theo nước, không cấp license thay tác giả), MuseScore.com từng bản khác nhau, **GiantMIDI-Piano CC BY 4.0 nhưng MIDI suy ra từ bản thu** → rủi ro; MAESTRO là **CC BY-NC-SA** |

## 12.7. Nhật ký nghiên cứu (chronological)

1. **Khảo sát workspace** — repo `ArenaAIWorkspace-1` chỉ có `README.md`, branch `arena/539934e3-arenaaiworkspace-1`, base `1c07b17`.
2. **Search: NoteFall open source piano game GitHub** → xác định `ekkx/notefall` + các repo cùng tên (Suma-Udd, fonghtdev, austinrsands, jrglee) → tạo "disambiguation" quan trọng.
3. **Search: Perfect Piano features** → thu thập toàn bộ tính năng mobile (bàn phím thông minh, học, multiplayer, USB MIDI).
4. **Search: best piano learning apps 2025/2026** → so sánh Simply Piano/Flowkey/Skoove/Yousician/Piano Marvel/Playground.
5. **Search: virtual piano web app Web Audio API** → nhóm virtual piano web + tính năng chơi tự do.
6. **Search: Synthesia features** → 3 chế độ luyện, chấm điểm 100, labels, keybind, Free Play.
7. **Search: MIDI SMF spec** → cấu trúc file, CC, tempo map, GM drums.
8. **Search: Web Audio piano sampler/Salamander/SF2** → sample library + polyphony/latency.
9. **Search: mic detection apps** → mức độ khó, chi phí, vì sao để P2.
10. **Search: Piano Marvel/Playground/OnlinePianist** → sight-reading SASR, MIDI-only, thư viện.
11. **Search: MusicXML/VexFlow/OSMD** → sheet music trong browser.
12. **Search: Web MIDI + Tone.js/smplr latency** → số liệu latency, browser support.
13. **`fetch_page` github.com/ekkx/notefall** → README, cấu trúc repo, commit mới nhất.
14. **`curl` raw.githubusercontent.com** → **thất bại (rỗng)** → chuyển sang `git clone`.
15. **`git clone` ekkx/notefall** → đọc LICENSE (PolyForm Shield), package.json, CLAUDE.md (kiến trúc chi tiết), `store.ts` (Settings + defaultSettings ~300 key), `midi/types.ts`, `audio/engine.ts` (public API), `audio/clock.ts`, `audio/playback.ts`, danh sách 201 file `src/`.
16. **Search: SeeMusic/Embers/PianoViz + open source visualizers** → bổ sung nhóm "piano video maker" (SeeMusic, PianoViz, Embers, LumaKeys, Neothesia, Piano From Above, Pianotify, worldwiderad/pianoroll, pirozhki, WebGL-Piano MIT).
17. **Search: Neothesia license/features** → GPL-3.0, Rust workspace, ffmpeg encoder, free-play recording.
18. **Viết bộ tài liệu** `research-piano/00–12` (file này là cuối cùng).
19. **Kiểm tra lại** toàn bộ file, đối chiếu chéo số liệu (đặc biệt license, giá, browser support).

### Đợt 2 — nghiên cứu tiếp (cùng ngày, theo yêu cầu "nghiên cứu tiếp")

20. **`api.github.com` cho 11 repo** → phát hiện: `ekkx/notefall` = NOASSERTION (PolyForm Shield), `Neothesia` = GPL-3.0, `soundfont-player` = MIT, `OSMD` = BSD-3, và **nhiều repo không có license** (WebGL-Piano, pianoroll, MIDIano, piano-app, pirozhki) → viết lại đánh giá pháp lý (file 14.2), **đính chính** file 06 (trước đó ghi WebGL-Piano là MIT).
21. **`registry.npmjs.org` cho 20+ package** → bảng version/license/size; phát hiện `mediabunny` = MPL-2.0, `lamejs` = LGPL-3.0, `postprocessing` = Zlib, `react-aria-components` = Apache-2.0, `@spotify/basic-pitch` = Apache-2.0, `onnxruntime-web` = 147 MB unpacked, R3F 9 cần React 19 → file 14.1.
22. **Đọc sâu source NoteFall lần 2**: lập bản đồ 201 file + số dòng từng module + export của từng module + luồng dữ liệu + 3 event bus (`addKeyListener`, `addLiveListener`, `currentSongTime`) → **file 15**.
23. **Đọc `scripts/fetch-salamander.sh` + `prepare-salamander.mjs`** → chốt: 30 phím × 16 layer = **480 OGG ~77 MB**, tên `<note>v<layer>.ogg` (`#`→`s`), CDN `samples.notefall.app` **CORS khoá theo notefall.app**, dev proxy `/samples-cdn`; các sample `rel*`/`harm*`/`pedal*` bị bỏ → file 14.4 + 15.6.
24. **Đọc codec/preflight của NoteFall** (`VIDEO_CODECS`, `pickCodecString`, `assertEncodersSupported`) → đối chiếu với bảng support thật của WebCodecs → file 17.2.
25. **Clone + đọc `IbrahimKhan25/piano-app`**: wait mode 266 dòng trên cursor OSMD (bẫy: halfTone+12, tie, cursor tạo lại, notehead SVG), fingering DP 204 dòng (Parncutt-style cost, mirror tay trái, fixed fingers) → **mô tả lại bằng lời + pseudocode tự viết** trong file 16.
26. **Đọc `MIDIano`**: `MicInputHandler` = autocorrelation đơn âm @8kHz → xác nhận mic detection đa âm cần ML; cấu trúc render tách lớp (PianoRender/NoteRender/SustainRenderer/MeasureLines…) → file 16.8 + 06.
27. **Kiển chứng support trình duyệt**: caniuse Web MIDI + 2 nguồn WebCodecs + blog midee/epiano → **đính chính** file 08 (Safari không có Web MIDI; Firefox 108+; WebCodecs Safari 26+; MP3 encode không có) và viết **file 17** + phát hiện **Tauri mất Web MIDI trên macOS/Linux**.
28. **Viết file 18 (ADR)**: 15 quyết định cần chốt trước khi code.
29. **Đọc `docs/design-system.md` + `ui/CLAUDE.md` + `tokens.css` + `useGlobalShortcuts.ts` + `pcInput.ts`** trong bản clone (tài liệu do chính tác giả NoteFall viết) → trích ra nguyên tắc thiết kế, token thật, bảng phím tắt, mapping phím đàn, 10 cạm bẫy UI/UX → **file 20**.
30. **Search giá & mô hình kinh doanh 2026** (ArtMaster, PianoStartGuide, Cooper Piano, MasterPiano, SeeMusic, Synthesia) → bảng giá, 5 nhóm thị trường, khoảng trống, kênh tăng trưởng, ghi chú thị trường VN → **file 21**.
31. **Search export/YouTube 2026** (ffmpeg-cookbook, KometMedia, Compresto, AudioUtils, YTtoWAV) → bitrate theo độ phân giải, **−14 LUFS**, −1 dBTP, AAC-LC 48 kHz, yuv420p → **file 23**.
32. **Search piano sound** (Pianoteq manual/SOS/review, KVR) → 16 velocity layer vs 127 mức liên tục, sympathetic resonance thật vs xấp xỉ, half-pedal, mic positions, release samples → **file 22**.
33. **Search motor learning** (repo `astraedus/piano` tổng hợp nghiên cứu, Fundamentals of Piano Practice của Chuan C. Chang, bài về adult learners) → deliberate practice 4 điều kiện, chunking, spacing d≈0.54, tempo ladder +5 BPM, tay riêng, mental rehearsal, gamification đúng/sai → **file 24**.
34. **Search thuật ngữ nhạc lý Việt** (vntre, mcma, pianoductri, tài liệu lý thuyết âm nhạc) → bảng thuật ngữ chuẩn (phách, ô nhịp, hóa biểu, khóa Sol/Fa, Đô trưởng…) → **file 25**.
35. **Kiểm tra font**: `registry.npmjs.org/@fontsource-variable/geist` → subsets có **vietnamese** → không cần đổi font, chỉ import đúng subset.
36. **Rà ca biên MIDI** (từ mã nguồn NoteFall + WebGL-Piano README + kinh nghiệm black MIDI): tempo map, note-on velocity 0, note treo, overlap, drum channel, pedal trung gian, tên track CJK, file 1M note → **file 19** + bộ 12 file test + tiêu chí round-trip.

37. **Search hosting & CDN** (fencode, shipai, xiaozha, guptadeepak, medium) → giới hạn Vercel Hobby 100 GB/tháng + **cấm thương mại**; Cloudflare Pages băng thông không giới hạn nhưng 20k file/25 MiB mỗi file; **R2 egress $0** → tính ra: 1.000 người dùng × 77 MB sample ≈ 77 GB → phải đặt sample ngoài Vercel → **file 26**.
38. **Search pedal USB MIDI** (pianoranked, pract.is, roland, pianoworld) → FC3A/DP-10/DS-1H là biến trở liên tục và **không tương thích chéo**; SP-2 là công tắc có đảo cực → app phải nhận CC64 **0–127** đầy đủ (NoteFall đã fade theo độ sâu pedal) → **file 22.4 + 26**.
39. **Viết file 27 (bảo mật/quyền riêng tư)**: mô hình mối đe doạ, giới hạn zip/MIDI cụ thể, CSP mẫu, bản đồ dữ liệu "cái gì rời khỏi máy", license compliance, checklist publish.
40. **Viết file 28 (test & CI)**: kim tự tháp test, mock `requestMIDIAccess`, `OfflineAudioContext` snapshot, 10 kịch bản Playwright, workflow GitHub Actions, quality gates, bộ fixture.
41. **Viết file 29 (backlog 6 tuần)** và **file 30 (tổng kết)**: cắt Sprint 0–5 (~30 ngày công), ma trận tính năng hợp nhất, 10 ADR, 10 con số phải nhớ, 7 rủi ro xếp hạng, việc còn lại + câu hỏi chặn code.

42. **Search transcription trong browser** (basic-pitch-rs, Transkun ONNX, PR worker offload) → xác nhận **chạy được 100% local**, có số đo thời gian thật, và bẫy `session.run` chặn thread → **file 31**.
43. **Search iOS/Safari Web Audio** (Reddit, issue iPad audio, testmu, WavePlayer KB) → 4 hành vi nghiêm trọng: context câm sau idle, silent switch, resample rè, bộ nhớ 23 MB/phút → **file 36**.
44. **Search storage quota/eviction** (qnotepad, unmango, rxdb) → **Safari ~1 GB + ITP xoá 7 ngày**, OPFS có từ Safari 26 → quyết định thiết kế autosave 3 lớp + nhắc xuất file → **file 33**.
45. **Search OSMD hiệu năng** (CHANGELOG 2.0–2.3, PR #1786/#1970) → số liệu render/bộ nhớ + chiến lược "MusicXML → MIDI nội bộ, sheet chỉ là lớp hiển thị" → **file 32**.
46. **Search thư viện piano miễn phí** (sfzinstruments, simplesoundbank, purgatorycreek, rekkerd) → thêm phương án nhẹ: **Upright Piano KW CC0 27 MB**, **Splendid Grand PD 77 MB**, VCSL CC0; lưu ý **Piano in 162 cấm đóng gói lại**, Salamander có nơi ghi BY-SA → **file 35.7 + 22**.
47. **Search nguồn MIDI & bản quyền** (playmarblemusic, MuseScore forum, OpenScore, registry nghiên cứu) → 4 lớp quyền, GiantMIDI-Piano rủi ro, MAESTRO NC → **file 35**.
48. **Viết file 31–36** và index vào `00-README`, `README`, `09` (A6), `12`, `11`.

49. **Viết file 37 (piano roll)**: chốt dùng **tick + tempo map** thay vì giây, command pattern có diff, 30 ca test, bảng tương tác đầy đủ.
50. **Viết file 38 (onboarding)**: đường đi 30 giây, 3 nhóm người dùng, playability gate, cơ chế giữ chân lành mạnh, thông điệp lỗi tiếng Việt.
51. **Viết file 39 (thị trường VN)**: định vị một câu, 6 kênh theo thứ tự, giá (miễn phí + Pro một lần 200–400k), kế hoạch 8 tuần, chỉ số không cần backend.
52. **Viết file 40 (chế sample)**: 3 phương án (77 MB / 20–25 MB Opus / 10–27 MB bộ nhẹ), công thức cắt 30 phím × N tầng, quy trình script, cách đánh giá (null test + nghe mù).

53. **Đổi góc nhìn: tài liệu này để AI đọc và clone app**, không phải cho người tự code → rà lại toàn bộ 41 file dưới góc nhìn "máy thi hành".
54. **Viết `41` (giao thức AI)**: 12 luật bắt buộc, thứ tự đọc theo 10 nhiệm vụ, thứ quyền 5 cấp, nhãn CHỐT/ĐỀ XUẤT/CHƯA QUYẾT/CẤM, 10 tiêu chí "xong" ở cấp sản phẩm, cách chống context rot, mẫu câu lệnh giao việc.
55. **Viết `43` (design system chốt)**: palette + typography (line-height ≥1.35 cho tiếng Việt) + spacing 4px + radius + blur 36 + motion + z-index + **13 component** kèm trạng thái + checklist "đẹp".
56. **Viết `42` (đặc tả màn hình)**: S0–S11, mỗi màn có bố cục ASCII, thành phần, bảng trạng thái, chuỗi tiếng Việt nguyên văn, tương tác, nghiệm thu.
57. **Viết `44` (hợp đồng dữ liệu)**: `ParsedSong` (tick-based), `Settings` 9 nhóm, `ProjectManifest`, `AudioEngine` API, cây thư mục + luật phụ thuộc, Command/undo, worker protocol, i18n, 8 bất biến.
58. **Viết `45` (build brief)**: M0–M6 (~24 ngày) với tiêu chí xong từng mốc, cổng chất lượng, 10 điều cấm, định nghĩa "clone đủ tính năng".
59. **Tạo `spec/design-tokens.json` + `spec/app-spec.json`** (34 tính năng có ID/milestone/priority).
60. **Tạo `AI-START-HERE.md`** — bản rút gọn ~90 dòng để AI mở phiên mới không cần đọc cả bộ (chống context rot).
61. **Viết `46` (audit)**: 15 mâu thuẫn đã xử lý (C1–C15), 7 câu chưa chốt (D1–D7), 10 khoảng trống (G1–G10), 8 chỗ AI dễ hiểu sai.

## 12.8. Điều chưa kiểm chứng / cần làm rõ sau

- Số lượng timbre chính xác của Perfect Piano thay đổi theo phiên bản/nền tảng (các nguồn ghi 9–19). Ghi "9+ và plugin".
- Giá các app subscription thay đổi thường xuyên — số trong file 05 là tham khảo.
- Chưa cài thử SeeMusic/PianoViz (chỉ đọc mô tả chính thức + review) → tính năng chi tiết có thể thiếu.
- Chưa kiểm chứng NoteFall trên Safari/Firefox thực tế (chỉ đọc code fallback).
- Chưa đo latency thực trên máy người dùng — cần làm khi build (giai đoạn 1.1).
- `WebCodecs`/AV1 support khác nhau theo GPU/OS — cần probe khi build.
- ~~Chưa xác nhận license của `worldwiderad/pianoroll` và `pirozhki/piano-visualizer-classic`~~ → **đã kiểm tra (14/11)**: **không có file LICENSE** ở cả hai (và ở MIDIano, piano-app). Coi như không dùng được code.
- `WebGL-Piano` README nói MIT nhưng **không có LICENSE file** → cần xác nhận trực tiếp tác giả nếu muốn dùng.
- Chưa đo latency thực tế trên máy người dùng; chưa test NoteFall/Wait-mode prototype trên Safari/Firefox thật.
- Chưa kiểm tra license của GeneralUser GS / FluidR3_GM / MIDI.js soundfonts ở mức file (chỉ biết là "free/kèm điều kiện") → đọc LICENSE trong bản tải trước khi đóng gói.
- Chưa thử `@spotify/basic-pitch` trên trình duyệt (chất lượng, thời gian xử lý, bộ nhớ).
- Chưa kiểm chứng giới hạn kích thước file tĩnh của Vercel cho bộ 480 sample (cần thử khi deploy thật).

## 12.9. Cách cập nhật bộ tài liệu này

- Tính năng mới phát hiện → thêm vào file tương ứng + cập nhật ma trận file 07 + checklist file 09.
- Quyết định kiến trúc mới → file 10 + ghi ADR.
- Nguồn mới → file 12 với ngày truy cập.
- Khi bắt đầu build: tạo thư mục `docs/build-log/` ghi tiến độ theo tuần, tách khỏi `research-piano/` (nghiên cứu đóng băng làm tham chiếu).
