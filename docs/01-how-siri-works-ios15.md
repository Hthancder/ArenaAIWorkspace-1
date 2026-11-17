# Cách Siri hoạt động trên iOS 15 (arm64, rootless) — ghi chú nghiên cứu

Tài liệu này là nền tảng kỹ thuật cho tweak **SiriBridge**. Toàn bộ thông tin lấy từ:

* bộ header runtime **iOS 15.5** (dump class-dump-c) — `lechium/iPhone_OS_15.5`;
* bộ header iOS 16.5 (đối chiếu chéo, `359266613/AiSiri`);
* các bài phân tích công khai về SiriPlus (chỉ để hiểu *hành vi*, không dùng code của họ).

## 1. Kiến trúc tổng thể

Siri không phải một app. Nó là một chuỗi tiến trình + framework private:

```
               ┌──────────────────────────── SpringBoard (UI host) ───────────────────────────┐
   "Hey Siri"  │ SiriActivation  →  SiriLongPressButtonSource / SiriHearst…                   │
   / nút nguồn │        │                                                                     │
   / tai nghe  │        ▼                                                                     │
               │ SASActivationRequest → SiriPresentationViewController (SiriUIActivation)     │
               │        │  (chứa AFUISiriViewController, vẽ UI, orb, blur)                     │
               └────────┼─────────────────────────────────────────────────────────────────────┘
                        │ NSXPC (view service / remote view controller)
               ┌────────▼──────── Applications/Siri (SiriViewService.app, "SR*" classes) ─────┐
               │  SRSiriViewController / SRCompactViewController  →  transcript UI            │
               │  SRTTSManager, SRPreSynthesisTask  →  TTS (VoiceServices)                    │
               │  AFUISiriSession  (AssistantUI.framework)  ← "bộ não" phía client            │
               └────────┬─────────────────────────────────────────────────────────────────────┘
                        │ AFConnection (AssistantServices.framework) — XPC tới daemon
               ┌────────▼──────────────── usr/libexec/assistantd ─────────────────────────────┐
               │  AD*  classes: audio, ASR (CoreSpeech/SiriCore), dialog 管理, ACE             │
               │  SiriCoreConnection → HTTPS tới Apple (guzzoni / "ServerDrivenDialog")       │
               └──────────────────────────────────────────────────────────────────────────────┘
                        │
                        ▼  Apple cloud (Guzzoni) — trả về ACE JSON (SAUIAddViews, SAUISayIt…)
```

Các tiến trình liên quan trên iOS 15:

| Tiến trình / bundle | Vai trò | Có inject được không |
|---|---|---|
| `com.apple.springboard` | kích hoạt Siri, present view service | ✅ (tweak filter) |
| `com.apple.SiriViewService` (`/Applications/Siri.app`) | UI Siri + `AFUISiriSession` | ✅ (tweak filter) |
| `com.apple.assistantd` (`/usr/libexec/assistantd`) | ASR, dialog, mạng | ⚠️ được, nhưng daemon có entitlement riêng và rất dễ panic nếu hook sai; **SiriBridge không chạm vào đây** |
| `com.apple.siriactionsd`, `siriinferenced` | intent / Shortcuts | không cần |
| `com.apple.voiceservices` / `speechsynthesisd` | TTS engine | ❌ (chỉ chạm nếu tự làm engine) |

**Kết luận thực dụng:** mọi tweak kiểu SiriPlus đều chỉ cần inject `SpringBoard` + `SiriViewService` và nói chuyện ở tầng `AFUISiriSession` / `AFUISiriSessionDelegate`.

## 2. `AFUISiriSession` — trái tim của phần UI

`AssistantUI.framework`, class `AFUISiriSession` (iOS 15.5, 1 instance / 1 phiên Siri).
Nó là `AFAssistantUIService` + `AFSpeechDelegate`, tức là nó nhận **mọi callback từ `AFConnection`** và chuyển tiếp cho `delegate` (thường là `SRSiriViewController`).

Các nhóm method quan trọng (nguyên văn từ header 15.5):

**Vòng đời / request**
```objc
- (void)assistantConnectionRequestWillStart:(id)connection;
- (void)startRequestWithOptions:(id)options completion:(void (^)(NSError *))completion;
- (void)startCorrectedRequestWithText:(NSString *)text correctionIdentifier:(id)corr
                  userSelectionResults:(id)res turnIdentifier:(NSUUID *)turn;
- (void)stopRequestWithOptions:(id)options;
- (void)end;
- (void)endForReason:(long long)reason;
```

