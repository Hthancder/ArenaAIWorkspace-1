# Nghiên cứu: SiriPlus & kiến trúc Siri trên iOS 15

Tài liệu này ghi lại **toàn bộ** những gì đã tìm hiểu trước khi viết SiriX: sản phẩm SiriPlus, cách Siri hoạt động trên iOS 15, các hook đã xác minh, những cái bẫy kỹ thuật (rootless/roothide), và các quyết định thiết kế kèm lý do.

---

## 1. SiriPlus là gì?

**SiriPlus** (tác giả *uckermark*, bán trên Havoc, **$4.99**) — tweak trả lời câu hỏi bằng AI (ChatGPT/Gemini/…) ngay trong giao diện Siri gốc.

### 1.1 Danh sách tính năng (tổng hợp từ trang Havoc, review Reddit, README các bản recon)

| Nhóm | Chi tiết |
|---|---|
| Trả lời AI | Chọn nhà cung cấp ChatGPT / Gemini / Managed; nhập API key; chọn model; chỉnh temperature; độ dài ngữ cảnh (slider, mặc định 1024) |
| Tác vụ thiết bị | Mở app, soạn email, thông tin hệ thống, lịch, danh bạ, gọi điện, dẫn đường, xóa ngữ cảnh — dạng “công cụ” cho AI gọi |
| Tích hợp Siri | Trả lời hiển thị & **được phát giọng nói** trong UI Siri gốc; bật/tắt từ Control Center; Type-to-Siri; Hey Siri |
| Hệ thống | Tương thích iOS 14.0 – 16.7.10, **rootless: có**, **roothide: không** |

### 1.2 Trạng thái roothide & phản hồi người dùng

- Trang Havoc ghi rõ **roothide NOT supported**; tác giả trên Reddit giải thích: *“roothide in general is not supported until they support libroot”* — tức gói còn phụ thuộc đường dẫn `/var/jb` cổ điển.
- Review tiêu biểu (Reddit r/jailbreak): bản 1.0 **chặn luôn câu trả lời gốc của Siri** (“completely kills usefulness of regular Siri”) vì cơ chế thay thế chưa hoàn thiện; bản sau mới vá dần.
- Nguồn code: **proprietary**. Bản recon “SiriPlus 1.4” trên GitHub (mekabrine/public) **thiếu** phần chặn/trình bày phản hồi — speech hook còn `%orig` nguyên vẹn nên Siri gốc vẫn trả lời đè lên. → **Không thể dùng làm nền tảng; phải thiết kế lại.**

**Kết luận:** SiriX làm lại từ đầu, học mô hình sản phẩm (feature set, UX) nhưng tự chọn kiến trúc kỹ thuật, ưu tiên: **hoạt động thật**, **không crash**, **iOS 15 rootless + roothide**, **log đầy đủ để cải tiến dần**.

---

## 2. Siri trên iOS 15 — luồng dữ liệu

Nguồn: Apple Wiki (AssistantUI áp cho SpringBoard/SiriViewService), dump runtime **yuzhouheike/iOS15.3.1-Runtime-Headers**, **lechium/iOS14Headers**, và các tweak đã chạy thật.

### 2.1 Process

- **iOS 13+**: UI Siri chạy trong **SpringBoard** (lớp `AFUISiriSession` / `AFUISiriViewController` của AssistantUI). `SiriViewService.app` chỉ còn giá trị tương thích; các tweak iOS 14–16 (LiquidSiri) vẫn inject kèm 4 bundle phòng hờ: `com.apple.springboard`, `com.apple.SiriViewService`, `com.apple.siri.SystemUI`, `com.apple.SiriUI`.
- **assistantd** là daemon xử lý nhận diện/ACE — **không hook** (quá xa, TCC/ sandbox). Toàn bộ hook của SiriX nằm phía client (SpringBoard).

### 2.2 Luồng câu hỏi (capture)

```
mic / Type-to-Siri
   → assistantd nhận diện xong
   → AFConnection (client trong SpringBoard) báo về
        • _tellSpeechDelegateSpeechRecognized:        ← kết quả cuối
        • (delegate) speechRecognized:
   → AFConversation.addItemForSpeechRecognizedCommand: ← chèn lời người dùng vào hội thoại
   → UI hiển thị câu hỏi
```

