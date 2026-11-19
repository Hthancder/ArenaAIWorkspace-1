# SiriX — tiến độ thực hiện thiết kế v1.2

> **1.1.7 — viết lại từng tính năng Settings, không còn bản vá chồng bản vá.**
> Mười màn hình Settings được dựng lại trên cùng một bộ khung: dữ liệu đọc trong
> nền có số thế hệ (kết quả cũ không ghi đè kết quả mới), trạng thái rỗng/lỗi
> hiện ngay trong bảng thay vì alert bật lên giữa lúc cuộn, mọi danh sách dùng ô
> tự vẽ để chữ xuống dòng đúng thay vì bị cắt cụt.
>
> - **Header tuỳ chỉnh**: chân bảng là `UILabel` cập nhật tại chỗ — gạt công tắc,
>   xoá, kéo hàng không còn `reloadSections:` (đường dẫn tới lỗi “invalid update”
>   và tới lần văng khi lưu của 1.1.6). Có dòng “3/4 header đang gửi” và cảnh báo
>   `http://` ngay trong danh sách.
> - **Lịch sử**: ô tự vẽ (câu hỏi + câu trả lời + giờ), nhóm theo ngày kèm số
>   lượt, tìm kiếm có debounce, kéo-để-làm-mới có chống ghi đè, xoá một lượt gỡ
>   ngay khỏi danh sách, chi tiết có nút Chép.
> - **Thống kê**: phần đầu Auto Layout (không còn frame cứng vỡ khi đổi cỡ chữ),
>   thêm “Tỉ lệ sự cố” và “Đánh giá tốc độ”, nút xoá chỉ bật khi có số liệu.
> - **Công cụ AI**: chạm ô để bật/tắt (một hành vi, một vùng chạm), mỗi ô giữ
>   closure riêng thay vì giải mã `tag = section*1000 + row`, tiêu đề nhóm hiện
>   “x/y đang bật”, thêm “Tắt tất cả”, nhấn giữ để xem khi nào AI dùng công cụ.
> - **Nhật ký**: vẽ theo từng dòng có màu mức log, nối thêm theo mảng dòng (log
>   xoay vòng không còn mất/lặp dòng), tìm kiếm debounce 0,25 s.
> - **Prompt hệ thống**: ô soạn thảo Auto Layout, mẫu “Gia sư”, chuyển tab không
>   còn lệch trạng thái công tắc, nút Lưu phản ánh đúng “Đã lưu”.
> - **Chọn mô hình**: thêm ô tìm kiếm, kiểm tra mã trước khi lưu, chạm lại mô
>   hình đang dùng chỉ đóng màn hình, dấu ✓ cập nhật khi quay lại.
> - Sửa chân trang Gemini: mốc chờ đúng là 8 giây (trước ghi 5).
>
> Cùng bản này: **trang nhà cung cấp** và **trò chuyện thử** đã được viết lại
> (xem mục 1.1.7 bên dưới), **trang chính** dựng lại với pill trạng thái sống.

