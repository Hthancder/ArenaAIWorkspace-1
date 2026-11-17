# SiriBridge

Tweak mã nguồn mở thay **Siri** bằng **LLM endpoint tuỳ chỉnh** + **TTS tuỳ chỉnh**,
dành cho **iOS 15 · arm64 (KHÔNG arm64e) · rootless *hoặc* roothide (KHÔNG rootful)**.

Đây là bản "làm lại từ đầu" theo tinh thần của SiriPlus (bản thương mại US$4.99),
nhưng:

* **miễn phí, mã nguồn mở**, không tài khoản, không telemetry;
* **không khoá vào OpenAI/Gemini**: endpoint + body + field đều cấu hình được
  → dùng được OpenAI, Gemini, Anthropic, OpenRouter, Groq, DeepSeek, Ollama, LM Studio,
  vLLM, llama.cpp server…;
* **không bị ràng buộc giọng Siri**: TTS on-device (AVSpeechSynthesizer, chọn voice bất kỳ),
  hoặc TTS qua endpoint (OpenAI speech / ElevenLabs / Azure / Piper tự dựng),
  hoặc (tuỳ chọn) để Siri đọc;
* có **tool-calling** để điều khiển thiết bị (mở app, gọi điện, lịch, nhắc nhở, nhạc, URL);
* **không** có "managed mode" (đó là nguồn chi phí server của bản thương mại).

---

## 1. Tương thích

| | |
|---|---|
| iOS | **15.0 – 15.x** (thiết kế cho 15.x; hook có kiểm tra method nên không crash nếu thiếu) |
| Kiến trúc | **arm64** (A11 trở xuống: iPhone 8/8 Plus/X, iPhone 7, SE2…, iPad tương ứng) |
| Jailbreak | **rootless** (palera1n rootless / Dopamine / XinaA15) **và roothide** (Bootstrap) |
| **Không** hỗ trợ | **arm64e** (binary), **rootful** (bị chặn cứng trong `common-scheme.mk`) |
| Tiến trình inject | `com.apple.SiriViewService`, `com.apple.springboard` |

Bảng chọn gói:

| File | Dùng cho | Package arch |
|---|---|---|
| `com.hthancder.siribridge_0.2.1_iphoneos-arm64.deb` | jailbreak **rootless** (cài vào `/var/jb`) | `iphoneos-arm64` |
| `com.hthancder.siribridge_0.2.1_iphoneos-arm64e.deb` | **roothide** Bootstrap | `iphoneos-arm64e` |

> Bản roothide có trường `Architecture: iphoneos-arm64e` **theo quy ước của roothide**
> (roothide/theos tự ép giá trị này). Code bên trong vẫn là **arm64 thuần** —
> `ARCHS = arm64`, `cpusubtype = 0` (ALL), không sinh mã arm64e.
> Đường dẫn được resolve lúc chạy: `jbroot()` từ `libroothide.dylib` (qua `dlsym`, không link),
> fallback `/var/jb`, fallback gốc `/` — xem `Sources/SBPaths.m`.

> Trên iOS 15, phần lớn máy A12+ là arm64e → tweak này **cố tình** không build cho arm64e
> theo yêu cầu.

---

## 2. Cài đặt

### Cách nhanh nhất: tải `.deb` build sẵn bởi GitHub Actions

Mỗi lần push, CI build **cả hai bản** (matrix rootless + roothide). Release được tạo
khi chạy tay (`workflow_dispatch`) hoặc gắn tag `v*` — và chứa **2 file `.deb`**:

```
https://github.com/Hthancder/ArenaAIWorkspace-1/releases
```

Tải đúng file theo máy:

| Máy | File |
|---|---|
| rootless (Dopamine, palera1n rootless) | `com.hthancder.siribridge_<ver>_iphoneos-arm64.deb` |
| roothide (Bootstrap) | `com.hthancder.siribridge_<ver>_iphoneos-arm64e.deb` |

```bash
# qua SSH (thiết bị đã jailbreak), ví dụ bản rootless
scp com.hthancder.siribridge_*_iphoneos-arm64.deb root@<IP>:/var/mobile/
ssh root@<IP> 'dpkg -i /var/mobile/com.hthancder.siribridge_*_iphoneos-arm64.deb && killall -9 SpringBoard'
# roothide: thay *_iphoneos-arm64.deb bằng *_iphoneos-arm64e.deb
```
Hoặc mở file `.deb` bằng **Sileo / Zebra / Filza** trên máy.

### Chọn bản rootless hay roothide khi build

```bash
make package                     # mặc định: rootless
make package SCHEME=roothide     # roothide (cần roothide/theos)
```

`common-scheme.mk` chặn mọi giá trị khác — **rootful không build được**, đó là chủ ý.

