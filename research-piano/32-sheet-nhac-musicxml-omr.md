# 32 — Sheet music, MusicXML và OMR

> "Hiện sheet nhạc" là tính năng hạng nặng về cả kỹ thuật và bản quyền. File này xác định: hiển thị được gì, chi phí thật, và **có nên làm không**.

## 32.1. Định dạng cần hỗ trợ

| Định dạng | Vai trò | Thư viện |
|---|---|---|
| **MusicXML (`.musicxml`, `.xml`)** | Chuẩn trao đổi chính, mọi phần mềm notation xuất được | OSMD, VexFlow (tự parse) |
| **MXL (`.mxl`)** | Zip chứa MusicXML + asset | tự giải nén (JSZip) |
| **MIDI** | Không phải sheet, nhưng suy ra được "sheet tối giản" | tự code |
| **MEI** | Học thuật, hiếm | không |
| **ABC / LilyPond** | Nhỏ, dễ parse | abcjs (MIT) |
| **PDF/ảnh** | Phổ biến nhất người dùng có, nhưng phải **OMR** | Audiveris (server), oemer (Python) |

**Thực tế:** người dùng Việt gần như chỉ có **PDF/ảnh** hoặc **MIDI**, rất ít khi có MusicXML. Đây là điểm quan trọng cho quyết định phạm vi.

## 32.2. OSMD — số liệu thật (2026)

`opensheetmusicdisplay/opensheetmusicdisplay` (BSD-3, dựa trên VexFlow):

| Phiên bản | Thay đổi hiệu năng |
|---|---|
| 2.0.0 (06/2026) | Nhanh gấp đôi: tính skyline hình học thay vì đọc pixel canvas (1.8×, tới 4×) |
| 2.1.2 (08/2026) | Nhanh thêm **40%** (47% với bản nhạc lớn) |
| 2.3.0 (11/2026) | Nhanh thêm 13%, **bộ nhớ giảm 8–19%** (Chrome), `clear()` giải phóng (10 MB thay vì 344 MB), có `dispose()` |

**Chi phí thật cho bản nhạc lớn (dữ liệu từ PR của OSMD):**

| Giai đoạn | Tỉ lệ thời gian |
|---|---|
| Vẽ (`drawSheet`) | ~52% (trong đó DOM/SVG ~30%, glyph ~14%) |
| Tính skyline | 12% |
| Format độ rộng ô nhịp | 6.4% |
| `formatMeasures` của VexFlow | 5.4% |
| GC | 5.4% |
| Còn lại (ngắt dòng, slur, lời…) | ~13% |

- `load()` (đọc MusicXML): model 40%, đối tượng đồ hoạ 27%, **XML parser của trình duyệt 22.5%**, GC 10%.
- Bộ nhớ sau render bản orchestral lớn: **~124 MB** (Chrome, OSMD 2.3.0). Với piano solo nhỏ hơn nhiều, nhưng vẫn phải `dispose()`.

**Kết luận:** OSMD dùng được cho **1 bản nhạc tại một thời điểm** trên desktop. Không dùng để render song song nhiều bản, không dùng trên điện thoại cũ.

## 32.3. Kiến trúc tích hợp sheet + nốt rơi

Đây là điểm khác biệt của app: **sheet và nốt rơi cùng một nguồn thời gian**.

```
ParsedSong (MIDI)  ──┬─→ falling notes (three.js)
                     ├─→ playback (audio engine)
                     └─→ score mapping ──→ OSMD cursor (nếu có MusicXML)
```

Vấn đề cốt lõi: **MusicXML và MIDI không tự khớp**. Cần một trong hai:
1. **Sinh MIDI từ MusicXML** (dùng chính OSMD hoặc thư viện) → một nguồn duy nhất. Cách này sạch nhất: nhập MusicXML → tạo MIDI nội bộ → mọi thứ chạy trên MIDI.
2. **Khớp thủ công** note-id giữa 2 nguồn — dễ lệch, không khuyến nghị.

→ **Quyết định:** nếu hỗ trợ MusicXML, hãy **chuyển thành MIDI nội bộ ngay khi nhập**; sheet chỉ là *lớp hiển thị*, không phải nguồn dữ liệu thứ hai. Điều này tránh toàn bộ lớp bug đồng bộ.

