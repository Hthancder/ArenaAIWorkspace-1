# Quyết định thiết kế & câu hỏi thường gặp

## Vì sao không "managed mode" như SiriPlus?
Vì đó là **chi phí thật**: mỗi câu hỏi tốn token của một API key do nhà phát triển giữ.
Nó cũng có nghĩa người dùng phải tin tưởng một server trung gian. SiriBridge dùng
key/endpoint của chính người dùng → 0 chi phí vận hành, không có điểm chết.

## Vì sao không hỗ trợ arm64e?
Theo yêu cầu. Ngoài ra arm64e trên iOS 15 dễ gặp vấn đề ký/PAC với tweak inject;
arm64 (A11-) với palera1n rootless là môi trường ổn định hơn.

## Vì sao chặn cả `SAUIClearScreen`, `SAUIDisambiguationList`?
Vì chúng là phần của "câu trả lời của Siri". Chặn ClearScreen tránh việc Siri xoá
transcript ngay trước khi ta bơm câu trả lời.

## Tại sao hiện "…" trước khi có câu trả lời?
`SAUIAssistantUtteranceView` với `dialogPhase = "Reflected"` làm orb quay và
transcript có chỗ chờ, giống trải nghiệm Siri thật. Nếu bạn thấy nó thừa, xoá
`showThinkingForDelegate:` trong SBEngine.

## Có thể dùng ChatGPT web / subscription thay API key?
Không. Web không có endpoint ổn định, vi phạm ToS và cần cookie phiên.
API key (hoặc endpoint tự host) là con đường duy nhất bền vững.

## Có thể dùng Gemini miễn phí?
Có — Google AI Studio có free tier cho `gemini-2.0-flash`; cấu hình theo §3 README.

## Có thể dùng model chạy trên máy?
Không trên iPhone iOS 15 (không có Metal LLM runtime ổn định). Nhưng có thể trỏ
endpoint tới máy tính trong LAN (Ollama/LM Studio) → vẫn "miễn phí".

## Tweak có gửi dữ liệu đi đâu không?
Chỉ tới `Endpoint` bạn cấu hình. Không telemetry, không analytics, không license check.
Toàn bộ mã nguồn trong repo này.

## Tôi muốn "Hey Siri" chỉ kích hoạt SiriBridge, không bao giờ Siri?
Đặt `Câu chứa các từ này thì để Siri gốc` = rỗng và `Chỉ xử lý khi câu bắt đầu bằng` = rỗng,
bật `Thay thế câu trả lời của Siri`. Mọi câu đều đi qua LLM.

## Muốn Siri vẫn làm báo thức/giờ, chỉ các câu khác mới qua LLM?
Giữ `NativeKeywords = báo thức,hẹn giờ,alarm,timer,giờ` — các câu chứa từ khoá đó
được nhả cho Siri xử lý bình thường.

## Tại sao tools không chạy được khi ở Managed/không có tools?
Chỉ hỗ trợ tool-calling theo chuẩn OpenAI (`tools` array). Nếu endpoint của bạn
không hỗ trợ, hãy tắt `Cho phép điều khiển thiết bị`.
