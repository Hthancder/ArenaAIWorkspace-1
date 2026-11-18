# SiriX v1.1 — Tài liệu thiết kế (DESIGN ONLY)

> Lượt này **chỉ thiết kế**. Không thay đổi code.
> **Quy ước / IA / luồng tổng thể → `DESIGN-SYSTEM.md` (nguồn sự thật, ưu tiên khi mâu thuẫn).**
> Cơ sở: log thật từ thiết bị iOS 15 (roothide,12:33–12:38, v1.0.2) + cấu trúc code hiện tại.

---

## A. Tổng quan

| Nhóm | Nội dung |
|---|---|
| P0 — Lỗi | (1) Thay thế không nhất quán dù chọn "Thay thế mọi câu trả lời"; (2) AI tra web → giao diện Siri tự đóng; (3) Đang nhắn → giao diện tự đóng |
| P1 — Tính năng | Streaming; Xem/chỉnh/khôi phục system prompt; Render Markdown; Cấu trúc Settings mới theo nhóm |
| P2 — Lượng chất | Thống kê, lịch sử hội thoại, tiền tố kích hoạt, model dự phòng, xuất/nhập cấu hình… |

**Nguyên tắc thiết kế**
1. Giữ nguyên hook surface đã chạy (AFConnection/AFConversation — không đổi selector).
2. Mọi hiển thị = bong bóng Ace (`SAUIAssistantUtteranceView`) / sửa `SAUIAddViews` tại chỗ — không tweak UI SpringBoard.
3. **Không bao giờ để đường ACE bị chặn > 5 giây** (chống watchdog đóng dialog).
4. Settings tiếng Việt, nhóm gọn, mọi thứ chỉnh được tại chỗ.
5. Log là kênh chẩn đoán số 1 — mọi quyết định display đều có dòng log.

---

## B. Phân tích & thiết kế sửa 3 lỗi P0

### B1. "Lúc AI trả lời, lúc Siri thường" dù chọn Thay thế mọi câu trả lời

**Root cause từ log:**
1. **Hết timeout** — câu #3: AI cần 21,7s > chờ 6s → giữ Siri gốc.
2. **Apple gửi AddViews không có trường văn bản** (chỉ thẻ, bị ẩn) → câu #2 rơi về Siri gốc *(v1.0.3 đã thêm chèn bubble — cần xác minh)*.
3. **AI lỗi** (`speakErrors` tắt) → giữ câu gốc.
4. Mode được đọc đồng bộ qua notify ✓ (log xác nhận SB và Prefs thấy cùng giá trị) — không phải lỗi mode.

**Thiết kế — Display Policy (ma trận quyết định duy nhất):**

| Trạng thái \ Chế độ | Thông minh | Thay thế mọi câu |
|---|---|---|
| AI sẵn sàng **trước** khi lệnh Siri đến | Sửa text / chèn bubble | **Sửa text / chèn bubble** |
| AI sẵn sàng **trong lúc chờ** (≤ timeout) | Sửa / chèn bubble | Sửa / chèn bubble |
| **Hết timeout** | Giữ Siri gốc (mặc định) + log gợi ý | **Không được thả Siri gốc**: hiện bubble "⏳ AI trả lời quá muộn — thử lại" *(hoặc retry 1 lần — xem J2)* |
| **AI lỗi** | Bubble lỗi nếu bật "Báo lỗi bằng giọng nói";否则 giữ gốc | **Luôn hiện bubble lỗi** ("⚠️ AI gặp lỗi: …") — không thả Siri gốc |
| Lệnh là **tác vụ** (báo thức, mở app…) | Không đụng | Không đụng (an toàn — AI không nhận tác vụ) |

**Ràng buộc cứng (full mode):** câu hỏi đã capture mà AI đã/đang trả lời thì **mỗi nhánh kết thúc đều phải mutate** — không có đường nào trả AddViews gốc.

