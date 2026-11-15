# 43 — Hệ thống thiết kế chi tiết (token · component · chuyển động)

> Đây là **nguồn sự thật duy nhất** về giao diện. Bản máy đọc: `spec/design-tokens.json`. Nếu có khác biệt giữa file này và file 20, **file này thắng** (20 là bản khảo sát, 43 là bản chốt).
> Mục tiêu thẩm mỹ: tối, sâu, "kính nổi trên canvas", nốt nhạc là thứ sáng nhất; không accent màu cho UI; chuyển động nhanh và kín.

## 43.1. Nguyên tắc thị giác (áp dụng khi code)

1. **Canvas là sản phẩm.** UI không có màu nhấn. Nút primary = trắng trên nền tối, không xanh/lá.
2. **Kính, không viền.** Bề mặt = `backdrop-filter: blur(36px) saturate(1.5)` + fill tối + viền 1px trắng 10% + inset highlight 1px trắng 7%.
3. **Không lồng kính trong kính.** Popover mở **ra ngoài** panel, không mở panel con bên trong panel.
4. **Chữ là cấu trúc.** Không dùng chữ hoa toàn bộ (trừ nhãn 11 px tracking 0.06em). Số dùng `font-variant-numeric: tabular-nums`.
5. **Một điểm nhấn mỗi màn.** Ví dụ: nút Record đỏ; còn lại trung tính.
6. **Bo góc nhất quán**: control 8, panel 16, dialog 20, pill 999.
7. **Mọi thứ có trạng thái**: hover, active, focus-visible, disabled, loading. Không có control "chết".
8. **Không đổ bóng màu.** Chỉ bóng đen, độ mờ thấp, blur lớn.

## 43.2. Token màu (chốt)

```css
:root {
  /* nền & bề mặt */
  --canvas: #05060a;
  --canvas-raised: #0a0b10;
  --glass-fill: rgba(16,17,20,.58);
  --glass-fill-strong: rgba(16,17,20,.82);
  --glass-fill-solid: #15161a;
  --glass-edge: rgba(255,255,255,.10);
  --glass-highlight: rgba(255,255,255,.07);
  --scrim: rgba(5,6,10,.45);

  /* chữ */
  --ink: #f3f2ee;
  --ink-muted: rgba(255,255,255,.66);
  --ink-faint: rgba(255,255,255,.44);
  --ink-disabled: rgba(255,255,255,.28);
  --on-ink: #0e0f11;

  /* fill tương tác */
  --fill-hover: rgba(255,255,255,.07);
  --fill-active: rgba(255,255,255,.10);
  --fill-selected: rgba(255,255,255,.13);
  --fill-field: rgba(255,255,255,.07);
  --fill-track: rgba(255,255,255,.16);
  --fill-well: rgba(0,0,0,.32);

  /* ngữ nghĩa */
  --record: #ff5a4f;
  --danger: #ff8b80;
  --success: #5ad7a5;
  --warning: #f5c451;
  --logo-note: #5ad7ff;

  /* nốt mặc định (khi không dùng màu theo tay) */
  --note-default: #f3f2ee;
  --note-left: #6aa9ff;
  --note-right: #ffb26a;

  /* focus */
  --focus-ring: #ffffff;
  --focus-width: 2px;
  --focus-offset: 2px;
}
```
**Quy tắc dùng màu ngữ nghĩa:** `--record` chỉ cho trạng thái ghi; `--danger` chỉ cho hành động phá huỷ; không dùng `--logo-note` cho UI (đó là màu logo).

## 43.3. Typography

| Token | Size / line-height / weight | Dùng cho |
|---|---|---|
| `display` | 32 / 1.2 / 600 | Số lớn ở start card ("88 phím") |
| `title` | 22 / 1.3 / 600 | Tiêu đề dialog |
| `heading` | 16 / 1.4 / 600 | Tên section trong panel |
| `label` | 12 / 1.35 / 500 | Nhãn field, tab |
| `label-caps` | 11 / 1.3 / 600 · tracking .06em · uppercase | Nhãn nhóm nhỏ |
| `body` | 14 / 1.45 / 400 | Mặc định |
| `body-sm` | 13 / 1.45 / 400 | Mô tả phụ |
| `caption` | 12 / 1.35 / 400 | Sàn tuyệt đối — **không nhỏ hơn** |
| `mono` | 13 / 1.4 | Thời gian, tọa độ (tabular-nums) |

- Font: `"Geist Variable", system-ui, sans-serif`; import subset **vietnamese + latin**.
- **Tiếng Việt:** line-height ≥ 1.35 (dấu chồng), không dùng `text-transform: uppercase` cho chuỗi có dấu (dấu bị cắt/dày), tránh `letter-spacing` âm.
- Trọng lượng chỉ 400/500/600 — không dùng 300 (mảnh, khó đọc trên nền tối).

## 43.4. Khoảng cách, kích thước, bo góc

