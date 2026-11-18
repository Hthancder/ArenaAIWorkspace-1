# SiriX v1.2 — Tài liệu thiết kế (DESIGN ONLY)

> Tiếp nối `DESIGN-v1.1.md` (đã chốt). Lượt này **chỉ thiết kế**.
> **Quy ước / IA / luồng tổng thể → `DESIGN-SYSTEM.md` (nguồn sự thật, ưu tiên khi mâu thuẫn).**
> Trọng tâm: **STT thay Apple Speech**, **TTS trả lời (free-first, tự nhận ngôn ngữ, chọn giọng)** và các mục v1.2 còn lại.

---

## A. Tổng quan v1.2

| Nhóm | Nội dung |
|---|---|
| **STT — thay nhận diện giọng nói mặc định của Siri** | Ghi mic khi Siri mở → Whisper/Groq/Gemini/Tự chỉnh → thay transcript; hỗ trợ endpoint tùy chỉnh, chế độ dịch |
| **TTS — đọc câu trả lời** | Nguồn free-first (Hệ thống/Edge/Google/Gemini/Tự chỉnh), tự nhận ngôn ngữ phản hồi → chọn giọng phù hợp, chọn giọng, tốc độ, âm lượng |
| **Mục v1.2 còn lại (đã chốt ở v1.1)** | Deferred push, Thống kê, Lịch sử hội thoại, tiền tố @ai/@siri, model dự phòng, xuất/nhập cấu hình, footer "Siri gốc", đọc to, ẩn danh, offline-fallback |
| **Chất lượng khác** | Trò chuyện thử trong Settings, kiểm tra cập nhật, công cụ ngữ cảnh app, trả lời cùng ngôn ngữ câu hỏi |

**Nguyên tắc:** free-first cho STT/TTS; mọi thứ cấu hình được trong Settings; Apple vẫn giữ vai trò **intent tác vụ** (báo thức/gọi điện… không bị vỡ khi thay transcript); fail-safe = luôn rơi về phương án Apple/hoạt động được.

---

## B. STT — Thay Apple Speech Recognition

### B1. Cách Siri nhận giọng (iOS 15) & điểm can thiệp

```
Người nói ──mic──► [Siri STT (Apple)] ──► partial hypotheses (hiện dần trên UI)
                                   └──► final: AFSpeechRecognizedCommand
                                            │  phrases[ interpretations[ tokens[text]]]
                                            │  + intent group (tác vụ — Apple)
                                            ▼
                          hook: AFConversation addItemForSpeechRecognizedCommand:
                                            ▼
                                     [capture của SiriX] ──► AI / hiển thị
```

**Điểm hook thiết kế:**

| Hook | Mục đích |
|---|---|
| Vào/ra Siri (AFUISiriSession lifecycle / request begin–end) | Bật/tắt **vòi mic** (SXAudioTap) đúng lúc |
| Kết thúc lời nói (endpoint: `_tellSpeechDelegateSpeechRecognized:` hoặc im lặng ≥500ms từ tap) | **Gửi STT sớm** — đi song song với Apple, gần như không thêm độ trễ |
| `addItemForSpeechRecognizedCommand:` (capture hiện có) | **Đổi text**: ưu tiên transcript STT nếu đã có (≤ `sttWaitMs`), không kịp → dùng Apple |

### B2. Hai mức thay thế (chọn mức 2 cho v1.2)

| Mức | Mô tả | Hiển thị trên UI Siri | AI hỏi | Tác vụ |
|---|---|---|---|---|
| **L1 — Chỉ cho AI** | AI dùng transcript STT; UI vẫn chữ Apple | Apple | STT ✓ | Apple ✓ |
| **L2 — Thay toàn bộ** *(mục tiêu)* | Mutate `phrases` của command TRƯỚC `%orig`:1 phrase /1 interpretation /1 token = transcript STT; **giữ nguyên intent group** | STT ✓ | STT ✓ | Apple ✓ (ổn định) |

- L2 fail (command không có `phrases`/không set được) → lặng lẽ xuống L1 → fail tiếp → Apple + log. **Không bao giờ để command hỏng lọt vào %orig** (mutate-on-copy).
- **Partial (chữ hiện dần khi đang nói) vẫn là của Apple** — ghi rõ giới hạn; phương án ẩn partial = spike (khó, không cam kết).
- **Type-to-Siri (nhập chữ)**: không đụng — đã là text.

### B3. Vòi mic — `SXAudioTap`

