# 20 — UI/UX, phím tắt và khả năng tiếp cận

> Nguồn chính: `docs/design-system.md`, `src/ui/CLAUDE.md`, `src/ui/kit/tokens.css`, `src/ui/useGlobalShortcuts.ts`, `src/ui/shell/ShortcutSheet.tsx`, `src/keyboard/pcInput.ts` trong bản clone NoteFall — đây là tài liệu **do tác giả viết**, đáng tin hơn mọi bài blog.

## 20.1. Sáu nguyên tắc thiết kế của NoteFall (giữ nguyên khi fork)

1. **"Bức tranh là sản phẩm"** — thứ sáng nhất, nhiều màu nhất trên màn hình phải là nốt nhạc của người dùng. UI **không có màu nhấn** (accent): toàn bộ palette là "ink trên kính".
2. **Nổi, không đóng khung** — canvas chạy full-bleed; control là các mặt kính nổi, không phải panel bao quanh canvas.
3. **Một cách làm cho mỗi việc** — mỗi control ở đúng một chỗ; không restyle riêng từng màn.
4. **Ít panel, theo công việc** — đóng hết thì chỉ còn 2 island trên + 1 pill transport; panel chỉ mở từ toggle.
5. **Chạm vào hình, không chạm vào số** — chỗ nào setting có dạng thị giác (gradient, curve, ảnh, vị trí) thì sửa trực tiếp hình đó; slider là phương án dự phòng.
6. **Chi tiết tạo nên chất lượng** — canh lề, typography, chuyển động, trạng thái.

> Đây cũng chính là câu trả lời cho yêu cầu "tùy chỉnh hầu hết thông số" mà vẫn **không rối**: nhiều thông số nhưng tổ chức theo tab + search + disclosure.

## 20.2. Bố cục (layout) — học theo và mở rộng

```
┌ island bài hát ─────────────┐   island input ──────────────────────┐
│ logo/menu  File  tên ●  ↶ ↷ │   MIDI ▾  ● Record ▾   Export        │
└─────────────────────────────┘   └────────────────────────────────────┘
                    canvas (video letterbox)
                    (start card khi chưa có bài)
┌ Timeline (nổi, tùy chọn) ─────────────────────────┐   ┌ Customize ┐
└───────────────────────────────────────────────────┘   └───────────┘
        ( ⏮ −10s ▶ +10s 🔁  thời gian ──●──  tổng │ 1.0× 🔈 ⬡ ⛶ │ Customize  Timeline )
```

| Bề mặt | Vị trí | Nội dung |
|---|---|---|
| Song island | trên-trái | menu app, File (New/Open/Recent/Demo · Save/Save As · Add audio · Export MIDI · Export), tên bài (sửa tại chỗ, chấm "chưa lưu"), Undo/Redo |
| Input island | trên-phải | chọn thiết bị MIDI, Record + ▾ (takes + count-in), Export (nút primary **duy nhất**) |
| Transport pill | dưới-giữa | về đầu, −10 s, play (đĩa trắng), +10 s, loop, thời gian, scrubber, tổng │ speed, volume, reset camera, fullscreen │ Customize, Timeline |
| Customize | cạnh phải | tab + search + section + footer "Reset to defaults" |
| Timeline | cạnh trái, trên pill | lane MIDI / speed / audio, trim, pin keyframe |
| Selection card | cạnh nốt đang chọn | velocity, tay, ngón, hành động |

**Hành vi chrome (rất đáng giữ):**
- Khi đang phát, island + pill **mờ dần sau vài giây** không di chuột; chuyển động chuột/chạm làm hiện lại. Không mờ khi đang mở menu/popover/dialog.
- Khi trỏ chuột vào Customize, island + pill **né sang một bên** để nhìn rõ hình.
- Fullscreen áp cho **app root** để chrome đi theo.
- **Không xếp kính lên kính**; popover gần đáy phải né pill.
- Trong lúc count-in và đang ghi: mọi bề mặt khác **nhường chỗ** (take focus) — tránh bấm nhầm khi đang thu.
- Dưới ngưỡng rộng tối thiểu → màn hình "unsupported" (NoteFall chặn < 1024 px). **App mới nên hạ xuống 768 px** và có layout hẹp.

## 20.3. Design tokens (giá trị thật, dùng lại được)

