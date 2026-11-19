# SiriX — Thiết kế hệ thống: Nhất quán & Phối hợp luồng

> **Nguồn sự thật duy nhất** cho quy ước Settings, luồng tổng thể và các tương tác giữa tính năng.
> Tài liệu này **ưu tiên hơn** `DESIGN-v1.1.md` / `DESIGN-v1.2.md` khi có mâu thuẫn về quy ước/IA.
> Thứ tự đọc: SYSTEM → v1.1 → v1.2.

---

## 1. Luồng master (một pipeline, mọi tính năng là công tắc trên nó)

```
                        ┌── Type-to-Siri (text) ─────────────────────────────┐
                        │                                                    ▼
[Mic — khi Siri mở] → SXAudioTap → [STT? (sttEnabled)] → [Dịch? (sttTranslate)]
   (v1.2)                    │            │                       │
   └─ fail/trễ >2.5s ────────┘            │                       │
        (fallback: text Apple)            └───────────┬───────────┘
                                                      ▼
   CAPTURE (AFConversation/AFConnection + dedupe + generation++)  ← triggerMode: @siri bỏ qua / @ai bắt buộc
                                                      ▼
   DisplayPolicy ─── mode=auto: action? → PASS-THROUGH (không đụng)
        │             mode=full: mọi câu đều chờ AI
        ▼
   LLM (stream? token đầu làm mốc timeout; tool ≤ maxToolRounds; backoff 429;
        lỗi/timeout → retry fallbackModel? → timeoutAction: bubble|keep|retry)
        ▼
   ANSWER (raw markdown, cùng ngôn ngữ câu hỏi — rule trong prompt)
        ▼
   SXMarkdown (markdown=on → render incremental tolerant) ──► BUBBLE (DisplayPolicy đã chốt ở capture)
        ▼
   TTS? (ttsMode × ttsSource) — CHỈ đọc answer đã hoàn tất;
   suppress Apple (SAPreSynthesizeTTS) khi nguồn ≠ off; lỗi → Apple đọc
        ▼
   STATS++ & HISTORY++ (nếu !incognito) & LOG
```

**Hợp đồng giữa các stage (mọi stage chỉ nhận/ra kiểu này):**

| Stage | Input | Output | Đồng bộ? |
|---|---|---|---|
| AudioTap | mặt trận Siri on/off | buffer PCM16 16k (≤30s) | event-driven |
| STT | buffer + config | `SXTranscript{text, lang, ms, ok}` | bg, ≤ sttWaitMs |
| Translate | transcript + `sttTranslate` | text đã dịch | bg |
| Capture | ACE command (text cuối) | `Question{gen, text, source, isAction}` | thread ACE — **không block >5s** |
| LLM | Question + history + tools | `Answer{gen, raw, ms, rounds, err}` | bg + stream |
| Display | Answer + policy | mutate command / bubble / keep | thread ACE — instantaneous |
| TTS | Answer đã render | audio phát / fallback Apple | bg fetch → main play |
| Stats/History/Log | event có gen | ghi bền | non-blocking |

---

## 2. Máy trạng thái & quy tắc hủy (generation-centric)

```
IDLE ─capture─► STT? ─► WAIT_LLM ─first token─► STREAMING ─complete─► DONE ─► SPEAKING ─► IDLE
   ▲              │          │  │                    │
   │   new capture│  timeout │  │new capture         │new capture
   └──────────────┴──────────┴──┴────────────────────┘  → hủy mọi thứ của gen cũ
```