> **1.1.6 — sửa hai lỗi chặn dùng ở màn hình Header (1.1.5 hỏng đúng chỗ này).**
> (1) Bàn phím tắt sau mỗi ký tự: `sx_validate` reload section 0 để cập nhật dòng
> gợi ý, reload gỡ ô nhập khỏi cửa sổ nên UIKit hạ bàn phím. Nay gợi ý lỗi nằm
> trong cell và cập nhật tại chỗ, không reload. (2) Văng Settings khi lưu: thuộc
> tính `headers` khai báo `copy` trên `NSMutableArray` nên runtime giữ bản **bất
> biến** — `addObject:`/subscript văng `unrecognized selector`. Đổi sang `strong`.
> Ô nhập giờ do từng cell tự giữ, chữ do màn hình giữ trong `nameText`/`valueText`
> nên cuộn hay tái sử dụng cell cũng không mất first responder và không mất chữ.
> `check-prefs.sh` thêm hai luật để hai lỗi này không quay lại.
>
> **1.1.5 — hoàn thiện trong phạm vi hiện có (không thêm tính năng mới).** Trò
> chuyện thử hiện được việc AI đang làm (công cụ nào, bao nhiêu ms) thay vì chỉ
> một dòng “đang trả lời”; màn hình header không còn bị bàn phím che, cảnh báo
> khi endpoint là `http://`; trang cấu hình nhà cung cấp đọc lại mọi hàng tóm tắt
> sau khi quay về và tự vô hiệu kết quả kiểm tra cũ khi header đổi; khóa dán từ
> web được bóc BOM/ký tự vô hình/dấu nháy; “Bật lại tất cả” công cụ ghi một lần
> thay vì 13 lần; nhãn trợ năng cho toàn bộ công tắc mới; thống nhất chính tả
> “tuỳ chỉnh/tuỳ chọn” trên UI và tài liệu.
>
> **1.1.4 — header HTTP tuỳ chỉnh + hết văng khi mở danh sách mô hình.** Mỗi nhà
> cung cấp có màn hình header riêng: thêm/sửa/bật-tắt/xoá/sắp xếp, kiểm tra tên
> theo RFC 7230 ngay khi gõ, gợi ý xếp theo endpoint đang cấu hình (OpenRouter,
> Azure, gateway nội bộ), và giá trị không bao giờ lộ ra danh sách hay log. Danh
> sách mô hình được vẽ lại từ đầu bằng UIKit thuần — bản cũ dùng `PSButtonCell`
> với `buttonAction`, class thật của Preferences không có setter đó nên Settings
> văng khi chạm vào hàng.
>
> **1.1.3 — làm lại toàn bộ tầng công cụ.** Từ một danh sách công cụ nhỏ dựng trực
> tiếp trong `SXTools`, công cụ giờ là một tầng riêng: `SXToolkit` (sổ đăng ký +
> thực thi có kiểm soát) và `SXToolCatalog` (13 công cụ thật). Model thấy công cụ
> qua schema + mô tả trong system prompt, gọi được cả khi stream (không tốn thêm
> một vòng request), tham số được validate/ép kiểu, kết quả lỗi được trả lại bằng
> tiếng Việt để model tự sửa, mỗi công cụ có trần thời gian riêng, và Settings có
> màn hình Công cụ bật/tắt từng công cụ. Chi tiết ở mục cuối tài liệu.
>
> **1.1.2 — sửa treo màn hình Log và văng Siri khi gọi công cụ.** Màn hình log đọc
> theo kiểu "đuôi file" trên luồng nền; pipeline công cụ có trần thời gian, bọc
> exception và chèn bong bóng đúng `dialogIdentifier`. Chi tiết ở mục cuối tài liệu.
>
> **1.1.1 — refactor Settings & logic.** Giao diện cài đặt được làm lại theo một tầng
> dùng chung (`Prefs/SXUISupport`), logic prefs có kiểm tra hợp lệ, và một số lỗi
> trong pipeline được vá.

Tài liệu thiết kế là mục tiêu, không phải danh sách tính năng đã hoàn tất.
Không đổi phiên bản gói sang 1.2 cho đến khi các hạng mục bắt buộc được thực hiện và kiểm thử.

## Đã thực hiện trong mã (vẫn cần kiểm thử trên thiết bị)

- Sửa ghi log sau khi xóa hoặc xoay vòng, và làm mới màn hình xem log.
- Các hook chỉ được cài khi class/selector có mặt; một quyết định trả lời được áp dụng cho các lệnh AddViews/SayIt cùng lượt, kèm giới hạn thời gian và ưu tiên tác vụ hệ thống khi đã nhận diện.
- Chế độ kích hoạt `auto` / `prefix`; trong `prefix`, chỉ `@ai` có nội dung được gửi tới AI, còn `@siri` hoặc câu không có tiền tố giữ Siri gốc. Nhận diện chính xác `@ai` phụ thuộc transcript Apple, nên Type-to-Siri là cách thử đáng tin cậy hơn.
- Tuỳ chọn hiển thị bản Siri gốc khi lệnh AddViews có văn bản; bản gốc không được đưa vào lời đọc.
- Trò chuyện thử trong Settings với provider đang chọn, không dùng tool và không lưu lịch sử lâu dài.
- Kiểm tra kết nối chạy nền, dùng đúng provider của trang cấu hình; retry HTTP 429/5xx tối đa hai lần mỗi vòng trên luồng nền.
- Lịch sử lưu trên thiết bị có giới hạn, xem chi tiết/sao chép/xóa từng mục hoặc toàn bộ; lượt ở chế độ không lưu chỉ ở bộ nhớ. Không phải chế độ ẩn danh mạng hoặc log.
- Thống kê thay/giữ/lỗi/hết giờ và thời gian trung bình có trọng số; có thể xóa riêng. Lưu/đọc kho làm trên hàng đợi nền, dùng lock liên tiến trình và epoch để tránh đáp án cũ phục hồi dữ liệu sau khi xóa.

