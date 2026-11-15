# 42 — Đặc tả giao diện từng màn hình

> Mỗi mục = 1 màn hình/modal. Cấu trúc cố định: **Mục đích · Bố cục · Thành phần · Trạng thái · Chuỗi UI · Tương tác · Nghiệm thu**.
> Token dùng tên ở `43`. Chuỗi tiếng Việt **chép nguyên văn**. Nếu màn hình chưa có trong danh sách → không được tự thêm.

## 42.0. Danh sách màn hình (bắt buộc)

| ID | Màn hình | Loại | Milestone |
|---|---|---|---|
| **S0** | Start / Empty | overlay trên canvas | M1 |
| **S1** | Player 3D | màn chính | M1 |
| **S2** | Customize | panel phải | M2 |
| **S3** | Timeline | panel trái | M3 |
| **S4** | Note Inspector | card nổi | M3 |
| **S5** | Piano Roll Editor | chế độ toàn màn | M4 |
| **S6** | Practice | overlay + HUD | M5 |
| **S7** | Export | dialog | M4 |
| **S8** | Open / Projects | dialog | M3 |
| **S9** | Settings | dialog nhiều tab | M2 |
| **S10** | About / Credits | dialog | M4 |
| **S11** | Trạng thái lỗi | banner + dialog | M1 |

---

## S0 — Start / Empty state

**Mục đích:** đưa người dùng tới phím đầu tiên trong < 15 giây.

**Bố cục**
```
                ┌─────────────────────────────┐
                │        (logo chữ nhỏ)       │
                │   Chơi piano trên máy tính  │   title
                │  Không cần đàn. Miễn phí.   │   body-sm
                │                             │
                │  [ Mở file MIDI ]  primary  │
                │  [ Thử bài demo ▾ ]  ghost  │
                │                             │
                │  hoặc bấm  A S D F G H J    │   caption
                └─────────────────────────────┘
```
- Card kính giữa màn hình, width 420, padding 24, radius 16.
- Bàn phím 3D vẫn hiện phía sau (không bị che hoàn toàn), camera hơi cao hơn bình thường.

**Thành phần:** logo chữ, `title`, `body-sm`, `Button primary`, `Button ghost` + dropdown 3 demo, `caption`.

**Trạng thái**
| Trạng thái | Hiển thị |
|---|---|
| Đang tải sample | `Button primary` → "Đang chuẩn bị đàn… 42%" (disabled) |
| Sẵn sàng | nút bình thường |
| Không có Web MIDI | thêm `caption`: "Trình duyệt không hỗ trợ đàn MIDI — chơi bằng bàn phím vẫn tốt." |
| Có project gần nhất | thêm dòng: "Tiếp tục: **Für Elise** · ô nhịp 24" (link) |

**Chuỗi UI (nguyên văn)**
- Tiêu đề: `Chơi piano trên máy tính`
- Phụ: `Không cần đàn. Miễn phí. File MIDI của bạn.`
- Nút 1: `Mở file MIDI`
- Nút 2: `Thử bài demo`
- Gợi ý: `hoặc bấm phím A S D F G H J để chơi thử`
- Link: `Tiếp tục: {tên bài} · ô nhịp {n}`

**Tương tác:** kéo file vào bất kỳ đâu → mở; `Esc` ẩn card (để xem bàn phím); bấm phím đàn → card mờ 60% nhưng không biến mất.

**Nghiệm thu:** mở app lạnh → thấy card < 500 ms; bấm phím → có tiếng < 15 s (kể cả khi sample chưa tải xong, dùng synth tạm).

---

## S1 — Player 3D (màn chính)

**Bố cục**
```
┌ island bài hát ─────────────────────┐   ┌ island input ────────────────────────┐
│ ☰  File  Tên bài ●  ↶ ↷             │   │ MIDI ▾   ● Record ▾      Export      │
└─────────────────────────────────────┘   └──────────────────────────────────────┘
                              (canvas: bàn phím + nốt rơi)
┌ Timeline (nếu mở) ─────────────┐                                  ┌ Customize ┐
└────────────────────────────────┘                                  └───────────┘
        ( ⏮  −10s  ▶  +10s  🔁 00:42.3 ──●──── 03:03 │ 1.0× 🔈 ⛶ │ Customize  Timeline )
```

**Thành phần**
| Vùng | Thành phần | Chi tiết |
|---|---|---|
| Song island | menu ☰, `File`, tên bài (editable inline), chấm "chưa lưu", undo/redo | cao 40, padding 8/12, gap 8 |
| Input island | chọn MIDI, Record + ▾, Export | Export là **primary duy nhất** trên màn |
| Canvas | WebGL | bàn phím ở `KEYBOARD_Y = -2.0`, 88 phím × 0.235 wu, camera `[0,0,12]` FOV 32 |
| Transport pill | về đầu, −10s, play 44px, +10s, loop, thời gian `mono`, scrubber, tổng, tốc độ, âm lượng, fullscreen, Customize, Timeline | cao 52, radius 999 |
| HUD góc dưới trái | FPS (debug), trạng thái thiết bị | 12px, `--ink-faint` |