### Tự build

```bash
./build.sh              # macOS + Theos
./build.sh --linux      # Linux + zig (xem §6)
make install            # cài trực tiếp qua SSH nếu Theos đã cấu hình device
```

Sau khi cài: **Settings → SiriBridge**.

Lần đầu nên bật:
1. `Bật SiriBridge`
2. `Endpoint` + `API key` + `Model` (xem §3)
3. `Kiểu TTS` = *Trên máy* và chọn giọng ở `Giọng đọc`

Respring (hoặc tắt/mở Siri một lần) là tweak hoạt động.

---

## 2.5. Giao diện cấu hình (Settings → SiriBridge)

Không dùng `PSListController` mặc định. Màn hình được vẽ tay bằng Auto Layout:

* **Hero card** gradient tím→xanh, công tắc tổng, pill trạng thái ĐANG BẬT/ĐANG TẮT;
* các **card bo tròn** nhóm theo mục: Kích hoạt · Trả lời · Mô hình · Tinh chỉnh · Giọng đọc;
* hàng **switch / text / long-text / slider / segment / choice / action** với giá trị hiển thị ngay trên hàng
  (slider hiện số, choice hiện nhãn, long-text hiện preview);
* **Preset nhanh**: OpenAI · OpenRouter · Ollama · LM Studio · Gemini · Groq — một chạm điền endpoint/model/field;
* **ẩn/hiện theo ngữ cảnh**: chọn TTS kiểu "Máy" mới hiện voice/tốc độ/cao độ/âm lượng,
  kiểu "Endpoint" mới hiện card endpoint TTS, kiểu "Siri" thì ẩn hết;
* **Nâng cao & gỡ lỗi** thu gọn được: môi trường (rootless/roothide + jbroot thật), xoá lịch sử,
  đặt lại toàn bộ, liệt kê voice ra log;
* **Kiểm tra kết nối**: POST thử tới endpoint và hiện nguyên văn HTTP code + body → biết ngay sai key hay sai URL;
* hỗ trợ **Dark Mode** (màu động), ghi cấu hình có **debounce 250ms** nên kéo slider không spam notify;
* text dài (system prompt, header JSON, body template) mở **editor toàn màn hình** dùng font mono.

---

## 3. Cấu hình LLM

### OpenAI
```
Endpoint:  https://api.openai.com/v1/chat/completions
Model:     gpt-4o-mini
API key:   sk-...
Response:  choices.0.message.content      (mặc định)
```

### Gemini (native API)
```
Endpoint:  https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}:generateContent?key=...
Model:     gemini-2.0-flash
Body template:
{"contents":[{"parts":[{"text":"{{PROMPT}}"}]}],
 "systemInstruction":{"parts":[{"text":"{{SYSTEM}}"}]}}
Response:  candidates.0.content.parts.0.text
```
(Nếu dùng OpenAI-compatible gateway của Gemini thì giữ cấu hình OpenAI.)

### Anthropic
```
Endpoint:  https://api.anthropic.com/v1/messages
Headers:   {"anthropic-version":"2023-06-01"}
Body:      {"model":"{{MODEL}}","max_tokens":400,"system":"{{SYSTEM}}",
            "messages":[{"role":"user","content":"{{PROMPT}}"}]}
Response:  content.0.text
```
`x-api-key` được gửi tự động cùng `Authorization`.

### Ollama / LM Studio / llama.cpp / vLLM (local, **miễn phí, không cần key**)
```
Endpoint:  http://192.168.1.10:11434/v1/chat/completions     (Ollama)
Model:     qwen2.5:7b
API key:   (để trống)
```
Lưu ý: iOS chặn HTTP thường (ATS). Nếu server LAN chỉ có HTTP:
– dùng `https://` với reverse proxy (Caddy/Cloudflare Tunnel), hoặc
– thêm ngoại lệ ATS qua profile, hoặc dùng Tailscale/Cloudflare Tunnel.

### Placeholder trong Body template
| Placeholder | Ý nghĩa |
|---|---|
| `{{SYSTEM}}` | system prompt (đã escape JSON) |
| `{{PROMPT}}` | câu người dùng (đã escape) |
| `{{HISTORY}}` | mảng JSON `[{"role":…,"content":…}]` các lượt trước |
| `{{MODEL}}` | model hiện tại |

Để trống `Body template` → dùng body OpenAI chuẩn (kèm `tools`).

---

## 4. TTS — không dùng giọng Siri