| Nhóm | Token | Giá trị |
|---|---|---|
| Nền | `--canvas` | `#05060a` |
| Kính | `--glass-fill` / `--glass-fill-strong` / `--glass-fill-solid` | `rgba(16,17,20,.58)` / `.82` / `#15161a` |
| Viền kính | `--glass-edge` | `rgba(255,255,255,.1)` |
| Chữ | `--ink` / `--ink-muted` / `--ink-faint` / `--on-ink` | `#f3f2ee` / trắng 66% / 44% / `#0e0f11` |
| Fill | `--fill-hover` / `--fill-selected` / `--fill-field` / `--fill-track` / `--fill-well` | trắng 7% / 13% / 7% / 16% / đen 32% |
| Ngữ nghĩa | `--record` / `--danger` / `--scrim` / `--logo-note` | `#ff5a4f` / `#ff8b80` / rgba(5,6,10,.45) / `#5ad7ff` |
| Blur | `--glass-blur` | 36 px, `saturate(1.5)` |
| Shadow | `--shadow-glass` | inset 1px trắng 7% + 0 10px 40px đen 35% |
| Font | `--font-sans` | Geist Variable → Hiragino Sans → Noto Sans JP → system-ui |
| Chữ | display / title / heading / label / body / caption | caption = **sàn 12 px**, không nhỏ hơn |
| Bo góc | round / panel / tab / field | island, pill, nút · panel, card, dialog · tab, chip · field, lane |
| Kích thước | `h-control`, `h-control-sm`, `h-icon-btn`, `h-play`, `h-bar`, `h-pill`, `w-panel`, `w-card`, `touch-min` | dùng theo tên, không viết số |

**Ghi chú tiếng Việt**: font **Geist trên Fontsource có subset `vietnamese`** (kiểm tra 14/11: subsets = cyrillic, cyrillic-ext, latin, latin-ext, **vietnamese**). Chỉ cần import đúng subset CSS là dấu tiếng Việt hiển thị đúng, **không cần đổi font**. Xem file 25.

## 20.4. Phím tắt hiện có của NoteFall

**Toàn cục (mọi trạng thái):**

| Phím | Hành động | Ghi chú kỹ thuật |
|---|---|---|
| `Space` | play/pause | gắn ở **capture phase** để thắng nút react-aria đang focus (Space kích hoạt button) |
| `Shift+R` | bật/tắt ghi âm | dùng Shift vì `R` đã là phím đàn (F4) |
| `Cmd/Ctrl+O` | mở project | capture phase |
| `Cmd/Ctrl+S` | lưu (ghi đè / Save As nếu chưa có file) | |
| `Cmd/Ctrl+Shift+S` | Save As | |
| `Cmd/Ctrl+B` | bật/tắt Timeline | |
| `?` | mở bảng phím tắt | |

**Chế độ sửa** (có bài, đang pause): `Esc` bỏ chọn · `Cmd+Z` undo · `Cmd+Shift+Z` / `Ctrl+Y` redo · `Delete/Backspace` xóa · `↑/↓` dịch thời gian ±0.05 s · `←/→` dịch cao độ ±1 · `Shift+K` đặt keyframe.

**Chuột (trên canvas):** click = thêm nốt · kéo = chọn vùng · kéo cạnh = đổi độ dài · right-click = menu/xóa · `Cmd`+click = thêm vào selection · `Alt`+click = split · `Cmd`+kéo = xoay camera.

**Mapping phím đàn trên bàn phím máy tính** (từ `pcInput.ts`, hiện **cứng**, cần cho remap):

| Hàng | Phím → MIDI |
|---|---|
| Z X C V B N M , . / | 48 50 52 53 55 57 59 60 62 64 (C3…E4) |
| S D G H J L ; | 49 51 54 56 58 61 63 (phím đen) |
| Q W E R T Y U I O P [ ] | 60 62 64 65 67 69 71 72 74 76 77 79 (C4…G5) |
| 2 3 5 6 7 9 0 = | 61 63 66 68 70 73 75 78 (phím đen) |

Lưu ý: `C4` bấm được bằng cả `,` và `Q`; mỗi phím tạo voice riêng. Velocity cố định **0.78** cho phím máy tính — nên cho người dùng chỉnh (hoặc dùng phím số để chọn velocity).

## 20.5. Đề xuất bộ phím tắt cho app mới (3 chế độ)