**Trạng thái**
| Trạng thái | Biểu hiện |
|---|---|
| Chưa có bài | canvas không nốt; S0 hiện |
| Đang tải | progress mảnh trên đỉnh pill (2px, `--ink`) |
| Đang phát | nút play → pause; nốt sáng; chrome mờ sau 2 s |
| Tạm dừng | chrome hiện; nốt đứng |
| Đang ghi | viền đỏ quanh canvas 2px `--record`, pill hiện "● 00:12" |
| Count-in | số đếm lớn giữa màn (72px, `display`), nốt chưa rơi |
| Loop bật | vùng A–B tô trắng 8% trên scrubber + icon sáng |
| Lỗi audio | banner "Âm thanh bị tắt" + nút "Bật âm thanh" |

**Chuỗi UI**
- Nút play aria-label: `Phát` / `Tạm dừng`
- Loop: `Lặp đoạn đã chọn`
- Record: `Ghi âm`
- Export: `Xuất`
- Tên bài mặc định khi chưa có: `Chưa có bài`

**Tương tác (bắt buộc)**
- `Space` phát/dừng; `←/→` ±1 s; `Shift+←/→` ±5 s; `Home` về đầu; `L` loop; `R` ghi; `Esc` đóng panel.
- Bấm phím đàn on-screen → có tiếng + phím lún; kéo ngang = glissando.
- Cuộn chuột trên canvas = zoom camera (giới hạn 0.6–2.0); kéo = xoay nhẹ (±15°).
- Double-click nốt trên canvas → mở S4.

**Nghiệm thu:** 88 phím hiển thị đúng thứ tự; nốt của bài sáng khi qua; nốt người dùng chơi có viền khác màu; không nhấp nháy khi pause.

---

## S2 — Customize (panel phải)

**Bố cục**
```
┌ Customize ─────────────────── ✕ ┐
│ [ Tìm thông số…              ]   │  search 32px
│ ( Bàn phím | Nốt | Màu | Camera | Cảnh | Âm thanh | Luyện )  tab cuộn ngang
├──────────────────────────────────┤
│ BÀN PHÍM                         │  label-caps
│ Số phím        [ 88 ▾ ]          │  row: 96px label + control
│ Hiện nhãn      [ ● ]             │
│ ...                              │
├──────────────────────────────────┤
│ Đặt lại mặc định                 │  footer, ghost danger
└──────────────────────────────────┘
```
- Width `--w-panel` (320), max-height `calc(100vh - 140px)`, radius 16, kính đậm.
- **Search lọc theo tên + từ đồng nghĩa tiếng Việt** (`phím`, `nốt`, `màu`, `tốc độ`).

**Tab & nội dung (thứ tự cố định)**
| Tab | Nhóm thông số (xem `09` Phần B) |
|---|---|
| Bàn phím | số phím, độ rộng, màu phím/gỗ, glow, nhãn phím, vạch quãng 8 |
| Nốt | hướng rơi, thời gian rơi, độ rộng/dài, bo góc, hình dạng, mờ dần |
| Màu | chế độ màu (theo tay / theo cao độ / 1 màu / random), bảng màu, độ sáng |
| Camera | FOV, khoảng cách, nghiêng, auto-follow, rung |
| Cảnh | nền (màu/gradient/ảnh/video), mờ nền, vignette, bloom, particle |
| Âm thanh | âm lượng master, velocity curve, pedal, reverb, limiter, bộ sample |
| Luyện | wait mode, tốc độ, đếm vào, metronome, chấm điểm, ẩn nốt |

**Thành phần:** `Tabs` (cuộn ngang, không wrap), `SearchField`, `Section` (heading + rows), `Slider` + số, `Switch`, `Select`, `ColorField`, `SegmentedControl`, footer.

**Trạng thái**
- Không có bài → tab "Nốt/Màu/Camera" vẫn dùng được (chỉnh cho lần sau).
- Thay đổi → áp dụng **ngay** (không cần Apply), ghi vào undo của settings (Ctrl+Z hoàn tác được).
- Đang phát → vẫn cho đổi (trừ số phím → cần reset camera).

**Chuỗi UI:** `Tìm thông số…`, `Đặt lại mặc định`, `Đã đặt lại`, `Không tìm thấy thông số nào khớp “{q}”`.

**Nghiệm thu:** mọi key trong `09` Phần B (P0) đều có control; search tìm được bằng tiếng Việt không dấu; panel không che transport pill.

