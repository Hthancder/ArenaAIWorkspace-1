# SiriX — Thiết kế giao diện Settings (UI/UX) & logic chỉn chu

> Lớp UI chi tiết **kế thừa** `DESIGN-SYSTEM.md` (IA, quy ước) — khi mâu thuẫn về **nhóm/luồng**: SYSTEM thắng; tài liệu này thắng về **thẩm mỹ & logic tương tác**.
> Áp dụng iOS 15 grouped table (Preferences/PSListController) — dark mode tự động theo hệ thống.

---

## 1. Nguyên tắc thiết kế

1. **Hiểu ngay trong 3 giây**: Status Card đầu trang trả lời “nó đang hoạt động không?”, mỗi nhóm có footer 1–2 câu.
2. **Một loại dữ liệu — một loại control** (bảng SYSTEM §5.1) — không tạo kiểu row lạ mắt nhưng khó đoán.
3. **Hiệu lực ngay, không nút Lưu** (trừ Prompt = document); mọi thay đổi phản hồi trong ≤500ms (log + reload row nếu cần).
4. **Mọi hành động có phản hồi** — bấm phải thấy: alert tiến trình → kết quả ✓/⚠️ → log. Không có “bấm rồi im”.
5. **Dọn dẹp an toàn**: đỏ + xác nhận; cấu hình sai **chặn sớm** (URL), **kiểm tra mạnh** bằng nút Kiểm tra/Thử.

---

## 2. Design system

### 2.1 Màu & chữ (chỉ dùng semantic của iOS — tự động dark mode)
| Thành phần | Style |
|---|---|
| Nhóm (group header) | footFont system13 `.secondaryLabel` (mặc định Settings) |
| Footer | system13 `.secondaryLabel` |
| Label row | system17 `.label` (mặc định) |
| Giá trị row (đã chọn) | system17 `.secondaryLabel` — right-aligned |
| Trạng thái tốt | `.systemGreen` (chấm ● + chữ) |
| Trạng thái cần chú ý | `.systemOrange` |
| Trạng thái lỗi/chưa cấu hình | `.systemRed` / `.secondaryLabel` cho “chưa đặt” |
| Nút phá (xóa) | `.systemRed` |
| Nhấn mạnh trong footer | **đậm** đúng thuật ngữ (dùng `**…**` khi render footer nếu cần) |

- **Không** dùng màu tuỳ biến, không gradient, không font ngoài system — nhất quán với Cài đặt gốc (điều kiện “đẹp = thuộc về iOS”).
- Custom cell: `adjustsFontForContentSizeCategory = YES` (Dynamic Type), chiều cao ≥44pt.

### 2.2 Bảng thuật ngữ (bắt buộc — trong label, footer, alert, log hướng dẫn)
| Dùng ✅ | Tránh ❌ |
|---|---|
| Khóa API | API key, token, secret |
| Nhà cung cấp | Provider, backend |
| Địa chỉ API gốc | Endpoint, base URL |
| Mô hình | Model |
| Thời gian chờ AI | Timeout |
| Nhận diện giọng nói (STT) | Speech-to-text, transcribe |
| Giọng đọc (TTS) | Text-to-speech, đọc voice |
| Chế độ trả lời | Mode, chính sách |
| Câu trả lời | Response, answer |
| Điểm kiểm tra = **“Kiểm tra…”** (mạng) / **“Thử…”** (âm thanh, mẫu) | Test… |

### 2.3 Định dạng số & đơn vị
| Giá trị | Hiển thị |
|---|---|
| Nhiệt độ | 1 chữ thập phân — `0.7` (bước 0.1, làm tròn half-even) |
| Thời gian chờ | số thuần, đơn vị nằm trong **label**: `Thời gian chờ AI (giây)` |
| Tốc độ đọc | `1.0×` (bước 0.05) |
| Âm lượng | `100` (bước 5) |
| Kích thước khóa | log mới: `gsk_…gWIT (56 ký tự)` (đã có — giữ nguyên) |
| Thời lượng ms | `672 ms` / `9,5 giây` (≥1s → giây,1 thập phân) |

### 2.4 Linh kiện chuẩn (component catalog)

