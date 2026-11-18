# SiriX — triển khai v1.2 và kiểm tra trước phát hành

Nhánh này triển khai các nhóm v1.2 bên dưới. **Chưa chốt phát hành 1.2.0**: phiên bản `.deb` và bundle giữ `1.1.0` cho đến khi xác nhận các hook/audio trên iPhone jailbreak. `local-check.sh` không kiểm tra được quyền mic, UI Siri hay cách audio session của Apple hoạt động.

| Hạng mục | Trong mã | Cần xác nhận trên thiết bị / giới hạn |
|---|---|---|
| Nhận diện & dịch | STT mặc định **tắt**; AVAudioEngine trong lượt nói Siri, PCM16 16 kHz trong bộ nhớ, ngừng ở lifecycle hoặc giới hạn thời lượng. Groq, OpenAI, Gemini và endpoint HTTPS tương thích; dịch VI bằng một request giới hạn / EN tại nguồn. | Quyền mic/routing từng jailbreak. Chỉ gửi sau khi có transcript Apple đủ điều kiện, không tự bật mic từ Settings. Hook UI thử bản sao L2; nếu không dùng được thì L1 (AI nhận STT, UI giữ Apple), rồi Apple. Không sửa luồng intent Apple hay chữ nhận diện từng phần. |
| Thử STT | Settings mở cửa sổ thử 60 giây cho lượt Siri giọng nói tiếp theo, hiển thị trạng thái khi quay lại. Không ghi audio/transcript của bài thử vào bản ghi chẩn đoán. | Bài thử dùng cùng pipeline Siri, không tự bắt đầu ghi âm hay tự bật STT. Ở chế độ tiền tố, Apple phải nhận ra `@ai` mới có upload. |
| Giọng đọc | Hệ thống, Google Cloud, Gemini và `/audio/speech`; chọn giọng/lọc, VI/EN tự động, tốc độ/âm lượng và Thử giọng. Gỡ nội dung đọc của Apple chỉ khi có đường đọc thay thế đã chuẩn bị; nguồn online trễ/lỗi trước khi sửa ACE → giữ Siri đọc. Lỗi phát sau khi đã làm im ACE → thử giọng hệ thống. | Xác nhận không đọc chồng, Siri không đóng và audio thực sự phát. Chọn `Dùng giọng Siri` nếu thiết bị không tương thích. Edge không có adapter ổn định được chọn; dùng phương án dự phòng trong thiết kế (Hệ thống/Google Cloud/Gemini/Tự chỉnh). Google Cloud cần khóa dịch vụ. |
| Streaming, hủy và model dự phòng | SSE có giới hạn token đầu và thời gian toàn lượt; hủy mạng/media theo lượt. Mini-chat hiển thị dần. Thử một lần với model dự phòng của đúng provider, không chạy lại tool; 429/5xx có backoff, mất mạng có nhánh giữ bản gốc / báo lỗi. | Hiển thị dần trong Siri là **opt-in thử nghiệm**, dùng `SAUIUpdateViews` khi có view và cùng `refId`; nếu không, hiển thị bản hoàn tất hoặc lịch sử. Giới hạn chờ ACE 5 giây, STT tối đa 2,5 giây. |
| Đáp án trễ | Có thể cập nhật bubble đang tồn tại nếu bật cập nhật thử nghiệm; nếu không, lưu lịch sử và thử gửi banner không chứa transcript. | Banner và đường dẫn sang Lịch sử phụ thuộc `BBServer`/PreferenceLoader và chính sách thông báo của máy. Nếu không khả dụng, xem đáp án trong Lịch sử. Không hiện nếu đã sang lượt khác hoặc không lưu lịch sử. |
| Dữ liệu & công cụ | Log chuẩn không ghi nguyên văn transcript/đáp án, API key, URL hay kết quả tool. Không lưu lịch sử giữ lượt riêng tư trong RAM, tắt tool và thông báo trễ. Chế độ chỉ dùng Siri gốc chặn request mạng của **SiriX**, kể cả thử kết nối và kiểm tra cập nhật. `current_app` tùy chọn, chỉ tên/mã gói. Tool kiểm tra bật/tắt lúc chạy; đọc web yêu cầu URL HTTPS nêu trong câu hỏi. | Chế độ này không kiểm soát kết nối Siri/Apple hoặc xóa log/lịch sử đã có. Nhận diện lệnh hệ thống từ text/các lệnh ACE là best effort; nếu cần chắc chắn không gửi ngoài Siri, dùng chế độ chỉ dùng Siri gốc. |
| Settings & phân phối | Thống kê STT/TTS, lịch sử, model dự phòng, xuất/nhập JSON có xác nhận và che khóa mặc định, chẩn đoán nhanh, kiểm tra GitHub Release. CI thêm test fixture và đường gắn cả hai gói vào release đã xuất bản đúng phiên bản. | Nếu repo không công khai hoặc chưa có stable GitHub Release, hàng cập nhật chưa có phiên bản từ API công khai. Không tự cài/bật cập nhật. |

