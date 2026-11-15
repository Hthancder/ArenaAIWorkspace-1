# 37 — Trình sửa MIDI (piano roll) — đặc tả tương tác

> "MIDI tùy chỉnh tự do" là yêu cầu gốc của bạn. File này biến nó thành **đặc tả tương tác cụ thể**: bấm vào đâu, ra cái gì, giới hạn nào. Dùng để code và để test.

## 37.1. Hai chế độ hiển thị, một dữ liệu

| Chế độ | Dùng khi | Ưu tiên |
|---|---|---|
| **3D falling notes** | chơi, xem, quay video | chính (NoteFall) |
| **Piano roll 2D** (trục X = thời gian, Y = cao độ) | sửa nốt chính xác | thêm mới |

**Bắt buộc:** cả hai cùng đọc/ghi một `ParsedSong`; sửa ở đâu cũng thấy ngay ở chế độ kia. Không có "bản sao dữ liệu".

## 37.2. Mô hình dữ liệu tối thiểu

```ts
type NoteId = string           // uuid ổn định, không dùng index
type Note = {
  id: NoteId
  pitch: number                // 0..127
  start: number                // giây (đã áp tempo map) hoặc tick — CHỌN MỘT
  duration: number
  velocity: number             // 1..127
  track: number
  hand?: 'L' | 'R'
  finger?: number              // 1..5
  color?: string               // null = theo quy tắc
}
```

**Quyết định quan trọng: dùng tick + tempo map, không dùng giây.**
- Lý do: đổi tempo mà không làm hỏng vị trí nốt; quantize theo phách; export MIDI chính xác.
- Giây chỉ là **dẫn xuất** khi phát/hiển thị.
- Nếu NoteFall lưu bằng giây (kiểm tra file 15), đây là điểm cần chuyển đổi — ghi lại khi đọc code.

## 37.3. Bảng tương tác (bắt buộc có)

| Hành động | Chuột | Bàn phím | Kết quả |
|---|---|---|---|
| Chọn nốt | click | `Tab`/mũi tên | viền sáng, hiện thuộc tính |
| Chọn nhiều | shift+click, kéo hộp | shift+mũi tên | |
| Chọn tất cả trong vùng | kéo hộp | `Ctrl+A` (cả bài) | |
| Di chuyển | kéo | `←→↑↓` (±1 phách/±1 nửa cung), `Shift` = ±1 tick | giữ nguyên độ dài |
| Đổi độ dài | kéo mép phải | `Alt+←/→` | snap theo grid |
| Đổi velocity | kéo dọc trong lane velocity | `Alt+↑/↓` | hiện số |
| Xoá | `Delete` / chuột phải | `Delete`/`Backspace` | |
| Nhân đôi | `Ctrl+D` | | dán ngay sau |
| Cắt đôi | `S` tại vị trí | | |
| Dán | `Ctrl+V` tại con trỏ | | |
| Vẽ nốt mới | công cụ bút, kéo để đặt độ dài | phím số chọn độ dài | |
| Undo/Redo | `Ctrl+Z` / `Ctrl+Shift+Z` | | ≥ 100 bước |
| Zoom ngang/dọc | `Ctrl+wheel` / wheel | `+/-` | |
| Pan | space+kéo / wheel ngang | | |
| Chạy thử từ vị trí | click thước | `Enter` | phát từ đó |

**Quy tắc snap:** mặc định 1/16 nốt; giữ `Alt` để tắt snap; dropdown chọn 1/4, 1/8, 1/8 ba, 1/16, 1/32, "theo phách".

## 37.4. Ràng buộc dữ liệu (invariants) — phải test

1. **Không 2 nốt cùng pitch chồng lấn trong cùng track** (khi bật "gộp"): nốt trước bị cắt tại điểm nốt sau bắt đầu.
2. `duration > 0`; `start ≥ 0`; `pitch ∈ [0,127]`; `velocity ∈ [1,127]`.
3. `id` duy nhất; xoá rồi undo phải khôi phục **cùng id** (để selection/keyframe tham chiếu còn đúng).
4. Sắp xếp theo `(start, pitch)` sau mỗi thao tác (hoặc dùng index).
5. Mọi thao tác sửa phải là **command** (undo/redo) — không sửa trực tiếp state.
6. Sửa không được làm thay đổi tempo map (trừ khi dùng công cụ tempo).