**Cursor theo nhịp:** OSMD có cursor chạy theo timestamp; cần map `AudioContext` time → `MusicXML` timestamp. Với 60–120 nốt/giây cuộn mượt, nên cập nhật cursor 30–60 Hz, không mỗi frame.

## 32.4. OMR (PDF/ảnh → MusicXML) — thực tế

| Công cụ | Chạy ở đâu | Chất lượng | Ghi chú |
|---|---|---|---|
| **Audiveris** | Java, desktop/CLI | Tốt nhất trong các bản mở | Nặng, không chạy browser |
| **oemer** | Python (PyTorch) | Khá, cần GPU để nhanh | Không chạy browser thực tế |
| **PhotoScore / SmartScore** | Thương mại | Tốt | Đắt |
| **Google/khác** | Cloud | Tốt | Upload = vi phạm local-first |

**Không có OMR chất lượng cao chạy được trong trình duyệt.** Muốn có OMR phải: (a) gọi server, hoặc (b) đóng gói Electron kèm Audiveris, hoặc (c) bỏ qua.

**Khuyến nghị:** không làm OMR. Hướng dẫn người dùng: dùng MuseScore (miễn phí) nhập PDF bằng OMR của họ rồi xuất MusicXML/MIDI — chất lượng tốt hơn và không tốn công mình.

## 32.5. Chế độ đọc sheet (không phải editor)

Nếu chỉ cần "xem sheet khi tập", có thể làm nhẹ hơn nhiều:
- **Hiển thị PDF/ảnh** với lật trang + zoom + nhớ vị trí. Không cần OSMD, không cần MusicXML.
- Đồng bộ trang với vị trí phát (người dùng tự đặt "mốc trang ↔ thời điểm") — đơn giản, hữu ích.
- **Ẩn/hiện sheet** bằng phím tắt; sheet chiếm nửa màn hình hoặc overlay.

Cách này giải quyết 80% nhu cầu với 5% công sức và **không vướng bản quyền** (chỉ hiển thị file người dùng có).

## 32.6. Bản quyền — điểm phải nhớ

- **Bản nhạc (composition)** và **bản in/khắc (edition/engraving)** là hai tác quyền khác nhau. Beethoven PD, nhưng bản khắc của nhà xuất bản hiện đại **có thể** vẫn được bảo hộ.
- MusicXML trên MuseScore.com thường là **bản của người dùng đăng** — license từng bản khác nhau (có CC, có "all rights reserved"). **Không được** tải về rồi phân phối lại.
- IMSLP: PD **theo từng quốc gia**; IMSLP không cấp license thay tác giả. Ở Việt Nam, thời hạn thường là **50 năm sau khi tác giả mất** (kiểm tra luật hiện hành trước khi dùng thương mại).
- **Không đóng gói sheet/MIDI của bài còn bản quyền** vào app. Chỉ nhận file người dùng tự có (xem file 35).

## 32.7. Quyết định

| Hạng mục | Quyết định | Lý do |
|---|---|---|
| v1 | Hiển thị **PDF/ảnh** + lật trang + mốc đồng bộ | Rẻ, hữu ích, không bản quyền |
| v2 | Nhập **MusicXML/MXL** → chuyển MIDI nội bộ → hiện sheet bằng OSMD | Giá trị cao, 1 nguồn dữ liệu |
| v3 (tùy chọn) | Editor MusicXML (thêm/xoá nốt trên sheet) | Rất đắt, chỉ khi có nhu cầu thật |
| Không làm | OMR trong browser; render nhiều bản nhạc cùng lúc | Không khả thi / không cần |

## 32.8. Ngân sách nếu làm v2

| Việc | Ước lượng |
|---|---|
| Tích hợp OSMD (lazy-load, chỉ ở route/chế độ sheet) | 1.5 ngày |
| MusicXML → MIDI nội bộ + map cursor | 2 ngày |
| Layout 2 chế độ (sheet / nốt rơi / cả hai) + phím tắt | 1 ngày |
| Test với 10 file MusicXML thật (đơn giản → phức tạp) | 1 ngày |
| **Tổng** | **~5.5 ngày** (chưa gồm editor) |

Tiêu chí xong: mở 1 bản sonata 10 trang < 1.5 s; cursor bám đúng ±1 ô nhịp; không rò rỉ bộ nhớ sau 5 lần mở/đóng (`dispose()`).