**① StatusCard** (`cellClass = SXStatusCell`, thay row “Trạng thái”):
```
┌──────────────────────────────────────────────┐
│  ●  SiriX sẵn sàng                    ▸     │  ← chấm màu + bold title
│     OpenAI · gpt-4o-mini · STT đang tắt     │  ← subtitle secondary,1 dòng
└──────────────────────────────────────────────┘
```
- Chấm: green = đủ cấu hình & (lần test gần nhất không lỗi); orange = thiếu cấu hình phụ (chưa test/STT mic chờ); red = test lỗi gần nhất / không khóa.
- Không chevron (không push) — tap → run **“Kiểm tra nhanh”** (logic §4.2).
- Nội dung computed — pseudocode §4.1.

**② Row tiêu chuẩn** — đúng bảng ánh xạ SYSTEM §5.1; label ≤2 dòng; value không truncate quá 40% chiều rộng.

**③ Nút test** — pattern modal: `alert tiến trình (không nút Đóng? → CANCEL được) → kết quả` (chi tiết §4.4).

**④ Xác nhận phá** — `UIAlertController` title = hành động, message = “Không hoàn tác được”, actions: **Hủy** (cancel style) + **Xóa** (destructive, `.destructive` style — chữ đỏ).

**⑤ Empty state** — mọi trang danh sách có chữ trung tâm `.secondaryLabel`1–2 câu (Log: “Chưa có log — gọi Siri hoặc mở Settings để tạo.”; Lịch sử: “Chưa có câu hỏi nào.”).

**⑥ Biến chèn prompt (chip)** — row ngang các chip `{date} {device} {lang}`: `UIButton` capsule, bg `.secondarySystemBackground`, tap → chèn vào con trỏ.

**⑦ Segmented preview** — `[Đang dùng] [Mặc định]` = `UISegmentedControl` titleView.

---

## 3. Màn hình (wireframe)

### 3.1 Root — “sẵn sàng → cấu hình → tinh chỉnh”
```
[SiriX — header: icon 68pt bo 15 · tên 24 semibold · phụ đề 13 secondary]
● SiriX sẵn sàng  ▸            ← StatusCard (tap = Kiểm tra nhanh)
┌ BẬT TẮT ────────────────────────────────┐
│ Bật SiriX                         [● ]  │
│ Chế độ trả lời              Thông minh ›│
│ Cách kích hoạt              Tự động   ›│
└ footer: Thông minh giữ tác vụ cho Siri…┘
┌ NHÀ CUNG CẤP ───────────────────────────┐
│ Nhà cung cấp         OpenAI tương thích›│
│ Cấu hình OpenAI                  ›      │  ← phụ đề mờ: “đã có khóa ✓ / chưa có khóa”
│ Cấu hình Gemini                  ›      │
└ footer: Mọi endpoint /chat/completions…┘
┌ NHẬN DIỆN GIỌNG NÓI ───────────────────┐   ← v1.2
│ Thay nhận diện của Siri            [○ ] │
│ Nguồn STT              Theo cấu hình AI›│
│ Chế độ dịch                    Tắt    ›│
│ Thử STT                             ›   │   ← dạng button
│ Cấu hình STT                        ›   │
└ footer: SiriX tự ghi âm chỉ khi Siri mở…┘
┌ GIỌNG ĐỌC (TTS) ───────────────────────┐   ← v1.2
│ Khi nào đọc                Trả lời AI ›│
│ Nguồn TTS                    Hệ thống  ›│
│ Ngôn ngữ đọc              Tự động     ›│
│ Giọng nói            An (Tiếng Việt)  ›│
│ Tốc độ đọc                      1.0×    │
│ Âm lượng                           100   │
│ Thử giọng                          ›   │
└ footer: Tự nhận ngôn ngữ phản hồi để chọn giọng phù hợp.┘
┌ TRẢ LỜI ───────────────────────────────┐
│ Nhiệt độ                            0.7 │
│ Số câu giữ lại                        8 │
│ Thời gian chờ AI (giây)               10 │
│ Khi hết giờ chờ        Bubble "chưa kịp"›│
│ Trả lời theo streaming            [● ]  │
│ Hiển thị Markdown đẹp              [● ] │
│ Ẩn thẻ kết quả tìm kiếm           [● ]  │
│ Báo lỗi bằng giọng nói          Tắt   ›│
│ Hiện câu trả lời Siri gốc         [○ ] │
└ footer: AI trả lời cùng ngôn ngữ câu hỏi.┘
┌ PROMPT ────────────────────────────────┐
│ Xem / chỉnh prompt                    ›│  ← phụ đề: “Đang dùng mặc định”
└ footer: {date} {device} {lang} · thay… ┘
┌ CÔNG CỤ AI ───3 switches + current_app·số vòng┘
┌ TRÒ CHUYỆN THỬ ───1 link┘            ← v1.2
┌ LỊCH SỬ HỘI THOẠI ───1 link┘         ← v1.2
┌ GỠ LỖI ── verbose · Xem log · Kiểm tra nhanh · Xóa thống kê ─┐
┌ VỀ SIRIX ── Phiên bản · Gói · Kiểm tra cập nhật · Respring ──┘
```
- Phụ đề mờ dưới link cấu hình provider = trạng thái cụ thể (`Chưa có khóa` / `Đã có khóa · đã kiểm tra`) — computed giống StatusCard.

