# Nghiên cứu app piano trên máy tính / điện thoại — Mục lục

> **ĐỌC MỤC NÀY TRƯỚC NẾU BẠN LÀ AI/MÁY:**
> 1. `AI-START-HERE.md` (2 phút) → `41-cach-ai-doc-bo-tai-lieu-nay.md` (luật thi hành, thứ quyền, chống trôi)
> 2. `45-build-brief-thi-hanh.md` — milestone M0–M6 + tiêu chí nghiệm thu
> 3. `spec/design-tokens.json` + `spec/app-spec.json` — dữ liệu máy đọc
> 4. File chủ đề của milestone đang làm (bảng ở `41.2`)
> Bộ tài liệu này được viết **để AI đọc và clone ra app**, không phải để người tự triển khai.

> Ngày nghiên cứu: 2026-11-14 (UTC). Ngôn ngữ: tiếng Việt.
> Trạng thái: **CHƯA LÀM APP — chỉ nghiên cứu.** Mọi file trong thư mục này là tài liệu để sau này dựa vào đó build app mới.

## Mục tiêu của bộ nghiên cứu này

1. Tìm hiểu **mọi thứ** về các dự án đánh đàn piano bằng máy tính/điện thoại (không cần đàn piano thật).
2. Liệt kê **toàn bộ tính năng** của các app tiêu biểu: Perfect Piano, NoteFall, Synthesia, Simply Piano, Flowkey, Skoove, Yousician, Piano Marvel, Playground Sessions, OnlinePianist, các virtual piano web, các dự án open-source khác.
3. Xác định app nào làm **nền tảng** để "bê nguyên source về, chỉ build tính năng còn thiếu" — kết luận: **NoteFall của ekkx** (xem file 02, kèm cảnh báo giấy phép rất quan trọng).
4. Tạo danh sách tính năng tổng hợp + lộ trình build app mới, ưu tiên **chơi đàn thật sự trên máy tính trước**, MIDI tùy chỉnh tự do, tùy chỉnh hầu hết thông số.

## Cách đọc