**Cơ chế bảo đảm:**
- Module mới `SXDisplayPolicy` — một hàm duy nhất `decision(mode, state, commandType)` trả về: `REPLACE_TEXT | INJECT_BUBBLE | KEEP_ORIGINAL | SHOW_ERROR_BUBBLE`. Tặng kèm log `"chính sách: …"` để debug.
- `INJECT_BUBBLE` = bong bóng `SAUIAssistantUtteranceView` (đã có ở v1.0.3) — luôn có `aceId` + `dialogId` + `parentGroupId` (xem B2).
- Đặt `errored (code -6)` **chỉ khi** không phải lỗi sanitize rỗng — sanitize rỗng → bubble lỗi chữ, không tín hiệu lỗi cho Siri (tránh dismiss).

### B2. "AI tra web → giao diện Siri tự đóng"

**Xác suất nguyên nhân (sắp xếp theo khả năng):**

| # | Giả thuyết | Vì sao hợp lý |
|---|---|---|
| 1 | **Chặn luồng ACE quá lâu** — tool loop tra web = 2–4 vòng × 5–10s ≈ 15–30s giữ thread ACE | Câu thường (≤6s) không đóng; tra web hay đóng → khớp |
| 2 | Trả tín hiệu lỗi `errored -6` cho Siri → dialog bị dismiss | Đường lỗi sanitize rỗng có thật (v1.0.2 log) |
| 3 | Bubble chèn thiếu field ACE (`aceId/dialogId`) → view controller invalid → tự pop | Bubble chèn bằng `alloc/init` — chưa chắc đủ field |
| 4 | Strip thẻ để lại `views` rỗng/trùng → state machine của dialog vỡ | Đã từng có nhánh `views=[]` |

**Thiết kế — "Không chặn dài, không lỗi, đủ field":**

1. **Hard-cap chặn luồng ACE = 5s** (đặt trong code, không phải setting):
   - Lệnh đến mà answer **sẵn** → mutate ngay (không chờ — phần lớn trường hợp xảy ra vì LLM bắt đầu ngay khi capture).
   - Chưa sẵn → chờ nốt **tối đa 5s** → quá hạn: **passthrough sạch** (Siri tự spinner — nó vẫn sống) + đăng ký **deferred push** (B2.1).
2. **Deferred push (khóa chống đóng/mất câu trả lời):**
   - Khi answer về muộn (sau khi đã passthrough): **gửi một `SAUIAddViews` mới** vào session đang mở (dialogId mới, cùng generation, còn hiệu lực <30s) → UI không đóng, câu trả lời "vào" sau.
   - Đây là outbound command — cần spike 1 API gửi (dự kiến `AFConnection` ngoài luồng inbound). Nếu spike thất bại → phương án dự phòng: notification "SiriX đã có câu trả lời" + lưu vào Lịch sử (P2).
   - *Để mở cho J1 — xác nhận phạm vi.*
3. **Web search không được làm treo UI:**
   - `fetch_url` giữ timeout 3500ms ✓; **giới hạn 2 vòng tool khi đang trong vùng chờ hiển thị**; các vòng còn chạy nền → kết quả cuối đưa vào deferred push.
   - Streaming (Phần C) cho **token đầu tiên sớm** → kết thúc chờ sớm hơn hẳn.
4. **Không bao giờ để `views = []`:** sau strip, nếu rỗng → chèn bubble (đã có); nếu giữ lại được ≥1 view gốc thì giữ.
5. **Mutate-on-copy:** trước khi sửa command, tạo bản copy (dict/ACE copy) — sửa lỗi → passthrough **bản gốc nguyên vẹn**; mọi thao tác bọc `@try/@catch` (handler đã có) — không để object hỏng lọt vào `%orig`.
6. **Validity checklist cho mọi view chèn:** `class` hợp lệ + `aceId` + `dialogId` (+ `parentGroupId` nếu có) — mỗi bubble chèn đều set đủ; log checklist khi DEBUG.

### B3. "Đang nhắn thì giao diện tự đóng"