## Chưa hoàn tất so với thiết kế

- STT thay Apple, ghi mic, dịch transcript và thử STT.
- TTS tuỳ chỉnh, chọn giọng/nguồn, tự nhận ngôn ngữ, và chống Siri đọc chồng.
- Deferred push/notification cho đáp án trễ; chế độ ẩn danh toàn diện (chặn dữ liệu nhạy cảm trong mọi log và không gửi mạng) chưa có.
- Model dự phòng khi lỗi/hết giờ, hủy request theo generation, phát hiện offline sớm.
- Xuất/nhập cấu hình, kiểm tra cập nhật, công cụ `current_app`, các trang cấu hình tương ứng.
- Hiển thị stream theo từng chữ và mốc timeout theo token đầu; hiện SSE chỉ tích lũy và hiển thị khi hoàn tất.

STT, TTS và deferred push phụ thuộc API riêng, quyền mic và audio session của Siri. Không đưa các công tắc chưa hoạt động vào Settings hoặc cam kết hành vi an toàn cho đến khi có kiểm thử trên thiết bị iOS jailbreak. Log có thể chứa câu hỏi, URL hoặc dữ liệu khác. Không lưu lịch sử không đồng nghĩa với ẩn danh khi dùng mạng hoặc log.

## 1.1.1 — Refactor Settings & logic (đã làm trong mã, cần thử trên thiết bị)

### Giao diện

- **Một tầng UI dùng chung** (`Prefs/SXUISupport`): màu theo trạng thái, pill trạng thái,
  empty state, alert/confirm, định dạng ngày tương đối, đếm số. Không màn hình nào tự vẽ kiểu riêng.
- **Root**: header có pill trạng thái sống (“Sẵn sàng / Thiếu khóa API / Đã tắt”) + 4 dòng
  tổng quan đọc ngay (trạng thái, nhà cung cấp + model, cách trả lời, lịch sử). IA chia lại
  thành 10 nhóm có footer giải thích; thêm “Khôi phục cài đặt mặc định” (xác nhận trước),
  respring có xác nhận. Mọi thay đổi debounce 0,25 s rồi mới reload + phát notify.
- **Cấu hình nhà cung cấp**: khóa được che dạng `sk-…abcd`, nút dán khóa từ bộ nhớ tạm
  (tự lấy dòng đầu, chặn chuỗi quá ngắn), hiển thị endpoint đã chuẩn hóa và cảnh báo khi
  URL sai, **kết quả kiểm tra kết nối hiện ngay trong trang** (không còn hộp thoại chặn),
  lưu lại lần kiểm tra gần nhất và tự xoá khi đổi cấu hình.
- **Chọn model**: trang mới `SXModelPickerController` liệt kê model gợi ý theo nhà cung cấp,
  đánh dấu model đang dùng; vẫn giữ ô nhập tay cho endpoint tự host.
- **Trò chuyện thử**: khung chat bong bóng thật (tự co giãn, trái/phải theo vai), trạng thái
  “Đang trả lời…”, bong bóng lỗi màu riêng, mốc thời gian, chạm giữ để sao chép, xoá hội thoại.
- **Lịch sử**: nhóm theo ngày, tìm kiếm, vuốt để xoá, empty state, trang chi tiết có chia sẻ.
- **Thống kê**: header tỉ lệ thay + thanh tiến trình, các dòng số liệu theo nhóm, kéo để làm mới.
- **Log**: lọc theo mức (Tất cả / Vấn đề / Lỗi), tìm kiếm, đếm dòng, chỉ sao chép phần đang xem,
  tự bám cuối khi đang ở cuối.
- **Prompt**: thêm bộ mẫu (Ngắn gọn / Giải thích kỹ / Lập trình) chèn vào ô soạn, có xác nhận
  khi đang sửa dở.

### Logic

- `SXPrefs`: thêm ghi giá trị tổng quát, `resetAll` (xoá cả key lạ trong domain), chuẩn hoá/
  kiểm tra endpoint, che khóa, đọc key phụ, và các chuỗi tóm tắt dùng cho UI.