- **Type-to-Siri**: `AFConnection.startRequestWithText:` — văn bản gõ tay đi thẳng vào đây.
- Trích xuất văn bản: `af_bestTextInterpretation` (category có sẵn trên object nhận diện) → fallback chuỗi KVC `recognition.phrases[*].interpretations[*].tokens[*].text` (cách CustomSiri làm).
- Kết quả **partial** (`_tellSpeechDelegateSpeechRecognizedPartialResult:`) **không** hook — tránh bắt nhầm.

### 2.3 Luồng câu trả lời (replace)

```
assistantd gửi lệnh ACE về
   → AFConnection._handleCommand:reply:        ← ĐIỂM THAY THẾ CHÍNH (mọi lệnh đi qua đây)
   → AFConnectionClientServiceDelegate.requestDidReceiveCommand:reply:
   → AFConversation.addItemsForAddViewsCommand: ← chèn AddViews vào hội thoại (điểm dự phòng + log)
   → UI hiển thị & TTS đọc speakableText
```

Cấu trúc trả lời trên iOS 15 (xác minh từ header SAObjects):

| Lớp | Trường mang văn bản | Ghi chú |
|---|---|---|
| `SAUIAddViews` | `views` (mảng `SAAceView`), `dialogPhase`, `displayTarget`, `refreshCommand`, `requiresResponse`, `supplemental`, `temporary` | **không** có `dialogStrings` (chỉ còn ở bản iOS cũ / `SAPreSynthesizeTTS`) |
| `SAAceView` | `speakableText` (L20), `dialog`, `speakableContextInfo` | gốc của mọi view |
| `SAUIAssistantUtteranceView` | `text`, `af_speakableText`, `af_text`, `dialogIdentifier` | view “utterance” — thay 2 trường này là Siri nói câu mới |
| `SAUISayIt` | **`message`** (có `setMessage:`), `dialogIdentifier`, `canUseServerTTS`, `listenAfterSpeaking` | phương án thay thế thứ hai |

→ **Chiến lược**: giữ nguyên object, **mutate tại chỗ** (`setSpeakableText:` / `setText:` / `setMessage:`), ẩn thẻ web (`groupIdentifier == com.apple.ace.ui.card` hoặc tên lớp chứa `Card`) — không rebuild dictionary như bản iOS 7–9.

### 2.4 Bảng selector đã xác minh (dùng làm hợp đồng hook)

| Selector | Lớp | Nguồn | Trả về |
|---|---|---|---|
| `_handleCommand:reply:` | AFConnection | yuzouheike iOS15.3.1 L107 | `void` |
| `_tellSpeechDelegateSpeechRecognized:` | AFConnection | yuzouheike L166 | `void` |
| `_tellSpeechDelegateSpeechRecognizedPartialResult:` | AFConnection | yuzouheike L167 | `void` *(không hook)* |
| `startRequestWithText:` | AFConnection | yuzouheike L269 | `void` |
| `_markSpeechRecognized` | AFConnection | yuzouheike L112 | `void` |
| `_requestWillBeginWithRequestClass:…` (2 bản overload) | AFConnection | yuzouheike L116–117 | `void` *(log)* |
| `addItemForSpeechRecognizedCommand:` | AFConversation | yuzouheike | `void` |
| `addItemsForAddViewsCommand:` | AFConversation | yuzouheike | `void` |
| `requestDidReceiveCommand:reply:` / `requestHandleCommand:reply:` | AFConnectionClientServiceDelegate | yuzouheike L37–38 | `oneway void` |
| `speechRecognized:` | AFConnectionClientServiceDelegate | yuzouheike L45 | `oneway void` |
| `assistantConnection:receivedCommand:completion:` | AFUISiriSession | lechium iOS14 | `void` |
| `af_bestTextInterpretation` | category trên object nhận diện | dump iOS15 | `NSString*` |

