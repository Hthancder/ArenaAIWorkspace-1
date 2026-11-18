# SiriX ⚡

**Trợ lý AI trả lời ngay trong giao diện Siri gốc** — hỗ trợ iOS 15, cả **rootless** lẫn **roothide**.
Chọn **OpenAI** (mặc định), **Groq**, **Google Gemini** hoặc **Tự chỉnh** (API tương thích OpenAI). Toàn bộ giao diện cài đặt bằng **Tiếng Việt**.

> SiriX lắng nghe câu hỏi của bạn qua Siri, gửi sang AI, rồi **thay câu trả lời ngay tại chỗ** — Siri vẫn phát giọng nói, hiển thị giao diện y như gốc. Các tác vụ hệ thống (báo thức, mở app, gọi điện…) vẫn do Siri gốc đảm nhiệm nên luôn ổn định.

---

## Tính năng

- **Trả lời bằng AI trong UI Siri gốc** — không cửa sổ phụ, không sao chép tay.
- **Cấu hình theo nhà cung cấp**: OpenAI, Groq và Gemini dùng địa chỉ chính thức. Chỉ **Tự chỉnh** có ô địa chỉ HTTPS (API `/chat/completions`).
- **2 chế độ trả lời**
  - *Thông minh (mặc định)*: AI trả lời câu hỏi tri thức; tác vụ hệ thống để Siri gốc xử lý.
  - *Thay thế mọi câu trả lời*: AI thay toàn bộ phản hồi của Siri.
- **Công cụ AI**: thông tin thiết bị, bảng nhớ tạm, đọc URL HTTPS có trong câu hỏi, ngữ cảnh ứng dụng (tùy chọn). Xóa lịch sử trong Cài đặt.
- **Hội thoại có ngữ cảnh** (giữ N cặp câu hỏi/trả lời gần nhất), lịch sử lưu trên máy, thống kê, nhiệt độ và thời gian chờ đều chỉnh được.
- **Riêng tư**: Không lưu lịch sử giữ lượt mới trong bộ nhớ và tắt tool/thông báo trễ, nhưng vẫn dùng API AI. **Chỉ dùng Siri gốc** chặn mạng của SiriX, không thay đổi luồng Apple. Lịch sử/log cũ phải xóa riêng.
- **Prompt tùy chỉnh** (để trống = dùng prompt mặc định).
- **Tiền tố @ai** tùy chọn, xem câu Siri gốc, và trò chuyện thử trong Settings.
- **Log gỡ lỗi đầy đủ, sao chép được** — gửi lại cho mình để cải thiện tweak từng bước.

> **Nhánh v1.2:** bổ sung nhận diện và dịch tùy chọn, giọng đọc Hệ thống/Google Cloud/Gemini/Tự chỉnh, model dự phòng, lưu câu trả lời đến muộn, và xuất/nhập cấu hình. STT mặc định tắt. [Tiến độ, các chế độ dự phòng và checklist kiểm thử thiết bị](docs/IMPLEMENTATION-STATUS.md). Chưa bump gói ổn định lên 1.2.0.

## Yêu cầu

- iOS **15.0 – 16.x** (thiết kế & thử nghiệm chính trên 15; 16 là mức hỗ trợ thêm)
- Jailbreak **rootless** (Dopamine…) hoặc **roothide**, có **PreferenceLoader**
- Một khóa API cho nhà cung cấp AI bạn chọn

## Cài đặt

1. Mở repo này trên GitHub → tab **Actions** → chạy mới nhất của workflow **Build SiriX**.
2. Chờ 2 job **rootless** / **roothide** hoàn tất (vài phút).
3. Vào run đó → mục **Artifacts** → tải `SiriX-rootless` hoặc `SiriX-roothide` (chọn đúng scheme jailbreak của bạn) → cài `.deb` bằng tweak installer quen thuộc.

Mỗi lần push code, CI tự build lại cả 2 gói.

## Cấu hình nhanh

1. **Cài đặt → SiriX**
2. Chọn **Nhà cung cấp** rồi mở trang **Cấu hình** xuất hiện ngay bên dưới. Với OpenAI, Groq hoặc Gemini, dán khóa API của nhà đó; có thể để mô hình mặc định hoặc nhập mô hình khác.
3. Nếu chọn **Tự chỉnh** (ví dụ OpenRouter hoặc proxy riêng), nhập địa chỉ HTTPS gốc và mã mô hình máy chủ hỗ trợ. Bấm **Kiểm tra kết nối** ngay trên trang vừa cấu hình.
4. Bật **Bật SiriX** rồi thử: *“Hey Siri, …”* hoặc Type-to-Siri.

Khóa, mô hình và giọng được lưu riêng theo nguồn. Khi đổi địa chỉ **Tự chỉnh**, SiriX xóa khóa gắn với địa chỉ cũ. Cấu hình OpenAI tương thích cũ được chuyển theo địa chỉ đã dùng (OpenAI, Groq hoặc Tự chỉnh); vẫn nhập được tệp JSON v1 và bản xuất mới che mọi khóa mặc định.

## Gửi log gỡ lỗi (quan trọng ⭐)

Khi có gì đó chưa đúng (Siri không trả lời bằng AI, trả lời chậm, lỗi khóa API…):

