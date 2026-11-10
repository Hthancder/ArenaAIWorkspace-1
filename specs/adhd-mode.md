# Chế độ ADHD — Đặc tả thiết kế (v2.3.0)

> Thiết kế dựa trên nghiên cứu về ADHD (executive dysfunction, time blindness, dopamine
> reward, rejection-sensitive dysphoria) và các nguyên tắc thiết kế cho não ADHD đã
> được ghi nhận trong tài liệu/thực hành của các app ADHD (Tiimo, Structured, Inflow,
> Finch, Habitica, Focusmate…). Đây **không phải** tính năng y khoa, không chẩn đoán,
> không thay thế điều trị — chỉ là chế độ giao diện + hành vi.

## 1. Kết quả nghiên cứu — từ đó thành nguyên tắc thiết kế

| Đặc điểm ADHD (khoa học) | Hệ quả thực tế | Nguyên tắc thiết kế (Taskora ADHD) |
|---|---|---|
| **Executive dysfunction** — khó "bắt đầu" hơn khó "làm" (task initiation) | Ngồi nhìn đống việc mà không biết làm gì; cả ngày trôi qua | **P1. Một việc tại một thời điểm.** Luôn hiện rõ "việc tiếp theo" — một thẻ duy nhất, tiêu đề duy nhất, hai nút: *Tập trung 25′* và *✓ Xong*. Không bắt người dùng chọn. |
| **Quyết định = chi phí não bộ**; quyết định càng nhiều càng tê liệt (decision paralysis) | Danh sách dài → không làm gì cả | **P2. Giảm lựa chọn gần như về 0.** ADHD mode không thêm menu nào; mọi thứ mới đều gắn vào 1 luồng duy nhất (thẻ Việc tiếp theo → phiên tập trung). |
| **Time blindness** — không cảm nhận thời gian trôi | "5 phút nữa" thành 90 phút; deadline bất ngờ | **P3. Thời gian hữu hình.** Phiên tập trung 25:00 với vòng tròn đếm ngược SVG — thời gian được "nhìn thấy", không phải đoán. |
| **Dopamine/reward deficit** — phần thưởng trì hoãn không có tác dụng | Checkbox thường "không đã", bỏ app sau 2 tuần | **P4. Thưởng tức thì.** Confetti nổ ngay khi hoàn thành + câu cổ vũ ngẫu nhiên (ấm, ngắn) ở mỗi lần xong việc; không cần streak để "được thưởng". |
| **Rejection Sensitive Dysphoria / shame spiral** — một lần "thất bại" → bỏ cuộc | Task quá hạn đỏ → né app → cảm giác tội lỗi | **P5. Không bao giờ phán xét.** Banner quá hạn chuyển hổ phách + câu chữ "Chưa kịp lần này — đẩy sang mai nhé?"; mọi copy bối rối thành khích lệ; không có màu đỏ cho lỗi cá nhân. |
| **Object permanence** — "xa mặt cách lòng" mất việc | Việc biến mất khỏi tâm trí | **P6. Luôn nằm trong tầm mắt.** Thẻ Việc tiếp theo ghim đầu danh sách; quick-add placeholder nhắc "ném mọi thứ vào đây". |
| **Working memory 3–5 item** | Quên bước, lạc giữa chừng | **P7. Tối đa 3 yếu tố hiển thị cùng lúc.** Thẻ tiếp theo chỉ có tiêu đề + 2 nút + 1 dòng phụ. |
| **Quá tải kích thích (extraneous cognitive load)** | Giao diện ồn ào gây xao lãng | **P8. Giao diện dịu.** Tắt hạt nhiễu nền, tăng kích thước vùng bấm, ring focus rõ, không thêm animation trang trí ngoài hiệu ứng thưởng. |
| **Body doubling / accountability** | Có người "ngồi cùng" thì dễ làm hơn | (Phase 2 — cần mạng/tài khoản, ngoài phạm vi. Ghi chú để mở rộng.) |
| **Các app ADHD tốt = "không thể gây shame" + "quá đáng yêu cũng được"** | "If a neurotypical user finds it too much, it's probably right for ADHD." | **P9. Nỗ lực thưởng luôn lớn hơn.** Hoàn thành nhỏ cũng được ăn mừng đủ đầy. |