```css
:root {
  --sp-1: 4px;  --sp-2: 8px;  --sp-3: 12px; --sp-4: 16px;
  --sp-5: 20px; --sp-6: 24px; --sp-8: 32px; --sp-10: 40px; --sp-12: 48px;

  --radius-control: 8px;
  --radius-panel: 16px;
  --radius-dialog: 20px;
  --radius-pill: 999px;

  --h-control-sm: 28px;
  --h-control: 32px;
  --h-control-lg: 40px;
  --h-icon-btn: 28px;
  --h-play: 44px;
  --h-pill: 52px;
  --h-bar: 36px;
  --w-panel: 320px;
  --w-panel-wide: 380px;
  --touch-min: 44px;

  --blur-glass: 36px;
  --shadow-glass: inset 0 1px 0 rgba(255,255,255,.07), 0 10px 40px rgba(0,0,0,.35);
  --shadow-pop: 0 16px 48px rgba(0,0,0,.55);
}
```
**Gap mặc định** trong toolbar: `--sp-2`. Padding panel: `--sp-4`. Padding dialog: `--sp-6`.
**Lưới:** panel dùng `display:grid; grid-template-columns: 1fr; row-gap: var(--sp-3)`; hàng label–control dùng `grid-template-columns: 96px 1fr` (label cố định để thẳng hàng).

## 43.5. Thang z-index & lớp

```css
:root {
  --z-canvas: 0;
  --z-hud: 10;
  --z-island: 20;
  --z-pill: 30;
  --z-panel: 40;
  --z-popover: 50;
  --z-dialog: 60;
  --z-toast: 70;
  --z-tooltip: 80;
}
```
- **Chrome ẩn khi phát:** island + pill `opacity: 0` sau `2000ms` không có chuột/chạm; hiện lại trong `120ms`. Không ẩn khi có popover/dialog/menu đang mở.
- **Panel Customize mở** → island/pill dịch sang trái `calc(var(--w-panel) / 2)` trong `180ms` (hoặc dùng `padding-inline-end` trên container để tránh layout shift).

## 43.6. Chuyển động

| Token | Giá trị | Dùng |
|---|---|---|
| `--dur-instant` | 80ms | hover fill |
| `--dur-fast` | 120ms | hiện/ẩn chrome, tooltip |
| `--dur-base` | 180ms | panel, popover |
| `--dur-slow` | 240ms | dialog, sheet |
| `--ease-out` | `cubic-bezier(.2,.8,.2,1)` | vào |
| `--ease-in-out` | `cubic-bezier(.4,0,.2,1)` | đổi trạng thái |

**Quy tắc:** không animate `width/height/top/left` (dùng `transform`, `opacity`, `clip-path`). Tôn trọng `prefers-reduced-motion: reduce` → tất cả về 0ms, trừ progress bar.

## 43.7. Component inventory (bắt buộc có, kèm trạng thái)

### 43.7.1. `Button`
| Variant | Nền | Chữ | Dùng |
|---|---|---|---|
`primary` | `--ink` | `--on-ink` | hành động chính duy nhất mỗi màn (Export / Bắt đầu) |
`ghost` | trong suốt | `--ink` | mặc định |
`ghost-hover` | `--fill-hover` | | |
`danger` | trong suốt, chữ `--danger` | | xoá project |
`icon` | trong suốt, 28×28 | | toolbar |

Sizes: `sm` (28px), `md` (32px), `lg` (40px). Radius `--radius-control`. Padding ngang: 10/12/16. Disabled: `opacity:.4`, `cursor:not-allowed`. Focus: ring trắng 2px offset 2.

### 43.7.2. `SegmentedControl`
- Track `--fill-track`, item active `--ink`/`--on-ink`.
- Dùng cho: chế độ xem (3D / Piano roll / Sheet), hệ tên nốt, đơn vị.

### 43.7.3. `Slider`
- Track 4px `--fill-track`; fill `--ink` 100%; thumb 14px trắng, viền `rgba(0,0,0,.4)`.
- **Luôn có ô số bên cạnh** (width 56px, `mono`, tabular). Kéo xong mới commit vào undo stack.
- Double-click về mặc định. `Shift` = bước nhỏ (÷10). `Alt` = nhập tay.

### 43.7.4. `ColorField`
- Ô 24×24 bo 6 + hex text (bấm để sửa) + nút "chọn từ màn hình" (EyeDropper API nếu có).
- Preset 12 màu + "theo tay" + "random theo nốt (seed)".

### 43.7.5. `Select` / `Dropdown`
- Cao 32px, fill field, chữ body, mũi tên 12px `--ink-faint`.
- Menu: `--glass-fill-solid`, radius 12, padding 4, item cao 30, hover `--fill-hover`.

### 43.7.6. `Panel` (Customize / Timeline / Inspector)
- `--glass-fill-strong` + blur + `--glass-edge` + radius 16 + shadow glass.
- Header: tiêu đề + nút đóng 28px; body scroll (scrollbar 8px, thumb trắng 16%).
- Section: heading + nội dung, cách nhau 20px, có đường kẻ 1px trắng 6% (không dùng card lồng).