**Nhận dạng giọng nói (đầu vào)**
```objc
- (void)assistantConnection:(id)c speechRecognized:(id)recognized;          // SASSpeechRecognized cuối cùng
- (void)assistantConnection:(id)c speechRecognizedPartialResult:(id)partial; // SASSpeechPartialResult
- (void)assistantConnectionSpeechRecordingDidEnd:(id)c;
- (void)assistantConnection:(id)c recognitionUpdateWithPhrases:(id)p utterances:(id)u refId:(id)r;
```

**Nhận lệnh từ server (đầu ra)**
```objc
- (void)assistantConnection:(id)c receivedCommand:(id)command
                 completion:(void (^)(id))completion;      // ← điểm nghẽn DUY NHẤT của mọi ACE
- (void)performAceCommand:(id)cmd turnIdentifier:(NSUUID *)turn;
- (void)_performAceCommand:(id)cmd turnIdentifier:(id)turn conflictHandler:(id)handler;
- (void)_performAceCommands:(id)cmds;
- (void)_performBlockWithDelegate:(id)block;                  // dispatch nội bộ sang delegate queue
```

**TTS / trạng thái**
```objc
- (void)speechSynthesisDidFinish:(id)record;
- (void)speechSynthesisDidUpdatePowerLevelTo:(float)lvl;
- (void)notifyStateManagerSpeakingBegan; / ...Ended;
- (void)forceAudioSessionActive; / -forceAudioSessionInactive;
- (void)cancelSpeechRequest;
```

### 2.1 Vì sao `receivedCommand:completion:` là điểm mấu chốt

Mọi thứ Apple cloud trả về đều là **ACE object** và đi qua đúng một cửa:

```
assistantd  --XPC-->  AFConnection
                         │  _handleCommand:reply:
                         ▼
              AFAssistantUIService (AFUISiriSession)
                         │  assistantConnection:receivedCommand:completion:
                         ▼
              _performAceCommand:turnIdentifier:conflictHandler:
                         │  _performBlockWithDelegate:
                         ▼
              AFUISiriSessionDelegate  (SRSiriViewController)
                         │  siriSessionDidReceiveAddViewsCommand:completion:
                         ▼
              SRUIFConversation → transcript UI → SRTTSManager → VoiceServices (TTS)
```

Nếu chặn ở `receivedCommand:` (không gọi `%orig`) thì **Siri im lặng hoàn toàn**: không UI, không TTS, không hành động. Đó chính là cách thay thế Siri trọn vẹn.

Nếu chỉ *thêm* một `SAUIAddViews` tổng hợp (như AiSiri làm) thì UI Siri cũ vẫn chạy → hai câu trả lời chồng nhau. SiriBridge chọn cách **chặn** (chế độ *Replace*), có tuỳ chọn *Coexist* cho ai muốn giữ Siri.

### 2.2 Đường vòng qua delegate (dùng để *bơm* câu trả lời)

Ta cần đưa câu trả lời của LLM vào UI + TTS **mà không** đi qua `assistantd` (vì `assistantd` sẽ gửi lên Apple). Hai cách hợp lệ:

1. **Gọi delegate trực tiếp** (khuyến nghị):
   ```objc
   SAUIAddViews *addViews = [SAUIAddViews addViews];
   addViews.dialogPhase = @"Completion";     // SRUIFDialogPhase: Completion / Reflected / Summary…
   addViews.views = @[utteranceView];
   addViews.supplemental = NO; addViews.temporary = NO;

   SAUIAssistantUtteranceView *v = [SAUIAssistantUtteranceView assistantUtteranceView];
   v.text = answer;
   v.dialogIdentifier = turnUUIDString;
   // speakableText trên SAAceView là cái SRTTSManager đem đi TTS
   v.speakableText = answer;
   v.canUseServerTTS = NO;       // ép dùng TTS trên máy

   [delegate siriSessionDidReceiveAddViewsCommand:addViews completion:^(id ack){...}];
   ```
   `completion` phải được gọi, nếu không session treo ở state “thinking”.

2. **Gửi ngược vào `AFConnection`** (`sendGenericAceCommand:`) — chỉ dùng khi cần mô phỏng trao đổi 2 chiều; nặng và dễ sai state machine.

### 2.3 Nói bằng audio tự tạo (TTS tuỳ chỉnh / file wav)

`SAUISayIt` có `audioData` (`SAUIAudioData`: `audioBuffer` = NSData PCM/opus, `decoderStreamDescription`, `playerStreamDescription`) và `audioDataUrl`. Tức là **có sẵn đường chính chủ để phát audio không do Apple tổng hợp**.