| Kiểu | Mô tả |
|---|---|
| **0 · Trên máy** | `AVSpeechSynthesizer`, chọn bất kỳ voice nào đã cài (kể cả Enhanced/Premium), chỉnh rate/pitch/volume. Không cần mạng. |
| **1 · Endpoint** | POST JSON → nhận audio. Mặc định là OpenAI `/v1/audio/speech`. Hỗ trợ ElevenLabs, Azure, Piper HTTP. |
| **2 · Siri đọc** | Không tự phát; set `speakableText` để Siri đọc (dùng giọng Siri). |

Ví dụ TTS endpoint:
```json
// OpenAI
{"model":"gpt-4o-mini-tts","input":"{{TEXT}}","voice":"{{VOICE}}","response_format":"mp3"}
// ElevenLabs
{"text":"{{TEXT}}","model_id":"eleven_multilingual_v2"}
   → Headers: {"xi-api-key":"..."} ; Voice lấy từ URL (/v1/text-to-speech/<voiceId>)
```

`{{VOICE}}` lấy từ ô **Voice (endpoint)** (mặc định `alloy`).

---

## 5. Tools (điều khiển máy)

Bật `Cho phép điều khiển thiết bị`. Model sẽ gọi các hàm:

| Tool | Việc |
|---|---|
| `open_app` | mở app theo tên (dò displayName → bundle id) |
| `call_phone` | gọi số / liên hệ |
| `open_url` | mở URL / deep link |
| `add_calendar_event` | thêm sự kiện (ISO8601) |
| `add_reminder` | tạo nhắc nhở |
| `send_message` | mở Tin nhắn soạn sẵn |
| `media_control` | play / pause / next / previous |
| `device_status` | pin, tên máy, iOS |
| `list_apps` | liệt kê app đã cài |
| `speak_only` | chỉ trả lời bằng lời |

Sau khi tool chạy, câu trả lời cuối được hỏi lại LLM để nói tự nhiên.

Tắt tools thường cho câu trả lời chất lượng hơn (giống nhận xét của người dùng SiriPlus).

---

## 6. Build

```bash
brew install ldid dpkg
export THEOS=~/theos          # git clone --recursive https://github.com/theos/theos.git
./build.sh                    # rootless
./build.sh SCHEME=roothide    # roothide
```

`build.sh` chạy `make package FINALPACKAGE=1` để Theos **ký ad-hoc bằng `ldid`
thật**, rồi tự chạy `tools/verify_deb.py --strict`.

Build bằng zig trên Linux **đã bị bỏ** — nó sinh Mach-O hỏng
(`LC_LOAD_DYLINKER` trong dylib + mạch load command rác), chính là nguyên nhân
safe mode và lỗi không thấy mục trong Cài đặt. Chi tiết:
`docs/09-ly-do-chuyen-sang-macos.md`.

### CI (GitHub Actions)
`.github/workflows/build.yml` chạy trên mọi branch, **matrix 2 job**:

| scheme | Theos | package arch |
|---|---|---|
| `rootless` | `theos/theos` | `iphoneos-arm64` |
| `roothide` | `roothide/theos` (clone `--recursive`, có `vendor/mod/roothide`) | `iphoneos-arm64e` |

Mỗi job chạy trên `macos-14`: Theos + `ldid` (brew) + SDK iPhoneOS15.6 →
build `FINALPACKAGE=1` (ký thật), rồi verify:

* arm64 thuần (`cpusubtype & 0xff == 0`), từ chối arm64e;
* **không** có `LC_LOAD_DYLINKER` trong dylib, mạch load command hợp lệ;
* chữ ký ad-hoc hợp lệ (superblob, SHA-256, hash từng trang);
* không phụ thuộc substrate, filter chỉ `com.apple.SiriViewService`;
* không có layout rootful.

Sau đó upload artifact + `SHA256SUMS` và phát hành Release (một Release chứa
**cả hai** .deb) khi tag `v*` hoặc chạy tay.
Trạng thái: https://github.com/Hthancder/ArenaAIWorkspace-1/actions

---

## 7. Cấu trúc mã

```
Sources/
  Tweak.x         hook AFUISiriSession (+ lưới an toàn SRSiriViewController)
  SBPaths.*       resolve jbroot: roothide (`jbroot()` qua dlsym) → /var/jb → /
  SBConfig.*      đọc/ghi prefs (NSUserDefaults suite com.hthancder.siribridge)
  SBCapture.*     lấy text người dùng từ SASSpeechRecognized / SASRequestOptions
  SBHistory.*     lịch sử hội thoại trong RAM
  SBLLM.*         gọi endpoint chat (body template / OpenAI mặc định, bóc JSON)
  SBTTS.*         AVSpeechSynthesizer + TTS endpoint + AVAudioPlayer
  SBTools.*       tool-calling → API hệ thống
  SBDeliver.*     bơm SAUIAddViews vào delegate, cờ "do chính tweak bơm"
  SBEngine.*      điều phối một lượt hỏi-đáp (LLM → tool → UI → TTS)
Prefs/            bảng cấu hình tự vẽ (card, hero gradient, live value, preset, test kết nối)
  SBRootListController.m  dựng toàn bộ màn hình từ các card
  SBPrefsUI.*             theme, store, row (switch/text/slider/segment/choice/action), editor, picker
docs/             nghiên cứu kỹ thuật (Siri, SiriPlus, kiến trúc, kiểm thử)
```