- `SXIntercept`: chỉ thay **một** view chính (ưu tiên `…Utterance`), không đè nội dung lên mọi
  view có chữ; quyết định chỉ dùng lại trong **cùng `dialogIdentifier`** và rút cửa sổ 30 s → 20 s.
- `SXLLM`: sửa role `functionResponse` của Gemini (`tool` → `user`, lỗi 400 trước đây);
  trả lại ngân sách retry sau mỗi request thành công; báo lỗi hết giờ rõ ràng thay vì “HTTP 0”;
  **không âm thầm rơi về api.openai.com** khi endpoint người dùng nhập không hợp lệ; UA dùng `SX_VERSION`.
- `SXTools` (`fetch_url`): chặn redirect, chặn host nội bộ/loopback/link-local, cắt body ở 2 MB.
- Thêm `scripts/check-prefs.sh` (lint plist ↔ controller ↔ selector, cân bằng ngoặc) chạy trên
  Linux và trong CI, trước job build.

### Vẫn còn thiếu (như trước 1.1.1)

STT/TTS thay Apple, deferred push cho đáp án trễ, model dự phòng, huỷ request theo generation,
xuất/nhập cấu hình, và hiển thị stream theo từng chữ trong bubble.

## 1.1.2 — Sửa treo màn hình Log & văng Siri khi gọi công cụ

Ca lỗi lấy từ log thiết bị thật (bản 1.1.1, roothide):

### 1. Màn hình Log làm treo Preferences

Nguyên nhân: mỗi 2 giây màn hình nạp **toàn bộ** `SiriX.log` (tới 512 KB) bằng
`dataWithContentsOfFile:` trên luồng chính, tách/lọc từng dòng rồi **dựng lại toàn bộ
UITextView** (`text`, `layoutIfNeeded`, `scrollRangeToVisible`). Khi log gần mức trần,
riêng một lần layout đã tốn hàng trăm ms; lặp lại mỗi 2 giây làm luồng chính bị chiếm
liên tục nên giao diện đơ, không bấm được nút, không thoát ra được.

Đã sửa:

- `SXLogFileReadTail()` (C, có test): chỉ đọc **160 KB cuối** file, bỏ dòng đầu bị cụt,
  không nạp cả file; gọi trên hàng đợi nền riêng, không bao giờ trên luồng chính.
- Hiển thị tối đa **1 200 dòng**; phần cũ bị cắt và hiện “đã cắt phần đầu” trên prompt.
- Chỉ vẽ lại khi nội dung **thực sự đổi**; bình thường **nối thêm** phần mới vào
  `textStorage` (tối đa 48 KB mỗi nhịp) thay vì dựng lại cả khối văn bản.
- Bỏ nhịp khi lần đọc trước chưa xong (không xếp hàng dồn), hoãn cập nhật khi đang bôi
  đen để sao chép, dừng hẹn giờ khi màn hình ẩn hoặc app xuống nền.
- Hẹn giờ 2,5 s có `tolerance`, hoãn được bằng “Tạm dừng tự làm mới”.

### 2. Siri văng khi AI gọi công cụ

Ba nguyên nhân độc lập, đều đã vá:

1. **Không có lưới an toàn exception**: `executor` của công cụ (UIKit, pasteboard, mạng,
   `UIDevice`) chạy trên luồng nền SpringBoard mà không có `@try`. Một exception lọt ra
   ngoài = giết cả SpringBoard (người dùng thấy “Siri văng”, log không có dòng nào vì
   crash là signal, không phải NSException). Nay: `SXRunTool()` bọc `@try/@catch`, mọi
   lỗi thành `NSError` để model đọc và trả lời tiếp; `SXTools.execute` cũng bọc tương tự.
2. **Lượt có công cụ bị cắt oan**: hook ACE chỉ chờ tối đa 5 s trong khi `fetch_url`
   cho phép tới 15 s, nên quyết định “hết giờ” được áp lên lệnh ACE trong khi model vẫn
   đang chạy; câu trả lời thật về sau đó không còn chỗ hiển thị ⇒ hội thoại bị đóng.
   Nay: chờ 6 s cơ bản + 3 s mỗi lần có tiến triển (tối đa 9 s), `fetch_url` giới hạn
   6 s/7 s, và cả lượt có trần `min(responseTimeout, 15 s)` — hết trần thì báo lỗi rõ
   ràng thay vì treo.