- **AVAudioEngine** input tap (mono, súng16kHz PCM16 — resample nếu thiết bị khác), ring buffer tối đa `sttMaxSec` (mặc định 30s).
- Bật khi Siri yêu cầu (request begin / session hiện), tắt khi kết thúc — không ghi nền thừa (pin/riêng tư).
- Quyền mic: **SpringBoard đã có cho Siri** — nếu log thấy `errNil` → bubble hướng dẫn *Cài đặt → Quyền riêng tư → Mic*.
- Encode gửi: **WAV** (header + PCM16) — Whisper/Groq nhận thẳng; không cần codec ngoài.
- Rootheide/rootless: đường dẫn không dùng — chỉ network + AVFoundation ✓.

### B4. Nguồn STT (free-first, endpoint tùy chỉnh)

| Nguồn | Endpoint | Model mặc định | Key | Ghi chú |
|---|---|---|---|---|
| **Groq Whisper** ⭐ mặc định khi đã có Groq | `api.groq.com/openai/v1/audio/transcriptions` | `whisper-large-v3-turbo` | reuse key LLM | Free tier, nhanh (~1s) |
| **OpenAI** | `api.openai.com/v1/audio/transcriptions` | `whisper-1` / `gpt-4o-transcribe` | key OpenAI | |
| **Gemini (audio)** | `generativelanguage.googleapis.com/...:generateContent` + `inline_data` audio | `gemini-2.0-flash` | key Gemini | Free tier; prompt "trích dẫn chính xác" |
| **Tự chỉnh (OpenAI-compatible)** ⭐ tùy biến | base URL bất kỳ (`/audio/transcriptions`) | do bạn đặt | optional | Whisper.cpp server, local, proxy… |
| **Tắt (Apple)** | — | — | — | Hành vi hiện tại |

- Cấu hình nguồn: `sttSource = off | auto(theo endpoint LLM) | groq | openai | gemini | custom`.
- Nhóm nâng cao (subpage **Cấu hình STT**): `sttBaseUrl`, `sttApiKey` (rỗng = reuse key LLM), `sttModel`, `sttLanguage` (`auto` = để model tự nhận), `sttPrompt` (dùng để chuẩn hoá tên riêng/việt hoá), `sttMaxSec`, `sttWaitMs` (mặc định 2500ms).
- **Bộ đếm thời gian:** gửi STT ngay khi kết thúc lời nói; tại thời điểm command Apple về: STT xong → dùng; chưa xong → đợi tối đa `sttWaitMs` → quá → Apple (log `stt=fallback`).

### B5. Chế độ dịch (Translate)

Row **"Chế độ dịch"** — `sttTranslate = off | vi | en`:

| Giá trị | Cách làm | Chi phí |
|---|---|---|
| `off` | Giữ nguyên transcript | — |
| `en` | Whisper `task=translate` (dịch về Anh) | Free (cùng endpoint) |
| `vi` | STT transcribe (ngôn ngữ auto) → **1 lượt LLM dịch nhanh** (model nhỏ/fallback, ≤300 token) → text mới vào capture | ~100ms |

- Câu hỏi AI + hiển thị = bản đã dịch; **intent Apple giữ nguyên** → tác vụ vẫn chạy theo nhận diện gốc.
- Log đủ 2 bản: `trc-dịch` và `đã-dịch` khi verbose.
- Test button **"Thử STT"**: quay về SpringBoard ghi 3s (SpringBoard có quyền mic) → gửi STT → kết quả hiện qua notification + log *(không record trong Preferences — process đó không có quyền mic)*.

---

## C. TTS — Đọc câu trả lời (free-first, tự nhận ngôn ngữ)

### C1. Nguồn TTS

| Nguồn | Chi phí | Key | Chất lượng | Ghi chú |
|---|---|---|---|---|
| **Hệ thống (AVSpeechSynthesizer)** ⭐ mặc định | Free, **offline** | không | Tốt — giọng iOS (có vi-VN) | Phù hợp mọi nơi; không phụ thuộc mạng |
| **Edge TTS** | Free online | không | **Rất tốt** (vi-VN-AnhiNeural…) | Cần spike dãy token Edge; fail → bỏ |
| **Google Translate TTS** | Free online | không | Khá | GET ~200 ký tự/lần → chia theo câu |
| **Gemini TTS** | Free tier | key Gemini | Tốt, nhiều giọng (Kore, Puck…) | `responseModalities:[AUDIO]` → PCM → phát |
| **Tự chỉnh (OpenAI-compatible `/audio/speech`)** | tùy endpoint | key | tùy | ElevenLabs-proxy, Piper-bridge, server self-host… |
| Apple (để Siri tự đọc — mặc định hôm nay) | Free | — | Giọng Siri | Được chọn qua `ttsMode=off` (tắt TTS SiriX → Siri đọc) |

