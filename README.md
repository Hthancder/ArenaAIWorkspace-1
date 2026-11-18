# SiriX ⚡

**Trợ lý AI trả lời ngay trong giao diện Siri gốc** — hỗ trợ iOS 15, cả **rootless** lẫn **roothide**.
Nhà cung cấp: **OpenAI tương thích** (mặc định) hoặc **Google Gemini**. Toàn bộ giao diện cài đặt bằng **Tiếng Việt**.

> SiriX lắng nghe câu hỏi của bạn qua Siri, gửi sang AI, rồi **thay câu trả lời ngay tại chỗ** — Siri vẫn phát giọng nói, hiển thị giao diện y như gốc. Các tác vụ hệ thống (báo thức, mở app, gọi điện…) vẫn do Siri gốc đảm nhiệm nên luôn ổn định.

---

## Tính năng

- **Trả lời bằng AI trong UI Siri gốc** — không cửa sổ phụ, không sao chép tay.
- **2 nhà cung cấp**: OpenAI tương thích (tự đổi địa chỉ API — dùng được mọi endpoint `/v1/chat/completions`) và Gemini.
- **2 chế độ trả lời**
  - *Thông minh (mặc định)*: AI trả lời câu hỏi tri thức; tác vụ hệ thống để Siri gốc xử lý.
  - *Thay thế mọi câu trả lời*: AI thay toàn bộ phản hồi của Siri.
- **Công cụ AI**: thông tin thiết bị, bảng nhớ tạm, đọc trang web (https), xóa lịch sử — bật/tắt từng cái.
- **Hội thoại có ngữ cảnh** (giữ N cặp câu hỏi/trả lời gần nhất), nhiệt độ, thời gian chờ đều chỉnh được.
- **Prompt tùy chỉnh** (để trống = dùng prompt mặc định).
- **Tiền tố @ai** tùy chọn, xem câu Siri gốc, và trò chuyện thử trong Settings.
- **Log gỡ lỗi đầy đủ, sao chép được** — gửi lại cho mình để cải thiện tweak từng bước.

> Tình trạng so với thiết kế v1.2, bao gồm các phần chưa triển khai: [docs/IMPLEMENTATION-STATUS.md](docs/IMPLEMENTATION-STATUS.md).

## Yêu cầu

- iOS **15.0 – 16.x** (thiết kế & thử nghiệm chính trên 15; 16 là mức hỗ trợ thêm)
- Jailbreak **rootless** (Dopamine…) hoặc **roothide**, có **PreferenceLoader**
- Một khóa API của OpenAI tương thích hoặc Gemini

## Cài đặt

1. Mở repo này trên GitHub → tab **Actions** → chạy mới nhất của workflow **Build SiriX**.
2. Chờ 2 job **rootless** / **roothide** hoàn tất (vài phút).
3. Vào run đó → mục **Artifacts** → tải `SiriX-rootless` hoặc `SiriX-roothide` (chọn đúng scheme jailbreak của bạn) → cài `.deb` bằng tweak installer quen thuộc.

Mỗi lần push code, CI tự build lại cả 2 gói.

## Cấu hình nhanh

1. **Cài đặt → SiriX**
2. *Nhà cung cấp & API*: chọn nhà cung cấp → dán **Khóa API** (mặc định dùng `gpt-4o-mini`; Gemini mặc định `gemini-2.0-flash`).
3. Bấm **Kiểm tra kết nối API** (mục *Gỡ lỗi*) — thấy “✓ Hoạt động” là xong.
4. Bật **Bật SiriX** rồi thử: *“Hey Siri, …”* hoặc Type-to-Siri.

## Gửi log gỡ lỗi (quan trọng ⭐)

Khi có gì đó chưa đúng (Siri không trả lời bằng AI, trả lời chậm, lỗi khóa API…):

1. **Cài đặt → SiriX → Gỡ lỗi → Xem & sao chép log**
2. Bấm **Sao chép** → gửi toàn bộ nội dung đó lại cho mình.

Log ghi mọi bước: hook nào đã cài / thiếu, câu hỏi bắt được từ đâu, lệnh ACE nào đến, quyết định thay thế hay cho qua, request AI (URL, model, số message — **không bao giờ ghi khóa API đầy đủ**), thời gian chờ, lỗi chi tiết. Nhờ log đó mình sẽ chỉnh đúng chỗ thay vì đoán.

Log nằm tại: `/var/mobile/Library/Logs/SiriX.log` (kiểm tra xoay vòng khi tiến trình khởi động nếu vượt 512 KB, có `.old`). Xóa log cũng xóa bản `.old`; các dòng mới tiếp tục được ghi mà không cần respring. Log có thể chứa nội dung câu hỏi và URL: hãy kiểm tra thông tin riêng tư trước khi chia sẻ.

## Cách hoạt động (ngắn gọn)

```
Siri nghe câu hỏi ──► AFConversation.addItemForSpeechRecognizedCommand:   (bắt câu hỏi)
                      AFConnection.startRequestWithText:                   (Type-to-Siri)
        │
        ▼
   SXIntercept ──► SXLLM (OpenAI/Gemini, có công cụ) ──► đáp án sẵn sàng
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
- Chế độ thay thế mặc định hiển thị thông báo khi hết giờ; tùy chọn **giữ Siri gốc** vẫn cố ý cho phản hồi gốc đi qua. Chờ trên luồng ACE tối đa 5 giây; đáp án đến sau khi đã quyết định hết giờ không tự hiện lại.

## Build cục bộ (tùy chọn)

CI là đường build chính (macOS + Xcode trên GitHub Actions). Muốn kiểm tra code trước khi push, trên Linux:

```bash
pip install --break-system-packages ziglang     # trình biên dịch ObjC
git clone --depth 1 https://github.com/theos/theos /tmp/theos-check
cd /tmp/theos-check && git submodule update --init vendor/logos vendor/include
git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks /tmp/sdks
cd /tmp/sdks && git sparse-checkout set iPhoneOS15.6.sdk

./scripts/local-check.sh    # Logos → compile toàn bộ (aarch64-ios, -Werror) → validate plist
./scripts/test-log-file.sh  # regression xóa/xoay vòng log (Linux/macOS)
```

Trên macOS, `./scripts/test-intercept-macos.sh` chạy thêm regression của state machine với ACE/LLM giả. CI chạy cả hai bộ test. Chúng không thay thế việc thử Siri trên thiết bị thật.

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

Cài đặt có lỗi? Gửi **log** (hướng dẫn ở trên) + mô tả câu bạn đã hỏi + model đang dùng. Có log là mình sửa được ngay.
