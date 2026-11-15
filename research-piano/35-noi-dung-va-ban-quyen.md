# 35 — Nội dung, nguồn MIDI và bản quyền

> App không host nhạc — nhưng người dùng sẽ hỏi "bài ở đâu?". Câu trả lời sai (đóng gói MIDI phổ biến) = rủi ro pháp lý trực tiếp. File này chốt chính sách nội dung.

## 35.1. Ba lớp quyền khác nhau (đừng gộp)

| Lớp | Ví dụ | Ai giữ quyền |
|---|---|---|
| **Tác phẩm** (composition) | "Für Elise" của Beethoven | Hết hạn → công cộng |
| **Bản thu/trình diễn** (recording) | Bản thu 2020 bởi nghệ sĩ X | Nghệ sĩ + hãng, **dù bài là PD** |
| **Bản khắc/biên tập** (edition/engraving) | Bản in của NXB hiện đại | Nhà xuất bản (có thể) |
| **File MIDI cụ thể** | MIDI do ai đó làm | Người làm file / người đăng |

→ **Bài hát hết bản quyền không có nghĩa là file MIDI đó tự do.** Một file MIDI có thể là bản chuyển soạn được bảo hộ.

## 35.2. Nguồn MIDI/sheet có thể dùng

| Nguồn | License | Dùng được cho app? | Ghi chú |
|---|---|---|---|
| **Mutopia Project** | Từng bản ghi rõ (thường CC BY-SA / PD) | ✅ có, cần ghi nguồn | Có LilyPond + MIDI + PDF |
| **MuseScore.com** | Từng bản: CC / "all rights reserved" | ⚠️ chỉ bản CC, phải kiểm từng file | Phần lớn **không** cho phân phối lại |
| **OpenScore (MuseScore × IMSLP)** | CC0 cho bản chép | ✅ tốt nhất | Bản chép lại của tác phẩm PD, có provenance rõ |
| **IMSLP** | PD theo từng nước; không cấp license thay tác giả | ⚠️ phải kiểm từng item | Chủ yếu PDF, ít MIDI |
| **Kunst der Fuge** | Thương mại/phi thương mại tùy gói | ❌ không dùng | |
| **GiantMIDI-Piano** | Repo ghi CC BY 4.0, **đã archive** | ⚠️ rủi ro | MIDI **suy ra từ bản thu** trên mạng → quyền bản thu không rõ (chính tài liệu nghiên cứu nêu vấn đề này) |
| **MAESTRO (Magenta)** | CC BY-NC-SA | ❌ không cho thương mại | Dùng để test nội bộ thì được |
| **BitMidi / MIDIWorld / freemidi** | Hầu hết **không rõ** | ❌ | Nguồn điển hình của vi phạm |
| **Người dùng tự có** | Của họ | ✅ | Mô hình chính của app |

**Nguyên tắc vàng:** chỉ đóng gói nội dung mà mình **truy được license bằng văn bản** (link + ngày truy cập lưu trong `docs/licenses/`).

## 35.3. Chính sách nội dung của app (đề xuất)

1. **Không host nhạc.** App mở file người dùng chọn (MIDI/MusicXML) — giống trình đọc PDF.
2. Nếu có "bộ bài khởi đầu": chỉ gồm **bản gốc do mình viết/soạn** (etude đơn giản, gam, hợp âm) + 3–5 bản PD có provenance rõ (OpenScore/Mutopia), kèm file `CREDITS`.
3. Không có tính năng "tải bài hát" hay tìm kiếm nội dung.
4. Không chia sẻ project công khai ở v1 (tránh trở thành nơi phân phối nhạc lậu). Nếu sau này có chia sẻ: chỉ chia sẻ **đường dẫn file**, không upload lên server của mình.
5. Trong phần Credits/About: nói rõ "app không cung cấp nhạc; bạn cần tự có file MIDI hợp pháp".

## 35.4. Thời hạn bản quyền — những gì cần biết

| Nơi | Thời hạn (đại ý) | Ghi chú |
|---|---|---|
| Việt Nam | Thường **50 năm** sau khi tác giả mất (tác phẩm âm nhạc) | Kiểm tra luật hiện hành; có ngoại lệ |
| Mỹ | 70 năm sau khi tác giả mất; bản công bố trước 1929 → PD | |
| EU | 70 năm sau khi tác giả mất | |
| Canada | 70 năm (đã tăng từ 50) | |

→ Nhạc cổ điển (Bach, Mozart, Beethoven, Chopin) an toàn. Nhạc pop/thế kỷ 20 **không**.

## 35.5. Nếu người dùng hỏi "làm sao có MIDI?"

Trả lời trung thực, không hướng dẫn vi phạm:
1. Mua bản nhạc số có kèm MIDI (một số nhà xuất bản bán).
2. Dùng MuseScore: nhập nốt hoặc OMR từ PDF bạn có quyền dùng → xuất MIDI.
3. Tìm bản PD trên Mutopia/OpenScore.
4. Tự chơi và ghi lại trong app (tính năng ghi âm) → xuất MIDI.
5. Chuyển từ bản thu của chính bạn bằng công cụ transcription.

## 35.6. Xử lý khiếu nại bản quyền

- Không host nội dung → **không có gì để gỡ**, nhưng vẫn cần kênh liên hệ.
- Nếu có bộ bài khởi đầu bị khiếu nại: gỡ file khỏi repo, phát hành bản mới, ghi trong changelog.
- Nếu app được đưa lên store: có mục "Copyright" trong metadata + email liên hệ.
- Lưu **nhật ký nguồn** cho mọi asset đóng gói (file, license, URL, ngày).

## 35.7. Giấy phép cho chính app

| Thành phần | License | Bắt buộc |
|---|---|---|
| Code của mình | MIT (khuyến nghị) hoặc giữ kín | — |
| Nếu fork NoteFall | **PolyForm Shield**: phải giữ LICENSE + Required Notice; **cấm** dùng làm sản phẩm cạnh tranh | ✅ |
| Sample Salamander | CC BY 3.0 (một số bản chuyển đổi ghi BY-SA — kiểm tra file kèm bản tải) | Ghi công Alexander Holm |
| Model transcription | Apache-2.0 (Basic Pitch) | Giữ notice |
| Font Geist | OFL-1.1 | Giữ notice |

**Kiểm tra mâu thuẫn:** nếu code là MIT nhưng chứa sample CC BY-SA → **toàn bộ** có thể bị kéo theo SA. Cách tránh: sample để ở repo/asset riêng, ghi license riêng, không nhúng vào bundle code.

## 35.8. Checklist pháp lý trước khi công bố

- [ ] Danh sách asset đóng gói + license + link + ngày (`docs/licenses/ASSETS.md`).
- [ ] Trang trong app: "Giấy phép & ghi công" hiển thị đủ.
- [ ] Không có file MIDI/âm thanh nào không rõ nguồn trong repo.
- [ ] README nêu: app không cung cấp nhạc; người dùng tự chịu trách nhiệm về file họ mở.
- [ ] Email liên hệ + quy trình gỡ nội dung.
- [ ] Nếu thương mại: kiểm tra lại hợp đồng license của sample và của NoteFall.
