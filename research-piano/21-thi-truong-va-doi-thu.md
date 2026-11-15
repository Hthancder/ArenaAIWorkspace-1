# 21 — Thị trường, đối thủ, định vị

> Số liệu giá tại thời điểm tra cứu (2026-11-14), lấy từ trang chính thức/bài tổng hợp 2026. Giá thay đổi theo khu vực và khuyến mãi — dùng để **so sánh tương quan**, không phải báo giá.

## 21.1. Bản đồ thị trường: 5 nhóm sản phẩm

| Nhóm | Việc người dùng cần | Sản phẩm tiêu biểu | Mô hình giá |
|---|---|---|---|
| **A. Học từ số 0** | Lộ trình, sửa tay, động lực | Simply Piano, Skoove, Yousician, Hoffman | Subscription $120–170/năm |
| **B. Học theo bài hát** | Học đúng bài mình thích | Flowkey, OnlinePianist, Artie | Subscription $90–150/năm |
| **C. Luyện với MIDI của mình** | Chơi bài tự mang, chấm điểm | Synthesia, Piano Marvel, Playground | $29 một lần / $130–150/năm |
| **D. Làm video / visual** | Video nốt rơi cho YouTube/TikTok | SeeMusic, NoteFall, Embers, PianoViz, Neothesia | Free/watermark, $80/năm, open-source |
| **E. Chơi tự do (instrument)** | Chơi ngay, không học | Perfect Piano, virtual piano web, RoxyPiano | Free + quảng cáo/IAP |

**App mới nằm ở giao của C + D + E** — đúng khoảng trống: *"chơi thật + luyện với MIDI của mình + hình ảnh đẹp + tùy chỉnh sâu + miễn phí/local-first"*.

## 21.2. Bảng giá đối thủ (2026)

| Sản phẩm | Giá/năm | Gói gia đình | Dùng thử | Cách nghe | Ghi chú |
|---|---|---|---|---|---|
| **Simply Piano** | ~$120–170 (giá dao động theo nguồn/khu vực) | ✅ ~$210 | 7–14 ngày | Mic (MIDI tùy chọn) | Curriculum mạnh nhất cho người mới; hết đất cho intermediate |
| **Flowkey** | ~$120 ($9.99–19.99/tháng); lifetime $329.99 | ✅ ~$180 | 7 ngày | Mic + **video tay thật** | 1.500+ bài; Wait Mode |
| **Skoove** | ~$120–150 | ❌ | 7–14 ngày | Mic | Thiên lý thuyết, ít gamification |
| **Yousician** | ~$68–140 | ✅ ~$210 | 7 ngày, free tier ~10 phút/ngày | Mic | Gamification mạnh nhất |
| **Piano Marvel** | ~$130 | (giáo viên/nhóm) | Free tier | MIDI (chính) + mic iOS | Sight-reading SASR, 25k+ bài |
| **Playground Sessions** | ~$150; lifetime ~$290–350 | ❌ | ✅ | **Chỉ MIDI** | Curriculum Quincy Jones |
| **Artie (ArtMaster)** | ~$90 | ✅ | ✅ | Mic/MIDI | Mới, AI feedback, giá thấp nhất nhóm |
| **Synthesia** | **$29 một lần** (mọi thiết bị, mọi update) | — | 20+ bài full | **Chỉ MIDI** | Giá trị tốt nhất nhóm C |
| **SeeMusic** | ~$80/năm (Pro), free có watermark | — | Free | MIDI/audio→MIDI | Record + footage sync + 4K |
| **PianoViz** | Freemium | — | Free 10 s preview | Audio→MIDI (AI) | Web, export MP4 Full HD |
| **NoteFall** | **Miễn phí, không watermark** | — | — | Sample piano | Web, source-available (PolyForm) |
| **Perfect Piano** | Free + IAP/quảng cáo | — | — | On-screen | Mobile, multiplayer |

**Nhận xét về giá:**
- Nhóm A/B subscription **$120–170/năm** là mặt bằng. Người dùng phổ thông **mệt mỏi subscription** (bằng chứng: Synthesia $29 một lần đượcđược giới thiệu liên tục trong các bài "alternatives").
- Nhóm D (video) có mức giá thấp hơn nhiều và cạnh tranh bằng **chất lượng hình**.
- **Không ai** kết hợp: miễn phí + local-first + BYO MIDI + wait mode + 3D đẹp + tùy chỉnh sâu + tiếng Việt.

## 21.3. Phân tích đối thủ trực tiếp (nhóm C+D)