### C2. Luồng phát & dập tiếng Apple

```
Answer ready → hiển thị bubble (text, markdown)
     │
     ├─ ttsMode = off → đặt speakableText (để Siri đọc — hành vi hiện tại)
     │
     └─ ttsMode ≠ off →
            ① KHÔNG đặt speakableText vào bubble (hoặc set rỗng)
            ② hook SAPreSynthesizeTTS (đã thấy trong log!) → bỏ qua khi TTS tùy biến BẬT
               → Siri im lặng
            ③ tạo audio: AVSpeech (offline) hoặc GET/POST provider (≤2s)
            ④ phát (AVAudioPlayer/AVSpeech) sau khi bubble hiện
            ⑤ lỗi provider → fallback: đặt speakableText → Siri đọc (không bao giờ im lặng)
```

- **`ttsMode = off | errors | ai | all`**: tắt / chỉ lỗi / mọi câu trả lời AI (mặc định `ai`) / mọi thứ kể cả lỗi.
- **Không nói ké**: kiểm tra `SAPreSynthesizeTTS` bị hookskip + log `tts=custom apple=silent`; nếu vẫn nghe Apple → spike 2 điểm suppress thêm (`SASpeakable`, `SAUISayIt` synthesis path) — ghi plan B.
- **Audio session**: spike phát `AVAudioPlayer` dưới Siri session (`.playback`, mixWithOthers nếu cần) — plan B: `AVSpeechSynthesizer` (ống system sẵn có dưới Siri).

### C3. Tự nhận ngôn ngữ phản hồi → chọn giọng

- Module **`SXLangDetect`** (nhẹ, on-device):
  1. Dấu tiếng Việt (ăâđêôơư + dấu) → `vi` (độ tin cậy cao).
  2. Bộ từ vựng khóa + tỷ lệ ASCII-words → `en`.
  3. Không chắc → ngôn ngữ cấu hình mặc định (`ttsLang`).
- Ánh xạ: `ngôn ngữ phản hồi → [danh sách giọng theo nguồn]` — ví dụ Hệ thống: `vi-VN` (An/Minh), `en-US` (Samantha/Daniel…); Edge: `vi-VN-AnhiNeural`, `en-US-AriaNeural`; Gemini: giọng hỗ trợ đa ngôn ngữ.
- Setting **"Ngôn ngữ đọc"** = `Tự động (nhận từ phản hồi)` ⭐ | `vi` | `en` | … — auto ON mặc định.
- **Giọng nói**: picker lọc theo **(nguồn × ngôn ngữ)** — nguồn Hệ thống đọc `AVSpeechSynthesisVoice.speechVoices()` thật; nguồn online dùng danh sách giọng curated trong code (kèm search ô nhỏ).
- Tốc độ 0.5–2.0 (slider), âm lượng 0–100.
- **Test**: button **"Thử giọng"** → nói ngay mẫu *"Xin chào, đây là SiriX"* — chạy cả trong Preferences (không cần mic) ✓.

### C4. Row "Giọng nói & phát lại" (nhóm TTS trên root)

```
[Nhóm] Giọng đọc (TTS)
  ├─ PSLinkList  Khi nào đọc            [Tắt | Lỗi | Trả lời AI ⭐ | Mọi câu]
  ├─ PSLinkList  Nguồn TTS              [Hệ thống ⭐ | Edge | Google | Gemini | Tự chỉnh]
  ├─ PSLinkList  Ngôn ngữ đọc           [Tự động ⭐ | vi | en | …]
  ├─ PSLinkList  Giọng nói              [picker theo nguồn×ngôn ngữ]
  ├─ PSSlider    Tốc độ đọc             0.5–2.0 (default 1.0)
  ├─ PSSlider    Âm lượng                0–100 (default 100)
  ├─ PSButton    Thử giọng
  └─ (subpage "Cấu hình TTS nâng cao": baseUrl/key/nhánh giọng riêng cho nguồn Tự chỉnh)
```

---

## D. Các thiết kế v1.2 còn lại (đã chốt + mở rộng)