| Nhóm | Phím | Hành động |
|---|---|---|
| **Chung** | `Space` | play/pause |
| | `Ctrl/Cmd+O` · `Ctrl/Cmd+S` · `Ctrl/Cmd+Shift+S` | mở · lưu · lưu thành |
| | `?` | bảng phím tắt |
| | `F11` / `F` | fullscreen |
| | `Esc` | đóng dialog / bỏ chọn / thoát chế độ |
| **Chơi** | `Z`/`X` | giảm/tăng octave của mapping phím máy tính |
| | `Shift+R` | ghi âm |
| | `L` | bật/tắt loop A–B |
| | `M` | metronome on/off |
| | `1..5` | (khi đang giữ note) không dùng — dành cho fingering |
| | `Ctrl/Cmd+K` | mở metronome/tempo nhanh |
| **Luyện** | `Tab` | chuyển chế độ Wait / Rhythm / Recital |
| | `H` | đổi tay L / R / both |
| | `[` `]` | giảm/tăng tốc độ 5% |
| | `Enter` | nghe mẫu đoạn hiện tại |
| | `,` `.` | lùi/tiến 1 ô nhịp (khi pause) |
| **Sửa** | `Ctrl/Cmd+Z` · `Ctrl/Cmd+Shift+Z` | undo/redo |
| | `Delete` · `Esc` | xóa · bỏ chọn |
| | `←/→` · `↑/↓` | đổi cao độ ±1 · đổi thời gian ±0.05 s |
| | `Alt+click` | split nốt |
| | `Ctrl/Cmd+B` | Timeline |

**Nguyên tắc chọn phím:**
- `Space` luôn là play/pause (chuẩn của mọi app media) — nhưng phải xử lý như NoteFall (capture phase).
- Không dùng phím đang là phím đàn (A–L, Q–P, số) cho shortcut không có modifier.
- `Esc` luôn là "thoát/lùi", không bao giờ là "xóa vĩnh viễn".
- Vùng nhập text phải nuốt shortcut (kiểm tra `input/textarea/contenteditable`, và **loại `input` type=checkbox/range** vì react-aria bọc control trong input ẩn — NoteFall đã gặp lỗi này).
- Cho **remap** toàn bộ, lưu theo preset QWERTY/AZERTY/Dvorak, hiển thị phím trên tooltip.

## 20.6. Onboarding & empty states

**Luồng 3 bước (mục tiêu <60 giây tới nốt đầu tiên):**
1. **Chọn cách chơi**: "Bàn phím máy tính" (mặc định) / "Đàn MIDI" (nếu phát hiện thiết bị) / "Chuột, chạm".
2. **Chơi thử 5 nốt** — hiện phím cần bấm, nghe tiếng ngay (không cần đăng ký, không modal dài).
3. **Mở nhạc hoặc luyện**: kéo file MIDI / chọn demo / bắt đầu bài học đầu tiên.

**Empty state (start card)** cần có: mở file, demo, ghi âm, **"Kéo file MIDI vào đây"**, và 1 dòng giải thích "MIDI là file gì" cho người mới.

**Trạng thái đang tải**: hiện từng việc một (đang tải tiếng đàn / đang chuẩn bị tay ảo) + tiến độ; **app vẫn dùng được** trong lúc tải.

## 20.7. Copy & thông báo lỗi (tiếng Việt)

| Tình huống | Nên viết |
|---|---|
| Thiếu Web MIDI | "Trình duyệt này không hỗ trợ bàn phím MIDI. Bạn vẫn chơi được bằng phím máy tính." |
| Bị từ chối quyền MIDI | "Bạn đã từ chối quyền MIDI. Bấm vào biểu tượng khoá trên thanh địa chỉ để cấp lại." |
| Bluetooth MIDI | "Thiết bị này kết nối Bluetooth — độ trễ cao (60–120 ms), khó chơi đúng nhịp." |
| File không phải MIDI | "File này không phải MIDI. Hỗ trợ .mid, .midi, .mxl." |
| Chưa lưu | "Bạn có thay đổi chưa lưu. Lưu lại trước khi tiếp tục?" (Lưu / Không lưu / Hủy) |
| Take rỗng | "Chưa ghi được nốt nào — bản ghi đã bị bỏ." |
| Lỗi export codec | "Trình duyệt không hỗ trợ codec này. Chọn VP9 (WebM) hoặc giảm độ phân giải." |
| Không có WebGL2 | "Máy không hỗ trợ WebGL2 — đã chuyển sang chế độ hiển thị đơn giản." |

Quy tắc: câu ngắn, chủ động, không đổ lỗi người dùng, luôn có **hành động tiếp theo**. Không dùng `alert()`/`confirm()` của browser (NoteFall đã bỏ hoàn toàn).

## 20.8. Khả năng tiếp cận (accessibility) — mục tiêu WCAG 2.1 AA