## Quy tắc Cài đặt theo nguồn

| Mục | Những gì được dùng |
|---|---|
| Nhà cung cấp AI | Một nút cấu hình cho lựa chọn hiện tại. OpenAI/Groq/Gemini có URL cố định; Tự chỉnh yêu cầu HTTPS, khóa và mã mô hình. Mỗi hồ sơ giữ khóa, mô hình và mô hình dự phòng riêng. |
| STT | Tắt thì dùng Apple và ẩn các mục phụ. Theo cấu hình AI lấy địa chỉ/khóa từ AI nhưng dùng mô hình nhận diện. Nguồn đặt tên có thể dùng khóa STT riêng hoặc khóa AI **cùng nhà cung cấp**; Tự chỉnh có URL/khóa riêng, không tự lấy khóa chat. Dịch EN qua Groq/OpenAI dùng mô hình dịch cố định và tự nhận ngôn ngữ. |
| TTS | Dùng giọng Siri thì ẩn mục đọc của SiriX. Chỉ đọc lỗi hoặc Không lưu lịch sử thì dùng hệ thống. Google Cloud chỉ cần khóa và giọng; Gemini thêm mô hình; Tự chỉnh có HTTPS, mô hình và một ô mã giọng, không có bộ chọn giọng/ngôn ngữ cục bộ. |
| Phản hồi / riêng tư | Thử lại khi hết giờ chỉ xuất hiện khi có mô hình dự phòng khác mô hình chính; Thông minh vẫn giữ Siri khi hết giờ. Khi không lưu lịch sử, ẩn công cụ và báo đáp án trễ. Tùy chọn cập nhật thẻ vẫn có thể dùng cho đáp án trễ ngay cả khi tắt streaming. |

Settings trên máy chuyển hồ sơ cũ lần đầu đọc, ghi các khóa mới cùng lần lưu kế tiếp. URL OpenAI/Groq chuẩn chuyển sang preset tương ứng; proxy hoặc URL không hợp lệ không biến thành endpoint chính thức. Bí mật lưu theo hồ sơ; đổi URL Tự chỉnh chỉ xóa khóa gắn với URL đó. JSON xuất **v2** và vẫn nhập **v1**. STT Tự chỉnh trước đây dựa vào khóa chat cần nhập khóa STT riêng nếu máy chủ yêu cầu.

## Checklist trên iPhone trước khi bump phiên bản

1. Cài gói đúng scheme, chạy qua ít nhất iOS 15 rootless và roothide; ghi rõ phiên bản iOS và jailbreak. Với iOS 16.x, kiểm tra selector có được nhận diện, không crash nếu thiếu.
2. Không bật STT: Type-to-Siri, giọng Siri gốc, `@ai`, `@siri`, đặt báo thức, hẹn giờ và mở app. Bật STT: nói VI; thử dịch EN→VI và VI→EN; thử mic không cấp quyền, hủy Siri giữa lượt, endpoint lỗi/chậm và Type-to-Siri.
3. Thử giọng hệ thống VI/EN và một nguồn online. Lượt có cả AddViews và SayIt chỉ đọc một lần; nguồn online lỗi vẫn có giọng Siri. Trả lời mới phải dừng âm thanh của lượt cũ.
4. Mạng chậm: thử giữ Siri, thông báo hết giờ, retry đúng một lần, vào lượt mới giữa stream, bật/tắt cập nhật dần. Kiểm tra đáp án trễ được lưu, banner không lộ nội dung và tap đi tới Lịch sử trên phiên bản PreferenceLoader đang dùng.
5. Bật Không lưu lịch sử và Chỉ dùng Siri gốc riêng rẽ; kiểm tra không rò dữ liệu mới và thao tác xóa không bị lượt đang chạy phục hồi. Kiểm tra xuất JSON mặc định không có khóa, nhập hủy không đổi gì, và nhập đổi endpoint không dùng lại khóa cũ.
6. Trong Cài đặt, đổi OpenAI → Groq → Gemini → Tự chỉnh rồi quay lại lần lượt. Xác nhận chỉ Tự chỉnh có ô URL, khóa/mô hình vẫn ở đúng nhà cung cấp, và Kiểm tra kết nối gọi đúng nguồn. Lặp lại với STT/TTS, thử tắt từng nhóm rồi bật lại để kiểm tra không mất lựa chọn.