### 3.2 Cấu hình OpenAI (subpage①) — “form an toàn”
```
Cấu hình OpenAI
┌ KHÓA & ENDPOINT ───────────────────────┐
│ Khóa API            [••••••••gWIT    ] │  ← secure, placeholder "sk-… / gsk-…"
│ Địa chỉ API gốc     [api.groq.com/…  ] │  ← isURL, auto https:// khi thiếu
│ Mô hình              [llama-3.3-70b…  ] │
│ Model dự phòng       [gpt-4o-mini     ] │  ← v1.2, footer: dùng khi lỗi/timeout
└ footer: Hỗ trợ OpenAI, Groq, OpenRouter… ┘
┌ KIỂM TRA ──────────────────────────────┐
│ Kiểm tra kết nối                       │  ← pattern modal §4.4
└ footer: Kiểm tra gửi1 câu thật, không lưu lịch sử. ┘
```
- Tương tự **Cấu hình Gemini** (placeholder `AIza…`) và **Cấu hình STT/TTS** (nguồn Tự chỉnh).

### 3.3 Prompt — “document editor”
```
Xem / chỉnh prompt          [Đang dùng | Mặc định]   ← segmented
┌────────────────────────────────────────┐
│  (UITextView — nội dung effective,     │
│   scroll, font15 mono? NO → system15)  │
└────────────────────────────────────────┘
Đang dùng: prompt tuỳ chỉnh (482 ký tự)   ← nhãn1 dòng, xanh/secondary
[{date}] [{device}] [{lang}]              ← chip chèn biến
[Lưu] [Khôi phục mặc định] [Sao chép]     ← bar nút dưới, primary/plain/destructive-lite
```
- Prompt mặc định **hiện ngay trong ô** khi chưa có bản tuỳ chỉnh (yêu cầu đã chốt).

### 3.4 Trang Log
```
Xem & sao chép log          [Sao chép] [Chia sẻ] [Xóa]
┌ monospace12 --------------------------------┐
│12:36:26 [INFO ] [capture] …                │  ← UITextView read-only, auto-refresh1s
│ …                                          │
└Đầu file ────────●──────── Đuôi (mới nhất) ┘ ← custom slider mỏng vị trí đọc
```
- Xoay file (size thu về) → reload toàn bộ; đang ở đáy → stick đáy (mới thêm tự cuộn theo), đang xem giữa → **không giật**.

### 3.5 Lịch sử hội thoại
```
Lịch sử hội thoại        [Xóa tất cả]
┌ Ghi âm・Ẩn danh (switch) ───────────────┐   ← incognito inline hàng đầu
│ 12:36  “hi ban”                    ⌫    │  ← swipe delete
│        AI: “Chào bạn! …”                │
│ …                                       │
└ trang 1:50 · [Tải thêm] khi cuộn hết ┘
```
- Tap → chi tiết:2 khối Q/A, nút **Sao chép câu này** / **Xóa**; empty state §2.4⑤.

### 3.6 Trò chuyện thử (mini-chat)
```
Trò chuyện thử
┌──────────────────────────────────────┐
│ bubbles: user phải / SiriX trái      │  ← md render như bubble thật
│ SiriX: …đang gõ ●●○                 │  ← placeholder3 chấm khi chờ
│                                      │
├──────────────────────────────────────┤
│ [Nhập câu hỏi…)         [■/Dừng] [➤]│  ■ khi đang chờ/stream; ➤ gửi
└──────────────────────────────────────┘
```
- **Ngữ cảnh riêng**: history test **trong RAM, tự xống khi rời trang** — không đụng lịch sử Siri (footer ghi rõ).

