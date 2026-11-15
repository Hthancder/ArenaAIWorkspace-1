# 41 — Cách AI đọc bộ tài liệu này (giao thức thi hành)

> **Đối tượng chính của bộ tài liệu là MÁY, không phải người.** Mục đích: một AI coding agent đọc đủ để **clone ra app piano hoàn chỉnh, đẹp, đủ tính năng** — không phải để người tự triển khai.
> File này là **hợp đồng đọc**. Đọc hết file này trước, rồi mới mở file khác.

## 41.1. Luật thi hành (bắt buộc, không thương lượng)

1. **Không bịa dữ kiện.** Mọi con số (màu, px, bitrate, giới hạn, công thức) phải lấy từ tài liệu. Nếu thiếu → ghi `// TODO(spec): <câu hỏi>` trong code, **không tự chọn** giá trị rồi coi là đúng.
2. **Không đổi tên khái niệm.** Dùng đúng tên trong `44` (`ParsedSong`, `NoteEvent`, `PedalEvent`, `Settings`, `TrackInfo`…). Không tạo type song song.
3. **Token trước, style sau.** Mọi màu/khoảng cách/bo góc/typography lấy từ `spec/design-tokens.json` + `43`. Cấm viết mã màu rời rạc trong component.
4. **Một nguồn sự thật.** Nốt nhạc nằm trong MIDI (tick + tempo map). Sheet/nốt rơi/HUD chỉ là **view** của cùng dữ liệu.
5. **Không thêm dependency** ngoài danh sách ở `14` + `43` nếu chưa ghi lý do vào `docs/deps.md`.
6. **Không tải tài nguyên từ CDN của NoteFall** (`samples.notefall.app` CORS khoá). Dùng `/public/samples` hoặc CDN riêng.
7. **Không copy code từ repo không có LICENSE** (WebGL-Piano, pianoroll, MIDIano, piano-app) — chỉ lấy ý tưởng.
8. **Không dùng code NoteFall nếu mục tiêu thương mại** (PolyForm Shield). Dùng nó như **bản tham chiếu hành vi**, viết lại theo đặc tả trong bộ này.
9. **Mọi màn hình phải chạy được ở 768 px** chiều rộng, không có "unsupported screen" cứng.
10. **Không có telemetry, không upload file.** Nếu cần đo, đo local và hiển thị cho người dùng.
11. **Bàn giao kèm test**: mỗi module có test theo `28`; UI có ít nhất 1 test Playwright cho luồng chính.
12. **Tiếng Việt là ngôn ngữ mặc định của UI**, chuỗi nằm trong `i18n/vi.ts`, không hard-code trong JSX.

## 41.2. Thứ tự đọc theo nhiệm vụ

| Nhiệm vụ của AI | Đọc theo thứ tự | Bỏ qua |
|---|---|---|
| **Dựng khung app** | `44` → `10` → `45` → `43` → `spec/*` | 21, 39 |
| **Làm giao diện/thiết kế** | `43` → `42` → `20` → `38` → `25` | 22, 23, 31, 32 |
| **Làm engine âm thanh** | `22` → `34` → `40` → `36` → `15.6` | 21, 39 |
| **Làm MIDI parse/export/edit** | `19` → `44` → `37` → `33` | 21, 39 |
| **Làm luyện tập/chấm điểm** | `16` → `24` → `13` | 21, 39 |
| **Làm export video** | `23` → `17` → `36` | 24, 31 |
| **Làm tính năng transcription** | `31` → `34` → `27` | 23, 39 |
| **Làm sheet nhạc** | `32` → `43` | 31, 40 |
| **Chuẩn bị phát hành** | `26` → `27` → `28` → `35` | 31, 32 |
| **Cần hiểu vì sao chọn vậy** | `30` → `18` → `02` | — |

## 41.3. Thẩm quyền khi tài liệu mâu thuẫn

Cao → thấp:

1. **`spec/*.json` và `44`** (hợp đồng máy đọc được, đã chuẩn hoá).
2. **File đặc tả theo chủ đề**: `42` (màn hình), `43` (thiết kế), `37` (editor), `33` (định dạng file), `16` (chấm điểm), `19` (MIDI).
3. **Tài liệu kỹ thuật nền**: `08`, `10`, `17`, `22`, `26`, `27`, `28`, `34`, `36`.
4. **Khảo sát đối thủ**: `02`–`07`, `15`, `21`.
5. **Ý kiến/đề xuất**: `09`, `11`, `29`, `30`, `38`, `39`, `40`.

Khi mâu thuẫn: **theo mức cao hơn**, và ghi lại vào `46` (audit) một dòng `CONFLICT: <mô tả> → <quyết định>`.

## 41.4. Nhãn trạng thái trong tài liệu

| Nhãn | Nghĩa | AI nên làm gì |
|---|---|---|
| **CHỐT** | Đã quyết, không đổi | Làm đúng |
| **ĐỀ XUẤT** | Khuyến nghị mạnh | Làm theo, trừ khi có lý do ghi lại |
| **TÙY CHỌN** | Có thể bỏ | Bỏ nếu không đủ thời gian |
| **CHƯA QUYẾT** | Cần người dùng chốt | **Không tự quyết**; dùng mặc định an toàn + TODO |
| **CẤM** | Không được làm | Tuyệt đối tránh |

Các mục "CHƯA QUYẾT" hiện tại (xem `30.6`, `46`): fork NoteFall hay tự dựng; có thương mại hay không; mobile trong v1; video export trong v1.

**Quy tắc khi gặp CHƯA QUYẾT:** chọn phương án **không khoá đường** (ví dụ: kiến trúc module hoá để sau này thay engine; không import code NoteFall) và ghi `TODO(decision)`.

## 41.5. Ba thứ AI phải "chép nguyên văn"

1. **Chuỗi UI tiếng Việt** trong `42` và `20.7` — không dịch lại, không "cải thiện" văn phong.
2. **Giá trị token** trong `spec/design-tokens.json` — không làm tròn, không đổi sang màu khác.
3. **Công thức** trong `16` (chấm điểm), `19` (parse MIDI), `22` (pedal/half-pedal), `33` (manifest `.nfz`).

## 41.6. Ba thứ AI phải "dịch sang code", không chép

- ASCII layout trong `42` → component tree + CSS grid/flex thật.
- Bảng "thông số tùy chỉnh" trong `09` Phần B → `Settings` type + panel schema.
- Mô tả hành vi ("mờ dần sau vài giây") → state machine có thời gian cụ thể.

## 41.7. Định nghĩa "xong" ở cấp sản phẩm (để AI tự kiểm)

Một bản build được coi là **đạt** khi tất cả đúng:

| # | Điều kiện | Cách kiểm |
|---|---|---|
| 1 | Mở app → bấm phím → nghe tiếng đàn trong **< 15 s** trên mạng 4G | Đo thủ công/Playwright với cache lạnh |
| 2 | Mở 12 file MIDI trong `19.6` không lỗi, không treo > 1 s | Test tự động |
| 3 | Phát 2.000 nốt @1080p ≥ **55 fps** | Benchmark trong CI (hoặc ghi nhận máy thật) |
| 4 | Chỉnh 10 thông số bất kỳ trong `09` Phần B đều có hiệu lực ngay và lưu vào `.nfz` | Test Playwright |
| 5 | Sửa nốt → undo 100 bước → export MIDI → nhập lại: dữ liệu bằng nhau | Test round-trip |
| 6 | Xuất WAV nghe đúng, không clip; xuất video 720p mở được | Kiểm bằng ffprobe |
| 7 | Không có request mạng nào ngoài CDN sample (DevTools) | Kiểm thủ công |
| 8 | Toàn bộ UI tiếng Việt có dấu, không trànlayout ở 768 px | Ảnh chụp + test |
| 9 | Lighthouse Accessibility ≥ 95, 0 lỗi axe serious | CI |
| 10 | Tất cả màn hình trong `42` tồn tại và đúng trạng thái rỗng | Checklist |

