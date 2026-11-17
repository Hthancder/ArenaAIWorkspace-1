# Kiến trúc SiriBridge

## 1. Luồng một lượt hỏi-đáp

```
người dùng nói "Hey Siri, thời tiết Hà Nội?"
        │
        ▼
SpringBoard: SiriActivation  →  present SiriViewService (UI)
        │
        ▼
[hook] AFUISiriSession -assistantConnectionRequestWillStart:
        → reset state, dedup
        │
        ▼  assistantd nhận dạng xong (ASR)
[hook] AFUISiriSession -assistantConnection:speechRecognized:
        → SBCaptureTextFromSpeechRecognized()  → "thời tiết Hà Nội"
        → SBConfig shouldHandleText: (prefix / native keywords)?
        │  có
        ▼
assistantd gửi SAUIAddViews / SAUISayIt (câu trả lời của Siri)
        │
[hook] AFUISiriSession -assistantConnection:receivedCommand:completion:
        → Replace mode?  → KHÔNG gọi %orig  (chặn UI + TTS của Siri)
        → gọi completion(SACommandSucceeded) để state machine không treo
        → SBEngine handleTurnWithText:  (chỉ 1 lần / câu)
        │
        ▼
SBEngine
  ├─ hiện "…" (SAUIAddViews, dialogPhase Reflected)
  ├─ SBLLM ask:  (endpoint tuỳ chỉnh)
  ├─ nếu có tool_call → SBTools runTool → hỏi lại LLM để nói tự nhiên
  ├─ SBHistory addAssistant
  ├─ SAUIAddViews (dialogPhase Completion) → SBDeliverCommand(delegate, …)
  └─ SBTTS speak: (AVSpeechSynthesizer hoặc endpoint) → completion
        → (tuỳ chọn) dismissAfterAnswer → [session end]
```

## 2. Vì sao chặn ở `receivedCommand:completion:`

Xem `docs/01-how-siri-works-ios15.md` §2.1. Tóm tắt:

* Đây là **cửa duy nhất** mọi ACE từ `assistantd` đi qua để vào UI.
* Không gọi `%orig` ⇒ Siri không có dữ liệu để hiển thị hay đọc.
* `completion` **phải** được gọi, nếu không `SRUIFStateMachine` kẹt ở
  "thinking/working" và Siri treo (không nhận câu tiếp theo).

## 3. Vì sao cần `SBDeliver`

Để hiển thị câu trả lời của mình, ta gọi thẳng delegate:

```objc
[delegate siriSessionDidReceiveAddViewsCommand:addViews completion:^(id ack){ … }];
```

Hook lưới an toàn trên `SRSiriViewController` cũng chặn `AddViews` có text thật,
vì vậy phải có cờ `SBDeliverIsOwnInjection()` để nó **không chặn câu của chính ta**.
Cờ này bật quanh lời gọi delegate và khôi phục sau đó (kể cả khi exception).

## 4. Trạng thái & luồng (thread-safety)

| Biến | Nơi | Bảo vệ |
|---|---|---|
| `gTurnText`, `gSink` | SBCapture | `NSLock` |
| `_turn`, `_cancelled` | SBEngine | chỉ dùng trên main queue (mọi callback của LLM/TTS đều `dispatch_async(main)`) |
| `gOwnInjection` | SBDeliver | cờ đơn luồng, chỉ set/restore đồng bộ quanh objc_msgSend |
| `SBDedupText` | Tweak.x | chỉ chạm trên delegate queue của AFUISiriSession |

`AFUISiriSession` gọi callback trên `_delegateQueue` (serial) → hook chạy tuần tự.
Mạng/TTS chạy nền, kết quả quay về main queue.

## 5. Chống trùng lặp

Một câu có thể sinh **nhiều** command (AddViews + SayIt + PreSynthesizeTTS…).
Ta chỉ muốn khởi động LLM một lần:

1. `SBClaimText(text)` — lưu text đã xử lý, reset ở `assistantConnectionRequestWillStart:`
   (hoặc khi `end`).
2. `SBEngine busy` — nếu một lượt đang chạy thì bỏ qua.

## 6. Coexist mode

`ReplaceSiri = NO`:

* hook `receivedCommand:` luôn gọi `%orig` → Siri trả lời như thường;
* tweak vẫn bắt được text (log, lịch sử) nhưng **không** bơm UI/TTS.

Dùng để thử nghiệm an toàn trước khi bật Replace.

## 7. Những gì KHÔNG hook

| Thành phần | Lý do |
|---|---|
| `assistantd` | hook sai → daemon chết, Siri hỏng, mất ASR. Không cần. |
| `SiriActivation` / SpringBoard activation | giữ nguyên để "Hey Siri", nút nguồn, tai nghe vẫn hoạt động. |
| `AFConnection` | có thể dùng `sendGenericAceCommand:` nhưng phức tạp hơn và dễ sai state; chỉ cần cho streaming sau này. |
| `VSSpeechSynthesizer` / `SRTTSManager` | không cần vì ta tự phát audio; chạm vào dễ gây im tiếng Siri (báo thức, cuộc gọi). |

## 8. Đường phát triển tiếp

| Việc | Cách làm |
|---|---|
| Streaming | SSE từ endpoint; mỗi chunk gọi `siriSessionDidReceiveUpdateViewsCommand:` hoặc `SAUIAddViews` với `temporary=YES` |
| Chat view riêng | `UIWindow` (SiriBridge đã có sẵn hook SpringBoard) + `UITableViewController` hiển thị `SBHistory` |
| Nhiều profile endpoint | lưu mảng dict trong prefs, chọn theo prefix ("dịch:", "code:"…) |
| Dịch/ghi chú ngắn | tool `save_note` + `NSUserActivity` |
| Voice tự host | TTSMode 1 + Piper server (`POST /api/tts`) |
| arm64e / iOS 16 | thêm `arm64e` vào `ARCHS`, test lại các selector (đổi tên giữa 15↔16) |
