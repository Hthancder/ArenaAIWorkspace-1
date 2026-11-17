# SiriPlus — nghiên cứu tính năng & mô hình thương mại

## 1. Thông tin gói

| | |
|---|---|
| Tên | SiriPlus |
| ID | `com.uckermark.siriplus` |
| Tác giả | uckermark (`@_Uckermark`) |
| Repo | Havoc (`https://havoc.app`) |
| Giá | **US$4.99** (mua một lần) |
| Phiên bản đã thấy | 1.0 → 1.4 (3/2024 → 5/2024) |
| Tương thích | iOS 14.0 – 16.7.5, rootful **và** rootless; *không* hỗ trợ roothide/serotonin |
| Kiến trúc gói | `iphoneos-arm` + `iphoneos-arm64` |
| Kích thước | ~140 KB (v1.0) → ~250 KB (v1.4) |

Nguồn: r/jailbreak release thread, idownloadblog, các trang repo-mirror (chimera-jailbreak, zeejb, onejailbreak, appinspecter). **Không** có source mở; đây là mô tả hành vi quan sát được, dùng để định nghĩa “tính năng cần có”, không phải để sao chép code.

## 2. Tính năng theo lời developer / người dùng

### 2.1 Lõi
* Thay Siri bằng ChatGPT hoặc Google Gemini, **dùng nguyên UI Siri** (không app riêng).
* Hoạt động với **“Hey Siri”**, nút nguồn, tai nghe — vì nó chỉ chặn ở tầng session.
* Câu trả lời hiển thị trong “Siri window” như câu trả lời của Siri; vẫn nói được (TTS).
* Bật/tắt bằng CC-toggle hoặc trong Settings (bản sau).

### 2.2 Chế độ AI
1. **Managed** (mặc định) — dùng server/API key của developer, mặc định là **Gemini**. Miễn phí, không cần key. *(Trong thread có người nghi ngờ key dùng chung; developer không xác nhận chi tiết.)*
2. **ChatGPT** — người dùng tự nhập API key OpenAI, gọi trực tiếp từ máy.
3. **Google Gemini** — key riêng, gọi trực tiếp.

### 2.3 Tuỳ chọn (preference pane)
* Bật/tắt tweak.
* Chọn engine (Managed / ChatGPT / Gemini).
* API key (bị bug “dùng chung key giữa GPT và Gemini” ở 1.0–1.1, sửa ở 1.2).
* **System prompt** tuỳ chỉnh.
* **Số token dành cho context** (độ dài lịch sử hội thoại được gửi kèm).
* **Model picker** (thêm ở v1.2: `gpt-3.5-turbo-0125`, `gpt-3.5-turbo-1106`, `gpt-4`).
* **Temperature slider** (thêm ở v1.2).
* **Reset chat context**.
* (Bản 1.4) cải thiện chất lượng giọng bằng cách **pre-synthesize TTS**.

### 2.4 “Functions” — điều khiển thiết bị
AI có thể gọi hành động thật trên máy:
* mở app, soạn email, thêm lịch, gọi điện, mở điều hướng, lấy thông tin hệ thống…
* Cơ chế: function/tool-calling → tweak thực thi bằng API hệ thống (không phải SiriKit).
* Người dùng báo: hoạt động tốt với key riêng; **không hoạt động ở chế độ Managed**; và **tắt functions thì chất lượng trả lời tốt hơn**.

### 2.5 Hạn chế được cộng đồng ghi nhận
* Hard-code `gpt-3.5-turbo-0125` (chất lượng thấp), max output ~100 token (đã cải thiện ở 1.2).
* **Không streaming** — phải chờ đủ câu trả lời (nguyện vọng “như iOS 18”).
* Mất một số tính năng Siri gốc (đặt báo thức, thời tiết, nhạc…) khi ở chế độ thay thế.
* Không hỗ trợ đa ngôn ngữ tốt — phụ thuộc model; hướng dẫn trong app đều tiếng Anh.
* Một số người dùng phàn nàn phải trả thêm phí API ngoài giá tweak.

### 2.6 Mô hình kinh doanh (đáng chú ý cho bạn)
Doanh thu = giá gói × số bản bán. Chi phí = (a) server “managed mode” — **đây là chi phí thật sự**, mỗi câu hỏi tốn token Gemini; (b) Havoc lấy % (không công khai, thường 20–30%); (c) hỗ trợ.
Điểm yếu cạnh tranh: không streaming, model cũ, không tự host, UI không đổi.

## 3. Ý nghĩa cho SiriBridge (bản mã nguồn mở, miễn phí)

| Tính năng SiriPlus | SiriBridge làm gì |
|---|---|
| Thay Siri | ✅ chặn `receivedCommand:` (Replace mode) + Coexist mode |
| Managed mode | ➖ **bỏ** — đó là nguồn chi phí. Thay bằng “dùng key của bạn” + hỗ trợ **endpoint tự host** (Ollama, LM Studio, vLLM, llama.cpp) ⇒ chi phí 0 |
| ChatGPT / Gemini | ✅ **endpoint tự do**: `baseURL`, `model`, `apiKey`, headers, JSON body template ⇒ dùng được mọi API tương thích OpenAI, Gemini native, Anthropic, OpenRouter, Groq, DeepSeek… |
| Model picker / temperature / max tokens / system prompt | ✅ có |
| Context length | ✅ (đếm theo turn, cắt theo ký tự/token ước lượng) |
| Reset context | ✅ |
| Functions / điều khiển máy | ✅ **tool calling** thật + fallback parser thẻ `<cmd>`; có whitelist app để tránh phá máy |
| **TTS** | ✅ vượt SiriPlus: chọn (1) AVSpeechSynthesizer với voice bất kỳ, (2) TTS endpoint OpenAI/ElevenLabs/Azure/Piper tuỳ chỉnh, (3) giọng Siri gốc |
| Streaming | ✅ streaming SSE → cập nhật `SAUIUpdateViews`/`SAUIAddViews` từng đoạn (tuỳ chọn) |
| UI | ✅ tuỳ chọn: dùng transcript Siri (giống SiriPlus) hoặc **chat view riêng của tweak** (SwiftUI/UIKit) để có lịch sử, chọn model, xem tool call |
| Wake word | ✅ giữ “Hey Siri” của hệ thống; thêm nút nổi/Activator (tuỳ chọn) |
| Giá | 0, mã nguồn mở |

**Không làm (có lý do):** managed proxy, tài khoản, telemetry, license check.