### 3.7 Thống kê
```
Thống kê                 [Xóa thống kê]
┌ header view (tableHeaderView — lưới2×3 số) ┐
│  Đã thay thế     Giữ Siri     Timeout       │
│     128            7            9           │
│  Lỗi             Tỉ lệ        TB trễ        │
│      2           89,1%        3,2 giây      │
└──────────────────────────────────────────────┘
Chi tiết theo ngày · STT 44 lần · TTS 131 lần …
```

### 3.8 Chọn giọng (custom list — không phải PSListItemsController)
```
Giọng nói — Hệ thống · [ Tiếng Việt ▾ ]    ← bộ lọc nguồn×ngôn ngữ
● An            (vi-VN)        ← tap = chọn + NGHE thử ngay0,8s
○ Minh          (vi-VN)
○ Kelly         (en-US)
```
- Nghe thử: `AVSpeechSynthesizer` nói `"Xin chào, đây là SiriX"` — không cần mạng với nguồn Hệ thống.

---

## 4. Logic chỉn chu (pseudocode — “mọi logic phải chỉn chu”)

### 4.1 computeStatus() — một hàm duy nhất cho StatusCard + phụ đề link
```
func computeStatus() -> (color, title, subtitle, micHint):
  if !enabled:            return (.secondary, "Đã tắt", "Bật SiriX để trả lời bằng AI", -)
  key = prefs.activeAPIKey            // theo provider đang chọn
  if key.isEmpty:          return (.orange, "Chưa có khóa API",
                                   "Mở “Cấu hình \(providerLabel)” để dán khóa", hint)
  if lastTest.failedRecently(<1h): return (.red, "Kiểm tra kết nối lỗi",
                                           lastTest.shortReason, -)
  if sttEnabled && micDenied:      return (.orange, "STT cần quyền mic",
                                           "Bật mic cho Siri trong Cài đặt", hint)
  sub = "\(providerShort) · \(modelShort) · STT \(sttEnabled ? "bật" : "tắt")"
  return (.green, "SiriX sẵn sàng", sub, -)
```
- Nguồn dữ liệu: prefs + `lastTest` (CFPreferences, có timestamp) + micDenied (đọc từ log flag do SpringBoard ghi, cache1 phiên).
- StatusCard & phụ đề subpage dùng **cùng1 nguồn** → không bao giờ “trái màu”.

### 4.2 Kiểm tra nhanh (tap StatusCard / nút Gỡ lỗi) — 4 bước tuần tự,1 alert
```
validate local: URL parse? key rỗng? → fail sớm (red alert, chỉ1 dòng)
① mạng: HEAD https://api.groq.com (host của base)        ≤3s
② mic:  SpringBoard đã ghi flag?                        (v1.2)
③ key+endpoint:1 chat completion “ping” (= Kiểm tra kết nối) ≤15s
④ dán kết quả: alert1 bảng ✓/⚠️ + [Xem log]
mọi bước song song tối đa (①③ song song) — tổng ≤15s
```

### 4.3 Chuẩn hóa & validate giá trị text (on set — CFPreferences write-through)
```
onSet(key, value):
  baseURL:
    trim → nếu thiếu scheme → prepend "https://" (ghi lại đã sửa + log info)
    NSURL parse fail → ALERT “Địa chỉ không hợp lệ”, KHÔNG ghi (giữ giá trị cũ)
    strip trailing "/"
  model: trim; nếu rỗng → ghi default của provider + footer flag “đang dùng mặc định”
  apiKey: trim; KHÔNG chặn theo prefix (proxy có prefix lạ) —
          chỉ warn trong log nếu prefix phổ biến không khớp (sk_/gsk_/AIza)
  temperature/turns/timeout: clamp theo biên slider; round (temperature ÷0.1, int khác)
  mọi success → notify prefs.changed (1 lần/kết thúc event — slider release đã là1 lần)
```
- **Nguyên tắc**: chặn cái sai không thể dùng (URL parse fail), bỏ qua cái sai kiểm chứng được (key) → kiểm chứng bằng nút Kiểm tra.