---

## S3 — Timeline

**Mục đích:** xem/sửa cấu trúc bài và keyframe theo thời gian.

**Bố cục:** panel trái, width 320, cao 220, cách pill 12.
Lane: `MIDI` (khối nốt), `Tốc độ` (đường + keyframe), `Âm lượng`, `Audio` (waveform nếu có).
Playhead dọc toàn bộ; thanh zoom ngang; nút "Fit".

**Trạng thái:** không có bài → ẩn; đang phát → playhead chạy; kéo keyframe → tooltip giá trị (`1.25×`).

**Nghiệm thu:** kéo keyframe tốc độ ở giây 30 → phát qua giây 30 tốc độ đổi đúng; không lệch khi đổi kích thước cửa sổ.

---

## S4 — Note Inspector (card nổi)

**Bố cục:** card 260px, xuất hiện cạnh nốt được chọn (né mép màn hình).

```
┌──────────────────────────┐
│ C4 · 0:42.30        ✕    │
│ Velocity  [ 96 ]  ▬▬▬▬   │
│ Tay       ( Trái | Phải )│
│ Ngón      [ 3 ▾ ]        │
│ Màu       [ ■ ]          │
│ [ Xoá nốt ]  [ Chép ]    │
└──────────────────────────┘
```

**Trạng thái:** chọn nhiều nốt → tiêu đề `12 nốt đã chọn`, chỉ hiện các trường chung; giá trị khác nhau hiện `—`.

**Nghiệm thu:** sửa velocity → nghe khác ngay; `Esc` bỏ chọn; undo hoạt động.

---

## S5 — Piano Roll Editor (toàn màn)

**Bố cục**
```
┌ toolbar: [chọn][bút] | snap [1/16 ▾] | ↶ ↷ | ⤢ Fit | [Về trình phát] ┐
├───────────┬──────────────────────────────────────────────────────────┤
│ Inspector │  thước thời gian                                          │
│ (S4)      │  piano roll (canvas)                                     │
│           ├──────────────────────────────────────────────────────────┤
│           │  lane velocity                                           │
└───────────┴──────────────────────────────────────────────────────────┘
```
- Bàn phím dọc bên trái canvas (mỗi phím 8px), nhãn C3/C4… ở quãng 8.
- Toolbar cao 40; canvas nền `--canvas-raised`.

**Trạng thái:** không có bài → empty state "Mở file MIDI để chỉnh sửa"; đang phát → playhead chạy, sửa vẫn được.

**Tương tác:** xem bảng đầy đủ ở `37.3`. Bắt buộc: kéo nốt, kéo mép, xoá, vẽ, snap, undo 100 bước.

**Nghiệm thu:** 10.000 nốt vẫn cuộn mượt (≥30 fps); sửa → về Player thấy thay đổi; export MIDI round-trip đúng.

---

## S6 — Practice

**Bố cục**
- Trên cùng: thanh tiến trình đoạn đang luyện (bar N/M), phần trăm đúng.
- Giữa: nốt rơi + **vạch chờ** (wait mode) — nốt kế tiếp sáng, các nốt khác mờ 40%.
- Dưới: `Bỏ qua` (Tab), `Chậm lại` (−10%), `Lặp đoạn`, `Dừng`.
- Kết thúc: card kết quả.

**Card kết quả**
```
┌────────────────────────────────────┐
│ Xong đoạn 12–20                    │  title
│ Đúng 87% · Đúng nhịp 74%           │  body
│ ▁▃▅▂▇▆▃▁  (bar 12..20)             │  bar chart
│ Ô nhịp yếu nhất: 15, 16            │
│ [ Luyện lại ô yếu ]  [ Tiếp ]       │
└────────────────────────────────────┘
```

**Chuỗi UI:** `Chờ đúng nốt…`, `Sai nốt — thử lại`, `Bỏ qua (Tab)`, `Đúng 87%`, `Ô nhịp yếu nhất: {n}`, `Luyện lại ô yếu`, `Tiếp`.

**Trạng thái:** không có MIDI input → "Chơi bằng bàn phím máy tính để chấm điểm" (vẫn chấm được); mic chưa cấp quyền → ẩn tùy chọn mic.

**Nghiệm thu:** bấm sai → không tiến; bấm đúng → tiến trong ≤ 50 ms; kết quả khớp công thức `16.3`; luyện lại ô yếu đúng phạm vi.

---

## S7 — Export (dialog)

**Bố cục:** 2 tab: `Âm thanh` · `Video`. Footer: `Huỷ` · `Xuất` (primary).

