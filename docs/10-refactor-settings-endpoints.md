# 10 · Settings, endpoint và jailbreak path: refactor dựa trên API thực tế

## Vấn đề được sửa

- `SBRowView` gắn tap action và long-press highlight với thời gian `0.01s`; long-press giành gesture trước tap nên action row có thể trông như nút nhưng không chạy. Highlight giờ không huỷ/cản tap và cho phép hai recognizer đồng thời.
- Fallback đọc plist trong `SBConfig` từng cache bằng `dispatch_once`. Nếu SiriViewService bị sandbox khỏi preferences domain, mọi lần reload sau notification vẫn lấy cấu hình cũ. Fallback giờ đọc lại file ở mỗi lần `reload`.
- `ReplaceSiri` trước đó chỉ nuốt một allow-list ACE class. Một class đầu ra khác trên iOS 15 có thể lọt qua và Siri gốc vẫn trả lời. Chế độ Replace giờ chặn command thuộc lượt đã capture, chỉ khi cờ bật và `shouldHandleText` chấp nhận câu; Coexist vẫn gọi Siri gốc.
- Body template giao diện có placeholder `{{MESSAGES}}` nhưng code chưa thay placeholder này. Cả gửi thật và kiểm tra template giờ thay `{{SYSTEM}}`, `{{PROMPT}}`, `{{HISTORY}}`, `{{MESSAGES}}`, `{{MODEL}}`, đồng thời từ chối JSON template sai.
- `Kiểm tra kết nối` giờ dùng cùng endpoint/model/header/body template của cấu hình, hiển thị HTTP status/body và kết quả lỗi thật, không xoá trạng thái loading sau 300 ms cố định.
- Thêm `Tải danh sách model`: OpenAI-compatible dùng `GET /v1/models`, Ollama dùng `GET /api/tags`, Gemini dùng `GET /v1beta/models`; kết quả hiện picker và lưu model đã chọn. API key và custom headers được gửi cùng request.
- Root path lookup kiểm tra symbol `jbroot` đã load trước, sau đó thử các install location, tương thích API C `const char *jbroot(const char *)` của libroothide.
- Giá trị mặc định system prompt/native keywords trong UI và engine được đồng bộ để UI không hiển thị mặc định khác hành vi chạy.

## Tài liệu API tham khảo

- roothide Developer API mô tả C API `const char* jbroot(const char*)` và chuyển đổi giữa đường dẫn jbroot/rootfs: <https://github.com/roothide/Developer/blob/main/interface.md>
- Header và implementation của libroothide: <https://github.com/roothide/libroothide/blob/main/roothide.h> · <https://github.com/roothide/libroothide/blob/main/jbroot.c>
- OpenAI List models: `GET /v1/models`, Bearer authentication, trả `data[].id`: <https://platform.openai.com/docs/api-reference/models/list>
- Ollama List models: `GET http://localhost:11434/api/tags`, trả `models[].name`: <https://docs.ollama.com/api/tags>
- Siri ACE capture/replace selectors trong repo được đối chiếu với iOS 15.5 runtime headers; selectors là private API, vì vậy phải xác minh trên đúng iOS build/jailbreak — không thể suy ra khả năng chạy thiết bị chỉ từ build thành công.

## Giới hạn cần biết

- Model list endpoint không phải chuẩn chung; provider/proxy có thể không hỗ trợ `GET /models`. Trường hợp đó báo HTTP response để cấu hình model thủ công.
- HTTP trên LAN có thể bị App Transport Security của iOS chặn. Dùng HTTPS tunnel/reverse proxy hoặc cấu hình ATS phù hợp trên môi trường jailbreak; không nên mặc định mở arbitrary HTTP cho toàn thiết bị.
- Việc build/verify `.deb` không thay thế test bằng Type to Siri, Siri giọng nói và log trên máy thật. Nếu command selector/class khác giữa các bản iOS 15 thì cần thu log/class thực tế để bổ sung adapter có kiểm chứng.