### 4.4 Pattern “Kiểm tra / Thử” —1 state machine dùng lại
```
idle ─tap─► localValidate ─fail─► redAlert (log err) ─OK─► idle
                 │pass
                 ▼
          progressAlert("Đang kiểm tra…", nút Hủy)
                 │ bg task (LLM/STT/TTS) — Hủy → cancel task
     ┌───────────┴───────────┐
 success                   failure(code)
     ▼                         ▼
 greenAlert                 redAlert
 "✓ 672 ms · llama-3.3"    "⚠️ 401 — khóa API sai" (mapping code→hint)
 (log info)                 (log err, ghi lastTest)
     └────────► idle ◄────────┘
```
- **Alert modal = guard chống bấm đôi** — không cần disable nút.
- Mapping lỗi cố định: `401/403→khóa sai · 404→địa chỉ sai/sai đường dẫn · 429→hết hạn mức · timeout→mạng/chậm · DNS→sai tên máy chủ`.
- Thử STT: SpringBoard ghi3s → notification hiện transcript + log; Preferences poll `lastSttTest` (CFPreferences, ≤5s) → alert.
- Thử giọng: phát ngay, alert nhỏ “✓ đang nói bằng giọng X” (không modal dài — không cần Hủy).

### 4.5 Trang Prompt — state machine
```
buffer (UITextView) · saved (effective) · isDirty = buffer != saved
segment [Đang dùng] → load(saved);  [Mặc định] → load(default)
   nếu isDirty → confirm “Thay nội dung đang sửa?” (Hủy → revert segment)
[Lưu]:  buffer==default || buffer=="" → ghi customPrompt="" (xem như mặc định)
        else → ghi customPrompt=buffer
        → isDirty=false, label cập nhật, notify, log
[Khôi phục mặc định]: confirm? KHÔNG (hành động constructive) →
        ghi customPrompt="", buffer=default, segment=Đang dùng, label “mặc định”
[Sao chép]: buffer → UIPasteboard
Thoát mà isDirty → alert “Thoát mà chưa lưu?” [Tiếp tục sửa] [Thoát]
```

### 4.6 Streaming / Markdown / TTS — tác động tức thì hay câu sau?
| Thay đổi lúc giữa chừng | Hành vi | Footer ghi rõ |
|---|---|---|
| Tắt streaming | hủy stream gen hiện tại → complete với phần có | “Áp dụng cho câu hỏi đang chờ và các câu sau” |
| Tắt/bật markdown | bubble hiện tại **không đổi** — câu sau áp dụng | “Áp dụng cho câu trả lời tiếp theo” |
| Đổi ttsMode → `off` | **stopSpeaking ngay** câu đang đọc | — |
| Đổi giọng/tốc độ/âm lượng | áp dụng lần phát **tiếp theo** (không đổi đang nói) | — |
| Tắt STT giữa phiên Siri | phiên hiện tại giữ nguyên, câu sau dùng Apple | — |
| Đổi provider LLM | notify → SpringBoard reload — **không** đụng bubble đang hiện | — |
| Tắt incognito | vẫn không đọc lại dữ liệu cũ (append-only từ lúc bật) | — |

### 4.7 Lưu & reload — khi nào cần `reloadSpecifiers`
```
GẦN NHƯ MỌI THAY ĐỔI: chỉ ghi CFPreferences + notify → row tự hiển thị giá trị mới
   (không reload — tránh giật & mất scroll)
CHỈ reload khi:
  • đổi Nhà cung cấp (filter danh sách trang con/thuộc provider)   → full reload
  • đổi Nguồn STT / Nguồn TTS (các row con đổi theo)             → full reload (nhóm nhỏ)
  • import cấu hình hoàn tất                                      → full reload
  • (v1.0 bug đã học: không reload trong notify handler nếu view chưa load xong → guard self.viewIfLoaded)
```

### 4.8 Log viewer — logic refresh
```
viewDidLoad: đọc tail 64KB → render; timer1s (tolerance0.5)
tick: size = fstat; nếu size < lastSize → xoay file → full reload
      nếu grew → đọc thêm range mới → append attributed
      giữ nguyên scroll: wasAtBottom ? cuộn theo : giữ vị trí tuyệt đối
viewDidDisappear: invalidate timer (không rò rỉ)
[Xóa]: confirm → truncate0 → reload → empty state
[Sao chép/Chia sẻ]: toàn bộ file (≤512KB) — chia sẻ dạng .log
```