## 2. Phạm vi (scope)

### Trong phạm vi v2.3.0 (làm ngay, theo spec này)

1. **Cài đặt:** toggle **"Chế độ ADHD"** (`settings.adhd_mode`, mặc định `false`) — Cài đặt → Giao diện, icon i-lightning, hint "Một việc tại một thời điểm · thưởng tức thì · không phán xét — thiết kế cho não ADHD".
2. **Thẻ "TIẾP THEO"** (`#adhd-next`) — ghim trên danh sách việc ở các view có thể làm việc (Hộp thư/Hôm nay/Sắp tới/Ghim/Danh sách). Hiển thị: tiêu đề việc đầu tiên trong danh sách đang hiện (tôn trọng sort/filter), chip ưu tiên/hạn nhỏ, hai nút:
   - **"Tập trung 25′"** → mở Phiên tập trung (mục 3).
   - **"✓ Xong luôn"** → toggle complete như bình thường (bật hiệu ứng thưởng nếu ADHD mode).
   Ẩn khi: view không làm việc (Thống kê/Cài đặt/Hoàn thành/Thùng rác), hoặc không còn việc chưa xong → thay bằng dòng dịu "Không còn việc nào — nghỉ xíu đi."
3. **Phiên tập trung** (`#focus-overlay`, fullscreen): vòng tròn SVG đếm ngược 25:00 (tick 1s), tên việc, câu nhắc "Đúng việc này thôi — mọi thứ khác có thể đợi", nút **Tạm dừng / Tiếp tục**, nút **"Dừng lại — không sao"** (thoát không bị phạt). Khi hết giờ → màn celebrate: "Xong một phiên! Bạn làm được." + confetti + 2 nút: **[Nghỉ 5:00 — đứng dậy, uống nước]** (vòng nghỉ, bỏ qua được bất cứ lúc nào) và **[Việc tiếp theo →]** (đóng overlay). Escape = dừng phiên. Việc đang chọn hiển thị đúng tiêu đề.
4. **Confetti** (`confettiBurst()`): ~26 mảnh giấy màu (accent/gold/xanh lá), rơi 900ms, tự hủy — chạy khi: hoàn thành việc qua mọi đường (toggle/Space/Next card/quả ✓), hoàn thành phiên tập trung. Chỉ trong ADHD mode.
5. **Câu cổ vũ ngẫu nhiên** (pool tiếng Việt, ấm — không "gamification trẻ con"): hiện qua toast khi hoàn thành việc ở ADHD mode.
6. **Overdue banner dịu** (`body.adhd`): nền hổ phách thay đỏ, tiêu đề "Chưa kịp lần này — xN việc chờ tới lúc bạn sẵn sàng", nút giữ nguyên chức năng (Dời sang hôm nay), icon i-clock.
7. **CSS `body.adhd`**: `body::after { display:none }` (tắt nhiễu), `.tcheck` 24px, `.task-row` padding tăng nhẹ, `:focus-visible` outline dày hơn, banner hổ phách, `.overdue-banner` đổi palette, `.adhd .stat-pill` cho quá hạn đổi hổ phách. Không đổi layout, không ẩn chức năng nào.
8. **Quick-add coaching** (ADHD mode bật): placeholder xoay vòng 8s/câu: "Chỉ cần 1 việc nhỏ nhất thôi…", "Viết 1 dòng — cứ ngắn và xấu cũng được", "Việc 2 phút cũng đáng kể", "Ném vào đây rồi tính sau".
9. **Không shame ở mọi copy mới**; undo vẫn 1 chạm (đã có).
10. **Reset settings** → tắt ADHD (mặc định false) ✓ nhất quán.

### Ngoài phạm vi (phase 2 — ghi nhận, không làm vội)