| Tiêu chí | SeeMusic | Synthesia | NoteFall | PianoViz | Neothesia | **App mới (định hướng)** |
|---|---|---|---|---|---|---|
| Nền tảng | Win/Mac/iOS/Android | Win/Mac/iOS/Android | Web desktop | Web | Win/Mac/Linux | **Web (PWA) desktop-first** |
| Học/luyện có chấm điểm | ⚠️ nhẹ | ✅ 3 chế độ | ❌ | ❌ | ⚠️ | ✅ **P1** |
| Wait Mode | ❌ | ✅ | ❌ | ❌ | ⚠️ | ✅ **P1** |
| Sheet music | ✅ MusicXML | ✅ | ❌ | ❌ | ❌ | ✅ P1 |
| MIDI editor | ✅ | ❌ | ✅ (trên canvas) | ❌ | ❌ | ✅ |
| Camera/footage sync | ✅ | ❌ | ❌ | ❌ | ❌ | P2 |
| Audio→MIDI | ✅ | ❌ | ❌ | ✅ (AI) | ✅ | P2 |
| Tùy chỉnh visual sâu | ✅ | ❌ | ✅✅✅ | ⚠️ | ⚠️ | ✅✅✅ |
| Export video | ✅ 4K | ❌ | ✅ 4K | ✅ FHD | ✅ ffmpeg | ✅ 4K + 9:16 |
| Miễn phí | ❌ (watermark) | ❌ ($29) | ✅ | ⚠️ | ✅ | ✅ |
| Local-first (không upload) | ⚠️ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Tiếng Việt | ❌ | ⚠️ | ❌ | ❌ | ❌ | ✅ **điểm khác biệt** |
| Mobile | ✅ | ✅ | ❌ | ✅ | ❌ | P2 |

## 21.4. Khoảng trống & định vị

**Khoảng trống 1 — "app của tôi, nhạc của tôi":** mọi app học đều khoá thư viện; người có MIDI riêng (tải trên mạng, tự làm, mua) phải dùng Synthesia (giao diện 2010, chỉ MIDI) hoặc NoteFall (đẹp nhưng không chấm điểm).

**Khoảng trống 2 — "đẹp + dạy được":** SeeMusic đẹp nhưng là công cụ làm video, không dạy. Synthesia dạy nhưng xấu. Không ai làm cả hai tốt.

**Khoảng trống 3 — "tùy chỉnh thật":** người dùng nâng cao (giáo viên, creator, người chơi lâu năm) muốn chỉnh màu, camera, velocity, pedal, soundfont, phím tắt… Các app subscription đóng kín.

**Khoảng trống 4 — "không cần đàn piano":** phần lớn app học giả định có đàn thật. Người chỉ có máy tính bị bỏ rơi (trừ virtual piano, nhưng virtual piano không dạy).

**Khoảng trống 5 — tiếng Việt:** không app nào bản địa hoá tử tế; thuật ngữ nhạc lý Việt (phách, ô nhịp, hóa biểu, Đô Rê Mi) không có trong app nước ngoài.

**Câu định vị (chọn 1, dùng nhất quán):**
- "Chơi piano thật trên máy tính — với bất kỳ file MIDI nào, đẹp như video, chấm điểm như giáo viên."
- "Studio piano trong trình duyệt: mở MIDI, chơi, luyện, quay video — tất cả trên máy bạn."
- Ngắn: **"Mở MIDI. Chơi. Luyện. Xuất video."**

## 21.5. Mô hình kinh doanh — 3 lựa chọn

| Mô hình | Ưu | Nhược | Phù hợp khi |
|---|---|---|---|
| **Miễn phí hoàn toàn + donate** | Niềm tin, lan truyền, không rào cản | Không có doanh thu, khó duy trì | Mục tiêu học tập/cộng đồng (giai đoạn 1) |
| **Freemium** (core free, pro trả một lần ~$29) | Giống Synthesia — được người dùng thích | Cần phân chia tính năng rõ, tránh cảm giác bị chặn | Khi muốn duy trì lâu dài |
| **Subscription $5–8/tháng** | Doanh thu ổn định | Đối đầu trực tiếp app lớn; người dùng mệt | Không khuyến nghị giai đoạn đầu |

**Khuyến nghị:** **miễn phí core** (chơi, MIDI, luyện, export không watermark) + **bản Pro một lần** cho tính năng nặng (4K/AV1, batch export, SoundFont packs, cloud sync tuỳ chọn). Không quảng cáo, không bán dữ liệu — đây là điểm khác biệt so với nhóm app mobile.

## 21.6. Kênh phân phối & tăng trưởng