### 4.9 Lịch sử — logic
```
load trang50 (mới nhất trước) · [Tải thêm] vô hạn lặp50
swipe ⌫ → xóa phần tử → ghi CFPreferences (debounce300ms để xóa hàng loạt không30 IO)
[Xóa tất cả]: confirm “Xóa N câu hỏi?” destructive → clear + notify resetHistory (SpringBoard xóa memory history)
incognito ON: chặn append (memory+persist) · UI ghi “Phiên này sẽ không lưu” trong footer nhóm
```

### 4.10 Trò chuyện thử — logic
```
vào trang: testHistory = [] (RAM)
gửi: append user bubble → askQuestion(history=testHistory) gen++
stream: flush250ms → render md incremental → bubble “đang gõ”
[■]: cancel task → giữ phần có + nhãn “(đã dừng)”
lỗi: bubble ⚠️ + chi tiết1 dòng, không mất câu đã gõ
rời trang: invalidate timer, cancel task, testHistory = [] (mất=đúng — đây là bàn thử)
```

### 4.11 Xuất / Nhập cấu hình
```
Xuất: JSON {sirixConfig:1, exportedAt, values{…}} — values = mọi key CẤU HÌNH
      (loại: history, stats.*, lastTest, customPrompt?? → GIỮ prompt — nó là cấu hình;
       mặc định: KHÔNG kèm khóa API → "apiKeyPresent":true/false thay vì giá trị;
       toggle “Kèm khóa API” bật → ghi thật + confirm cảnh báo chia sẻ)
      → share sheet tệp sirix-config.json
Nhập: parse → validate version/fields (unknown key → bỏ qua + đếm)
      → alert tóm tắt: “Sẽ thay 38 giá trị,1 khóa API,0 mục lạ”
      → OK → ghi (loại history/stats) → notify → full reload
      fail parse → redAlert dòng lỗi chính xác (JSON path)
```

### 4.12 Trạng thái load trang đầu tiên (first-run)
```
open Root lần đầu, chưa key: StatusCard orange + footer nhóm Nhà cung cấp
  in đậm “bắt đầu từ Cấu hình OpenAI” — không hiện onboarding modal (không lái người dùng)
STT lần đầu ON: nếu mic denied → bubble1 lần/phiên hướng dẫn (SYSTEM §7)
```

---

## 5. Accessibility & hiệu năng

| Hạng | Quy tắc |
|---|---|
| Dynamic Type | custom cell `adjustsFontForContentSizeCategory`; wireframe chỉ nêu size tham chiếu |
| Nhấn vùng | mọi target ≥44×44 (chip, segmented, nút bar) |
| VoiceOver | StatusCard: label = title+subtitle hợp nhất; chấm màu kèm chữ trong label (“sẵn sàng/mắc lỗi”) |
| Dark mode | chỉ semantic colors — kiểm tra2 mode trong QA |
| Giật hình | log append không render lại cả buffer (attributed range mới); history debounce ghi; stats atomic O(1) |
| Timer | mọi timer invalidate ở `viewDidDisappear` |
| Ảnh/Icon | icon header dùng `UIImage(named:)` trong bundle (đã có); SF Symbols cho custom cell (`UIImage(systemName:)` iOS15 ✓) |

---

## 6. Checklist QA UI (chạy trước mỗi release)

1. StatusCard đúng4 trạng thái (§4.1) với4 cấu hình mô phỏng.
2. Đổi provider → đúng1 lần reload, scroll giữ nguyên ở nhóm khác.
3. URL thiếu `https://` → tự thêm + ghi log; URL rỗng/lỗi → alert, giá trị cũ giữ nguyên.
4. Thử STT/TTS/Kiểm tra kết nối: progress → kết quả; bấm Hủy không treo; lỗi401/404 hiện đúng hint.
5. Prompt:3 đường (lưu bản mới / lưu=y mặc định / khôi phục) + segment dirty-confirm + thoát dirty-confirm.
6. Log: refresh1s không giật khi cuộn giữa; xoay file reload; timer dừng khi ra trang.
7. Lịch sử: swipe, xóa tất cả (confirm đúng N), incognito chặn append ngay, Tải thêm phân trang.
8. Trò chuyện thử: ■ dừng đúng, md incremental không gãy, rời trang mất session.
9. Export (2 toggle khóa) → Import 2 file (hợp lệ/lỗi JSON) → reload đúng.
10. Dark mode + Dynamic Type XL không cắt chữ; VoiceOver đọc đủ StatusCard.
11.100% row có footer hoặc lý do không cần (ghi vào review).
12. local-check + CI2 scheme xanh.