- Thuộc gốc B2 (chặn lâu + ACE invalid) — hard-cap 5s + mutate-on-copy + validity checklist xử lý.
- **Guard thế hệ (generation):** deferred push / bubble chỉ được gửi khi `generation` khớp và <30s — câu cũ không được bơm vào dialog mới (đã có counter ✓ — áp dụng thêm cho push).
- **Không bao giờ block thread chính của ACE khi đang stream** (stream đọc trên background queue, mutate tại điểm hiển thị).

---

## C. Streaming (trả lời theo từng chữ)

### Wire protocol
- **OpenAI-compatible:** body thêm `"stream": true` → đọc SSE `data: {…delta.content…}` → cộng dồn → `data: [DONE]`.
  - Trong stream, `delta.tool_calls` phải gom theo index → **quyết định: stream chỉ dùng khi KHÔNG cần tool**; nếu model trả `tool_calls` → fallback sang vòng non-stream như hiện tại (đơn giản, an toàn).
- **Gemini:** `streamGenerateContent?alt=sse` — cùng cách đọc.

### Mức hiển thị (chọn cho v1.1)

| Mức | Mô tả | Quyết định |
|---|---|---|
| **M1 — Kết nối sớm** | LLM bắt đầu stream **ngay khi capture**, hiển thị khi hoàn tất — lợi ích: token đầu làm mốc timeout mới + log first-token | ✅ **Làm ngay** |
| **M2 — Gõ dần** | Từ token đầu: cập nhật text trong bubble đang mở (thử cùng `dialogId` để ACE thay tại chỗ; nếu ACE không nhận → mỗi ~500ms một AddViews mới) | 🔬 **Spike 1 phiên trên iOS15** — được thì bật, không thì bỏ |
| **M3 — Caret nhấp nháy** | Giống ChatGPT gõ chữ | ❌ iOS15 Ace không hỗ trợ — không làm |

- **Setting:** `streaming` (default ON) — "Trả lời theo từng chữ (streaming)".
- **Ảnh hưởng tới timeout:** timeout tính từ **token đầu tiên** (đã thấy tiến trình) → tăng đáng kể tỉ lệ thay thế; kết hợp hard-cap 5s của B2.

---

## D. Hệ thống Prompt (xem / chỉnh / khôi phục)

### Mô hình dữ liệu (giữ tương thích)
- `customPrompt` (string, CFPreferences `com.sirix.tweak`): **rỗng = dùng mặc định**.
- Mặc định: `SXDefaultSystemPrompt()` — chuyển sang file riêng `Sources/SXPromptDefault.m` để dễ bảo trì.
- **Biến hỗ trợ** (chèn runtime): `{date}` (yyyy-MM-dd), `{device}` (ví dụ "iPhone (iOS 15)"), `{lang}` — câu hỏi không cần biến vì nằm trong messages.

### Màn hình "Prompt" (redesign `SXPromptController`)
```
┌ Prompt ──────────────────────────┐
│ [Đang dùng] [Mặc định]          │  ← segmented: xem 2 bản
│ ┌──────────────────────────────┐ │
│ │ (TextView — hiện EFFECTIVE   │ │  ← sửa trực tiếp = tạo bản tùy chỉnh
│ │  prompt: custom nếu có,      │ │
│ │  không thì mặc định)        │ │
│ └──────────────────────────────┘ │
│ Đang dùng: prompt tùy chỉnh      │  ← nhãn trạng thái (N ký tự)
│  {date} {device} {lang}          │  ← chip biến — bấm để chèn
│ [Lưu] [Khôi phục mặc định] [Sao chép] │
└──────────────────────────────────┘
```
- **Xem mặc định:** mở màn hình là thấy ngay prompt mặc định trong ô (khi chưa có custom).
- **Chỉnh:** sửa text → bấm **Lưu** → lưu thành `customPrompt`.
- **Khôi phục mặc định:** xóa `customPrompt` → ô hiện lại mặc định + nhãn "Đang dùng mặc định".
- **Tự nhận diện:** text lưu vào **khác** mặc định thì ghi; **giống** mặc định → lưu rỗng (tương lai upgrade mặc định tự áp dụng).
- Chặn mất mát: sửa mà chưa lưu → thoát hiện alert "Thoát mà chưa lưu?".
- Footnote: "Prompt áp dụng cho mọi câu hỏi, mọi nhà cung cấp."