Hai lựa chọn cho “không bị giọng Siri gốc ràng buộc”:

* **A. TTS trên máy (offline, mặc định của SiriBridge)** — `AVSpeechSynthesizer` với `AVSpeechSynthesisVoice` bất kỳ đã cài (kể cả giọng Enhanced/Premium, hoặc voice của app khác). Không cần mạng, không tốn tiền, không phụ thuộc Apple TTS daemon. SiriBridge tự quản `AVAudioSession` category `.playAndRecord` + `.duckOthers`.
* **B. TTS từ endpoint** (OpenAI `/v1/audio/speech`, ElevenLabs, Azure, Piper tự dựng…) — tải mp3/wav → decode sang PCM → phát, **hoặc** nhét vào `SAUIAudioData` để chính Siri UI phát (giữ nguyên hiệu ứng orb “đang nói”).
* **C. Giọng Siri nhưng khác voice** — set `AFPreferences.outputVoice` / dùng `AFVoiceInfo` (xem §4). Vẫn là giọng Apple nhưng không nhất thiết là giọng mặc định.

SiriBridge hỗ trợ cả A, B (và C chỉ như tuỳ chọn “native voice”).

## 3. Đầu vào: từ giọng nói tới text

`AFSpeechRecognition` → `phrases[].interpretations[].tokens[]`, và trên `SASSpeechRecognized` có `recognition.utterances[]` (`SASUtterance.text`). Trong thực tế, cách lấy text ổn định nhất:

```objc
// recognized là SASSpeechRecognized (ACE)
NSString *text = nil;
for (id u in [[recognized recognition] utterances]) {
    if ([u respondsToSelector:@selector(text)]) { text = [u text]; break; }
}
// fallback: phrases[0].interpretations[0].tokens → ghép .text
```

AiSiri có sẵn module `AxsAiSiriTranscript` làm đúng việc này — SiriBridge có bản tương đương `SBCapture.m`.

**Type-to-Siri** còn dễ hơn: text nằm trong `SASRequestOptions.text` khi `startRequestWithOptions:` được gọi, hoặc trong `assistantConnection:startUIRequestWithText:completion:`.

## 4. “Giọng nói gốc của Siri” bị ràng buộc ở đâu

Ba tầng khoá:

1. **`AFPreferences.outputVoice`** (`AFVoiceInfo`: languageCode/gender/name/footprint/isCustom). Trong Settings chỉ hiện các voice Apple đã tải.
2. **`SRTTSManager`** (`Applications/Siri`) — chọn `VSSpeechSynthesizer`, set `voice`, `language`, `rate`, gọi `startSpeakingRequest:` (`VSSpeechRequest`). Nó **có nhận** `VoiceServices` resource URL tuỳ biến (`customResourceURLs`, `resourceListURL`, `resourceSearchPathURL`) → về lý thuyết có thể nhét resource giọng riêng, nhưng định dạng resource Apple không public ⇒ không thực tế.
3. **`SAPreSynthesizeTTS` / `canUseServerTTS`** — Apple cloud tổng hợp trước, trả audio Opus.

⇒ Cách duy nhất *sạch* để “không bị ràng buộc”: **đừng dùng `VSSpeechSynthesizer` nữa**. Tự phát audio (AVSpeechSynthesizer hoặc audio tải về). Khi chặn `receivedCommand:`, Siri không bao giờ nhận được `SAUISayIt` nên tầng 2–3 tự động vô hiệu.

## 5. Kích hoạt: “Hey Siri”, nút nguồn, tai nghe

Không cần hook gì: chỉ cần để nguyên `SiriActivation` của hệ thống. Nó sẽ mở Siri như thường, `AFUISiriSession` khởi tạo, hook của ta bắt đầu can thiệp từ `assistantConnectionRequestWillStart:` trở đi.

Các kiểu kích hoạt trên iOS 15 (đều dẫn về cùng một chỗ):

| Nguồn | Class | Ghi chú |
|---|---|---|
| “Hey Siri” | `SiriHearstLongPressButtonContext` + `ADAudioPowerCoreSpeechProvider` | wake-word chạy trong `assistantd`, ta không chạm |
| Nút nguồn giữ | `SiriLongPressButtonSource` | |
| Tai nghe | `SiriBluetoothDeviceSource` | |
| Type to Siri | `SASRequestOptions.text` | đường tốt nhất để test không cần micro |
| Shortcuts / SiriKit | `siriactionsd` | không liên quan |