**Tab Âm thanh:** định dạng (WAV 16/24-bit, MP3 nếu có lamejs, Opus), sample rate (44.1/48), phạm vi (cả bài / đoạn chọn), chuẩn hoá (`-1 dBTP`), tiến trình + ước lượng thời gian.
**Tab Video:** preset (`YouTube 1080p60`, `YouTube 4K30`, `Shorts 9:16`, `Vuông 1:1`, `Tuỳ chỉnh`), fps, bitrate, nền, watermark (tắt mặc định), tail 5 s. Chi tiết `23.3`.

**Chuỗi UI:** `Xuất âm thanh`, `Xuất video`, `Đang render… {p}%`, `Xong — tải xuống`, `Huỷ`, `Ước tính: ~{n} giây`.

**Trạng thái:** không có WebCodecs → chỉ WAV + thông báo; render xong → toast có action `Mở thư mục`/`Tải lại`.

**Nghiệm thu:** WAV mở được, không clip; video 720p30 5 s có `ffprobe` hợp lệ; huỷ giữa chừng không treo.

---

## S8 — Open / Projects (dialog)

**Bố cục:** danh sách project gần đây (thumbnail 96×54, tên, thời gian sửa), nút `Mở file…`, `Tạo mới`, khu vực kéo-thả.

**Trạng thái:** trống → empty state "Chưa có project nào"; file lỗi → dòng đỏ + nút xoá khỏi danh sách.

**Nghiệm thu:** mở `.nfz` cũ → migrate; xoá project → có xác nhận; kéo file `.mid` vào dialog → mở luôn.

---

## S9 — Settings (dialog, 4 tab)

| Tab | Nội dung |
|---|---|
| **Chung** | ngôn ngữ (Tiếng Việt/English), hệ tên nốt, theme (tối), giảm chuyển động |
| **Thiết bị** | chọn MIDI in, test phím, độ trễ ước lượng + calibrate, cảnh báo Bluetooth |
| **Âm thanh** | bộ sample (đầy đủ/nhẹ), chất lượng, voice limit, reverb, limiter |
| **Dữ liệu** | dung lượng đã dùng, `persist()`, xuất tất cả, xoá dữ liệu (2 bước) |

**Chuỗi UI:** `Thiết bị MIDI`, `Chưa kết nối thiết bị nào`, `Đo độ trễ`, `Dung lượng: {x} / {y}`, `Xuất tất cả`, `Xoá toàn bộ dữ liệu`.

**Nghiệm thu:** đổi ngôn ngữ → toàn UI đổi ngay; calibrate lưu được; xoá dữ liệu yêu cầu gõ `XOÁ`.

---

## S10 — About / Credits

Nội dung: phiên bản + commit, license code, **Salamander Grand Piano — Alexander Holm (CC BY 3.0)** + link, font Geist (OFL), thư viện (three.js, R3F, zustand…), "Không upload file của bạn", email liên hệ.

**Nghiệm thu:** mọi asset trong `docs/licenses/ASSETS.md` đều xuất hiện.

---

## S11 — Trạng thái lỗi

| Tình huống | Hiển thị | Hành động |
|---|---|---|
| AudioContext bị treo | Banner: `Âm thanh đang tắt. Bấm để bật.` | `ctx.resume()` |
| Sample lỗi | Banner: `Không tải được đàn. Đang dùng âm thanh tạm.` | Thử lại |
| File quá lớn | Dialog: `File này có {n} nốt — quá lớn để mở mượt. Vẫn mở?` | Mở / Huỷ |
| File hỏng | Dialog: `Không đọc được file này. Có thể file bị hỏng hoặc không phải MIDI.` | Chọn file khác |
| Hết bộ nhớ | Banner: `Trình duyệt hết bộ nhớ. Đã giảm hiệu ứng.` | Tự hạ cấp |
| Không hỗ trợ WebGL2 | Màn hình: `Trình duyệt không hỗ trợ đồ hoạ 3D.` + hướng dẫn bật | — |
| Safari xoá dữ liệu | Banner: `Safari có thể xoá dữ liệu trang sau 7 ngày không dùng. Xuất bản sao lưu?` | `Xuất .nfz` |

**Luật:** không hiện stack trace, không hiện `undefined`, mỗi lỗi có **một** hành động rõ.

---

## 42.12. Bảng kiểm toàn bộ màn hình

- [ ] S0–S11 tồn tại, đúng ID, đúng chuỗi.
- [ ] Mỗi màn có trạng thái rỗng/đang tải/lỗi.
- [ ] Mọi chuỗi nằm trong `i18n/vi.ts` (không hard-code).
- [ ] Mọi màn dùng được ở 768 px (panel → sheet).
- [ ] Không màn nào có > 1 nút primary.
- [ ] `Esc` đóng mọi overlay; focus trả về nơi mở.
- [ ] Không màn nào chặn người dùng bằng modal không cần thiết.