---

## E. Render Markdown

- Module mới **`SXMarkdown`** (Sources): Markdown → chữ đẹp cho bong bóng Siri (iOS15 Ace chỉ có text thường):

| Input | Output |
|---|---|
| `# Tiêu đề` … `######` | `— TIÊU ĐỀ —` (in hoa, dòng riêng) |
| `**đậm**` / `__đậm__` | giữ chữ, bỏ dấu |
| `*nghiêng*` / `_nghiêng_` | giữ chữ, bỏ dấu |
| `- ` / `* ` / `1. ` | `• ` / giữ số |
| `` `code` `` | giữ nguyên (bao `…` nếu có space) |
| ``` ```fence``` ``` | mỗi dòng + tiền tố `▸ `, giữ thụt đầu dòng |
| `[nhãn](url)` | `nhãn (url)` |
| `> trích` | `▍trích` |
| bảng Markdown | mỗi dòng: `— ô: giá trị` |
| --- phân cách | dòng `· · ·` |

- **Áp dụng ở:** bubble SiriX (default ON), ô xem prompt, xem lịch sử (P2).
- **Giữ nguyên văn** trong history + khi gửi lên API (chỉ đổi lúc hiển thị).
- Setting: `markdown` (default ON) — "Hiển thị Markdown đẹp".

---

## F. Cấu trúc Settings mới (IA v2)

> Quyết định lớn: **tách trang con** cho từng nhà cung cấp — bỏ cơ chế ẩn/hiện row theo `provider` trên trang root (đỡ reload, root gọn hơn).

```
SiriX (Root)                              ← header icon + tiêu đề (giữ)
│
├─ [Nhóm] Trạng thái
│   ├─ PSTitleValue  Trạng thái
│   └─ PSLinkCell    Thống kê chi tiết        → trang Thống kê (P2; v1.1 có hàng chờ)
│
├─ [Nhóm] Bật tắt
│   ├─ PSSwitch      Bật SiriX
│   ├─ PSLinkList    Chế độ trả lời            [Thông minh | Thay thế mọi câu]
│   └─ PSLinkList    Cách kích hoạt            [Tự động | Tiền tố "@ai"]  (P2)
│
├─ [Nhóm] Nhà cung cấp
│   ├─ PSLinkList    Nhà cung cấp               [OpenAI tương thích | Google Gemini]
│   ├─ PSLinkCell    Cấu hình OpenAI/Groq…      → trang con ①
│   └─ PSLinkCell    Cấu hình Google Gemini     → trang con ②
│
├─ [Nhóm] Trả lời
│   ├─ PSSlider      Nhiệt độ                   0–2, step 0.1, showValue
│   ├─ PSSlider      Số câu giữ lại             2–40
│   ├─ PSSlider      Thời gian chờ AI (giây)     2–30, default 10 — chỉnh tự do
│   ├─ PSLinkList    Khi hết giờ chờ (chế độ Thay thế)
│   │                  [Bubble "chưa kịp" | Giữ Siri gốc]   (mới — chỉnh được)
│   ├─ PSSwitch      Trả lời theo streaming     (mới)
│   ├─ PSSwitch      Hiển thị Markdown đẹp       (mới)
│   ├─ PSSwitch      Ẩn thẻ kết quả tìm kiếm
│   └─ PSSwitch      Báo lỗi bằng giọng nói
│
├─ [Nhóm] Prompt
│   ├─ PSLinkCell    Xem / chỉnh prompt         → SXPromptController (redesign, D)
│   └─ footerText    giải thích mặc định/tùy chỉnh + biến
│
├─ [Nhóm] Công cụ AI
│   ├─ PSSwitch      Thông tin thiết bị
│   ├─ PSSwitch      Bảng nhớ tạm (copy/paste)
│   ├─ PSSwitch      Đọc trang web (https)
│   ├─ PSSlider      Số vòng công cụ tối đa     1–4, default 3 (mới)
│   └─ PSButton      Xóa lịch sử hội thoại
│
├─ [Nhóm] Gỡ lỗi
│   ├─ PSSwitch      Ghi log chi tiết
│   ├─ PSLinkCell    Xem & sao chép log
│   └─ PSButton      Xóa thống kê               (P2)
│
└─ [Nhóm] Về SiriX
    ├─ PSTitleValue  Phiên bản                   (1.1.0)
    ├─ PSTitleValue  Gói cài đặt                 (rootless/roothide)
    └─ PSButton      Khởi động lại SpringBoard
```