## 37.5. Lịch sử & hiệu năng sửa

- **Command pattern**: `{do, undo, label}`; stack giới hạn 200; gộp thao tác kéo liên tục thành 1 command (bắt đầu/kết thúc drag).
- Với bài 10.000 nốt: mỗi command lưu **diff** (id + trường thay đổi), không lưu toàn bộ mảng.
- Khi kéo nhiều nốt: cập nhật hình ngay (optimistic) nhưng chỉ commit command khi thả chuột.
- Không re-render toàn bộ piano roll mỗi lần kéo: chỉ vẽ lại vùng bị ảnh hưởng (dirty rect) hoặc dùng canvas 2 lớp.

## 37.6. Công cụ nâng cao (theo thứ tự ưu tiên)

| Công cụ | Mô tả | Ưu tiên |
|---|---|---|
| **Quantize** | làm tròn start/duration về grid; hiện trước/sau | P0 |
| **Humanize** | thêm lệch nhỏ ±ms và ±velocity (seed cố định) | P1 |
| **Transpose** | ±nửa cung, giữ đúng spelling khi hiển thị | P0 |
| **Legato/Staccato** | kéo dài/rút nốt tới % | P1 |
| **Chọn theo tay** | tách L/R theo ngưỡng pitch hoặc theo track | P0 |
| **Đổi nhạc cụ / kênh** | gán track → instrument | P2 (nếu có nhiều timbre) |
| **Velocity curve** | map lại velocity toàn track (đường cong) | P1 |
| **Fix overlap / merge** | dọn dữ liệu MIDI bẩn | P0 (nhập từ nguồn ngoài) |
| **Split theo bar** | cắt thành đoạn để luyện | P1 |
| **Fingering** | gán/gợi ý ngón (file 16.6) | P2 |

## 37.7. Bố cục UI (gợi ý)

```
┌──────────────────────────────────────────────┐
│ Toolbar: công cụ, snap, undo/redo, zoom      │
├───────────┬──────────────────────────────────┤
│ Inspector │  Piano roll (canvas)             │
│ (nốt đang │  ├─ lane velocity (dưới)         │
│  chọn)    │  └─ thước thời gian (trên)       │
├───────────┴──────────────────────────────────┤
│ Transport: ▶ ⏸ ⏹ | 00:42.3 | 1.0× | loop A–B │
└──────────────────────────────────────────────┘
```
- Inspector **chỉ hiện khi có nốt chọn** (đỡ rối).
- Lane velocity cao 60–80 px, kéo được.
- Chế độ toàn màn hình cho piano roll (ẩn bàn phím 3D).

## 37.8. Test cho editor (tối thiểu 30 ca)

| Nhóm | Ca tiêu biểu |
|---|---|
| Chọn | click, shift, hộp, click vùng trống để bỏ chọn |
| Di chuyển | 1 nốt, nhiều nốt, snap bật/tắt, chặn ở pitch 0/127 |
| Độ dài | kéo mép, không cho âm, không vượt nốt kế (nếu bật gộp) |
| Velocity | kéo lane, phím tắt, chặn 1..127 |
| Undo | 100 bước, undo sau khi đổi tempo, undo sau khi xoá nhiều |
| Invariant | không overlap, sắp xếp đúng, id ổn định |
| Hiệu năng | 10.000 nốt, kéo 500 nốt → ≥ 30 fps |
| Round-trip | sửa → export MIDI → nhập lại → dữ liệu bằng nhau |

## 37.9. Điều dễ làm sai

- **Dùng index làm id** → xoá 1 nốt là mọi tham chiếu lệch.
- **Sửa trực tiếp object trong state** → undo không hoạt động, React không re-render.
- **Lưu giây thay vì tick** → đổi tempo làm hỏng bài.
- **Snap cứng không có Alt** → không đặt được nốt lệch (nhạc sống cần).
- **Không gộp command khi kéo** → 1 cú kéo = 200 bước undo.
- **Vẽ lại toàn bộ canvas mỗi frame** → giật với bài lớn.