---

## 7.5. Download hiện có

Release gần nhất: <https://github.com/Hthancder/ArenaAIWorkspace-1/releases/latest>

| File | Kích thước | scheme |
|---|---|---|
| `com.hthancder.siribridge_0.2.1_iphoneos-arm64.deb` | ~70 KB | rootless |
| `com.hthancder.siribridge_0.2.1_iphoneos-arm64e.deb` | ~70 KB | roothide |

---

## 7.5. Không thấy mục trong Cài đặt?

Chạy trên máy:

```bash
sh /var/jb/usr/share/siribridge/sb-doctor.sh
```

Nguyên nhân thường gặp (chi tiết: `docs/08-settings-khong-hien.md`):

1. **Cài nhầm bản** — máy rootless phải dùng `*_iphoneos-arm64.deb`, roothide
   dùng `*_iphoneos-arm64e.deb`. Sai bản ⇒ file nằm sai thư mục gốc.
2. **Thiếu PreferenceLoader** — không có nó thì Settings không hiện *bất kỳ*
   tweak nào. Từ 0.1.2 gói đã `Depends: preferenceloader`.
3. **Đang ở safe mode** — mọi tweak bị tắt, kiểm tra tweak khác còn mục không.
4. Cờ `.safemode` của SiriBridge còn bật (xoá file đó rồi respring).

---

## 7.6. Nếu bị safe mode

Bản 0.1.1 sửa đúng nguyên nhân gây safe mode khi respring. Tóm tắt (chi tiết:
`docs/07-safe-mode-rootcause.md`):

| Nguyên nhân | Sửa |
|---|---|
| Build bằng **zig trên Linux** sinh Mach-O hỏng: `LC_LOAD_DYLINKER` trong dylib + mạch load command bị rác | chuyển sang **macOS runner** (clang + ld64 + `ldid` thật); CI chặn nếu còn `LC_LOAD_DYLINKER` |
| Dylib phụ thuộc `MSHookMessageEx` (chỉ có khi substrate đã nạp) | bỏ Logos, hook bằng `class_replaceMethod` của libobjc |
| Inject vào **SpringBoard** dù không có hook nào ở đó | plist chỉ còn `com.apple.SiriViewService` |
| `%ctor` làm I/O nặng (plist, CFPreferences, dlopen) trên main thread | hoãn 1.5 s, bọc `@try`, có **crash-loop guard** |
| KVC (`setValue:forKey:`) trên ACE object có thể ném | `SBSetSafe()` dùng khắp nơi |
| `AVAudioSession setCategory:` khi Siri đang giữ micro | chỉ `setActive:YES` |
| TTS không bao giờ gọi completion → kẹt `busy` | thêm timeout |
| `substringToIndex:` với số byte của NSData | cắt theo `NSString.length` |

Thoát khẩn cấp (xem chi tiết trong `tools/README-safe-mode.md`):

```bash
touch /var/mobile/Library/Preferences/com.hthancder.siribridge.safemode
killall -9 SpringBoard
```

---

## 8. Giới hạn đã biết (đọc trước khi test)

* **Chưa có thiết bị thật để test** — code đã build được ra `.deb` arm64 nhưng
  chưa chạy trên iPhone. Xem `docs/05-testing.md` để biết checklist debug.
* Không có streaming (LLM trả lời xong mới hiện) — thiết kế để an toàn với
  state machine của `AFUISiriSession`. Có thể thêm sau bằng `SAUIUpdateViews`.
* Câu trả lời của Siri bị **chặn hoàn toàn** ở Replace mode → các domain
  Siri-native (báo thức, hẹn giờ, gọi, nhạc) phải dùng `tools` hoặc thêm từ khoá
  vào `Câu chứa các từ này thì để Siri gốc`.
* Nếu hook không cài được (SiriViewService load trễ), xem log `[SiriBridge]`.
* TTS qua endpoint cần mạng; on-device TTS cần voice đã tải.

---

## 9. Giấy phép & đạo đức

MIT cho phần code của repo này. **Không** chứa code của SiriPlus hay bất kỳ
tweak thương mại nào; `docs/02-siriplus-feature-study.md` chỉ mô tả **hành vi**
công khai để định nghĩa tính năng. Tự chịu trách nhiệm khi cài tweak lên máy.