| Hạng mục | Yêu cầu | Cách làm trong app piano |
|---|---|---|
| **Bàn phím** | Mọi chức năng làm được không cần chuột | Tab order logic, focus ring rõ (`--ink`), không bẫy focus; canvas có "chế độ bàn phím" điều hướng nốt bằng phím |
| **Screen reader** | Đọc được trạng thái, không cần đọc canvas | `aria-live="polite"` cho: vị trí hiện tại ("ô nhịp 3, phách 2"), kết quả chấm ("đúng 8/10"), thông báo lỗi; nút có label; sheet music có bản text (danh sách nốt của ô nhịp hiện tại) |
| **Màu sắc** | Không dựa **chỉ** vào màu | Đúng/sai phân biệt bằng **hình dạng + icon + độ sáng**, không chỉ đỏ/xanh; có preset cho người mù màu; kiểm tra tương phản ≥4.5:1 cho text |
| **Chuyển động** | Tôn trọng `prefers-reduced-motion` | Tắt particle, bloom, rung, camera tự động; giảm tốc độ animation UI |
| **Nhấp nháy** | Không quá 3 lần/giây | Giới hạn hit flash; cảnh báo nếu người dùng bật hiệu ứng mạnh |
| **Phóng to** | Dùng được ở zoom 200% | Layout co giãn, không cắt nút; `rem` đúng (NoteFall đặt base size trên `body`, không phải `html` — giữ nguyên) |
| **Mục tiêu chạm** | ≥ 48×48 px | `touch-min` token; nút ngón tay (fingering) to |
| **Thời gian** | Không ép thời gian | Wait Mode không giới hạn; cửa sổ chấm điểm có preset "rộng rãi"; tắt chấm timing nếu người dùng muốn |
| **Âm thanh** | Có phản hồi không phụ thuộc âm thanh | Hiển thị trực quan luôn có; không bắt buộc nghe để hiểu trạng thái |
| **Một tay** | Người khuyết tật vận động | Chế độ "một tay": app tự chơi tay còn lại; giảm số phím hiển thị; latency không quan trọng bằng độ chính xác |
| **Ngôn ngữ** | `lang="vi"` đúng, có `lang` đổi khi chuyển | Giúp screen reader phát âm đúng |

**Kiểm thử tối thiểu**: điều hướng toàn app chỉ bằng Tab/Enter/Esc; bật NVDA/VoiceOver đọc 5 màn chính; chạy axe DevTools; thử `prefers-reduced-motion`; thử zoom 200%; thử chế độ mù màu bằng DevTools rendering.

## 20.9. Cạm bẫy UI/UX đã gặp (từ NoteFall + các app khác)

1. **Space bị nút đang focus "ăn"** → phải bắt ở capture phase.
2. **Kiểm tra `input` để bỏ qua shortcut** nhưng quên react-aria bọc switch trong `<input type=checkbox>` → Cmd+Z bị nuốt. Lọc theo **type** của input.
3. **Click phải trên canvas** mặc định mở menu browser → phải `preventDefault` trong canvas, nhưng **giữ menu browser ở ngoài canvas**.
4. **Drag & drop file** chỉ gắn ở một vùng → người dùng thả vào toolbar thì mất file. Gắn `DropZone` cho **toàn layout**.
5. **`DragTypes.has('Files')`** của react-aria **không** phản ánh `dataTransfer.types.includes('Files')` → đừng gate theo nó, hãy lọc MIME khi drop.
6. **Panel mở quá nhiều** → người dùng mất hình. Chỉ 2 panel (Customize, Timeline), còn lại là popover.
7. **Modal chặn lúc tải sample** → người dùng tưởng app treo. Tải nền + vẫn chơi được phần đã sẵn sàng.
8. **Không có trạng thái "đang ghi" rõ** → ghi nhầm. Dùng take focus: mọi thứ khác nhường chỗ, chỉ còn nút Stop đỏ.
9. **Thông báo lỗi chung chung** ("Đã xảy ra lỗi") → luôn nêu nguyên nhân + cách sửa.
10. **Phím tắt không hiện trong tooltip** → người dùng không bao giờ học được. Hiện phím cạnh label.

## 20.10. Lưu ý riêng cho môi trường preview (iframe)

- Web MIDI trong **iframe khác origin** bị chặn trừ khi trang cha gửi `Permissions-Policy: midi=(self "<origin>")`. Khi nhúng app vào preview/iframe, **MIDI có thể không hoạt động dù Chrome hỗ trợ** → luôn có fallback phím máy tính và hiển thị lý do rõ ràng.
- Fullscreen API, clipboard, file system access cũng bị hạn chế trong iframe không có `allow` tương ứng → thiết kế luồng không phụ thuộc các API này.
- Khi tự host: gửi header `Permissions-Policy: midi=(self)` để chắc chắn iframe cùng origin hoạt động.