1. **Cài đặt → SiriX → Gỡ lỗi → Xem & sao chép log**
2. Bấm **Sao chép**, xem lại dữ liệu rồi chia sẻ các dòng liên quan.

Log chẩn đoán ghi trạng thái hook, nguồn bắt câu hỏi, quyết định thay/giữ, mã lỗi và thời gian. Mã hiện tại không ghi nguyên văn câu hỏi, địa chỉ API, đáp án hay kết quả công cụ.

Log nằm tại: `/var/mobile/Library/Logs/SiriX.log` (kiểm tra xoay vòng khi tiến trình khởi động nếu vượt 512 KB, có `.old`). Xóa log cũng xóa bản `.old`; các dòng mới tiếp tục được ghi mà không cần respring. Log của bản cũ có thể chứa nội dung câu hỏi hoặc URL: hãy kiểm tra thông tin riêng tư trước khi chia sẻ.

## Cách hoạt động (ngắn gọn)

```
Siri nghe câu hỏi ──► AFConversation.addItemForSpeechRecognizedCommand:   (bắt câu hỏi)
                      AFConnection.startRequestWithText:                   (Type-to-Siri)
        │
        ▼
   SXIntercept ──► SXLLM (nhà cung cấp đang chọn, có công cụ) ──► đáp án sẵn sàng
        │
Siri gốc trả lời ──► AFConnection._handleCommand:reply:                    (lệnh ACE đến)
        │               ├─ là tác vụ hệ thống  → cho qua, Siri gốc xử lý
        │               ├─ là AddViews/SayIt   → chờ đáp án (≤ timeout) rồi THAY tại chỗ
        │               └─ hết giờ             → giữ câu trả lời gốc (fail-safe)
        ▼
   Siri phát giọng nói / hiển thị câu trả lời AI — giao diện gốc, không đổi.
```

- Mỗi hook được kiểm tra class/selector lúc khởi động; selector không có sẽ được bỏ qua và ghi log. Các API Siri là API riêng của Apple nên cần xác minh trên từng thiết bị.
- Trong một lượt, AddViews và SayIt dùng cùng quyết định AI/lỗi/hết giờ; tác vụ hệ thống được ưu tiên khi đã nhận diện. Nếu không sửa được lệnh hoặc thiếu hook, Siri gốc vẫn có thể xuất hiện.
- Chế độ thay thế mặc định hiển thị thông báo khi hết giờ; tùy chọn **giữ Siri gốc** vẫn cố ý cho phản hồi gốc đi qua. Chờ trên luồng ACE tối đa 5 giây. Nếu bật lưu đáp án đến muộn, đáp án hợp lệ của lượt hiện tại được lưu trong Lịch sử khi không thể cập nhật bubble; banner phụ thuộc máy.

## Build cục bộ (tùy chọn)

CI là đường build chính (macOS + Xcode trên GitHub Actions). Muốn kiểm tra code trước khi push, trên Linux:

```bash
pip install --break-system-packages ziglang     # trình biên dịch ObjC
git clone --depth 1 https://github.com/theos/theos /tmp/theos-check
git -C /tmp/theos-check submodule update --init vendor/logos vendor/include
git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks /tmp/sdks
git -C /tmp/sdks sparse-checkout set iPhoneOS15.6.sdk

./scripts/local-check.sh    # Logos → compile toàn bộ (aarch64-ios, -Werror) → validate plist
./scripts/test-log-file.sh  # regression xóa/xoay vòng log (Linux/macOS)
```

Trên macOS, `./scripts/test-intercept-macos.sh` chạy regression với ACE/LLM giả, `./scripts/test-store-macos.sh` kiểm tra kho dữ liệu, và `./scripts/test-v12-macos.sh` dùng fixture cho di trú/xuất nhập, hiện/ẩn mục theo nguồn, địa chỉ/khóa thực sự dùng trong request, audio format và SSE. CI chạy các bộ test này; chúng không thay thế việc thử Siri trên thiết bị thật.

Build deb thật (cần macOS/theos): `make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless|roothide`.

## Cấu trúc repo

```
Sources/            tweak: Logos hooks, log, prefs, LLM, tools, state machine
Prefs/              bundle cài đặt (PSListController, xem log, soạn prompt) + header Preferences
layout/             entry PreferenceLoader
include/            header CydiaSubstrate (để build được ở cả CI lẫn máy cá nhân)
scripts/            local-check.sh — kiểm tra không cần macOS
docs/RESEARCH.md    toàn bộ nghiên cứu về SiriPlus & kiến trúc Siri iOS 15
.github/workflows/  build rootless + roothide, validate deb, upload artifact
```

## Nghiên cứu & ghi công

- Tính năng và mô hình sản phẩm tham khảo từ **SiriPlus** (uckermark) — nguồn gốc proprietary, chỉ nghiên cứu từ bên ngoài.
- Kỹ thuật hook lấy cảm hứng từ các tweak mở: **SiriAI**, **CustomSiri**, **Googiri**, **LiquidSiri**, **Quorra** (xem `docs/RESEARCH.md`).
- Không liên kết với Apple, OpenAI hay Google.

## Phản hồi

Cài đặt có lỗi? Gửi các dòng **log** đã kiểm tra thông tin riêng tư, model, iOS/scheme và một ca thử không chứa dữ liệu nhạy cảm.