> ⚠ **Nhất quán (đã chốt):** “Kiểm tra kết nối” sống trong 2 trang *Cấu hình OpenAI/Gemini* (không lặp ở Gỡ lỗi); “Xóa lịch sử” sẽ chuyển vào trang *Lịch sử hội thoại* khi có (v1.2).

**Trang con ① — Cấu hình OpenAI tương thích**
```
[Nhóm] Khóa & Endpoint
  ├─ PSSecureEditText  Khóa API        (placeholder "sk-… / gsk-…")
  ├─ PSEditText        Địa chỉ API gốc  (isURL, default api.openai.com/v1)
  │    footer: "Hỗ trợ OpenAI, Groq, OpenRouter, LM Studio… — mọi endpoint /chat/completions"
  └─ PSEditText        Mô hình          (default gpt-4o-mini)
[Nhóm] Kiểm tra
  ├─ PSButton          Kiểm tra kết nối   (dời từ trang Gỡ lỗi sang đây)
  └─ (P2) PSEditText   Model dự phòng
```
**Trang con ② — Cấu hình Gemini** (cấu trúc y hệt: Khóa API `AIza…`, Mô hình, Kiểm tra).

**Keys mới (bảng thống nhất):**

| Key | Type | Default | Nhóm |
|---|---|---|---|
| `streaming` | bool | YES | Trả lời |
| `markdown` | bool | YES | Trả lời |
| `timeoutAction` | `bubble`\|`keep` | `bubble` | Trả lời (khi hết giờ, chế độ Thay thế) |
| `maxToolRounds` | int 1–4 | 3 | Công cụ |
| `triggerMode` | `auto`\|`prefix` | `auto` | Bật tắt (P2) |
| `fallbackModel` | string | "" | Trang con (P2) |
| `incognito` | bool | NO | Gỡ lỗi (P2) |
| `stats.*` | int | 0 |,readonly (P2) |

**Chuẩn visual (nhất quán):**
- Mỗi nhóm = 1 `PSGroupCell` có `label` + `footerText` giải thích bằng tiếng Việt, giọng thân thiện.
- Slider luôn `showValue`; switch ngắn gọn; button đỏ riêng cho hành động phá (xóa lịch sử/thống kê).
- Thứ tự nhóm theo tần suất dùng: Bật tắt → Nhà cung cấp → Trả lời → Prompt → Công cụ → Gỡ lỗi → Về.

---

## G. Tính năng chất lượng (nghĩ đủ)

**v1.1 — làm ngay (P0+P1):** Display Policy (+ `timeoutAction` chỉnh được), chống đóng UI (hard-cap 5s + mutate-on-copy + validity checklist), streaming M1(+M2 spike), Prompt UX, Markdown, IA Settings mới + trang con, `maxToolRounds`.

**v1.2 — P2 (roadmap):**

