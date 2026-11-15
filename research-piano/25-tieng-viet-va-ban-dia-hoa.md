# 25 — Tiếng Việt & bản địa hoá

> Mục tiêu: app không chỉ "dịch" mà **dùng đúng thuật ngữ nhạc lý Việt**, và không vỡ layout / sai định dạng khi chuyển sang tiếng Việt.
> Đây là lợi thế cạnh tranh thật: không app piano nước ngoài nào làm tử tế (xem file 21).

## 25.1. Thuật ngữ nhạc lý Việt — bảng chuẩn dùng trong app

| English | Tiếng Việt (dùng trong UI) | Ghi chú |
|---|---|---|
| note | **nốt** (nốt nhạc) | "nốt" = note; "phím" = key — **không lẫn** |
| key (piano) | **phím** | "phím đàn", "phím trắng/đen" |
| pitch | **cao độ** | |
| octave | **quãng tám** | "Đô4" hoặc "C4" tùy setting |
| duration | **trường độ** | |
| velocity | **lực bấm** / **vận tốc phím** | giữ "(velocity)" trong tooltip |
| dynamics | **cường độ** | pp/ff… |
| timbre / instrument | **âm sắc** / **nhạc cụ** | |
| staff | **khuông nhạc** | |
| treble clef | **khóa Sol** | |
| bass clef | **khóa Fa** | |
| ledger line | **dòng kẻ phụ** | |
| accidental | **dấu hóa** | thăng (#), giáng (♭), hoàn/bình (♮) |
| key signature | **hóa biểu** | |
| time signature | **số chỉ nhịp** | 4/4 đọc "nhịp bốn bốn" |
| measure / bar | **ô nhịp** (tiết nhịp) | "ô nhịp 3" |
| barline | **vạch nhịp** | |
| beat | **phách** | "phách mạnh/nhẹ" |
| tempo / BPM | **nhịp độ** / **BPM** | BPM giữ nguyên |
| metronome | **máy đập nhịp** (metronome) | nhiều người quen "metronome" |
| whole / half / quarter note | **nốt tròn / nốt trắng / nốt đen** | |
| eighth / sixteenth | **nốt móc đơn / nốt móc đôi** | |
| rest | **dấu lặng** | "nốt lặng" cũng gặp, dùng "dấu lặng" |
| dotted | **chấm dôi** | "nốt đen chấm dôi" |
| tie | **dấu nối** | nối 2 nốt cùng cao độ |
| slur | **dấu luyến** | |
| triplet | **liên ba** | |
| interval | **quãng** | quãng 3, quãng 5… |
| semitone / tone | **nửa cung / cung** | |
| chord | **hợp âm** | |
| major / minor | **trưởng / thứ** | "Đô trưởng" (C major) |
| diminished / augmented | **giảm / tăng** | |
| seventh chord | **hợp âm bảy** | |
| key (tonality) | **giọng** | "giọng Đô trưởng" |
| scale | **âm giai** (scale) | "âm giai Đô trưởng" |
| sustain pedal | **pedal giữ âm** (bàn đạp) | |
| soft pedal | **pedal nhẹ** | |
| half pedal | **pedal một nửa** | |
| thumb…little finger | **ngón cái, trỏ, giữa, áp út, út** | số 1–5 |
| hands separately | **luyện từng tay** | "tay trái / tay phải" |
| sight-reading | **đọc nhạc** (thị tấu) | |
| ear training | **cảm âm** | |
| solfège | **xướng âm** | |
| transcribe | **chép nhạc / chuyển thành MIDI** | |
| loop | **lặp** / **vòng lặp** | "lặp đoạn A–B" |
| wait mode | **chế độ chờ** | hoặc "Chờ đúng nốt" |
| score / grade | **chấm điểm** | |
| accuracy | **độ chính xác** | |
| timing | **độ đúng nhịp** | |
| latency | **độ trễ** | |
| soundtrack / backing track | **nhạc đệm** | |
| export | **xuất** (xuất video) | "Xuất" ngắn hơn "Xuất ra tệp" |
| render | **kết xuất** / **xuất** | dùng "xuất" cho người dùng |

## 25.2. Tên nốt: 3 hệ, phải cho chọn

| Hệ | Ví dụ | Ai quen |
|---|---|---|
| **Chữ cái quốc tế** | C4, C#, D… | Người học hiện đại, đọc tài liệu nước ngoài |
| **Solfège cố định (Việt)** | Đô4, Đô thăng, Rê… | Học sinh nhạc viện, người học nhạc lý Việt |
| **Solfège di động (movable do)** | Đô = bậc 1 của giọng hiện tại | Dạy cảm âm, hợp xướng |

**Cách làm:** setting `noteNaming: 'letter' | 'solfege' | 'solfegeMovable'` + `accidental: 'sharp' | 'flat'` + `case: 'C4' | 'c4'`.
Bảng quy đổi cố định (Việt): **C=Đô, D=Rê, E=Mi, F=Fa, G=Sol, A=La, B=Si**; thăng = "thăng", giáng = "giáng" → `C#4` = "Đô thăng 4", `Bb3` = "Si giáng 3".
- Trong nhãn trên phím, dùng dạng ngắn: **Đô, Rê, Mi, Fa, Sol, La, Si** (không kèm số) để không rối.
- Cảnh báo: **không tự đổi "C#" thành "Rê giáng"** — enharmonic phải theo hóa biểu/ngữ cảnh (xem file 16.3 về transpose giữ đúng cách viết).

## 25.3. Font & hiển thị dấu

- **Geist trên Fontsource có subset `vietnamese`** (kiểm tra 14/11/2026: subsets = cyrillic, cyrillic-ext, latin, latin-ext, **vietnamese**). Vì vậy **không cần đổi font** — chỉ cần import subset vietnamese trong CSS:
  ```css
  @import '@fontsource-variable/geist/wght.css';        /* latin */
  @import '@fontsource-variable/geist/wght-vietnamese.css';
  ```
  (hoặc import cả package nếu bundle không thành vấn đề).
- **Line-height**: dấu tiếng Việt xếp tầng (ế, ộ, ữ, ỹ) cần line-height ≥ 1.35 cho heading; nếu không sẽ bị cắt đỉnh dấu. Kiểm tra ở `text-display`, `text-heading`.
- **Uppercase**: `text-transform: uppercase` với "đ" → "Đ" hoạt động đúng, nhưng kiểm tra font; tránh uppercase cho chuỗi dài tiếng Việt (dấu chồng lên nhau).
- **Số & đơn vị**: dùng `Intl.NumberFormat('vi-VN')` → `1.234,5`. Thời gian: `m:ss` giữ nguyên (không dịch). Ngày: `dd/MM/yyyy`.
- **So sánh & sắp xếp**: dùng `Intl.Collator('vi')` để "Đ" xếp sau "D" đúng tiếng Việt.
- **Tìm kiếm không dấu**: chuẩn hoá NFD + bỏ dấu để "do truong" tìm ra "Đô trưởng" — người dùng VN rất hay gõ không dấu.

## 25.4. Câu chữ UI (mẫu)

| Ngữ cảnh | Tiếng Việt | Tránh |
|---|---|---|
| Nút chính | **Chơi** / **Tạm dừng** | "Play/Pause" |
| Mở file | **Mở tệp MIDI** | "Tải lên" (gợi ý upload → sai mô hình) |
| Ghi âm | **Ghi** / **Dừng ghi** | "Record" |
| Lưu | **Lưu** / **Lưu thành…** | "Save as" |
| Xuất | **Xuất video** | "Render" |
| Chế độ chờ | **Chờ đúng nốt** | "Wait Mode" (không có tiếng Việt) |
| Chấm điểm | **Kết quả** · "Đúng 42/50 nốt · 38 nốt đúng nhịp" | "Score: 84%" (không giải thích) |
| Lỗi | "Không mở được tệp này. Hỗ trợ .mid, .midi, .mxl." | "Error 415" |
| Trống | "Kéo tệp MIDI vào đây, hoặc chọn một bài demo." | "No data" |
| Cài đặt | **Tùy chỉnh** (tab) · **Cài đặt** (app) | "Settings" lẫn "Customize" |
| Độ trễ | **Độ trễ ước tính: 18 ms** | "latency: 18ms" |

**Quy ước:** thuật ngữ kỹ thuật quốc tế (MIDI, BPM, WAV, MP4, SoundFont, velocity) **giữ tiếng Anh** nhưng kèm giải thích trong tooltip/trợ giúp. Người dùng VN quen các từ này hơn bản dịch.

## 25.5. i18n kỹ thuật — cạm bẫy cụ thể

| Vấn đề | Chi tiết | Cách xử lý |
|---|---|---|
| Chuỗi tiếng Việt **dài hơn ~30%** | Nút "Xuất video" vs "Export" | Không đặt width cố định cho nút; test ở 320 px panel |
| **Không có số nhiều** | "1 nốt" / "5 nốt" giống nhau | Không cần plural key; nhưng đừng hard-code "notes" |
| Thứ tự từ | "3 nốt" (số trước danh từ) | Dùng placeholder: `{{count}} nốt`, không ghép chuỗi |
| Ghép chuỗi | `"Chơi " + tên bài` sai ngữ pháp trong vài ngữ cảnh | Dùng i18next interpolation đầy đủ câu |
| `lang` | Screen reader cần biết | `<html lang="vi">` + đổi khi chuyển ngôn ngữ (`document.documentElement.lang`) |
| Số thập phân | 1,5 vs 1.5 | `Intl.NumberFormat` cho mọi số hiển thị (trừ giá trị kỹ thuật như "0.5×" nên hiện "0,5×"?) → **chọn 1 quy ước và ghi rõ**: khuyến nghị dùng dấu phẩy cho số thập phân trong UI tiếng Việt |
| Phím tắt | "Shift+R" không dịch | Dịch tên hành động, giữ tên phím |
| Ngày/giờ | `dd/MM/yyyy` | `Intl.DateTimeFormat('vi-VN')` |
| Icon + chữ | Tiếng Việt dài → icon bị đẩy | Ưu tiên icon-only + tooltip ở không gian hẹp |
| Viết hoa tiêu đề | Tiếng Việt **không** viết hoa mọi từ | Chỉ viết hoa chữ đầu câu/thương hiệu |

Cấu trúc i18n của NoteFall đã tốt: `i18n/locales/{en,ja}/{common,dialogs,editor,inspector,screens,timeline,toolbar}.json` — thêm `vi/` với 7 file tương ứng, giữ key y nguyên, chỉ dịch value.

## 25.6. Những chỗ **không** nên dịch

- Tên định dạng: MIDI, WAV, MP4, WebM, SoundFont, MusicXML.
- Tên codec: H.264, VP9, AV1, AAC, Opus.
- Đơn vị: ms, BPM, dB, Hz, px.
- Tên phím: Space, Shift, Ctrl, Cmd, Esc, Tab.
- Tên nốt khi người dùng chọn hệ chữ cái (C, D, Е…).
- Thuật ngữ đã phổ biến: **pedal**, **metronome** (có thể kèm tiếng Việt trong ngoặc lần đầu).

## 25.7. Kế hoạch bản địa hoá (thực dụng)

1. **Tuần 1**: tạo `vi/` với 7 file, dịch toàn bộ string hiện có (khoảng vài trăm key). Giữ `en` làm nguồn.
2. **Tuần 2**: thêm setting chọn hệ tên nốt (letter / solfege / movable) + nhãn phím theo hệ đã chọn.
3. **Tuần 3**: rà layout với chuỗi dài (panel 320–400 px, mobile 360 px), sửa width cứng.
4. **Tuần 4**: kiểm tra screen reader tiếng Việt (NVDA đọc "ô nhịp", "phách" — nếu sai, thêm `aria-label` viết rõ).
5. **Sau**: thêm `en` hoàn chỉnh (nếu muốn chia sẻ quốc tế); `ja` giữ nguyên từ NoteFall nếu không muốn bỏ.

## 25.8. Glossary mở rộng cho trợ giúp trong app (tooltip)

| Thuật ngữ | Giải thích 1 dòng (dùng cho tooltip) |
|---|---|
| Phách | Đơn vị đếm nhịp; nhịp 4/4 có 4 phách mỗi ô nhịp. |
| Ô nhịp | Một đoạn nhạc giữa 2 vạch nhịp. |
| Hóa biểu | Bộ dấu thăng/giáng ở đầu khuông, quy định giọng của bài. |
| Dấu hóa | Ký hiệu thăng/giáng/hoàn đặt trước một nốt. |
| Quãng | Khoảng cách cao độ giữa 2 nốt. |
| Hợp âm | 3 nốt trở lên vang cùng lúc (Đô trưởng = Đô–Mi–Sol). |
| Velocity | Lực bấm phím, 1–127; quyết định độ to và màu âm. |
| Pedal giữ âm | Giữ âm vang sau khi nhả phím. |
| Chế độ chờ | Bài dừng lại cho tới khi bạn bấm đúng nốt. |
| Vòng lặp | Lặp một đoạn để luyện. |
| Đọc nhạc | Chơi bài mới khi chỉ nhìn bản nhạc. |
| Ngón 1–5 | 1 = ngón cái, 5 = ngón út. |