| File | Nội dung | Đọc khi |
|---|---|---|
| `00-README.md` | Mục lục này | Bắt đầu ở đây |
| `01-tong-quan-va-pham-vi.md` | Định nghĩa, phân loại app, phạm vi dự án | Hiểu bức tranh lớn |
| `02-notefall-ekkx-deep-dive.md` | NoteFall (ekkx): stack, kiến trúc, tính năng chi tiết, giấy phép, cách bê nguyên source | Quyết định nền tảng |
| `03-perfect-piano-deep-dive.md` | Perfect Piano (Android/iOS): bàn phím thông minh, học chơi, multiplayer, MIDI USB | So sánh với NoteFall |
| `04-synthesia-deep-dive.md` | Synthesia: falling notes, 3 chế độ luyện, điểm số 100, MIDI/MusicXML | Học cơ chế luyện tập |
| `05-cac-app-hoc-piano-khac.md` | Simply Piano, Flowkey, Skoove, Yousician, Piano Marvel, Playground Sessions, Pianote, Hoffman, Artie… | Học curriculum, gamification, mic detection |
| `06-virtual-piano-web-va-open-source-khac.md` | Virtual piano web, Midiano, RoxyPiano, PianoBooster, các dự án GitHub khác | Học tính năng "chơi tự do" + open-source |
| `07-ma-tinh-nang-tong-hop.md` | Ma trận tính năng: app nào có gì | Tra cứu nhanh, tìm tính năng còn thiếu |
| `08-ky-thuat-nen-tang.md` | MIDI SMF, Web MIDI, Web Audio, sampler/SoundFont, latency, sheet music, audio→MIDI | Nền kỹ thuật để build |
| `09-danh-sach-tinh-nang-app-moi.md` | Checklist tính năng app mới (P0/P1/P2) + danh sách thông số tùy chỉnh | Dùng khi bắt đầu code |
| `10-kien-truc-de-xuat-cho-app-moi.md` | Kiến trúc đề xuất: giữ gì của NoteFall, thêm gì, module nào | Thiết kế hệ thống |
| `11-lo-trinh-thuc-hien.md` | Lộ trình theo giai đoạn, thứ tự ưu tiên | Lập kế hoạch |
| `12-nguon-va-lich-su-nghien-cuu.md` | Nguồn tham khảo (URL) + nhật ký nghiên cứu | Kiểm chứng, cập nhật sau |
| `13-kien-thuc-nhac-ly-can-thiet.md` | Nhạc lý/piano tối thiểu để code đúng: cao độ, quãng, hợp âm, scale, nhịp, velocity, pedal, fingering, phương pháp luyện | Khi làm practice/chord/sheet/scoring |
| `14-thu-vien-va-giay-phep.md` | **Ma trận dependency** (version/license/dung lượng) + giấy phép từng repo + tài nguyên âm thanh + checklist pháp lý | Trước khi cài thêm thư viện / publish |
| `15-code-map-notefall.md` | **Bản đồ source NoteFall**: file lớn nhất, export từng module, luồng dữ liệu, "muốn thêm X sửa ở đâu", hằng số toạ độ, checklist sửa khi fork | Ngay khi bắt đầu code |
| `16-practice-engine-chi-tiet.md` | **Thiết kế Wait Mode, chấm điểm, calibration, DP fingering** (pseudocode + công thức + test plan) | Làm P1 — phần khó nhất |
| `17-nen-tang-trinh-duyet-va-phan-phoi.md` | Web MIDI / WebCodecs support thật, latency budget, PWA vs Electron vs Tauri, hosting (Vercel), offline, ngân sách hiệu năng | Chọn nền tảng, deploy |
| `18-quyet-dinh-can-chot.md` | 15 quyết định (ADR) kèm lựa chọn + khuyến nghị + mẫu ghi | Trước khi code dòng đầu tiên |
| `19-midi-ca-bien-va-do-ben.md` | 40+ ca biên của MIDI thực tế + cách xử lý + bộ 12 file test + tiêu chí round-trip | Khi làm parse/export, trước khi test |
| `20-ui-ux-phim-tat-va-tiep-can.md` | Design system NoteFall (token thật), toàn bộ phím tắt + đề xuất bộ phím mới, onboarding, copy lỗi, **accessibility WCAG** | Làm UI / trước khi test với người khác |
| `21-thi-truong-va-doi-thu.md` | Bảng giá đối thủ 2026, 5 nhóm thị trường, khoảng trống, định vị, mô hình kinh doanh, kênh tăng trưởng, rủi ro, thị trường VN | Quyết định sản phẩm |
| `22-am-thanh-nang-cao.md` | Sample vs physical modeling, 9 yếu tố tạo "cảm giác thật", xấp xỉ resonance/release/pedal, reverb, limiter, LUFS, voice stealing, test âm thanh | Khi tinh chỉnh âm thanh |
| `23-san-xuat-video-va-chia-se.md` | Thông số export thật cho YouTube/TikTok/Reels, preset đề xuất, loudness −14 LUFS, checklist trước khi đăng | Làm export / làm nội dung |
| `24-hoc-tap-va-su-pham.md` | Deliberate practice, chunking, spacing, tempo ladder, tay riêng, động lực, template phiên luyện, curriculum 9 level, chống "nghiện nốt rơi" | Thiết kế P1 (practice) |
| `25-tieng-viet-va-ban-dia-hoa.md` | **Thuật ngữ nhạc lý Việt** chuẩn, 3 hệ tên nốt, font/dấu, cạm bẫy i18n, glossary tooltip | Làm i18n / UI tiếng Việt |
| `26-trien-khai-vercel-cdn-pwa.md` | Giới hạn Vercel Hobby/Pro thật, R2 cho sample, header/CSP, PWA + chiến lược service worker, checklist go-live | Khi deploy |
| `27-bao-mat-va-quyen-rieng-tu.md` | Mô hình mối đe doạ (zip bomb, MIDI dị dạng, XSS, supply chain), giới hạn cụ thể, CSP, bản đồ dữ liệu, license compliance | Trước khi publish |
| `28-kiem-thu-va-ci.md` | Kim tự tháp test cho app piano, mock Web MIDI/audio, determinism, 10 kịch bản Playwright, workflow CI, quality gates | Ngay từ Sprint 0 |
| `29-backlog-va-ke-hoach-6-tuan.md` | **Backlog cắt nhỏ theo sprint** (S0–S5, ~30 ngày công), thứ tự ưu tiên, Definition of Done, checklist dễ bỏ sót | Khi bắt đầu code |
| `30-tong-ket-va-quyet-dinh.md` | **Bản đồ toàn bộ nghiên cứu**: bảng sản phẩm, ma trận tính năng hợp nhất, 10 ADR, 10 con số, rủi ro, việc còn lại, thuật ngữ, sơ đồ đọc | Đọc đầu tiên, sau `01` |
| `31-am-thanh-sang-midi-transcription.md` | Âm thanh → MIDI trong browser: Basic Pitch/basic-pitch-rs/Transkun (số đo thật), bẫy worker, kiến trúc route `/transcribe`, chất lượng kỳ vọng, UI sửa kết quả | Làm tính năng v2 |
| `32-sheet-nhac-musicxml-omr.md` | MusicXML/MXL, OSMD 2.3 số liệu hiệu năng/bộ nhớ, chiến lược sheet + nốt rơi một nguồn, OMR (không khả thi), bản quyền bản khắc | Làm chế độ sheet |
| `33-luu-tru-va-dinh-dang-project.md` | **Đặc tả `.nfz` v1** (manifest JSON), quota/eviction từng trình duyệt, ITP 7 ngày của Safari, autosave 3 lớp, migration | Trước khi lưu project |
| `34-hieu-nang-va-toi-uu-render.md` | Ngân sách 16.6 ms/frame, instancing, chi phí giải mã sample (~550 MB nếu giải mã hết), voice stealing, đo lường, cấp đồ hoạ | Khi app bắt đầu giật |
| `35-noi-dung-va-ban-quyen.md` | 4 lớp quyền, bảng nguồn MIDI/sheet (Mutopia, OpenScore, IMSLP, GiantMIDI…), chính sách nội dung, thời hạn bản quyền, checklist pháp lý | Trước khi đóng gói bất kỳ file nhạc nào |
| `36-ios-safari-va-am-thanh.md` | Silent switch, bug context "running nhưng câm", rè khi resample, API thiếu, bộ nhớ iPad, chạm/multi-touch, checklist iOS | Khi hỗ trợ mobile |
| `37-trinh-sua-midi-piano-roll.md` | **Đặc tả tương tác piano roll**: bảng hành động, invariants, undo/diff, bộ công cụ, bố cục UI, 30 ca test | Khi làm trình sửa MIDI |
| `38-onboarding-va-giu-chan-nguoi-dung.md` | Đường đi 30 giây tới tiếng đàn đầu tiên, 3 nhóm người dùng, playability gate, streak lành mạnh, thông điệp lỗi | Làm UI/UX lần đầu |
| `39-ra-mat-thi-truong-viet-nam.md` | Thực tế thị trường VN, định vị một câu, 6 kênh, giá, trang giới thiệu, kế hoạch 8 tuần | Trước khi công bố |
| `40-che-tao-bo-sample.md` | **Công thức chế bộ sample**: 3 phương án dung lượng, license nguồn, cắt/nén (77 → 20 MB), script, null test + nghe mù | Khi tự host sample |