- Lưu thống kê phiên tập trung/streak vào data.json (schema drift; dùng `done_today` làm mỏ neo thưởng tạm).
- Brain-dump nhiều việc một lúc (tính năng riêng).
- Body doubling / accountability xã hội (cần mạng+tài khoản).
- Chặn distraction ở OS/browser level.
- Break 4-7-8 breathing, 5′/10′/50′ options (tránh thêm quyết định).

## 3. Thiết kế Phiên tập trung (wireframe)

```
╭──────────────────────── Overlay full màn, glass ────────────────────────╮
│        "Tập trung vào đúng việc này thôi" (câu nhắc nhỏ, nhạt)          │
│                  ○ Vòng SVG  240px, stroke 10                           │
│                   24:59                                             │
│            (còn bao lâu — số to, tabular-nums)                          │
│   ┌─────────────────────────────────────────────┐                     │
│   │  Tiêu đề việc (esc, 1–2 dòng, căn giữa)      │                     │
│   └─────────────────────────────────────────────┘                     │
│        [⏸ Tạm dừng]        [Dừng lại — không sao]                     │
╰─────────────────────────────────────────────────────────────────────────╯
Hết giờ → cùng khung đổi sang celebrate: "Xong một phiên!" + confetti +
[Nghỉ 5:00 — đứng dậy, uống nước, nhìn xa]  [Việc tiếp theo →]
```

- Không âm thanh (tránh bất ngờ/ồn); phản hồi chính = vòng tròn + confetti.
- Tạm dừng giữ nguyên tiến độ; "Dừng lại" không ghi gì, copy không trách.
- Escape đóng; Space trong overlay = tạm dừng/tiếp tục (không toggle việc ở nền).

## 4. Luồng dữ liệu & trạng thái

```
Settings.adhd_mode (Rust, serde default false)
  → snapshot → postSnap → body.classList.toggle("adhd", …)
  → renderTaskList() cuối cùng cũng renderNextUp() (chỉ listable views)
  → syncSettingsControls() đặt checkbox #set-adhd
```
- Persist: chỉ qua `update_settings` (`patch.adhd_mode`) — không thêm lệnh backend.
- Trạng thái overlay/focus nằm trong JS (`F.active`, `F.paused`, `F.remaining`, `F.taskId`), không persist.
- Toggle tắt ADHD giữa chừng phiên → overlay tự đóng (an toàn), mọi hiệu ứng thưởng tắt theo cờ.

## 5. Copy (tiếng Việt, không shame)

- Toast hoàn thành (random): "Xong rồi! Một điểm cộng nữa ✦" · "Tốt! Bạn đang lấy đà." · "Thêm một việc được xử đẹp." · "Đã xong — thưởng cho mình một hơi thở sâu." · "Tuyệt, việc tiếp theo thôi."
- Banner: tiêu đề `Chưa kịp lần này — ${n} việc chờ tới lúc bạn sẵn sàng` · nút `Dời sang hôm nay`
- Next card: nhãn `TIẾP THEO` · nút `Tập trung 25′` · `✓ Xong luôn` · rỗng: `Không còn việc nào — nghỉ xíu đi.`
- Focus: nhắc `Đúng việc này thôi — mọi thứ khác có thể đợi` · dừng sớm `Dừng lại — không sao` · hết giờ `Xong một phiên! Bạn làm được.`

## 6. Tiêu chí nghiệm thu (test theo spec này)

1. Toggle ADHD trong Cài đặt → `body.adhd` xuất hiện/biến mất ngay, checkbox đồng bộ khi mở lại.
2. Có việc chưa xong + view listable → thẻ TIẾP THEO hiện đúng task đầu; hết việc → hiện dòng dịu.
3. Bấm "Tập trung 25′" → overlay hiện, vòng tròn chạy; Escape → đóng; ✓ Xong → việc được toggle + confetti (khi ADHD bật).
4. Toggle ADHD tắt → thẻ ẩn, overlay đóng, banner đỏ trở lại như cũ; không side-effect nào khi ADHD tắt.
5. Reset cài đặt → ADHD tắt.
6. Harness jsdom: bật/tắt ADHD, thẻ tiếp theo, overlay mở/đóng, quick-add placeholder đổi — tất cả PASS.