### D1. Deferred push — trả lời trễ "vào" dialog đang mở
- **Spike outbound**: tìm API gửi command từ SpringBoard vào session (ex-tương tự `AFConnection` send / conversation `addItem:` — cần khảo sát headers). Điều kiện: generation khớp, <30s.
- Log: `push: dialog=… gen=…`.
- **Plan B (chốt làm mức cam kết)**: câu trả lời trễ → **notification "SiriX đã trả lời"** (tap → mở trang Lịch sử) + lưu lịch sử.

### D2. Trang Thống kê
- Counters (ghi bởi DisplayPolicy/LLM/STT/TTS): `stats.replaced`, `stats.kept`, `stats.timeout`, `stats.error`, `stats.msAvg` (EWMA), `stats.stt`, `stats.tts`.
- UI: danh sách số + "Tỉ lệ thay thế %" + **Xóa thống kê**.

### D3. Trang Lịch sử hội thoại
- List (giờ · câu hỏi · đáp án ngắn) → chi tiết: full text + **Sao chép** / **Xóa**; **Xóa tất cả**; **Chế độ ẩn danh** (switch `incognito` — không ghi thêm).
- Nguồn: `_history` đã có trong SXIntercept + persist CFPreferences (`history` array ≤ turns×2).

### D4. Tiền tố kích hoạt — `triggerMode`
| Mode | Hành vi |
|---|---|
| `auto` ⭐ | Thông minh (mặc định như hiện tại) |
| `prefix` | Không tiền tố → **Siri gốc**; `@ai …` → bắt buộc AI; `@siri …` → bỏ qua; gỡ tiền tố trước khi gửi |

### D5. Model dự phòng — `fallbackModel`
- Lỗi/không mạng/timeout ở lượt đầu → **retry1 lần** bằng model nhanh (ô nhập riêng trong trang cấu hình LLM).
- Đưa vào row **"Khi hết giờ chờ"** thêm phương án **`retry`** (cùng `timeoutAction`): `bubble | keep | retry`.

### D6. Xuất / Nhập cấu hình
- **Xuất**: JSON (phiên bản 1) → Share sheet (AirDrop/Files). Toggle **"Kèm khóa API"** mặc định **TẮT** (ẩn key = `***`).
- **Nhập**: chọn file → validate → preview số key thay đổi → xác nhận → ghi CFPreferences → `notify prefs.changed`.

### D7. Footer "Câu trả lời Siri gốc" — `showOriginal`
- Bubble chính = AI; dưới cùng append: `—\nSiri: <original>` (đọc từ command trước mutate — giữ snapshot). Switch trong nhóm Trả lời.

### D8. Offline / hết mạng
- Tại capture: không mạng → bubble ngay *"Không có mạng — giữ Siri gốc"* (full mode) hoặc passthrough (smart) + log — không đợi timeout.

### D9. Chất lượng khác ("nghĩ đủ")
| Tính năng | Mô tả |
|---|---|
| **Trò chuyện thử** (trang trong Settings) | Mini-chat: ô nhập → gọi `askQuestion` (đã có) → hiện text render markdown — test không cần Siri |
| **Kiểm tra cập nhật** | Button + dòng "Phiên bản mới nhất: x.y.z" — GitHub API `releases/latest` (CI gắn release); nếu không về được → im lặng + log |
| **Ngữ cảnh app hiện tại** | Tool mới `current_app` (frontmost app từ SpringBoard) cho AI hỏi ngữ cảnh |
| **Trả lời cùng ngôn ngữ câu hỏi** | Quy tắc thêm vào default prompt ("trả lời bằng ngôn ngữ người dùng hỏi") — detect câu hỏi qua `SXLangDetect` |
| **Backoff khi rate-limit** | 429/5xx → retry với backoff 0.5s/1.5s (≤2) trước khi báo lỗi |

---

## E. Cấu trúc Settings v1.2 (mở rộng từ IA v1.1)