## Lớp "máy đọc" (dành riêng cho AI thi hành)

| File | Nội dung | Dùng khi |
|---|---|---|
| `41-cach-ai-doc-bo-tai-lieu-nay.md` | **Giao thức**: 12 luật bắt buộc, thứ tự đọc theo nhiệm vụ, thứ quyền khi mâu thuẫn, nhãn CHỐT/ĐỀ XUẤT/CHƯA QUYẾT, định nghĩa "xong" 10 mục, cách chống context rot | Mở đầu mọi phiên |
| `42-dac-ta-giao-dien-tung-man-hinh.md` | **S0–S11**: bố cục ASCII, thành phần, trạng thái, chuỗi tiếng Việt nguyên văn, tương tác, nghiệm thu | Làm UI |
| `43-he-thong-thiet-ke-chi-tiet.md` | **Chốt token** (màu/typo/spacing/radius/blur/motion/z), 13 component với trạng thái, bố cục, icon, checklist "đẹp" | Làm UI, review |
| `44-hop-dong-du-lieu-va-kien-truc-module.md` | **TypeScript contracts** (`ParsedSong`, `NoteEvent`, `Settings`, `ProjectManifest`, `AudioEngine`), cây thư mục, luật phụ thuộc, command/undo, worker protocol, i18n, 8 bất biến | Ngay khi tạo `src/` |
| `45-build-brief-thi-hanh.md` | **Milestone M0–M6** (≈24 ngày), việc cần làm + tiêu chí xong từng mốc, cổng chất lượng, 10 điều cấm, mẫu câu lệnh giao việc, định nghĩa "clone đủ tính năng" | Điều phối build |
| `46-audit-nhat-quan-va-khoang-trong.md` | 15 mâu thuẫn đã xử lý (C1–C15), 7 câu chưa chốt (D1–D7), 10 khoảng trống (G1–G10), chỗ dễ hiểu sai | Khi thấy tài liệu "vênh" |
| `spec/design-tokens.json` | Token dạng JSON (màu, space, radius, size, typography, motion, z, breakpoint) | Sinh `tokens.css` |
| `spec/app-spec.json` | 34 tính năng (ID, P0/P1/P2, milestone, docs), screens, quality gates, `neverDo` | Lập kế hoạch/kiểm tiến độ |
| `AI-START-HERE.md` | **Bản rút gọn 2 phút**: sản phẩm, thứ tự đọc, 10 luật, thứ tự build, định nghĩa xong, bảng tra cứu khi bí | Giao việc cho AI / mở phiên mới |