3. **Bong bóng chèn sai hội thoại**: `SAUIAssistantUtteranceView` được tạo với
   `dialogId` ngẫu nhiên, không có `refId`, lệch với `dialogIdentifier` của lệnh ACE.
   Siri gắn view vào hội thoại theo id này; lệch id làm giao diện đóng/layout lỗi. Nay
   view mới kế thừa `dialogIdentifier` của lệnh, có `refId`/`aceId`, `listenAfterSpeaking = NO`,
   và danh sách view sau khi sửa được kiểm tra nil + ghi log từng lớp.

Ngoài ra: mọi hook trong `Tweak.x` đều bọc `@try` để một lỗi trong tweak không bao giờ
làm chết SpringBoard, và log ghi rõ hook chạy trên luồng chính hay không.

### Kiểm chứng

- `./scripts/local-check.sh` → lint Settings + compile toàn bộ (aarch64-ios 15.0, `-Werror`) + plist.
- `./scripts/test-log-file.sh` → thêm 5 ca cho `SXLogFileReadTail` (file nhỏ, đuôi bị cắt,
  file rỗng, file không tồn tại, một dòng dài hơn cửa sổ đọc).
- Trên thiết bị: log khởi động phải ghi `SiriX 1.1.2`; màn hình Log hiện `N dòng · X KB`.

## 1.1.3 — Tầng công cụ mới

**Vì sao làm lại.** Bản 1.1.2 truyền công cụ theo kiểu "một mảng dictionary dựng
tay trong `SXTools`" và chỉ đường non-stream mới chạy được công cụ. Hệ quả trên
máy thật: model không thấy đúng schema, mỗi lượt có công cụ phải gửi lại request
lần hai (chậm gấp đôi, thường quá hạn chờ của Siri), tham số sai kiểu làm handler
hỏng, và không có chỗ nào để bật/tắt từng công cụ.

**Kiến trúc.**

| Thành phần | Vai trò |
| --- | --- |
| `Sources/SXToolkit.{h,m}` | `SXTool` (tên, tiêu đề, mô tả cho model, schema, handler, timeout, main-thread, side-effect) + sổ đăng ký có lock + bộ thực thi |
| `Sources/SXToolCatalog.{h,m}` | 12 công cụ dựng sẵn; `SXInstallBuiltinTools()` đăng ký một lần |
| `Sources/SXTools.{h,m}` | Facade cho pipeline: `definitions`, `execute:arguments:error:`, `promptBrief`, `beginTurn`, `catalog`; đọc `SXPrefs.disabledTools` |
| `Sources/SXIntercept.m` | Đăng ký thêm `reset_conversation` (cần `SXIntercept` nên không nằm trong catalog) |
| `Prefs/SXToolsController.{h,m}` | Màn hình "Công cụ AI": nhóm theo loại, mô tả tiếng Việt, công tắc từng công cụ, nút bật lại tất cả |

**Hành vi thực thi.** Validate theo JSON schema (thiếu tham số bắt buộc → lỗi 422
kèm tên tham số); ép kiểu khi model gửi chuỗi cho số/boolean; chạy handler trên
hàng đợi riêng với trần thời gian của từng công cụ (504 khi quá hạn); bọc
`@try/@catch` (500 thay vì làm sập SpringBoard); chuẩn hoá kết quả về
`@{@"result": NSString}`, cắt ở 4 000 ký tự; cache theo `(tên, tham số)` trong một
lượt để model không gọi lặp cùng một việc; tắt công cụ → 403, tên lạ → 404 kèm
danh sách công cụ đang dùng (model tự sửa được).

**Đường stream.** `SXStream` giờ gộp `tool_calls` (OpenAI) và `functionCall`
(Gemini) ngay trong SSE, nên `SXLLM` thực thi công cụ tại chỗ — bỏ được trọn một
vòng request so với bản "thấy tool call thì quay lại non-stream".

**Danh sách công cụ 1.1.3.** `device_info` (3 s) · `clipboard_read/write/clear`
(3 s, main thread) · `web_fetch` (10 s; chỉ http/https, chặn host nội bộ, không đi
theo redirect, trần 2 MB) · `list_apps` (4 s) · `open_app` (5 s) · `open_url`
(5 s) · `run_shortcut` (5 s) · `remember`/`recall`/`forget` (4 s; plist tại
`/var/mobile/Library/SiriX/memory.plist`, tối đa 200 ghi chú) · `calculate` (2 s;
parser đệ quy, không `eval`) · `reset_conversation` (4 s).