```
SiriX (Root)
├─ [Nhóm] Trạng thái          — status · link Thống kê · link Lịch sử
├─ [Nhóm] Bật tắt             — enabled · chế độ · Cách kích hoạt (auto|prefix)
├─ [Nhóm] Nhà cung cấp        — provider · trang con OpenAI · trang con Gemini
│                                (+ dòng "Model dự phòng" trong từng trang con)
├─ [Nhóm] Nhận diện giọng nói (STT)          ★ MỚI
│   ├─ Switch   Thay nhận diện của Siri
│   ├─ LinkList Nguồn STT    [Theo cấu hình AI ⭐ | Groq | OpenAI | Gemini | Tự chỉnh | Tắt]
│   ├─ LinkList Chế độ dịch  [Tắt ⭐ | Tiếng Việt | Tiếng Anh]
│   ├─ Button   Thử STT
│   └─ PSLinkCell Cấu hình nâng cao → subpage (base/key/model/ngôn ngữ/prompt/…)
├─ [Nhóm] Giọng đọc (TTS)                    ★ MỚI
│   ├─ LinkList Khi nào đọc  [Tắt | Lỗi | Trả lời AI ⭐ | Mọi câu]
│   ├─ LinkList Nguồn TTS    [Hệ thống ⭐ | Edge | Google | Gemini | Tự chỉnh]
│   ├─ LinkList Ngôn ngữ đọc [Tự động ⭐ | vi | en]
│   ├─ LinkList Giọng nói    (theo nguồn×ngôn ngữ)
│   ├─ Slider   Tốc độ · Âm lượng
│   ├─ Button   Thử giọng
│   └─ PSLinkCell Cấu hình nâng cao → subpage (custom endpoint/key)
├─ [Nhóm] Trả lời            — nhiệt độ · turns · timeout · Khi hết giờ (bubble|keep|retry)
│                               streaming · markdown · Ẩn thẻ · Báo lỗi voice · Hiện Siri gốc
├─ [Nhóm] Prompt              — Xem/chỉnh prompt (redesign v1.1)
├─ [Nhóm] Công cụ AI          — 3 công cụ + current_app (mới) · số vòng · xóa lịch sử
├─ [Nhóm] Trò chuyện thử      ★ MỚI (1 link)
├─ [Nhóm] Gỡ lỗi              — verbose · test kết nối · xem log · xóa thống kê
├─ [Nhóm] Lịch sử hội thoại   ★ MỚI (1 link + ẩn danh nhanh)
├─ [Nhóm] Xuất / Nhập cấu hình ★ MỚI (2 button)
└─ [Nhóm] Về SiriX            — phiên bản · gói · Kiểm tra cập nhật · Respring
```

### Bảng keys mới (v1.2)

| Key | Type | Default |
|---|---|---|
| `sttEnabled` | bool | NO |
| `sttSource` | `off\|auto\|groq\|openai\|gemini\|custom` | `auto` |
| `sttBaseUrl` / `sttApiKey` / `sttModel` | string | "" (reuse LLM) / `whisper-large-v3-turbo` |
| `sttLanguage` | string | `auto` |
| `sttTranslate` | `off\|vi\|en` | `off` |
| `sttWaitMs` / `sttMaxSec` | int | 2500 / 30 |
| `ttsMode` | `off\|errors\|ai\|all` | `ai` |
| `ttsSource` | `system\|edge\|google\|gemini\|custom` | `system` |
| `ttsLang` | `auto\|vi\|en\|…` | `auto` |
| `ttsVoice` | string | "" (mặc định theo nguồn) |
| `ttsSpeed` / `ttsVolume` | real | 1.0 / 100 |
| `ttsBaseUrl` / `ttsApiKey` | string | "" |
| `triggerMode` | `auto\|prefix` | `auto` |
| `fallbackModel` | string | "" |
| `timeoutAction` | `bubble\|keep\|retry` | `bubble` |
| `showOriginal` | bool | NO |
| `incognito` | bool | NO |
| `history` | array | [] |
| `stats.*` | int | 0 |

---

## F. Kiến trúc module (dự kiến)

```
Sources/
  SXAudioTap.{h,m}    ★ MỚI — AVAudioEngine tap, buffer PCM16 16k, encode WAV
  SXSTT.{h,m}         ★ MỚI — client STT (groq/openai/gemini/custom), thời gian chờ, L1/L2
  SXTTS.{h,m}         ★ MỚI — client TTS + AVSpeech + phát + fallback
  SXLangDetect.{h,m}  ★ MỚI — detect vi/en/… (on-device)
  SXTranslate.{h,m}   ★ MỚI — dịch nhanh qua LLM (sttTranslate=vi)
  SXStats.{h,m}       ★ MỚI — bộ đếm + EWMA
  SXHistoryStore.{h,m}★ MỚI — persist history (incognito tôn trọng)
  SXACEPush.{h,m}     ★ MỚI — spike outbound push (plan B: notification)
  SXConfigIO.{h,m}    ★ MỚI — export/import JSON
  SXIntercept.m       SỬA — STT swap tại capture; suppress Apple TTS; trigger prefix;
                            timeoutAction=retry; offline fast-fail
  SXLLM.m             SỬA — backoff 429/5xx; fallbackModel; tool current_app
  Tweak.x             SỬA — hook SAPreSynthesizeTTS; speech-end; session lifecycle (tap)
Prefs/
  SXSubpageSTTController / SXTTSConfigController   ★ MỚI
  SXHistoryController / SXStatsController / SXChatTestController  ★ MỚI
  SXVoicePickerController (theo nguồn×ngôn ngữ)   ★ MỚI
  Root.plist — IA theo E
```