| Kênh | Cách làm | Chi phí | Ghi chú |
|---|---|---|---|
| **YouTube piano channels** | Chính app tạo ra video → chính nó là quảng cáo (watermark-free nhưng có credit nhỏ tuỳ chọn) | Thấp | Vòng lặp tăng trưởng tự nhiên nhất |
| **TikTok/Shorts** | Export 9:16 sẵn | Thấp | Cần tính năng vertical (P1) |
| **Reddit** (r/piano, r/pianolearning, r/pianoapps) | Post demo + xin feedback (như các dev khác đã làm) | Thấp | Trung thực, không spam |
| **Discord piano/music-production** | Cộng đồng, hỗ trợ | Thấp | |
| **SEO** | "piano visualizer", "play midi piano online", "học piano trên máy tính", "tạo video nốt rơi" | Trung bình | Tiếng Việt ít cạnh tranh hơn |
| **Product Hunt / Hacker News** | 1 lần ra mắt | Thấp | Nhấn "local-first, không upload" |
| **Giáo viên piano VN** | Công cụ dạy (tạo bài tập, chấm, xuất video) | Trung bình | Kênh B2B nhỏ nhưng trung thành |
| **GitHub** (nếu mở source phần nào) | Thu hút dev | Thấp | Cẩn thận giấy phép NoteFall |

**Vòng lặp tăng trưởng cốt lõi**: người dùng tạo video → video có credit/nhận diện app → người xem tải app → tạo video. Đây là cách SeeMusic và NoteFall tồn tại.

## 21.7. Rủi ro thị trường

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| **Bản quyền nội dung** (MIDI/bài hát có bản quyền) | Cao | Không phân phối thư viện; BYO MIDI; demo public domain; cảnh báo trách nhiệm thuộc người dùng |
| SeeMusic thêm tính năng học | Trung bình | Tập trung vào "học + tùy chỉnh + miễn phí + tiếng Việt" |
| Các app lớn thêm web + BYO MIDI | Trung bình | Tốc độ và cộng đồng; local-first |
| AI transcription thành commodity | Trung bình | Tích hợp thay vì cạnh tranh |
| Giấy phép NoteFall khi publish | **Cao** | Xem file 10.1, chốt trước khi build |
| Chi phí CDN sample (77 MB/người dùng) | Trung bình | Cache mạnh, nén, CDN rẻ; hoặc giảm bộ sample cho bản free |
| Kỳ vọng "miễn phí mãi" | Thấp | Nói rõ mô hình ngay từ đầu |

## 21.8. Chỉ số cần theo dõi (nếu publish)

| Chỉ số | Mục tiêu gợi ý | Cách đo |
|---|---|---|
| **Activation**: mở app → bấm nốt đầu tiên | > 80% | event nội bộ (opt-in) |
| Mở MIDI đầu tiên trong 5 phút | > 50% | |
| **Retention D7 / D30** | > 25% / > 12% | |
| Số phút luyện/ngày (người quay lại) | > 10 phút | |
| Số buổi luyện có chấm điểm | > 1/tuần | |
| Export video/người dùng | > 0.1/tuần | |
| Tỉ lệ lỗi export | < 2% | log lỗi cục bộ, người dùng tự gửi nếu muốn |
| Thời gian tới nốt đầu tiên | < 3 s (cold, có cache) | performance mark |

**Nguyên tắc dữ liệu**: mặc định **không gửi gì**; nếu bật analytics phải là loại không cookie, có nút tắt, và nói rõ trong UI. Đây vừa là đạo đức vừa là điểm bán hàng ("nhạc của bạn không rời khỏi máy").

## 21.9. Thị trường Việt Nam — ghi chú riêng

- Người học piano ở VN phổ biến dùng **đàn điện (digital piano) + app nước ngoài** hoặc **học qua YouTube**; app bản địa gần như trống.
- Rào cản: giá subscription quốc tế ($120/năm ≈ 3 triệu VND) là **lớn** với học sinh/sinh viên → **miễn phí** là lợi thế quyết định.
- Thiết bị: laptop Windows phổ biến (Chrome/Edge → **có Web MIDI**), nhiều người có đàn điện Yamaha/Roland/Casio có **USB MIDI** → đúng điều kiện lý tưởng.
- Nội dung: nhạc Việt (bolero, nhạc trẻ, nhạc phim) ít có MIDI chất lượng → cơ hội cho tính năng **audio→MIDI** (P2) và **cộng đồng chia sẻ MIDI** (nếu làm, phải có cơ chế bản quyền).
- Ngôn ngữ: thuật ngữ nhạc lý Việt cần chuẩn hoá (file 25); nhiều người quen **Đô Rê Mi** hơn C D E → cho chọn.
- Thanh toán: nếu thu phí, dùng chuyển khoản/Momo/VietQR thay vì chỉ thẻ quốc tế.