## Lộ trình đọc gợi ý (khi đã có 31 file)

| Bạn muốn gì | Đọc theo thứ tự |
|---|---|
| **Chỉ cần quyết định** | `30` (tổng kết) → `18` (ADR) → `29.11` (5 câu hỏi chặn code) |
| Hiểu đối thủ | `01` → `02`–`06` → `21` → `07` |
| Chuẩn bị code | `10` (kiến trúc) → `15` (code NoteFall) → `29` (backlog) → `28` (test/CI) |
| Làm âm thanh | `22` → `14.4` → `26.2` (host sample) |
| Làm UI/tiếng Việt | `20` → `25` → `24` |
| Phát hành | `26` → `27` → `23` (nếu làm video) |
| Tra cứu nhanh | `12` (nguồn) · `09` Phần B (catalogue ~400 thông số) · `25.7` (glossary) |
| Làm tính năng nâng cao | `31` (audio→MIDI) · `32` (sheet) · `33` (định dạng file) |
| Sửa lỗi hiệu năng / mobile | `34` (hiệu năng) · `36` (iOS/Safari) |
| Làm trình sửa MIDI | `37` (tương tác) · `19` (ca biên) · `15` (code NoteFall) |
| Ra mắt sản phẩm | `38` (onboarding) · `39` (thị trường VN) · `40` (sample) |
| **AI bắt đầu build** | `41` → `45` → `spec/*` → file của milestone |
| **AI làm giao diện** | `43` → `42` → `spec/design-tokens.json` |
| **AI kiểm tra tiến độ/định nghĩa xong** | `41.7` · `45.14` · `spec/app-spec.json` |

## Quy ước trong bộ tài liệu

- **P0** = bắt buộc cho bản đầu tiên (chơi đàn thật trên máy tính).
- **P1** = nên có ngay sau P0 (học/luyện tập, MIDI nâng cao).
- **P2** = mở rộng sau (multiplayer, AI, mobile…).
- "Tùy chỉnh được" = người dùng sửa được qua UI, không cần sửa code.
- Mọi tuyên bố về tính năng đều có nguồn trong file 12. Tính năng của app đóng (Perfect Piano, Simply Piano…) lấy từ trang store / trang chủ / bài review công khai — có thể thay đổi theo phiên bản.

## Kết luận nhanh (đọc 30 giây)