**Không đổi:** LLM core, DisplayPolicy (v1.1), markdown, prompt UX, scheme rootless/roothide, kênh log/CI.

---

## G. Spike & Rủi ro (mỗi mục có plan B)

| # | Spike | Plan A | Plan B |
|---|---|---|---|
| 1 | Ghi mic trong SpringBoard khi Siri mở | AVAudioEngine tap theo session | Ghi theo slice nhỏ quanh endpoint; hoặc dừng ở L1 |
| 2 | Dập tiếng Apple (pre-synth) | Hook `SAPreSynthesizeTTS` skip | Set `speakableText` rỗng trước %orig + hook thêm `SASpeakable` |
| 3 | Edge TTS sec-token | Reproduce flow token Edge | Bỏ Edge (vẫn còn Hệ thống/Google/Gemini) |
| 4 | Outbound push vào dialog | API gửi command AFConnection | Notification + Lịch sử (cam kết) |
| 5 | Phát audio dưới Siri session | AVAudioPlayer + session mix | AVSpeechSynthesizer (system) |
| 6 | Partial hypotheses của Apple khi STT bật | Chấp nhận (chỉ thay final) | Spike ẩn partial (không cam kết) |
| 7 | Whisper `translate` + intent mismatch | Intent group Apple giữ nguyên | Nếu action sai → auto-fallback Apple text cho câu đó |

---

## H. Ma trận kiểm thử (v1.2)

**STT:** ① Nói VI → transcript VI (Groq); ② Nói EN + chế độ dịch=VI → AI/hiện VI, tác vụ "đặt báo thức" vẫn chạy; ③ `sttTranslate=en` → transcript EN; ④ STT chậm >2500ms → fallback Apple + log; ⑤ Type-to-Siri không đổi; ⑥ Tắt "Thay nhận diện" → giống Apple y hiện tại.
**TTS:** ⑦ `ai` mode: bubble hiện + đúng nguồn đọc (không nghe ké Apple — check log); ⑧ Ngôn ngữ auto: câu VI → giọng VI, EN → EN; ⑨ Đổi giọng/tốc độ có hiệu lực ngay (notify); ⑩ Provider lỗi → Siri đọc thay (không im lặng); ⑪ Thử giọng chạy trong Preferences.
**Mục khác:** ⑫ Thống kê tăng đúng; ⑬ Lịch sử copy/xóa/ẩn danh; ⑭ `@ai`/`@siri`; ⑮ Export không kèm key khi tắt toggle; ⑯ Retry model dự phòng khi timeoutAction=retry; ⑰ Trò chuyện thử render markdown; ⑱ CI xanh cả2 scheme.

---

## I. Đề xuất thứ tự triển khai (khi làm)

1. **Nhóm Settings IA + keys** (khung trước — làm nền).
2. **TTS** (ít rủi ro nhất, dùng được ngay: Hệ thống + Gemini).
3. **STT L2 + AudioTap** (spike 1–2 song song).
4. **Mục D** (stats/history/prefix/fallback/export…) — nhiều việc nhưng chắc.
5. **Mini-chat / cập nhật / current_app** — rải rác khi rảnh nhánh.
6. Spike Edge/Deferred-push cuối cùng (được thì cộng, không được thì plan B đã cam kết).

---

## J. Đã chốt (phiếu chọn của bạn — 2026-11-18)

1. **"Thay nhận diện của Siri" (STT)** → mặc định **OFF** — người dùng tự bật trong Settings *(khớp key `sttEnabled = NO`)*.
2. **Phạm vi v1.2** → **gộp tất cả vào một v1.2 đầy đủ**: STT + TTS + toàn bộ mục D (deferred push, thống kê, lịch sử, tiền tố, model dự phòng, xuất/nhập, footer Siri gốc, ẩn danh, offline) + nhóm chất lượng (trò chuyện thử, kiểm tra cập nhật, tool `current_app`, backoff 429).
3. **Edge TTS** → **giữ spike Edge TTS** (nguồn free chất lượng cao); fail → plan B Hệ thống/Google/Gemini như mục G3.