Lưu ý ABI: **trả về `void`** nên hook an toàn (không làm hỏng giá trị trả về). Mọi selector đều được `class_getInstanceMethod` kiểm tra trước khi `%init`, thiếu thì ghi log “KHÔNG tìm thấy”.

---

## 3. Bẫy kỹ thuật đã ghi nhận (và cách SiriX đối phó)

| # | Bẫy | Nguồn | SiriX đối phó |
|---|---|---|---|
| 1 | **Roothide**: mọi đường dẫn jailbreak bị ngụy trang; ghi file kiểu cũ hỏng | qnblackcat/DePuke PR#1 | Chỉ dùng `CFPreferences` + đường dẫn **`/var/mobile/…`** (không nằm dưới `/var/jb`) cho prefs & log; không dùng `jbroot()` |
| 2 | Prefs phải reload được **không cần respring** | DePuke | Darwin notify `com.sirix.tweak/prefs.changed` — cả SpringBoard lẫn bundle Cài đặt đều đăng ký |
| 3 | Header Preferences **không còn** trong theos | theos/theos `include/` chỉ có `.keep` | Vendor `PSListController/PSSpecifier/PSViewController/PSTableCell.h` vào `Prefs/` |
| 4 | `CydiaSubstrate/CydiaSubstrate.h` không có trong theos/headers (chỉ còn shim) | thử build thật | Vendor header saurik (BSD-3, từ theos/orion) vào `include/CydiaSubstrate/` + `-I$(THEOS_PROJECT_DIR)/include` |
| 5 | Roothide **cần scheme kép** trong CI | qq1643240/injection-probe-theos | `THEOS_PACKAGE_SCHEME ?= rootless` (override được), workflow build cả `rootless` (theos/theos) và `roothide` (roothide/theos) |
| 6 | Kiến trúc gói roothide khác nhau giữa nguồn | DePuke (arm64) vs Eevee CI (arm64e) | CI **in Architecture** và chỉ chấp nhận `iphoneos-arm64|iphoneos-arm64e` — xem log job才知道 chính xác |
| 7 | Không có clang/ldid/Xcode cục bộ (Linux) | đo sandbox | Zig (clang frontend) + SDK theos/sdks → **compile toàn bộ ObjC -Werror cục bộ**; build deb thật trên GitHub Actions (macOS) |
| 8 | Release assets GitHub bị chặn trong sandbox | thử tải toolchain/SDK | Clone git (theos, theos/sdks sparse) thay vì tải tarball |
| 9 | Blocking main/XPC thread chờ AI | SiriAI (production) làm tương tự | Chờ **CÓ GIỚI HẠN** (2–15 s, mặc định 6) + **fail-safe về Siri gốc**; chỉ chờ khi thật sự có câu hỏi đang mở |
| 10 | Nhiều capture point trùng | thiết kế | Dedupe theo văn bản chuẩn hóa trong **2,5 s** — chỉ câu đầu tiên gửi AI |

---

## 4. Quyết định thiết kế SiriX