**Quy tắc cứng:**
1. **Mọi bất đồng bộ mang `generation`** (capture++, uint64). Kết quả gen cũ về trễ → **bỏ im lặng** + log `stale(gen=…)` (verbose). Áp dụng: STT, Translate, LLM, stream chunks, deferred push, TTS fetch.
2. **Capture mới hủy:** `cancel` task stream, `cancel` STT/translate request, `stopSpeaking/stopAudio`, bỏ bubble partial của gen cũ.
3. **Không stage nào block thread ACE quá 5s** (hard-cap v1.1) — phần chờ còn lại chạy nền, kết quả đưa vào bằng bubble/push gen đúng.
4. **TTS không bao giờ đọc answer chưa complete** (stream dở dang → im lặng đến `complete`; hủy gen → stop ngay).
5. **Deferred push** chỉ khi `gen` còn hiệu lực <30s và dialog cùng session (plan B: notification — đã chốt v1.1/J).
6. `errored code -6` **chỉ** dùng cho "AI không có nội dung thật"; mọi lỗi khác → bubble chữ (không dismiss UI).

---

## 3. Ma trận phối hợp tính năng (quyết định đã chốt)

| ↓ feature × feature → | STT ON | Dịch=vi/en | Stream ON | Markdown OFF | TTS≠off | trigger=prefix | incognito |
|---|---|---|---|---|---|---|---|
| **Type-to-Siri** | bỏ qua STT | text gốc→dịch? **không** (text đã là ngôn ngữ người dùng) | áp dụng | áp dụng | áp dụng | kiểm tra prefix | — |
| **Voice (nói)** | transcript thay Apple (L2) | dịch trước khi vào capture | áp dụng | áp dụng | áp dụng | prefix = **sau** STT | history không ghi |
| **mode=full + action** | action vẫn theo intent Apple | — | — | — | lỗi action → bubble lỗi | không có prefix → vẫn auto-skip action | — |
| **timeout + retry** | — | — | hủy stream gen cũ khi retry (gen mới) | — | chưa có answer → chưa nói | — | — |
| **offline** | bỏ STT (dùng Apple text) | bỏ (cần LLM) | kết nối fail → timeoutAction | — | **nguồn Hệ thống vẫn chạy** ✓ | — | — |
| **STT fail/trễ** | fallback text Apple + `stt=fallback` | — | — | — | — | — | — |
| **TTS fail** | — | — | — | — | → Apple đọc (speakableText) + log | — | — |

