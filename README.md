# SiriBridge

Tweak mã nguồn mở thay **Siri** bằng **LLM endpoint tuỳ chỉnh** + **TTS tuỳ chỉnh**,
dành cho **iOS 15 · rootless · arm64 (KHÔNG arm64e)**.

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
| Jailbreak | **rootless** — palera1n rootless / Dopamine / XinaA15 (tuỳ máy) |
| **Không** hỗ trợ | **arm64e** (A12+), rootful, roothide, Serotonin |
| Tiến trình inject | `com.apple.SiriViewService`, `com.apple.springboard` |

> Trên iOS 15, phần lớn máy A12+ là arm64e → tweak này **cố tình** không build cho arm64e
> theo yêu cầu. Nếu sau này cần, thêm `arm64e` vào `ARCHS` và test kỹ.

---

## 2. Cài đặt

```bash
# build
./build.sh              # macOS + Theos
./build.sh --linux      # Linux + zig (xem §6)

# cài (thiết bị đã jailbreak, đã cấu hình SSH trong Theos hoặc dùng Sileo/Zebra)
make install
# hoặc copy packages/*.deb sang máy rồi mở bằng Sileo
```

Sau khi cài: **Settings → SiriBridge**.

Lần đầu nên bật:
1. `Bật SiriBridge`
2. `Endpoint` + `API key` + `Model` (xem §3)
3. `Kiểu TTS` = *Trên máy* và chọn giọng ở `Giọng đọc`

Respring (hoặc tắt/mở Siri một lần) là tweak hoạt động.

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

### macOS (chính thức)
```bash
export THEOS=~/theos
./build.sh
# hoặc
make package FINALPACKAGE=1
```

### Linux (đã kiểm chứng trong sandbox của dự án)
Yêu cầu: Theos clone `--recursive`, SDK `iPhoneOS15.6.sdk` (từ `theos/sdks`),
`zig` 0.13.x (`pip install ziglang==0.13.0`), `rsync`, `dpkg-deb`.

```bash
export THEOS=/path/to/theos
export ZIG_BIN=/path/to/zig
./build.sh --linux
```

Cách hoạt động: `tools/theos-toolchain-stub/bin/clang` là wrapper gọi
`zig cc --target aarch64-ios`, tự thêm `-isystem <SDK>/usr/include`,
`-F<SDK>/System/Library/Frameworks`, `-L<SDK>/usr/lib`, `-fno-modules`.
`build.sh --linux` symlink wrapper vào `$THEOS/toolchain/linux/iphone/bin/`.

### Ký
Rootless (ElleKit / libhooker) nạp dylib **không cần** chữ ký.
Nếu muốn ký ad-hoc: `make package TARGET_CODESIGN=ldid`.

---

## 7. Cấu trúc mã

```
Sources/
  Tweak.x         hook AFUISiriSession (+ lưới an toàn SRSiriViewController)
  SBConfig.*      đọc/ghi prefs (NSUserDefaults suite com.hthancder.siribridge)
  SBCapture.*     lấy text người dùng từ SASSpeechRecognized / SASRequestOptions
  SBHistory.*     lịch sử hội thoại trong RAM
  SBLLM.*         gọi endpoint chat (body template / OpenAI mặc định, bóc JSON)
  SBTTS.*         AVSpeechSynthesizer + TTS endpoint + AVAudioPlayer
  SBTools.*       tool-calling → API hệ thống
  SBDeliver.*     bơm SAUIAddViews vào delegate, cờ "do chính tweak bơm"
  SBEngine.*      điều phối một lượt hỏi-đáp (LLM → tool → UI → TTS)
Prefs/            bảng cấu hình (PreferenceLoader bundle)
docs/             nghiên cứu kỹ thuật (Siri, SiriPlus, kiến trúc, kiểm thử)
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