**Kiểm thử.** `tests/toolkit_test.m` (chạy bằng `scripts/test-toolkit-macos.sh`
trong CI) phủ: registry, thứ tự, thay thế khi trùng tên, schema, ép kiểu, thiếu
tham số, cache trong lượt, reset theo lượt, 404/403/500/504, cắt kết quả, handler
trả nil. Trò chuyện thử trong Settings giờ dùng đúng bộ công cụ như Siri thật.

**Đã bỏ.** Ba công tắc cũ (`toolSystemInfo`, `toolClipboard`, `toolFetchURL`) nay
được migrate sang `toolsDisabled` (danh sách tên công cụ bị tắt); Root.plist thay
ba hàng công tắc bằng một liên kết tới màn hình Công cụ.

## 1.1.4 — Header tuỳ chỉnh & sửa lỗi văng danh sách mô hình

**Vì sao.** Nhiều endpoint tương thích OpenAI không chỉ cần khóa: OpenRouter cần
`HTTP-Referer`/`X-Title`, Azure dùng `api-key` thay `Authorization`, gateway sau
proxy cần header định danh riêng. Trước 1.1.4 chỉ có đúng một bộ header cứng.

**Tầng dữ liệu — `Sources/SXHeaders.{h,m}` (Foundation-only, có test).**
- `SXHeaderNameIsValid`: token RFC 7230 (chữ, số, `!#$%&'*+-.^_`|~`); tên có dấu
  cách, dấu hai chấm hay ký tự ngoài ASCII bị từ chối ngay trong ô nhập.
- `SXHeaderNameIsReserved`: `Host`, `Content-Type`, `Content-Length`,
  `Transfer-Encoding`, `Connection`, `Accept-Encoding`, `Expect`, `Upgrade` —
  ghi đè sẽ làm hỏng request nên bị lọc bỏ (kèm giải thích).
- `SXHeaderValidate`: trả về lỗi cụ thể (trống / sai tên / giá trị rỗng hoặc có
  xuống dòng / trùng tên / quá trần `SXHeaderMaximum` = 16).
- `SXHeadersNormalized`: đọc dữ liệu thô từ prefs (kể cả dạng từ điển cũ), bỏ
  rác, điền `enabled` mặc định.
- `SXHeadersApplied`: bộ header thật sự gửi đi — chỉ mục đang bật và hợp lệ;
  trùng tên (không phân biệt hoa thường) thì giá trị sau thắng.
- `SXHeaderValueMasked` / `SXHeadersSummary`: hiển thị `••••a1b2` và “2 header ·
  1 đang bật”.
- `SXHeaderPresetsForEndpoint`: gợi ý khớp endpoint hiện tại được xếp lên đầu.

**Lưu trữ.** `SXPrefs` có `openaiHeaders` / `geminiHeaders` (mảng
`{name, value, enabled}`), `-headersForProvider:`, `+setHeaders:forProvider:`,
`-headersSummaryForProvider:`. `+setValue:forKey:` giờ chấp nhận mọi kiểu
property list (trước đây chỉ chuỗi/số). Tóm tắt ở trang chính hiện thêm “· N
header” khi có header đang bật.

**Gửi đi.** `SXRequestHeaders()` trong `SXLLM` ghép header xác thực mặc định với
header tuỳ chỉnh (áp sau, nên gateway riêng có thể thay cả `Authorization`), dùng
chung cho non-stream, stream (SSE) và cả “Kiểm tra kết nối”. Log chỉ ghi **tên**
header và số lượng, không bao giờ ghi giá trị.

**Giao diện.** `Prefs/SXHeadersController`: danh sách header (tên đẳng khoảng,
giá trị đã che, công tắc gửi/ngừng, vuốt để xoá, “Sửa” để xoá + sắp xếp), màn
hình soạn header với kiểm tra trực tiếp dưới ô nhập, nút “Dán” làm sạch token
dán từ web, và danh sách gợi ý theo endpoint. Trang cấu hình từng nhà cung cấp
có thêm nhóm “Header tuỳ chỉnh” + dòng “Đang gửi”.

**Lỗi đã sửa: Settings văng khi mở “Chọn từ danh sách”.** Hàng trong danh sách
mô hình được dựng bằng `PSButtonCell` rồi gán `row.buttonAction = @selector(…)`.
`PSSpecifier` thật của Preferences không có setter `setButtonAction:` → ném
`NSInvalidArgumentException` ngay khi bảng được dựng. `SXModelPickerController`
được viết lại thành `PSViewController` + `UITableView` (cùng khuôn với các màn
hình khác của SiriX): mục “Đang dùng”, danh sách gợi ý có dấu ✓, và hàng “Nhập
mô hình khác…” mở hộp thoại nhập tay. Không còn phụ thuộc private API nào của
Preferences.

**Kiểm thử.** `tests/headers_test.m` (chạy bằng `scripts/test-headers-macos.sh`
trong CI) phủ: validate tên/giá trị/trùng tên/trần, header hệ thống, chuẩn hoá
dữ liệu thô, dạng từ điển cũ, thứ tự thắng khi trùng tên, tóm tắt, che giá trị,
gợi ý theo endpoint.

## 1.1.5 — Hoàn thiện trong phạm vi hiện có

Không thêm tính năng lớn. Mục tiêu: mọi thứ đang có phải “xong” — không còn chỗ
nào là bản nháp.

**Trò chuyện thử.** `SXLLM` phát `SXLLMToolActivityNotification` (tên công cụ,
số ms, có lỗi hay không) trên hàng đợi chính. Màn hình thử hiển thị đúng một
dòng hoạt động `🛠 web_fetch · 320 ms`, cập nhật tại chỗ khi có nhiều công cụ
liên tiếp rồi “đóng băng” khi câu trả lời tới — người dùng thấy AI thật sự làm
gì mà không bị một loạt bong bóng làm rối. Không kèm tham số hay kết quả công
cụ, nên không lộ dữ liệu. Ngoài ra: không cho xoá hội thoại khi đang chờ trả
lời (câu trả lời sẽ rơi vào màn hình trống), và nội dung trạng thái rỗng đã
đúng thực tế (dùng đúng bộ công cụ như Siri).

**Header tuỳ chỉnh.** Đáy bảng soạn header bám `keyboardLayoutGuide` nên bàn
phím không che ô đang gõ; cảnh báo ngay dưới ô giá trị khi endpoint là `http://`
(không mã hoá); công tắc trong danh sách có `accessibilityLabel` theo tên header.

**Trang cấu hình nhà cung cấp.** Quay về từ màn hình con sẽ đọc lại cả bốn hàng
tóm tắt (`modelDisplay`, `keyDisplay`, `endpointDisplay`, `testStatus`) — trước
đây chỉ đọc lại dòng header nên mô hình vừa chọn vẫn hiện giá trị cũ. Kết quả
kiểm tra cũ tự bị vô hiệu khi bộ header đang gửi thay đổi. Khóa dán vào được bóc
BOM, ký tự zero-width, dấu nháy và khoảng trắng — những thứ khiến request luôn
401 dù khóa đúng.

**Công cụ.** “Bật lại tất cả” ghi một lần (`+setDisabledTools:`) thay vì 13 lần
ghi + reload + notify. Công tắc có nhãn trợ năng và gợi ý phân biệt công cụ chỉ
đọc với công cụ có tác dụng phụ. Trang chính thêm dòng “Đang bật 12/13 · 3 vòng”.

**Danh sách mô hình.** Hiện endpoint đang cấu hình ở dòng ngữ cảnh dưới tiêu đề,
và đánh dấu “Đang dùng” cho trình đọc màn hình.

**Ngôn ngữ.** Thống nhất “tuỳ chỉnh”, “tuỳ chọn”, “tuỳ biến” (trước đây lẫn
“tùy…” và “tuỳ…” giữa các màn hình) trong toàn bộ chuỗi UI, README và tài liệu.

## 1.1.6 — Hai lỗi ở màn hình Header

Bản 1.1.5 làm hỏng đúng màn hình mà nó định đánh bóng. Người dùng báo: “ghi được
một chữ là bàn phím tắt”, và “lưu header thì văng Settings”.

**Bàn phím tắt sau một ký tự.** `sx_validate` chạy trên mỗi `EditingChanged` và
gọi `reloadSections:` cho section 0 để đổi dòng gợi ý dưới ô nhập. Reload gỡ cell
— cùng ô nhập đang là first responder — ra khỏi cửa sổ, nên UIKit hạ bàn phím.
Cách sửa không phải “xoá gợi ý” mà là đổi chỗ: `SXHeaderFieldCell` tự có
`UITextField` và một `UILabel` gợi ý ngay dưới, trong cùng cell. Gợi ý được cập
nhật tại chỗ và chỉ gọi `beginUpdates`/`endUpdates` để tính lại chiều cao — không
tạo lại cell nào, nên bàn phím và con trỏ đứng yên.

**Văng Settings khi lưu.** `@property (nonatomic, copy) NSMutableArray *headers;`
— `copy` trên `NSMutableArray` trả về `__NSArrayI`, một mảng **bất biến**. Màn
hình vẫn gán được, nhưng lần đầu chạm vào là văng:
`-[__NSArrayI addObject:]: unrecognized selector sent to instance`. Đúng là lúc
bấm Lưu (thêm mới) hoặc bật/tắt/xoá/sắp xếp một header. Đổi sang `strong`. Cùng
lỗi tiềm ẩn ở `SXToolsController.grouped` cũng đã đổi (ở đó chỉ đọc nên chưa nổ).

**Ô nhập không còn bị “dời”.** Trước đây màn hình giữ hai ô nhập rồi nhét vào cell
khi `cellForRow` chạy; mỗi lần cuộn hay tái sử dụng cell là gỡ ra gắn vào, kéo
theo mất first responder và có thể mất chữ. Nay cell tự giữ ô của nó, còn chữ
sống trong `nameText`/`valueText` của màn hình — ô nhập chỉ là chỗ hiển thị.

**Chặn tái phát.** `scripts/check-prefs.sh` thêm hai luật: (a) cấm khai báo
`NSMutable…` với `copy`; (b) cấm gọi `reloadData`/`reloadSections`/
`reloadSpecifier(s)` bên trong hàm đang xử lý `UIControlEventEditingChanged`.
Cả hai luật đã được thử bằng một file vi phạm cố ý rồi xoá.

## 1.1.7 — Viết lại từng tính năng

Không thêm tính năng mới; mục tiêu là hết lỗi vặt và mọi màn hình cùng một chuẩn.
Bốn nhóm việc:

**Cấu hình nhà cung cấp.** Gõ tới đâu lưu tới đó nhưng **không reload bảng** —
mỗi hàng tóm tắt (`keyDisplay`, `modelDisplay`, `endpointDisplay`, `headersDisplay`,
`testStatus`) được vá thẳng vào `PSTableCell.value`, nên con trỏ và bàn phím đứng
yên. Khoá dán từ trình quản lý mật khẩu được bóc BOM, ký tự vô hình, dấu nháy và
xuống dòng trước khi kiểm tra. Địa chỉ endpoint sai hiện “⚠️ địa chỉ không hợp lệ”
và **không được lưu**; đổi cấu hình thì kết quả kiểm tra cũ tự mất hiệu lực để
không ai đọc nhầm một chữ “✓” từ cấu hình trước. Nút “Dán khoá” đọc clipboard,
kiểm tra tối thiểu 8 ký tự, và chỉ hiện khoá đã che.

**Trò chuyện thử.** Mỗi lần gửi có một số thế hệ: xoá hội thoại giữa lúc chờ thì
câu trả lời cũ bị bỏ, không rơi vào cuộc mới. Bong bóng “đang gõ” được **thay**
bằng bong bóng trả lời ở token đầu tiên thay vì để lại hai dòng. Lịch sử gửi kèm
là các cặp hỏi/đáp thật, cắt theo “Ngữ cảnh hội thoại”. Dòng phụ dưới tiêu đề ghi
`ms · token đầu · số mảnh` — đọc được chất lượng stream mà không cần mở log.

**Lịch sử & thống kê.** Đọc kho trong nền có số thế hệ nên kéo-xuống-làm-mới liên
tục không ghi đè bằng dữ liệu cũ. Lỗi quyền ghi hiện thành trạng thái rỗng có
hướng dẫn thay vì alert chen ngang. Lịch sử chia nhóm ngày có số lượt; thống kê
thêm tỉ lệ sự cố và mức tốc độ (nhanh/vừa/chậm/rất chậm).

**Công cụ & nhật ký.** Ô công cụ tự vẽ giữ closure riêng nên không còn bấm nhầm
khi thứ tự nhóm đổi. Log tô màu theo mức, nối thêm theo mảng dòng nên log bị xoay
vòng không làm mất dòng. Ô tìm kiếm của cả hai màn đều có debounce.