**Quy tắc phối hợp trọng yếu:**
- **Streaming × Markdown:** render **incremental tolerant** — mỗi flush (≤250ms) tự đóng cặp chưa đóng (`` ``` ``, `**`) → không nhấp nháy/gãy khối; `markdown=off` → hiển thị thô từng flush.
- **Streaming × TTS:** TTS khởi động tại **complete** duy nhất (không đọc theo token).
- **Streaming × timeout:** mốc timeout = **token đầu tiên** (đã chốt v1.1); quá hạn → hủy stream → `timeoutAction`.
- **Dịch × TTS:** `sttTranslate=vi` → câu hỏi vào capture là VI → AI trả lời VI (rule prompt) → detect VI → giọng VI. Journey đầy đủ ở §4.
- **SpeakErrors cũ × ttsMode mới:** `ttsMode` (v1.2) **thay thế hoàn toàn** `speakErrors` — xem di trú §9.
- **Action (tác vụ):** không bao giờ qua LLM/STT-hiệu lực — intent group Apple nguyên vẹn; DisplayPolicy không mutate câu action.

---

## 4. Hành trình ngôn ngữ (một luồng duy nhất, 5 mốc)

```
mốc1            mốc2                mốc3                 mốc4              mốc5
ngôn ngữ nói → [STT lang auto] → [translate? (vi/en)] → AI trả lời cùng   → [SXLangDetect] → giọng TTS
hoặc gõ        (sttLanguage)      (sttTranslate)         ngôn ngữ câu hỏi   (ttsLang=auto)   (nguồn×ngôn ngữ)
                                                                          ↑ nếu detect thấp
                                                                          → dùng ngôn ngữ cấu hình (ttsLang cố định)
```
- **Prompt rule cố định** trong default prompt: *"Trả lời bằng ngôn ngữ của câu hỏi."* — prompt tuỳ chỉnh **thay thế toàn bộ** (user tự giữ rule — footnote trong trang Prompt ghi rõ).
- `ttsLang=auto` (mặc định) là mốc5; người dùng ép `vi`/`en` thì bỏ detect.
- Log verbose ghi cả 5 mốc khi có lệch (`lang: vi→(dịch)→vi→detect=vi→voice=An`).

---

## 5. Quy ước Settings (nhất quán bắt buộc)

> **Lớp UI chi tiết (wireframe, design system, logic từng màn hình) → `DESIGN-UI.md`.**

### 5.1 Ánh xạ điều khiển — dùng đúng 1 kiểu cho mỗi loại dữ liệu
| Dữ liệu | Control | Ví dụ |
|---|---|---|
| Bật/tắt | `PSSwitch` | Bật SiriX, Streaming |
| Chọn 1 trong ≤6 | `PSLinkListCell` + `detail=PSListItemsController` | Chế độ trả lời, Nguồn TTS |
| Số trong khoảng | `PSSliderCell` + `showValue` + min/max | Nhiệt độ, Thời gian chờ |
| Số thập phân | slider step theo min/max (0.1 với dải ≤2) | Nhiệt độ |
| Chuỗi ngắn/tên | `PSEditTextCell` | Mô hình, base URL |
| Bí mật | `PSSecureEditTextCell` + `isSecure` + placeholder | Khóa API |
| Vùng dài (document) | `PSLinkCell` → editor có **[Lưu]** duy nhất | Prompt |
| Hành động | `PSButtonCell` (+alert xác nhận nếu phá) | Thử giọng, Xóa… |
| Thông tin chỉ đọc | `PSTitleValueCell` | Trạng thái, Phiên bản |
| Điều hướng | `PSLinkCell` → subpage | Cấu hình STT |

### 5.2 Quy tắc hành vi
1. **Hiệu lực ngay**: mọi row ghi CFPreferences → `notify com.sirix.tweak/prefs.changed` — **không có nút Lưu** ngoại trừ trang **Prompt** (semantic document: [Lưu] [Khôi phục mặc định] [Sao chép]).
2. **Nút test**: mạng = **"Kiểm tra…"** (Kiểm tra kết nối, Kiểm tra nhanh); sinh mẫu cục bộ/media = **"Thử…"** (Thử STT, Thử giọng).
3. **Hành động phá** (xóa): nhãn đỏ + alert "Xác nhận? — không hoàn tác được".
4. **Mỗi nhóm ≥1 `footerText`** giải thích *"cái gì — khi nào — an toàn ra sao"*, giọng thân thiện tiếng Việt, ≤2 câu.
5. **Tên nhóm** danh từ ngắn gọn, Title Case tiếng Việt (Xem §6).
6. **Subpage**: tiêu đề `Cấu hình <Tên>` (Cấu hình STT / Cấu hình TTS / Cấu hình OpenAI / Cấu hình Gemini) — **không** dùng chữ "nâng cao" trong nhãn.
7. **Tên key**: prefix theo miền `stt*`, `tts*`, còn lại tên mô tả camelCase; bool mặc định YES phải set tường minh trong doc.
8. **Chỉ 3 Darwin notify**: `prefs.changed` (mọi thay đổi), `resetHistory`, `respring` — không thêm kênh mới.
9. **Log category** cố định (§8) — module nào chỉ được ghi category của nó.
10. **Bubble/Thông báo**: emoji đầu dòng **một trong** `⏳ ⚠️ ✓` (không dùng emoji khác trong chuỗi hiển thị).

---

## 6. IA tổng thể cuối cùng (target = v1.2; v1.1 = bỏ các nhóm ★v1.2)

```
SiriX (Root — header icon + tên + phụ đề)
│
├─ [Nhóm] Trạng thái
│   ├─ PSTitleValue  Trạng thái            (đã tắt / chưa khóa / sẵn sàng — computed)
│   └─ PSLinkCell    Thống kê chi tiết      ★ (v1.1: hàng chờ "Sắp có" hoặc ẩn)
│
├─ [Nhóm] Bật tắt
│   ├─ PSSwitch      Bật SiriX
│   ├─ PSLinkList    Chế độ trả lời         [Thông minh ⭐ | Thay thế mọi câu]
│   └─ PSLinkList    Cách kích hoạt ★       [Tự động ⭐ | Tiền tố "@ai"]
│
├─ [Nhóm] Nhà cung cấp
│   ├─ PSLinkList    Nhà cung cấp            [OpenAI tương thích ⭐ | Google Gemini]
│   ├─ PSLinkCell    Cấu hình OpenAI        → subpage ① (key/base/model/Model dự phòng★/Kiểm tra kết nối)
│   └─ PSLinkCell    Cấu hình Gemini        → subpage ② (key/model/Model dự phòng★/Kiểm tra kết nối)
│
├─ [Nhóm] Nhận diện giọng nói (STT) ★v1.2
│   ├─ PSSwitch      Thay nhận diện của Siri   (mặc định OFF — đã chốt)
│   ├─ PSLinkList    Nguồn STT                [Theo cấu hình AI ⭐ | Groq | OpenAI | Gemini | Tự chỉnh]
│   ├─ PSLinkList    Chế độ dịch              [Tắt ⭐ | Tiếng Việt | Tiếng Anh]
│   ├─ PSButton      Thử STT                  (SpringBoard ghi 3s → notification + log)
│   └─ PSLinkCell    Cấu hình STT             (base/key/model/ngôn ngữ/prompt/thời gian chờ)
│
├─ [Nhóm] Giọng đọc (TTS) ★v1.2
│   ├─ PSLinkList    Khi nào đọc              [Tắt | Lỗi | Trả lời AI ⭐ | Mọi câu]
│   ├─ PSLinkList    Nguồn TTS                [Hệ thống ⭐ | Edge | Google | Gemini | Tự chỉnh]
│   ├─ PSLinkList    Ngôn ngữ đọc             [Tự động ⭐ | Tiếng Việt | Tiếng Anh]
│   ├─ PSLinkList    Giọng nói                (lọc theo nguồn×ngôn ngữ; Hệ thống đọc giọng thật)
│   ├─ PSSlider      Tốc độ đọc               0.5–2.0
│   ├─ PSSlider      Âm lượng                  0–100
│   ├─ PSButton      Thử giọng
│   └─ PSLinkCell    Cấu hình TTS              (custom endpoint/key — nguồn Tự chỉnh)
│
├─ [Nhóm] Trả lời
│   ├─ PSSlider      Nhiệt độ                  0–2 (bước 0.1)
│   ├─ PSSlider      Số câu giữ lại            2–40
│   ├─ PSSlider      Thời gian chờ AI          2–30s (mặc định 10)
│   ├─ PSLinkList    Khi hết giờ chờ           [Bubble "chưa kịp" ⭐ | Giữ Siri gốc | Retry ★]
│   ├─ PSSwitch      Trả lời theo streaming
│   ├─ PSSwitch      Hiển thị Markdown đẹp
│   ├─ PSSwitch      Ẩn thẻ kết quả tìm kiếm
│   ├─ PSLinkList    Báo lỗi bằng giọng nói ★(hợp nhất)  [Tắt | Chỉ lỗi | Mọi lỗi]  ← thay switch speakErrors ở v1.2 (§9)
│   └─ PSSwitch      Hiện câu trả lời Siri gốc ★
│
├─ [Nhóm] Prompt
│   ├─ PSLinkCell    Xem / chỉnh prompt        → SXPromptController (segment Đang dùng/Mặc định, chip biến)
│   └─ footerText    biến {date}{device}{lang} · prompt tuỳ chỉnh thay thế toàn bộ
│
├─ [Nhóm] Công cụ AI
│   ├─ PSSwitch      Thông tin thiết bị
│   ├─ PSSwitch      Bảng nhớ tạm (copy/paste)
│   ├─ PSSwitch      Đọc trang web (https)     (+ ★ current_app trong cùng nhóm: PSSwitch "Ngữ cảnh app")
│   ├─ PSSlider      Số vòng công cụ tối đa     1–4 (mặc định 3)
│   └─ footerText    (giữ — giải thích tác vụ vẫn do Siri gốc)
│   ⚠ "Xóa lịch sử" DI CHUYỂN sang trang Lịch sử ★v1.2 (hành động phá sống cùng dữ liệu)
│
├─ [Nhóm] Trò chuyện thử ★v1.2        — 1 PSLinkCell
├─ [Nhóm] Lịch sử hội thoại ★v1.2     — 1 PSLinkCell (bên trong: list/copy/xóa từng/xóa hết/ẩn danh)
│
├─ [Nhóm] Gỡ lỗi
│   ├─ PSSwitch      Ghi log chi tiết
│   ├─ PSLinkCell    Xem & sao chép log
│   ├─ PSButton      Kiểm tra nhanh ★         (mạng · mic · khóa · endpoint → 1 alert + log)
│   └─ PSButton      Xóa thống kê ★           (đỏ, có xác nhận)
│   ⚠ "Kiểm tra kết nối" KHÔNG nằm ở đây — sống trong mỗi trang Cấu hình nhà cung cấp
│
└─ [Nhóm] Về SiriX
    ├─ PSTitleValue  Phiên bản
    ├─ PSTitleValue  Gói cài đặt
    ├─ PSButton      Kiểm tra cập nhật ★      (im lặng nếu không gọi được GitHub)
    └─ PSButton      Khởi động lại SpringBoard
```

**Delta v1.1 → v1.2 (nhất quán, không surprises):** +nhóm STT, +nhóm TTS, +Trò chuyện thử, +Lịch sử; `speakErrors`→`ttsMode`-rows; timeoutAction +`retry`; trang con LLM +`Model dự phòng`; Gỡ lỗi +Kiểm tra nhanh, +Xóa thống kê; Công cụ +`current_app`, −Xóa lịch sử; Về SiriX +Cập nhật.

---

## 7. Ma trận thất bại (mỗi ô = hành vi + log)

| Sự cố | Hành vi | Log |
|---|---|---|
| Mic bị từ chối | Tắt STT 1 phiên, bubble hướng dẫn Cài đặt (1 lần/phiên) | `stt: mic denied` |
| STT timeout/lỗi | Dùng text Apple | `stt=fallback reason=…` |
| Không mạng tại capture | Bubble "⏳ Không có mạng" (full) / passthrough (smart) — không đợi timeout | `llm: offline` |
| LLM 429/5xx | Backoff 0.5s→1.5s (≤2) → lỗi | `llm=retry n` |
| LLM timeout | `timeoutAction`: bubble ⏳ / keep / retry `fallbackModel` 1 lần (trần riêng 20–45 s; giữ Siri gốc, đáp án tới sau qua thông báo) | `resp: timeout …` |
| AI trả lời rỗng | bubble ⚠️ "AI không trả lời" | `llm: empty` |
| Stream disconnect giữa chừng | Nếu đã có ≥1 token → complete với phần có; không → coi timeout | `llm: sse cut` |
| Provider TTS lỗi | Apple đọc (đặt lại speakableText) | `tts=fallback apple` |
| Suppress Apple TTS thất bại (vẫn nghe ké) | log WARN — không chặn pipeline | `tts: apple leaked` |
| Mutate command ném exception | passthrough **bản gốc** | `err: mutate …` |
| Gen cũ về trễ (STT/LLM/push) | bỏ | `stale(gen=…)` (verbose) |
| Nhập cấu hình JSON sai | alert chi tiết, không đổi gì | `cfg: import fail …` |
| Hết quota history | cắt câu cũ (≤ turns) | im lặng |

---

## 8. Log taxonomy & Stats events (một hệ, không pha trộn)

**Category (kể từ v1.1 — mở rộng có trật tự):**
`boot · pref · hook · capture · llm · resp · stt ★ · tts ★ · err`
- Quy tắc:1 quyết định =1 dòng; DEBUG chỉ khi `verbose`; **không** ghi stats ra log mỗi lần (trừ verbose).
- Cấu trúc dòng giữ nguyên: `ts [LEVEL] [cat] [process] message`.

**Stats events (ghi tại điểm quyết định duy nhất):**

| Event | Nơi ++ | Mapping |
|---|---|---|
| `stats.replaced` | DisplayPolicy = REPLACE/INJECT | bubble/đổi text |
| `stats.kept` | DisplayPolicy = KEEP | passthrough (kể cả action? **không** — action không đếm) |
| `stats.timeout` | nhánh timeout | |
| `stats.error` | AI lỗi | |
| `stats.stt_ok / stt_fb` | SXSTT | |
| `stats.tts_ok / tts_fb` | SXTTS | |
| `stats.msAvg` | EWMA(α=0.2) của LLM ms | tỉ lệ = replaced/(replaced+timeout+error) |

---

## 9. Di trú (không phá cấu hình người dùng cũ)

| Từ | Đến | Quy tắc |
|---|---|---|
| v1.0/v1.1 `speakErrors` | v1.2 `ttsMode` | `speakErrors=YES` & chưa từng set `ttsMode` → `ttsMode=all`; mặc định cũ NO → `ttsMode=ai` giữ nguyên không ghi đè cấu hình đã chọn |
| Row `provider`-filter trên Root (v1.0–1.1) | Subpage riêng (v1.1 IA) | code bỏ nhánh filter `propertyForKey:@"provider"`; key `provider` vẫn đọc để chọn trang cấu hình nào hiển thị trạng thái |
| `timeout` đã lưu (6/15s…) | giữ nguyên | slider 2–30s chỉ là biên mới — **không** ép lại default 10 |
| `customPrompt` | như cũ | effective = custom ? custom : default (không đổi) |
| Root.plist 35 → ~N specifier | code `specifiers` chỉ còn @try load + fallback | log in tỉ lệ `N/N` |
| History array v1.0 | `history` schema mới (có `gen`,`ms`) | migrate-on-read, thiếu field → mặc định |

---

## 10. Ngân sách hiệu năng & threading

| Ngân sách | Giá trị |
|---|---|
| Block thread ACE | **≤5s hard-cap** (mọi giá trị timeout) |
| Capture → gửi STT | ≤500ms sau endpoint |
| STT total (gửi+nhận) | ≤ `sttWaitMs` (2500ms) → fallback |
| First token mục tiêu | ≤1.5s (tùy provider) |
| Flush markdown stream | 250ms ± 50 |
| TTS fetch (online) | ≤2s → fail fallback |
| Buffer mic | ≤30s × 16k × 2B ≈ 960KB |
| History | ≤ turns×2 messages, cắt đầu |
| Ghi log | O_APPEND, không lock, fail im lặng |

**Thread:** ACE-hook = block ngắn ≤5s · network = URLSession bg · AVAudio tap = audio render thread → queue serial `sx.audio` · UI/bubble/AVSpeech = main · CFPreferences = bất kỳ (nhẹ) · stats = atomic.

---

## 11. Kiểm thử phối hợp (cross-feature — chạy trước khi đóng v1.2)

1. Nói VI, STT ON, translate OFF, streaming ON, markdown ON, TTS hệ thống/auto → **voice journey**: transcript VI → bubble md đẹp gõ dần → giọng VI đọc1 lần (log `apple=silent`).
2. Nói EN, translate=vi → bubble VI → giọng VI.
3. Type-to-Siri + `@siri` (mode full, trigger=prefix) → passthrough, không gọi LLM (log `prefix skip`).
4. Stream dở + capture mới → task cũ cancel (log `stale`), không đọc TTS câu cũ.
5. Không mạng → bubble offline ngay, TTS hệ thống vẫn đọc được bubble lỗi.
6. STT endpoint sai (custom) → fallback Apple text, AI vẫn trả lời.
7. speakErrors cũ=YES sau upgrade → ttsMode=all (di trú §9).
8. Xóa lịch sử từ trang Lịch sử → công cụ AI không còn nút đó (§6).
9. Mọi row đổi → đúng1 dòng log `pref` +1 notify → SpringBoard nhận ≤500ms.
10. CI xanh 2 scheme, local-check green.