| Tính năng | Mô tả |
|---|---|
| Trang **Thống kê** | Số câu đã thay / giữ Siri / timeout / lỗi / ms trung bình — đếm ngay khi display policy chạy, ghi vào `stats.*` |
| Trang **Lịch sử hội thoại** | Danh sách câu hỏi–đáp án (đọc từ history đã lưu), copy từng câu, xóa từng câu/all |
| **Chế độ ẩn danh** | Không lưu history (chỉ dùng trong phiên) |
| **Tiền tố kích hoạt** | `@ai …` = bắt buộc AI; `@siri …` = bỏ qua; chế độ "Tự động" giữ như hiện tại |
| **Model dự phòng** | Lỗi/timeout → retry 1 lần bằng `fallbackModel` (cùng endpoint) |
| **Đẩy câu trả lời trễ** | Deferred push hoàn chỉnh (nếu spike B2.1 thành công) |
| **Câu trả lời Siri gốc** | Footer nhỏ "Siri: …" dưới bubble khi bật (đối chiếu) |
| **Xuất/nhập cấu hình** | JSON chia sẻ cấu hình (share qua AirDrop/Files) |
| **Đọc to mọi câu trả lời** | Tùy chọn speak (không chỉ khi lỗi) |
| **Tự động dự phòng offline** | Không có mạng → hiện bubble "Không có mạng — dùng Siri gốc" ngay |
| **Quick-toggle** | Hành động nhanh trong Control Center?? — ngoài phạm vi (giữ理想 nhỏ) |

---

## H. Kiến trúc module (dự kiến cho v1.1)

```
Sources/
  SXDisplayPolicy.{h,m}   ← MỚI: ma trận quyết định hiển thị (B1)
  SXStream.{h,m}          ← MỚI: SSE client (tách từ SXLLM)
  SXMarkdown.{h,m}        ← MỚI: md → text đẹp (E)
  SXStats.{h,m}           ← MỚI: bộ đếm (P2 nhưng giao diện sẵn)
  SXACEPush.{h,m}         ← MỚI (spike): gửi AddViews ra session (B2.1)
  SXPromptDefault.m       ← MỚI: default prompt tách riêng (D)
  SXLLM.m                 ← SỬA: dùng SXStream, tool-fallback khi stream
  SXIntercept.m           ← SỬA: gọi DisplayPolicy; hard-cap 5s; mutate-on-copy
Prefs/
  SXSubpageOpenAIController.m   ← MỚI
  SXSubpageGeminiController.m   ← MỚI
  SXPromptController.m          ← REDESIGN (D)
  Resources/Root.plist          ← RESTRUCTURE (F)
```
Không đổi: hook selector surface, định dạng log, scheme rootless/roothide, CI.

---

## I. Ma trận kiểm thử chấp nhận (v1.1)

1. Full mode: 10 câu Type-to-Siri liên tiếp → **10/10 hiện lời AI** (trừ câu là tác vụ).
2. Câu hỏi tra web (fetch_url) → **UI không đóng**; nếu trả lời trễ → bubble vào sau (hoặc P2 notification).
3. Không có block nào trên luồng ACE > 5s (log `chặn N ms`).
4. Streaming ON: log có `first-token=…ms`; OFF: hành vi như cũ.
5. Prompt: sửa → Lưu → respring → giữ; Khôi phục mặc định → effective = default; lưu đúng default → custom rỗng.
6. Markdown: mẫu đủ 10 loại cú pháp ở E → bubble dễ đọc, không sót ký tự `*#|`.
7. Settings: đủ nhóm F; trang con OpenAI/Gemini hiện đúng khi đổi nhà cung cấp; mọi row chỉnh được.
8. Regression: test connection, xem log, xóa lịch sử, respring, rootless/roothide.

---

## J. Đã chốt (phiếu chọn của bạn —2026-11-18)

1. **Deferred push** (câu trả lời trễ "vào" đúng dialog đang mở) → **để v1.2**.
   v1.1 cam kết: hard-cap 5s, không đóng UI, bubble lỗi/bubble trễ, mutate-on-copy.
2. **Hết timeout ở chế độ Thay thế** → **chỉnh được trong Cài đặt**: row *"Khi hết giờ chờ"* = `bubble` (mặc định) | `keep`; thời gian chờ chỉnh bằng slider 2–30s; *(P2: thêm phương án `retry` bằng model dự phòng)*.
   Yêu cầu "cho chỉnh timeout tùy chỉnh, etc." → mọi thông số sống trong Settings, nhóm Trả lời / Nâng cao.
3. **Thống kê + Lịch sử hội thoại** → **để v1.2**.