1. **Không suppress lệnh gốc.** Chỉ thay văn bản của `AddViews`/`SayIt`. Lệnh tác vụ (`Alarm/Timer/Call/Message/…`) đi qua nguyên vẹn → không bao giờ “Siri chết” như v1.0 của SiriPlus.
2. **Chế độ Thông minh (mặc định)**: nếu trong trao đổi có lệnh tác vụ → **giữ** câu trả lời gốc (Siri tự nói “Đã đặt báo thức…”); chỉ câu hỏi tri thức mới bị thay bằng AI. Chế độ **Thay thế tất cả** cho người muốn full (prompt đã dặn AI xác nhận tác vụ ngắn gọn).
3. **Chờ đáp án tại điểm vào lệnh** (`_handleCommand:reply:`), không canh ở UI insertion — sớm nhất có thể, vẫn kịp trước khi UI render; `addItemsForAddViewsCommand:` là **lưới an toàn thứ hai** (semantics consume-once nên hai điểm không xung đột).
4. **State machine dùng `NSCondition` + generation**: câu hỏi mới vô hiệu hóa đáp án cũ; waiter cũ thức dậy thấy gen khác là thoát; timeout/đã-consume đều cho qua — không bao giờ treo vĩnh viễn.
5. **LLM**: NSURLSession, loop công cụ tối đa 4 vòng, prompt tiếng Việt mặc định (ngắn gọn, không markdown, khớp ngôn ngữ câu hỏi). OpenAI: `chat/completions` + `tool_calls`; Gemini: `generateContent` + `functionDeclarations` (schema tự đổi `type` IN HOA).
6. **Công cụ**: `system_info`, `clipboard`, `fetch_url` (https, cắt HTML ≤ 3500 ký tự), `reset_conversation`. **Không** làm công cụ danh bạ/lịch/gọi — TCC từ SpringBoard không ổn định, và Siri gốc đã làm tốt (xem mục 1).
7. **Log là sản phẩm**: 6 category (`boot/hook/capture/resp/llm/tool/pref/err`), mỗi dòng có timestamp ms + process, ghi `O_APPEND` một lần write (an toàn đa-process), tự xoay 512 KB, song song `os_log` để xem Console.app. Khóa API chỉ ghi dạng `sk-…abcd (51 ký tự)`.

## 5. Kế hoạch cải tiến qua debug log (vòng lặp với người dùng)

| Triệu chứng trong log | Hành động sửa |
|---|---|
| `AFConnection._handleCommand:reply: KHÔNG tìm thấy` | chuyển điểm thay thế sang `addItemsForAddViewsCommand:` / delegate |
| Capture đến mà `resp` không bao giờ thấy `AddViews` | thêm hook `requestDidReceiveCommand:reply:` (delegate) |
| Lệnh tác vụ bị nhận nhầm là trả lời (class lạ) | thêm vào danh sách `SXIsActionClass` — log đã ghi tên class đầy đủ |
| Timeout liên tục | tăng timeout mặc định / tối ưu prompt ngắn hơn / prefetch sớm hơn |
| `HTTP 401/404` | hướng dẫn key/URL đúng từng provider (test connection đã có sẵn) |
| Siri nói 2 lần (câu gốc + AI) | tìm nguồn phát câu thứ hai (SayIt lẻ) → consume-once mở rộng |

## 6. Nguồn tham khảo chính

- havoc.app/package/siriplus — trang bán hàng, tính năng, compat.
- reddit.com/r/jailbreak/comments/1b5mac1/ — review & phát ngôn về roothide.
- github.com/mekabrine/public — recon SiriPlus 1.4 (thiếu phần suppress — chỉ tham khảo).
- github.com/yuzhouheike/iOS15.3.1-Runtime-Headers — `PrivateFrameworks/AssistantServices.framework/{AFConnection,AFConnectionClientServiceDelegate,AFConversation}.h`, dump SAObjects (`SAUIAddViews`, `SAUISayIt`, `SAAceView`, `SASSpeechRecognized`…).
- github.com/lechium/iOS14Headers — `AFUISiriSession.h`.
- github.com/tr3tol/SiriAI — production hook AFConversation + chờ pthread, pattern prefs (đã copy vào `research/SiriAI/`).
- github.com/squ1dd13/CustomSiri — mutate ACE object trước `%orig`.
- github.com/shrugs/Googiri — `startRequestWithText:` để inject Type-to-Siri.
- github.com/Thijs2004/LiquidSiri — 4-bundle filter iOS 14–16.
- github.com/banaisakula/AllTweakSource (Quorra) — `AFUISiriSession` lifecycle.
- github.com/qnblackcat/DePuke PR#1, qq1643240/injection-probe-theos, SideloadLabs/EeveeSpotifyReincarnated, writing11/VCamInject — công thức build rootless/roothide + CI kép.
- github.com/theos/{theos,sdks,headers,logos}, roothide/theos — hạ tầng build.
- github.com/uroboro/PSSpecifiers, tr3tol/SiriAI/Root.plist, theos/headers PSSpecifier.h — specifier keys chuẩn (`validValues/validTitles`, `showValue`, `PostNotification`, `keyboard`, `autoCaps`…).
