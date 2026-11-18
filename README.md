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
- **Log gỡ lỗi đầy đủ, sao chép được** — gửi lại cho mình để cải thiện tweak từng bước.

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

Log nằm tại: `/var/mobile/Library/Logs/SiriX.log` (tự xoay vòng ở 512 KB, có `.old`).

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

- Mọi hook đều **bọc kiểm tra runtime**: thiếu class/selector là bỏ qua và ghi log, không crash.
- Mọi đường lỗi đều **fail-safe về Siri gốc** — SiriX hỏng thì Siri vẫn chạy bình thường.

## Build cục bộ (tùy chọn)

CI là đường build chính (macOS + Xcode trên GitHub Actions). Muốn kiểm tra code trước khi push, trên Linux:

```bash
pip install --break-system-packages ziglang     # trình biên dịch ObjC
git clone --depth 1 https://github.com/theos/theos /tmp/theos-check
cd /tmp/theos-check && git submodule update --init vendor/logos vendor/include
git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks /tmp/sdks
cd /tmp/sdks && git sparse-checkout set iPhoneOS15.6.sdk

./scripts/local-check.sh    # Logos → compile toàn bộ (aarch64-ios, -Werror) → validate plist
```

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