## 41.8. Cách AI nên làm việc với bộ tài liệu (quy trình)

```
1. Đọc 41 (file này) + 45 (brief) + spec/*
2. Chọn milestone M0..M6 trong 45
3. Với mỗi milestone: đọc file chủ đề tương ứng ở 41.2
4. Viết code + test; chạy quality gates (45.6)
5. Nếu gặp điều tài liệu không nói: TODO(spec) + ghi vào 46
6. Không mở rộng phạm vi ngoài milestone đang làm
7. Kết thúc milestone: tự kiểm 41.7 (phần liên quan) rồi mới sang milestone sau
```

## 41.9. Những gì bộ tài liệu **không** cung cấp (AI phải tự tạo)

- Toàn bộ **code** (đây là đặc tả, không phải repo).
- **Asset hình ảnh** (logo, icon): dùng bộ icon có license (Lucide, MIT) hoặc vẽ SVG đơn giản theo `43.9`.
- **Sample âm thanh**: tải theo `40` (script), hoặc dùng file giả 1–2 cái khi dev.
- **Nội dung bài demo**: 3 bản tự soạn/PD (AI có thể tạo MIDI đơn giản bằng script).
- **Tên app/domain**: chưa chốt — dùng tên tạm `piano-app` trong code, hiển thị "Piano" trong UI.

## 41.10. Chống "trôi" (context rot) khi AI làm việc dài

- **Chia việc theo milestone**, mỗi milestone đọc lại đúng file của nó (không cần nhớ cả bộ).
- **Mọi quyết định mới** ghi vào `docs/decisions.md` (1 dòng/ quyết định) + `46` nếu là mâu thuẫn.
- **Không giữ bộ tài liệu trong prompt**; chỉ giữ: `41`, `45`, file của milestone, `spec/*`.
- Khi bắt đầu phiên mới: đọc `45.2` (trạng thái milestone) để biết đang ở đâu.
- **Commit sau mỗi milestone** với message `feat(M2): ...` để có mốc quay lại.

## 41.11. Câu lệnh mẫu để giao việc cho AI coding

```
Bạn đang xây "piano-app": web app chơi piano 3D, local-first, tiếng Việt.
Đọc theo thứ tự: research-piano/41 → research-piano/45 → research-piano/spec/*
Nhiệm vụ: hoàn thành milestone M2 (xem 45.4).
Ràng buộc: tuân thủ 41.1 (12 luật); token từ spec/design-tokens.json;
không thêm dependency; mọi chuỗi UI lấy từ 42; test theo 28.
Bàn giao: code + test + ảnh chụp 3 màn hình + cập nhật 45.2 (trạng thái).
Nếu thiếu thông tin: ghi TODO(spec) và liệt kê cuối câu trả lời, không tự bịa.
```

## 41.12. Bản đồ file (máy đọc)

| File | Loại | Dùng để |
|---|---|---|
| `spec/design-tokens.json` | JSON | Sinh `tokens.css` / Tailwind config |
| `spec/app-spec.json` | JSON | Danh sách tính năng + ưu tiên + trạng thái |
| `44` | TypeScript | Types, module, luồng dữ liệu (chép sang `src/`) |
| `42` | Đặc tả | Từng màn hình, từng trạng thái, chuỗi UI |
| `43` | Đặc tả | Token, component, chuyển động, icon |
| `45` | Kế hoạch | Milestone + tiêu chí nghiệm thu |
| `46` | Audit | Mâu thuẫn đã xử lý, khoảng trống còn lại |
| `01`–`40` | Tham chiếu | Kiến thức nền theo chủ đề |