Muốn **chỉ dùng SiriBridge mà không cần nói “Hey Siri”** vẫn được: bật Type-to-Siri trong Accessibility, hoặc dùng Activator (nếu có) trỏ tới “Siri”.

## 6. Rootless trên iOS 15 — những điểm phải nhớ

* Jailbreak rootless đầu tiên cho iOS 15 là **Dopamine** (iOS 15.0–15.4.1, A12–A15; một số bản 15.5+ hạn chế). Máy **arm64e** (A12+) hiện không được hỗ trợ bởi tweak này (yêu cầu của bạn) ⇒ nhắm **A11 và cũ hơn (arm64)** dùng **palera1n rootless** hoặc **XinaA15**/**Dopamine** trên máy arm64 (iPhone 8/X, iPad…).
* Đường dẫn bị dịch: mọi thứ nằm dưới `/var/jb`. `THEOS_PACKAGE_SCHEME = rootless` lo phần prefix; code **không được** hard-code `/Library/...`.
* Substrate/ElleKit API trên rootless: `MSHookMessageEx` vẫn có (qua `libhooker`/`ElleKit`). `%hook` của Theos dùng `substrate.h` — trên rootless cần `libhooker`/`ellekit` cung cấp symbol; Theos tự link đúng nếu `THEOS_PACKAGE_SCHEME=rootless`.
* **Không** dùng `%hookf` lên hàm C nội bộ nếu không chắc (thiếu symbol → crash cả SpringBoard).
* Tiến trình bị inject phải có entitlement/`get-task-allow` phù hợp — với palera1n/Dopamine thì SpringBoard & SiriViewService đều inject được.
* arm64e: **không** build, không `arm64e` slice. Theos mặc định thêm arm64e — phải override `ARCHS = arm64`.

## 7. Bảng “chỗ nào làm được gì”

| Việc muốn làm | Hook / API | Ghi chú |
|---|---|---|
| Bắt câu hỏi người dùng | `-[AFUISiriSession assistantConnection:speechRecognized:]` | chuẩn nhất |
| Bắt câu hỏi (type) | `startRequestWithOptions:` → `options.text` | |
| Chặn Siri trả lời | `-[AFUISiriSession assistantConnection:receivedCommand:completion:]` | **không gọi `%orig`** |
| Bơm câu trả lời | `-[AFUISiriSessionDelegate siriSessionDidReceiveAddViewsCommand:completion:]` | gọi trực tiếp trên delegate |
| Bơm câu trả lời ngắn (chỉ nói) | `siriSessionDidReceiveSayItCommand:completion:` | |
| TTS tuỳ chỉnh | `AVSpeechSynthesizer` / HTTP TTS + `AVAudioPlayer` | SiriBridge tự làm |
| Đổi giọng Siri | `-[AFPreferences setOutputVoice:]` | chỉ với giọng Apple |
| Kết thúc phiên | `-[AFUISiriSession end]` / `endForReason:` | dùng khi LLM xong |
| Hiện “đang xử lý” | `SAUIAddViews` với `SAUIAssistantUtteranceView` text rỗng + orb | |
| Chạy hành động thiết bị | `SAUIAppPunchOut`, `SASendCommands`, hoặc `LSApplicationWorkspace openApplicationWithBundleID:` | SiriBridge dùng “tool call” → command |

## 8. Những cái bẫy đã biết

1. **`completion` của `receivedCommand:`**: nếu chặn mà không gọi completion ⇒ session treo; phải gọi với một `SACommandSucceeded` (hoặc `SACommandFailed`) để state machine về `Idle`.
2. **Luồng**: các callback đến trên `_delegateQueue` (serial). Không được block ở đó; phải `dispatch_async` ra queue riêng rồi quay lại đúng queue để gọi delegate.
3. **`SASRequestOptions`/turnIdentifier**: khi bơm `SAUIAddViews` phải có `refId`/`dialogIdentifier` khớp turn hiện tại, nếu không UI coi là của turn cũ và bỏ.
4. **Audio session**: Siri đang giữ `.playAndRecord`; nếu tự tạo `AVAudioPlayer` mà không `setActive:YES` + category phù hợp thì im tiếng.
5. **`canUseServerTTS`**: để `NO` khi tự sinh audio, nếu không Siri có thể thử tổng hợp trên server.
6. **Kết thúc phiên khi đang nói**: gọi `end` quá sớm sẽ cắt audio; phải đợi delegate callback hoàn tất.
7. **SpringBoard respring**: hook vào SpringBoard nhưng chỉ nên *thụ động* (quan sát) — mọi xử lý nặng đặt ở SiriViewService.