### 43.7.7. `Dialog`
- Scrim `--scrim` + blur 8px; panel radius 20, width `min(520px, 92vw)`, padding 24.
- Nút ở footer phải: huỷ (ghost) + xác nhận (primary). `Esc` đóng; focus trap; trả focus về nút mở.

### 43.7.8. `Toast`
- Dưới cùng giữa, cách pill 16px; `--glass-fill-solid`, radius 12, padding 12/16; icon 16 + text 13; tự ẩn 4s; hover giữ; tối đa 3 cái.
- Có action ("Hoàn tác", "Xuất ngay").

### 43.7.9. `Tooltip`
- Trễ 400ms, ẩn 80ms; nền `#15161a`, chữ 12, radius 8, padding 6/8, max-width 240px.
- Không dùng tooltip cho thông tin bắt buộc (chỉ phụ).

### 43.7.10. `Timeline` (lane)
- Lane cao 28px; nhãn trái 96px; nốt MIDI là khối bo 2px màu `--ink-faint`..`--ink`.
- Keyframe: hình thoi 10px, kéo được, double-click để sửa giá trị.
- Playhead: 1px `--ink` + tam giác 8px ở đầu.

### 43.7.11. `PianoRoll` (canvas)
- Nền `--canvas-raised`; đường kẻ dọc (nhịp) trắng 6%, (ô nhịp) 12%; đường kẻ ngang theo quãng 8 trắng 5%.
- Nốt: rect bo 2, cao 70% lane, màu theo quy tắc; viền sáng khi chọn (`--focus-ring` 1.5px).
- Lane velocity cao 64px dưới cùng.

### 43.7.12. `EmptyState`
- Icon 40px `--ink-faint`, tiêu đề 16/600, mô tả 13 `--ink-muted`, 1 nút primary.
- Dùng ở: chưa có bài, chưa có take, chưa có project.

### 43.7.13. `Banner`
- Ngang, cao 40px, nền `rgba(245,196,81,.12)` (warning) hoặc `rgba(255,139,128,.12)` (danger), chữ 13, icon 16, nút đóng.
- 1 banner/lúc; ưu tiên: mất dữ liệu > thiếu MIDI > sample lỗi.

## 43.8. Bố cục màn hình (khung chung)

```
┌──────────────────────────────────────────────────────────────┐
│ island bài hát (trái)              island input (phải)        │  top: 16px, side: 16px
├──────────────────────────────────────────────────────────────┤
│                         CANVAS (full-bleed)                   │
│  (WebGL) + HUD overlay (góc dưới trái: phím tắt gợi ý)        │
├──────────────────────────────────────────────────────────────┤
│                 TRANSPORT PILL (giữa, dưới)                   │  bottom: 20px
└──────────────────────────────────────────────────────────────┘
```
- Canvas chiếm `100vw × 100vh`; chrome là `position: fixed`.
- **Breakpoint:** ≥1280 đủ chỗ; 1024–1279 giảm padding; **768–1023**: panel thành sheet trượt từ phải (rộng 92vw), transport pill thu gọn (ẩn speed/volume vào menu).
- <768: không chặn, nhưng hiện banner "Màn hình nhỏ — xoay ngang để có trải nghiệm tốt hơn".

## 43.9. Icon

- Bộ: **Lucide** (MIT), stroke 1.75, size 16 (toolbar), 20 (dialog), 24 (empty state).
- Không tự vẽ icon mới nếu Lucide có; nếu cần (ví dụ phím đàn), vẽ SVG 24×24 stroke 1.5 theo cùng grid.
- Màu icon = `currentColor`; không tô đặc (trừ trạng thái active được phép fill 12%).

## 43.10. Âm thanh của giao diện (UI sound)

- **Không** có tiếng click UI mặc định (app nhạc, dễ nhiễu).
- Tùy chọn: tiếng "tick" metronome, tiếng đếm vào — thuộc engine, không phải UI.

## 43.11. Hình nền & độ tương phản

- Background mặc định: gradient rất tối (`#05060a → #0a0b10` chéo 160deg) + vignette 40%.
- Nếu người dùng đặt ảnh/video: phủ scrim `rgba(5,6,10,.35)` để nốt vẫn nổi; độ mờ ảnh tùy chỉnh 0–80%.
- **Không** dùng nền sáng cho UI (nốt trắng sẽ mất tương phản) — nếu cần light theme, phải đổi cả màu nốt (ngoài phạm vi v1).

## 43.12. Checklist "đẹp" (tự kiểm trước khi bàn giao)

- [ ] Không có màu ngoài token (grep hex trong `src/ui`).
- [ ] Mọi khoảng cách là bội số 4.
- [ ] Không chữ nào < 12px.
- [ ] Mọi control có hover + focus-visible + disabled.
- [ ] Không panel nào cao quá 80vh mà không scroll.
- [ ] Ảnh chụp 3 trạng thái (rỗng / đang phát / panel mở) không có phần tử lệch 1px (kiểm bằng mắt + lưới 8px).
- [ ] Blur không làm giật khi cuộn (test trên máy yếu: nếu giật, giảm blur còn 24px).
- [ ] Viền kính 1px không bị "double border" khi 2 panel cạnh nhau.