- **Nền tảng chọn: NoteFall (ekkx)** — web app (Vite + React + TypeScript + Three.js), chạy 100% trên trình duyệt, có sẵn: bàn phím 88 phím 3D, falling notes, chơi live bằng chuột/phím máy tính/Web MIDI, ghi MIDI, sửa MIDI ngay trên canvas, export video 4K, timeline keyframe, project `.nfz`, sample Salamander Grand Piano.
- **⚠️ Giấy phép NoteFall là PolyForm Shield 1.0.0 — KHÔNG phải open-source tự do.** Điều khoản Noncompete cấm dùng để làm sản phẩm cạnh tranh. Dùng cá nhân / học tập / nội bộ thì được; muốn công bố app cạnh tranh phải xin phép tác giả hoặc viết lại phần code đó. Chi tiết ở file 02, mục 2.
- **Tính năng còn thiếu so với các app khác** (phải tự build): chế độ luyện tập kiểu Synthesia (Wait Mode, chấm điểm), sheet music (MusicXML/VexFlow/OSMD), curriculum bài học, mic detection cho đàn piano thật, SoundFont `.sf2` tùy chọn, nhiều timbre/instrument, multiplayer, mobile app.
- **Đối thủ mạnh nhất của NoteFall không phải Perfect Piano mà là SeeMusic** (record MIDI+audio+camera, tự align footage, audio→MIDI, MusicXML, chroma color, preset, vertical 4K). Nếu muốn app "hơn tất cả", xem bảng ở file 07 mục 7.5.
- **Giấy phép — phát hiện quan trọng (14/11)**: các repo tưởng là "MIT" như `RenCheng0525/WebGL-Piano`, `worldwiderad/pianoroll`, `Bewelge/MIDIano`, `IbrahimKhan25/piano-app` **đều KHÔNG có file LICENSE** → không được copy code (chỉ học ý tưởng). Repo visualizer duy nhất có license rõ là **Neothesia (GPL-3.0, copyleft mạnh)**. Chi tiết: file 14.2.
- **Hai lỗi kỹ thuật dễ mắc** (file 16.1): (1) sự kiện MIDI **không** được tính là user gesture → AudioContext không tự chạy; (2) chấm điểm phải neo `performance.now()` với `AudioContext.getOutputTimestamp()` rồi trừ offset calibration, nếu không mọi điểm số lệch bằng độ trễ loa.
- **Chi phí hạ tầng thực tế (14/11)**: bộ sample 77 MB/người dùng → 1.000 người dùng ≈ 77 GB, sát mức 100 GB/tháng của Vercel Hobby (và Hobby **cấm thương mại**) → đặt sample trên **Cloudflare R2 (egress $0)** hoặc Cloudflare Pages; app tĩnh giữ trên Vercel nếu phi thương mại — file 26.
- **Ba việc không được để "làm sau"**: test/CI (file 28), bảo mật + giới hạn file người dùng (file 27), và license/Credits (file 27.4). Kế hoạch cắt nhỏ theo sprint ở file 29 (~30 ngày công).
- **Tauri không phù hợp** nếu MIDI là cốt lõi: macOS dùng WKWebView (không có Web MIDI). PWA (Chrome/Edge) hoặc Electron mới đúng — file 17.4.
- **Thị trường**: không app nào kết hợp "miễn phí + local-first + MIDI tự mang + wait mode + 3D đẹp + tùy chỉnh sâu + tiếng Việt". Giá đối thủ $29 một lần (Synthesia) → $120–170/năm (app học) — file 21.
- **Sư phạm**: app phải thưởng cho *chất lượng luyện* (tempo ladder +5 BPM sau 3 lần đạt), không thưởng "điểm danh"; kết thúc phiên bằng thành công; cảnh báo "nghiện nốt rơi" — file 24.
- **Tiếng Việt**: Geist đã có subset `vietnamese` (không cần đổi font); thuật ngữ chuẩn (phách, ô nhịp, hóa biểu, Đô trưởng) đã có bảng ở file 25.
- **Ưu tiên theo yêu cầu:** chơi đàn thật trên máy tính trước → MIDI tùy chỉnh tự do → tùy chỉnh hầu hết thông số → sau đó mới tới học/luyện, mobile, multiplayer.

## Ghi chú về "bê nguyên source NoteFall về"

Theo yêu cầu "CHƯA CẦN LÀM GÌ CẢ, chỉ nghiên cứu", bộ tài liệu này **chưa copy source NoteFall vào repo**. File 02 ghi rõ các bước để bê về khi bắt đầu build (clone, giữ LICENSE, giữ Required Notice, ghi nguồn). Không commit source của bên thứ ba vào repo này nếu chưa rõ quyền sử dụng.
