# Tabspace — đặc tả thiết kế sản phẩm

**Trạng thái:** đặc tả đang được triển khai dần theo từng bản 0.x; mục 16 ghi lại cái gì đã có ở bản nào. Phần **chưa** làm tính đến 0.126: các điểm cần kiểm chứng bằng Chrome thật (mục 12), thông báo kết quả lượt Tự động theo kênh hệ điều hành (15.4), và quyền `processes` ở dạng mặc định (0.126 chỉ xin dưới dạng tùy chọn, bấm nút trong khối, còn Chrome kênh ổn định thì không cấp), so sánh quy tắc chồng lấn ở mức giữa các preset với nhau (5.7/6.3), và bộ mockup/design system hoàn chỉnh (14.1).  
**Phạm vi:** extension Chrome cho nhu cầu cá nhân; ưu tiên dữ liệu cục bộ.  
**Mục đích:** là nguồn tham chiếu thống nhất cho thiết kế, triển khai và kiểm thử, hạn chế mất ngữ cảnh giữa các lượt làm việc.

> Những giá trị thời gian, giới hạn và phím tắt dưới đây là mặc định đề xuất, không phải kết quả đo hay cam kết đã triển khai. Các quyết định còn cần kiểm chứng được ghi ở cuối tài liệu.

## 1. Vấn đề và mục tiêu

Người dùng giữ nhiều tab vì còn cần quay lại, nhưng tab chiếm tài nguyên, tự tải lại và làm thanh tab bừa bộn. Tabspace giúp giảm tải, tìm lại và tiếp tục công việc mà vẫn kiểm soát được những gì xảy ra.

Mục tiêu:

1. Quản lý tab đang mở, tab đã nghỉ và tab đã lưu trên nhiều cửa sổ.
2. Lưu và khôi phục có chọn lọc; tổ chức bằng nhóm, tag, workspace và preset.
3. Tự động hóa hữu ích nhưng an toàn, giải thích được, có thể tạm dừng và tùy chỉnh.
4. Giao diện trực quan, thao tác nhanh bằng chuột và bàn phím; khả năng nâng cao không làm rối tác vụ thường dùng.
5. Thiết kế local-first, cá nhân, không yêu cầu tài khoản; sao lưu và khôi phục rõ ràng.

Không hứa không bao giờ mất trạng thái trang, ngăn mọi lần tải của Chrome, đo chính xác RAM theo tab, hay không còn lỗi. Không đưa cộng tác nhóm, tài khoản bắt buộc, AI tự đóng tab vào phạm vi cốt lõi.

## 2. Thuật ngữ và mô hình

| Đối tượng | Ý nghĩa |
| --- | --- |
| Tab đang mở | Tab thực trong một cửa sổ Chrome; có thể đang chạy hoặc đã nghỉ. |
| Tab đã nghỉ | Tab Chrome vẫn tồn tại nhưng nội dung đã bị discard; khi kích hoạt thường sẽ tải lại. Đây không phải tab đã đóng. |
| Mẫu đo tài nguyên | Giá trị bộ nhớ, CPU hoặc mạng của một **tiến trình** tại một thời điểm, kèm nguồn và thời điểm đo; nhiều tab có thể dùng chung một mẫu. |
| Mục tab đã lưu | Bản ghi của URL, tiêu đề và metadata có thể thu thập; không phải bản sao trạng thái đầy đủ của trang. |
| Nhóm đã lưu | Bộ sưu tập mục tab trong Tabspace, có tên, màu, icon, tag, ghi chú và thứ tự. Khác nhóm tab gốc của Chrome. |
| Tag | Nhãn gắn vào nhóm hoặc mục tab; một mục có thể có nhiều tag. |
| Lượt lưu | Tập các bản ghi và kết quả được tạo bởi một lần lưu/dọn, phục vụ lịch sử và hoàn tác. |
| Phiên/snapshot | Ảnh chụp cấu trúc các cửa sổ và tab tại một thời điểm, trong phạm vi metadata Chrome cho phép. |
| Workspace | Không gian tổ chức cá nhân chứa tham chiếu tới các nhóm và bố cục mong muốn; không phải môi trường Chrome cô lập. |
| Preset dọn tab | Bộ quy tắc chọn tab, nơi lưu, lịch/kích hoạt, hành động và ngoại lệ. |
| Nhóm thông minh | Một bộ lọc lưu sẵn, là cách xem động, không tự di chuyển hay sao chép dữ liệu. |
| Hộp để sau | Nhóm hệ thống cho lưu nhanh khi chưa muốn phân loại. |

**Ba trạng thái người dùng cần phân biệt:**

- **Đang mở:** có tab trên thanh tab; chuyển đến tab để dùng.
- **Đã nghỉ:** vẫn có tab trên thanh tab; kích hoạt có thể tải lại và mất trạng thái trong bộ nhớ.
- **Đã lưu:** có bản ghi trong Tabspace; nếu đã đóng tab Chrome, cần mở URL lại. Một tab có thể vừa đang mở vừa có bản lưu; phải hiển thị cả hai, không coi là một trạng thái độc quyền.

### Danh tính, bản sao và tham chiếu

- Tab Chrome đang mở được nhận diện theo ID trong phiên Chrome; không dùng ID đó như định danh bền vững sau khởi động lại. Mục đã lưu, nhóm, workspace, preset, lượt và snapshot có ID riêng bền vững.
- Mỗi lần lưu tạo bản ghi/lượt có thể truy vết; các URL giống nhau không mặc nhiên là cùng một tab hay cùng trạng thái. Dọn tab trùng không tự xóa bản lưu.
- Một mục thuộc một nhóm lưu chính; nhiều workspace có thể tham chiếu cùng nhóm. Xóa tham chiếu workspace không xóa nhóm. Di chuyển mục đổi nhóm sở hữu; sao chép tạo bản ghi độc lập. Xóa nhóm cảnh báo các tham chiếu và preset bị ảnh hưởng.
- Tag gắn trực tiếp vào mục và/hoặc nhóm. Lọc theo tag hiển thị riêng nhóm gắn tag và mục gắn tag; mục không tự kế thừa tag nhóm thành metadata của chính nó. Có thể hiển thị mục nằm trong nhóm khớp tag như kết quả có nhãn nguồn, tránh đếm nhầm.
- Lượt lưu là lịch sử sự kiện, không phải nhóm mới. Di chuyển hoặc xóa mục không được âm thầm sửa lịch sử; lịch sử cho biết bản ghi còn tồn tại hay đã bị xóa. Hoàn tác dùng dữ liệu lượt còn giữ được và giải thích giới hạn.

## 3. Hạn chế thực tế và cam kết an toàn

- Chrome có Memory Saver; discard giải phóng nội dung tab khỏi bộ nhớ nhưng tab vẫn hiện. Trang thường tải lại khi kích hoạt; dữ liệu biểu mẫu chưa gửi, tác vụ nền, media hoặc trạng thái ứng dụng có thể mất.
- Không có tín hiệu tổng quát đáng tin cậy để phát hiện mọi biểu mẫu chưa lưu, cuộc họp im lặng, upload hay tác vụ nền. Tab không phát âm thanh không có nghĩa an toàn.
- Chrome có thể từ chối discard tab đang active trong một cửa sổ hoặc các trường hợp khác. Không chuyển tab đang xem để discard nếu không có sự đồng ý rõ ràng.
- Không thể bảo đảm ngăn Chrome bắt đầu tải trang khi khôi phục phiên hoặc khi mở nhiều URL. Không hứa khôi phục tab ở trạng thái chưa tải. Tab đã lưu không tạo yêu cầu mạng cho đến khi người dùng hoặc tự động hóa mở lại; hành vi tải sau khi mở do Chrome quyết định.
- Mở lại URL không bảo đảm lịch sử back/forward, scroll, form, phiên đăng nhập, trạng thái ứng dụng, nội dung đã thay đổi hoặc cấu trúc Chrome được khôi phục chính xác. Báo kết quả và các giới hạn thay vì gọi đó là khôi phục hoàn hảo.
- Không đưa ra số RAM tiết kiệm như số đo nếu không có nguồn đáng tin cậy. Hiển thị số tab và trạng thái thực tế.
- Không có kênh ổn định để đo RAM hoặc CPU của từng tab cho extension trên mọi kênh Chrome; số đo khả dụng là của tiến trình và nhiều tab có thể dùng chung. Không có nguồn tin cậy thì không hiện số và không tự động nghỉ, theo mục 15.
- Một số URL đặc biệt/nội bộ, file, trang extension, tab bị hạn chế quyền, trang yêu cầu đăng nhập, tab ẩn danh và URL không còn hợp lệ có thể không lưu hoặc mở lại được. Kiểm tra theo khả năng thực tế, hiển thị lý do; không cố vượt bảo vệ của Chrome.
- Extension có thể bị dừng hoặc lịch báo thức chạy trễ; không bảo đảm chạy đúng từng giây hay khi Chrome đóng. Không dùng thông báo bị bỏ lỡ làm bằng chứng đồng ý.

## 4. Kiến trúc trải nghiệm và thiết kế thị giác

### 4.1 Popup thao tác nhanh

Popup gồm tìm kiếm, số tab đang mở/đã nghỉ/đã lưu có giải thích cách đếm, tab gần đây, preset thường dùng và nút mở trang quản lý. Hành động chính: chuyển tab, **Lưu bản sao**, **Lưu & đóng**, **Cho nghỉ**, **Dọn cửa sổ** và **Lưu để sau**. Tác vụ nhiều tab có xem trước theo cài đặt an toàn; thao tác một chạm chỉ bật riêng khi người dùng chủ động chọn.

### 4.2 Trang quản lý

Sidebar: Tổng quan, Tab đang mở, Hộp để sau, Nhóm đã lưu, Workspace, Phiên, Preset/tự động hóa, Thùng rác, Cài đặt. Hiển thị nhóm yêu thích và tag ở khu vực có thể thu gọn. Nội dung chính hỗ trợ tìm kiếm, lọc, sắp xếp, chọn nhiều, chi tiết, trạng thái rỗng, đang tải và lỗi. Nhóm thu gọn để danh sách dài dễ đọc.

Các hành động thường dùng có nhãn; menu `⋯` chứa hành động ít dùng; thanh thao tác hàng loạt xuất hiện khi chọn. Không dùng màu làm tín hiệu duy nhất. Có giao diện sáng/tối, mật độ hiển thị, tương phản và focus rõ, nhãn cho trình đọc màn hình, hỗ trợ thu phóng và kích thước cửa sổ nhỏ.

### 4.3 Command palette và chuột

Một bảng tìm kiếm lệnh/tab/nhóm/tag/workspace/preset; phân loại kết quả **chuyển tới tab đang mở** và **mở bản lưu**. `↑/↓`, Enter, Escape và chọn nhiều hoạt động xuyên suốt; bảng `?` giải thích phím trong từng màn hình. Phím tắt toàn Chrome theo khả năng Chrome, người dùng chỉnh và được cảnh báo xung đột; không cam kết một tổ hợp cụ thể luôn khả dụng. Chuột hỗ trợ kéo thả, chọn bằng checkbox/Shift, menu bổ sung; mọi chức năng chính có đường thay thế bằng bàn phím.

### 4.4 Timestamp

Theo múi giờ và locale người dùng: hôm nay `14:36`; hôm qua `Hôm qua · 14:36`; ngày khác cùng năm `12 thg 10 · 14:36`; năm khác `12 thg 10, 2025 · 14:36`. Hover hoặc focus xem thời gian đầy đủ và múi giờ. Mỗi giá trị ghi rõ nghĩa: **Đã lưu**, **Cập nhật**, **Truy cập gần nhất** hoặc **Lần chạy**. Lưu thời điểm tuyệt đối, hiển thị theo múi giờ hiện tại; thay đổi ngày/múi giờ phải cập nhật nhãn. Không bịa thời gian truy cập nếu không có dữ liệu đáng tin cậy.

## 5. Chức năng quản lý và tổ chức

### 5.1 Tab đang mở

Xem theo cửa sổ, nhóm Chrome và trạng thái; tìm, chuyển đến, đóng, ghim/bỏ ghim, cho nghỉ, lưu bản sao, lưu & đóng. Hiển thị các tín hiệu Chrome thực sự cung cấp như active, audible, pinned, discarded; không suy diễn an toàn. Chọn nhiều, sắp xếp và thao tác hàng loạt với xem trước. Phát hiện URL trùng là gợi ý, không tự đóng; người dùng chọn bản nào xử lý.

### 5.2 Nhóm đã lưu

Tạo/sửa tên, màu tùy chỉnh, icon đơn giản từ thư viện, tag, ghi chú, yêu thích, thứ tự; kéo thả và thao tác bằng bàn phím. Lưu tab, nhiều tab, nhóm Chrome hoặc cửa sổ; xem theo lượt lưu, tất cả mục hoặc tên miền. Mở một, chọn nhiều hoặc tất cả, tại cửa sổ hiện tại/mới; hiển thị số lượng, cảnh báo theo ngưỡng tùy chỉnh và báo lỗi từng mục. Có tùy chọn đề xuất tạo lại nhóm Chrome khi mở, nhưng Chrome có bảng màu và giới hạn riêng: màu tùy chỉnh/icon Tabspace có thể không được biểu diễn chính xác trên thanh tab. Mở lại mặc định giữ bản lưu, không tự xóa.

### 5.3 Hộp để sau

Lưu nhanh một/nhiều tab khi chưa phân loại; phân biệt **lưu bản sao** và **lưu & đóng**. Hộp có tìm kiếm, tag, chuyển/sao chép sang nhóm, chọn nhiều. Lời nhắc phân loại là tùy chọn, có thể tắt. Xóa mục vẫn tuân theo thùng rác và xác nhận.

### 5.4 Tag và tìm kiếm

Tìm theo tiêu đề, URL, tên miền, nhóm, tag, ghi chú, workspace, preset, lượt lưu và metadata có sẵn. Bộ lọc trạng thái/cửa sổ/nhóm/tag/thời gian; lưu bộ lọc thành nhóm thông minh. Trang tag tách nhóm gắn tag và mục gắn tag; giải thích kết quả liên quan qua nhóm. Không lập chỉ mục toàn văn trang mặc định; nếu có trong tương lai cần opt-in, quyền, dung lượng và chính sách riêng.

### 5.5 Workspace

Workspace chứa tham chiếu nhóm và bố cục mong muốn; một nhóm có thể thuộc nhiều workspace. Chuyển workspace là tác vụ có xem trước: tab nào đề xuất lưu & đóng, tab bảo vệ nào giữ lại, nhóm nào sẽ mở; lựa chọn chỉ mở bảng, mở từng nhóm hoặc mở toàn bộ. Mặc định không âm thầm đóng/mở hàng loạt. Tab Chrome có thể liên quan nhiều workspace: chỉ đóng khi được chọn trong bản xem trước và qua chính sách bảo vệ; việc đóng có tác động trên toàn Chrome. Ghi rõ không có cô lập thật. Chuyển workspace sử dụng cùng giao dịch, lịch sử và thời gian miễn xử lý như preset.

### 5.6 Phiên, lịch sử và thùng rác

Snapshot lưu cấu trúc cửa sổ, tab, thứ tự, trạng thái ghim và metadata nhóm Chrome khi khả dụng. Cho lưu thủ công/tự động theo thiết lập, giới hạn số lượng/thời gian giữ, xem và so sánh hai snapshot theo dữ liệu thực sự có, khôi phục chọn lọc. Tạo điểm khôi phục trước thao tác lớn nếu bật; không xem snapshot là bảo đảm phục hồi trạng thái trang.

Nhật ký ghi thời điểm, nguồn kích hoạt, quy tắc áp dụng, kết quả/ngoại lệ và lỗi; không ghi nội dung trang. Thùng rác dành cho bản ghi đã lưu và metadata liên quan, thời hạn cấu hình; xóa vĩnh viễn và khôi phục có xác nhận. Tab Chrome đã đóng không được thùng rác bảo toàn trạng thái. Giới hạn số lượng, lưu trữ và thời hạn lịch sử phải minh bạch.

### 5.7 Sức khỏe tab

Gợi ý tab trùng, lâu không truy cập (chỉ khi có dữ liệu), đã lưu nhưng còn mở, quy tắc chồng lấn. Mỗi gợi ý có lý do, xem trước, bỏ qua/tắt; không tự coi tab cũ là rác. Không dùng ước lượng RAM như số đo. Gợi ý theo mức tiêu hao tài nguyên dùng chung khối xem trước và chịu cùng chính sách bảo vệ; điều kiện, nguồn đo và giới hạn ở mục 15.

**Trạng thái (0.122):** trang **Sức khỏe tab** đã có trong thanh bên và mang danh sách "được đề xuất nghỉ" mà mức **Chỉ gợi ý** (15.3) cần; ba loại gợi ý còn lại vẫn nằm ở trang riêng của chúng và trang này dẫn đường tới đó. **Quy tắc chồng lấn**: trang không tự đếm; dòng "Quy tắc chồng lấn" nói thẳng là bản này chưa so sánh preset với nhau và dẫn sang trang Preset, nơi đã có *Kiểm tra preset chồng lấn* chạy theo tab đang mở. Còn thiếu là phép so sánh **giữa các quy tắc** (hai preset nào chồng nhau kể cả khi không có tab nào mở), không phải một dòng trống ngụ ý "không có gì". Hộp thoại *Thái độ tài nguyên* không còn phải nhận là thiếu danh sách.

**Trạng thái (0.123):** trang còn là nơi duy nhất để xem kết quả một lượt Tự động: khối "Lượt tự động gần nhất" gọi `AutoDiscard.actionLabel()` và nêu từng tab đã nghỉ hoặc không xác nhận được. Danh sách gợi ý không đổi, và trang vẫn không có nút nghỉ tab nào.

## 6. Preset dọn tab

### 6.1 Cấu hình

Preset có tên, icon, màu, nhóm đích, quy tắc khớp/ngoại lệ, phạm vi cửa sổ, kích hoạt, chế độ, bảo vệ, giới hạn mỗi lượt, thông báo và lịch sử. Tạo từ tab đang mở hoặc nhập quy tắc; xem trước tab đang khớp và xung đột trước khi lưu.

Kiểu khớp dễ hiểu: tên miền chính xác; tên miền và tên miền con; URL có tiền tố đường dẫn; URL chính xác. Mặc định chuẩn hóa tên miền không phân biệt hoa thường; so khớp tên miền con theo ranh giới nhãn, không coi `notgithub.com` là con của `github.com`. Đường dẫn, query, fragment, cổng và scheme có ảnh hưởng tùy kiểu quy tắc và phải được hiển thị rõ trong UI; quy tắc URL chính xác mặc định so URL đầy đủ, kể cả query/fragment. Tiền tố đường dẫn phải theo ranh giới đoạn đường dẫn, không để `/work` khớp `/workshop`. Không tự loại query có thể mang ý nghĩa. Trang dùng chung domain cho tài khoản cá nhân/công việc không thể phân biệt chắc chỉ bằng URL: cảnh báo và cho ngoại lệ.

Quy tắc loại trừ của preset thắng quy tắc bao gồm của cùng preset. Không bắt người dùng dùng regex; regex nếu bổ sung sau phải tùy chọn nâng cao, có kiểm thử và bảo vệ hiệu năng.

### 6.2 Chế độ và kích hoạt

| Chế độ | Hành vi | Không phản hồi |
| --- | --- | --- |
| Đề xuất — mặc định | Nhận diện và hiện gợi ý; người dùng mở xem trước rồi xác nhận. | Không hành động. |
| Hỏi trước | Đến lịch hiển thị lời nhắc với Xem & dọn, Nhắc lại, Bỏ qua. | Không đóng; giữ gợi ý trong ứng dụng nếu còn phù hợp. |
| Tự động, opt-in | Sau khi người dùng bật và xác nhận rủi ro, lưu & đóng các tab đủ điều kiện; thông báo kết quả. | Không cần phản hồi, nhưng chính sách bảo vệ vẫn áp dụng. |

Kích hoạt thủ công, theo lịch ngày/giờ và ngày trong tuần, hoặc sau khoảng không hoạt động nếu có dữ liệu phù hợp. Không chạy chỉ vì tab vừa mở. Nút kết thúc công việc là lệnh người dùng, có xem trước mặc định. Tùy chọn dọn một chạm áp dụng riêng cho preset đã tin tưởng và không bỏ qua bảo vệ cứng. Thông báo hệ điều hành chỉ là kênh phụ; bị chặn/bỏ lỡ không đồng nghĩa đồng ý. Khi Chrome đóng hoặc lịch bị bỏ lỡ, mặc định không tự chạy bù; có thể báo và cho lựa chọn khác trong Nâng cao.

### 6.3 Bảo vệ và xung đột

Mặc định tự động bỏ qua tab active trong bất kỳ cửa sổ nào, pinned, audible, website/tab được bảo vệ, tab vừa mở/truy cập và tab trong thời gian miễn xử lý sau mở lại. Không hứa danh sách này phát hiện được tác vụ đang chạy. Khi tab không còn active, chỉ xem xét ở lần chạy tiếp theo, không đóng ngay do sự kiện chuyển tab.

Một tab khớp nhiều preset: quy tắc bao gồm cụ thể hơn thắng (URL chính xác > đường dẫn dài hơn > domain chính xác > domain kèm tên miền con); nếu cùng mức, thứ tự ưu tiên người dùng; nếu vẫn không phân định thì không tự xử lý và báo xung đột. Loại trừ chỉ áp dụng trong preset tương ứng; bảo vệ toàn cục vẫn áp dụng. Mỗi tab chỉ do tối đa một preset xử lý trong một lượt. Xem trước cho biết các preset cùng khớp và cho đổi đích nếu hợp lệ.

Mặc định lưu vào nhóm đích, mỗi lượt có bản ghi riêng. Tab trùng URL được đánh dấu, không tự xóa/gộp. Khi nhóm đích bị xóa hoặc không hợp lệ: tạm dừng preset, yêu cầu chọn đích mới; không tự tạo nhóm khác. Cho chạy thử, tạm dừng riêng/toàn bộ, nhắc lại sau, lịch sử và giải thích kết quả.

## 7. Chính sách chung, cài đặt và tự động hóa

### 7.1 Tầng cài đặt

- **Cơ bản:** ngôn ngữ, sáng/tối, mật độ, hành động mở bản lưu, ngưỡng xác nhận, thông báo, bảo vệ website, xuất/nhập.
- **Theo tính năng/đối tượng:** nhóm, preset, workspace, phiên và nghỉ tab; thể hiện cấu hình ngay tại nơi dùng.
- **Nâng cao:** ưu tiên preset, phạm vi, thời gian miễn sau khôi phục, giới hạn từng lượt, lịch bị bỏ lỡ, hành vi trùng, quyền, thời hạn lịch sử và phím tắt. Có mô tả, mặc định và nút khôi phục.

Cấp cấu hình: toàn cục → tính năng → preset/nhóm → website/tab → lựa chọn của một lượt. Mỗi cấp có **Dùng thiết lập cấp trên**, hiển thị nguồn hiệu lực và phần ghi đè. Nhóm không tự tạo quy tắc đóng tab; cấu hình nhóm chỉ áp dụng khi tính năng tương ứng dùng đến.

### 7.2 Thứ tự quyết định thống nhất

1. Giới hạn kỹ thuật, quyền và điều kiện lưu thành công không thể ghi đè.
2. **Bảo vệ cứng do người dùng đặt:** ngăn tự động; để thao tác thủ công phải sửa chính quy tắc bảo vệ, không thể bỏ qua chỉ bằng xác nhận trong lượt.
3. **Bảo vệ khỏi tự động / yêu cầu xác nhận:** tự động bỏ qua; thủ công có thể chọn và xác nhận rõ, tùy loại bảo vệ.
4. Lệnh thủ công đã xác nhận và lựa chọn từng lượt, trong phạm vi các bước trên.
5. Ngoại lệ website/tab và cài đặt preset/tính năng cụ thể.
6. Cài đặt chung, rồi mặc định.

Các tab active/pinned/audible được bảo vệ khỏi tự động mặc định; người dùng có thể đổi mức bảo vệ mặc định trong Nâng cao, ngoại trừ thao tác Chrome không cho phép. Giao diện cảnh báo khi giảm bảo vệ. Hành động thủ công vẫn phải tuân theo xác nhận và bảo vệ cứng. Không trộn lẫn **không tự động**, **luôn hỏi** và **không được xử lý cho đến khi sửa quy tắc**.

### 7.3 Điều phối

Một bộ điều phối chung cho preset, cho nghỉ, chuyển workspace và các tác vụ hàng loạt. Không để hai tác vụ tác động cùng tab đồng thời; kiểm tra lại tab, URL, đích, quyền và chính sách ngay trước hành động. Mỗi lượt có ID, trạng thái và kết quả từng mục; tác vụ chạy lại sau gián đoạn không được tự nhân đôi đóng/mở. Khi mơ hồ sau gián đoạn, dừng và yêu cầu xem kết quả thay vì đoán. Thay đổi quy tắc chỉ áp dụng cho lần chạy sau; nếu dữ liệu tab thay đổi trong lượt, kiểm tra lại và bỏ qua khi không còn đủ điều kiện.

Có nút **Tạm dừng tất cả tự động hóa**, trạng thái hiển thị rõ và tùy chọn tiếp tục; tác vụ thủ công vẫn hoạt động theo chính sách. Thời gian miễn xử lý sau mở lại áp dụng chung cho preset và cho nghỉ; mặc định đề xuất 30 phút, có thể chỉnh. Cần mô tả và kiểm chứng cách duy trì thời gian này qua khởi động lại Chrome; không dựa vào ID tab cũ một cách mù quáng.

## 8. Giao dịch, lỗi và hoàn tác

### 8.1 Lưu & đóng

1. Tạo danh sách ứng viên, lý do chọn/bỏ qua, đích và bản xem trước khi cần.
2. Tạo điểm khôi phục nếu bật; lưu bản ghi cho từng tab và xác nhận ghi thành công bền vững.
3. Ngay trước khi đóng, kiểm tra lại tab còn tồn tại, URL/chính sách/đích còn phù hợp. Nếu không, bỏ qua và báo lý do; bản lưu đã tạo được đánh dấu rõ.
4. Chỉ yêu cầu đóng tab đã lưu thành công. Ghi kết quả từng tab: đã lưu & đóng, đã lưu nhưng không đóng được, đã bỏ qua, hoặc lưu thất bại.
5. Hiện tóm tắt, chi tiết và hoàn tác. Không báo thành công toàn bộ khi có lỗi từng phần.

Lưu thất bại thì không đóng. Chrome/service worker bị gián đoạn giữa các bước: phục hồi trạng thái có thể xác minh, không đóng lại tab dựa trên ID không còn đáng tin; báo phần chưa rõ. Tính nguyên tử tuyệt đối giữa lưu trữ và Chrome API không được giả định.

### 8.2 Hoàn tác

Hoàn tác lượt dọn mở lại các URL đã đóng thành công, cố gắng khôi phục thứ tự/cửa sổ/nhóm khi khả thi; có thể chọn lại, báo lỗi và chống mở lặp khi nhấn nhiều lần. Giữ bản lưu mặc định. Không tự xóa mục, không coi tab đã lưu nhưng không đóng là cần mở lại. Khi nguồn dữ liệu hoàn tác đã hết hạn hoặc bị xóa, báo rõ. Mở lại URL không phục hồi chắc trạng thái ứng dụng; áp dụng thời gian miễn tự động hóa.

### 8.3 Một số edge case bắt buộc

- Tab đổi URL hoặc trở thành active giữa xem trước và đóng: kiểm tra lại và bỏ qua theo chính sách.
- Tab đóng ngoài Tabspace, cửa sổ biến mất, hoặc quyền bị thu hồi: báo kết quả thực tế.
- Chrome từ chối discard/đóng/nhóm tab: không giả báo thành công; nêu nguyên nhân nếu biết.
- Đầy dung lượng hoặc storage lỗi: ngừng đóng mục chưa lưu, cảnh báo và đề nghị xuất/dọn dữ liệu.
- Đồng hồ hoặc múi giờ thay đổi; lịch bị trễ, Chrome ngủ/đóng: không ngầm chạy bù theo mặc định; không gửi lặp hàng loạt lời nhắc.
- URL không còn hợp lệ, trang nội bộ hoặc đích mở không được hỗ trợ: ghi lỗi từng mục, tiếp tục phần còn lại nếu an toàn.
- Xóa/đổi tên nhóm, tag hoặc workspace đang được tham chiếu: xem ảnh hưởng, chọn xử lý; không tạo tham chiếu mồ côi.
- Nhập trùng ID, dữ liệu cũ/hỏng/phiên bản mới hơn: xác thực, xem trước, không ghi đè âm thầm; có thể hủy và giữ dữ liệu gốc.
- Tab trùng URL nhưng trạng thái khác: không tự gộp và không khẳng định bản sao tương đương.
- Cửa sổ ẩn danh: mặc định không truy cập/lưu; nếu hỗ trợ sau phải bật riêng, cấp quyền và giải thích rủi ro; tuyệt đối không trộn vào dữ liệu thường một cách vô hình.
- Đóng popup, từ chối thông báo, mất kết nối hoặc khởi động lại: không suy ra người dùng đã đồng ý.

## 9. Quyền riêng tư, dữ liệu và sao lưu

Local-first; không tài khoản, không tự truyền URL/lịch sử lên máy chủ. Quyền Chrome phải tối thiểu theo chức năng, giải thích trước khi xin quyền tùy chọn; phân biệt quyền cần để xem tab, nhóm, lịch, thông báo và các quyền nhạy cảm khác. Không lưu nội dung trang hay favicon từ dịch vụ ngoài một cách vô hình; xử lý favicon thiếu bằng biểu tượng dự phòng. Metadata URL, query, tiêu đề, ghi chú và file xuất có thể chứa dữ liệu nhạy cảm; cảnh báo khi xuất/chia sẻ, không ghi vào log công khai.

Xuất/nhập phiên bản hóa, xem trước số lượng và lựa chọn gộp/thay thế; nhập thực hiện sao lưu trước hoặc yêu cầu người dùng xác nhận rủi ro. Preset tự động nhập vào mặc định tạm dừng; không tự cấp quyền hay chạy. Lưu cục bộ không đồng nghĩa an toàn trước mất profile/gỡ extension; nhắc xuất bản sao ngoài profile theo tùy chọn. Nếu hỗ trợ đồng bộ đa thiết bị sau này: opt-in, giải quyết xung đột, bảo mật và chính sách dữ liệu riêng, không được giả định đã có.

## 10. Ưu tiên triển khai

**Giai đoạn 1 — nền tảng đáng tin:** tab đang mở, popup, tìm kiếm, nhóm/tag, Hộp để sau, lưu & đóng an toàn, nghỉ tab thủ công, khôi phục chọn lọc, bảo vệ, cài đặt cơ bản, xuất/nhập và bàn phím. Thiết kế sẵn mô hình lịch sử và xử lý lỗi; không đưa tự động đóng vào mặc định.

**Giai đoạn 2 — cá nhân hóa:** preset thủ công và chạy thử, giải thích/xung đột, phiên/snapshot, nhật ký và thùng rác; sau đó hỏi trước và tự động opt-in khi bộ điều phối và bảo vệ đủ tin cậy.

**Giai đoạn 3 — mở rộng:** workspace, nhóm thông minh, sức khỏe tab, so sánh phiên, tự động hóa nâng cao, gồm tự động cho nghỉ tab theo mức tiêu hao tài nguyên (mục 15) khi và chỉ khi nguồn đo được kiểm chứng. Đồng bộ, tìm nội dung trang, AI đề xuất là nghiên cứu tương lai, không phải cam kết.

Thứ tự có thể điều chỉnh sau kiểm chứng kỹ thuật; mỗi giai đoạn phải giữ các bất biến an toàn, không bỏ qua chỉ để giao nhanh.

## 11. Tiêu chí nghiệm thu và kiểm thử

- Tìm được tab đang mở và bản lưu; phân biệt rõ, không mở bản lưu khi định chuyển tab.
- Lưu thất bại/đầy dung lượng không đóng tab; đóng thất bại sau lưu được báo riêng. Tab đổi URL/active trong lúc xử lý được kiểm tra lại.
- Tự động hóa mặc định tắt hoặc chỉ đề xuất; không phản hồi lời hỏi không gây đóng. Tab được bảo vệ cứng không bị tác vụ thủ công hay tự động vượt qua.
- Preset xung đột, ngoại lệ, ranh giới domain/đường dẫn, query/fragment, nhóm đích bị xóa và quy tắc thay đổi giữa lượt có kết quả xác định.
- Hai tác vụ đồng thời không xử lý cùng tab; thử gián đoạn sau từng bước lưu/đóng, khởi động lại và thực hiện lại không gây đóng/mở lặp không mong muốn.
- Mở lại/hoàn tác được miễn xử lý trong khoảng cấu hình; không bảo đảm dữ liệu form. Khi mở rất nhiều tab có xem trước, tiến trình và kết quả từng phần.
- Nhập file lỗi/trùng ID/phiên bản khác không âm thầm ghi đè; preset nhập luôn tạm dừng. Kiểm tra khôi phục sao lưu thực tế, không chỉ kiểm tra file tồn tại.
- Kiểm tra múi giờ, nửa đêm, năm mới, giờ mùa hè, lịch bị bỏ lỡ và máy ngủ; timestamp có nhãn và thời gian đầy đủ.
- Kiểm thử nhiều cửa sổ, nhóm Chrome, pinned, audible, discarded, trang hạn chế, URL trùng, ẩn danh bị tắt, quyền bị thu hồi và dữ liệu lớn.
- Tất cả tác vụ chính dùng được bằng bàn phím; trạng thái có nhãn không phụ thuộc màu; popup/trang quản lý có trạng thái rỗng, lỗi và hiển thị phù hợp màn hình nhỏ.
- Nguồn đo tài nguyên: không có nguồn đáng tin thì không hiện số và không tự động nghỉ; tab dùng chung tiến trình không bị gán số riêng; mẫu đo cũ hoặc không rõ bị loại; thay đổi cấu hình hoặc cấu hình hỏng giữa lượt có kết quả xác định (15.7).

## 12. Các điểm cần xác minh trước hoặc trong triển khai

1. **Chrome API và quyền:** phiên bản Chrome hỗ trợ, khả năng truy xuất metadata/tín hiệu, màu nhóm native, hạn chế URL, ẩn danh và hành vi discard/khôi phục thực tế. Không suy ra quyền hoặc khả năng từ bản thiết kế.
2. **Tính bền vững của lưu trữ và điều phối MV3:** kiểm thử worker bị dừng giữa lưu và đóng; định nghĩa lưu thành công theo cơ chế lưu thực tế và khôi phục trạng thái không chắc chắn.
3. **Thời gian truy cập và miễn xử lý:** nguồn dữ liệu khả dụng, giới hạn sau restart, đồng hồ thay đổi và trường hợp tab có cùng URL. Nếu không xác định tin cậy, chọn bỏ qua tự động thay vì đoán.
4. **Lịch chạy và thông báo:** kiểm thử alarms, trạng thái Chrome đóng, quyền thông báo và hành vi nhắc lại trên phiên bản Chrome mục tiêu.
5. **Phạm vi workspace và snapshot:** xác định chính xác metadata nào có thể tái tạo; thiết kế UI thể hiện sai lệch khi khôi phục.
6. **Quy mô:** đo hiệu năng tìm kiếm, storage, xuất/nhập và UI với hàng nghìn bản ghi; chọn giới hạn phù hợp sau kiểm thử, không giả định con số.
7. **Chuẩn URL:** kiểm thử IDN, cổng mặc định, encoding, redirect, fragment và URL đặc biệt; mô tả điều kiện khớp trong UI trước khi bật tự động.
8. **Thời hạn lưu/khôi phục:** chọn mặc định sau thử nghiệm; phải công bố giới hạn và cho cấu hình thay vì hứa hoàn tác vô hạn.
9. **Nguồn đo tài nguyên theo tab:** kiểm chứng `chrome.processes` (kênh và nền tảng hỗ trợ, quyền `processes`, độ lệch so với Task Manager, ánh xạ tab ↔ tiến trình, chi phí CPU khi bật `includeMemory`), phạm vi của `chrome.system.memory`, và mức độ khả dụng còn lại của `performance.memory` đã bị deprecated. Chỉ bật Hỏi trước và Tự động sau khi số đo được xác nhận trên từng nền tảng mục tiêu; nếu không xác định được, chọn không đo thay vì đoán.

## 13. Tham khảo định hướng

Khảo sát ban đầu chỉ mang tính đại diện, không phải đánh giá mọi sản phẩm hay xác nhận tất cả tính năng hiện tại của đối thủ: [so sánh OneTab, Workona, Toby, Session Buddy và Tabli](https://botab.net/blog/best-chrome-edge-tab-managers-2026); [ví dụ thực tế về giới hạn tab discard và khôi phục](https://github.com/mahant3595/tabUnloader-ChromeExtension). Cần kiểm tra tài liệu Chrome chính thức và thử nghiệm API khi triển khai.

## 14. Đặc tả bổ sung: giao diện, thông báo, âm thanh và toàn màn hình

### 14.1. Mức độ hoàn thiện thiết kế giao diện

Các phần trên là định hướng sản phẩm và bố cục, **chưa phải bộ mockup, prototype hay design system hoàn chỉnh**. Trước khi triển khai giao diện cần thiết kế và duyệt thêm màn hình thực tế, trạng thái và khả năng tiếp cận; không coi sơ đồ chữ là thiết kế visual cuối cùng.

- **Hệ thống thiết kế:** định nghĩa token cho màu nền/chữ/viền/trạng thái, spacing, typography, bán kính, bóng, icon, focus và độ tương phản trong sáng/tối. Màu nhóm tùy chỉnh phải có cách hiển thị đọc được trên cả hai nền; không phụ thuộc màu để truyền tải trạng thái.
- **Thành phần thống nhất:** nút chính/phụ/nguy hiểm, trường nhập, bộ lọc, checkbox, menu, dialog, toast, banner, khối cài đặt thu gọn, danh sách, tab, bảng tiến trình và trạng thái lỗi/rỗng. Cùng một hành động phải có tên, icon và hậu quả nhất quán ở popup, trang quản lý và command palette.
- **Màn hình cần thiết kế:** onboarding/quyền, popup, tab đang mở, hộp để sau, nhóm/chi tiết nhóm, tìm kiếm, preset/tạo/chạy thử, workspace, phiên/khôi phục, thùng rác, cài đặt thường/nâng cao, xuất/nhập và trung tâm thông báo.
- **Trạng thái:** trống, tải, rất nhiều dữ liệu, không có kết quả, quyền bị từ chối, lỗi từng phần, xung đột, xác nhận nguy hiểm, đang thực hiện, hoàn tất và hoàn tác. Nút tắt khi không khả dụng phải giải thích lý do; không chỉ dựa vào tooltip để cung cấp thông tin bắt buộc.
- **Thích ứng:** popup có diện tích giới hạn; trang quản lý có bố cục thay đổi theo chiều rộng và zoom, không cắt hành động quan trọng. Hỗ trợ bàn phím, focus nhìn thấy, tên truy cập và kiểm thử độ tương phản; tôn trọng chế độ giảm chuyển động của hệ điều hành.

### 14.2. Các kênh thông báo — không giả định luôn phủ được trang

1. **Trong giao diện Tabspace:** toast ngắn cho xác nhận không nguy hiểm; banner hoặc panel cho cảnh báo có hành động; dialog cho quyết định quan trọng. Trung tâm thông báo/lịch sử lưu các thông báo cần xem lại. Đây là kênh mặc định khi popup hoặc trang quản lý đang mở.
2. **Thông báo hệ điều hành/Chrome:** tùy chọn để báo khi người dùng không ở giao diện Tabspace, phụ thuộc quyền, cài đặt và chế độ tập trung của hệ điều hành. Người dùng có thể tắt từng loại; không bảo đảm được hiển thị ngay.
3. **Trên trang web đang xem:** nếu bổ sung, là tính năng riêng **opt-in**, cần kiểm chứng quyền và giới hạn kỹ thuật theo từng trang. Không tiêm giao diện lên mọi website mặc định; không hiện nội dung tab riêng tư trong trang không liên quan. Không hoạt động được trên mọi trang hạn chế, trang nội bộ, trình xem đặc biệt hoặc mọi trạng thái toàn màn hình. Không giả định overlay extension có thể vẽ trên các ứng dụng khác hoặc video toàn màn hình.
4. **Badge trên icon extension:** tùy chọn báo có việc cần xem lại; không dùng làm kênh duy nhất vì icon có thể bị ẩn, và không đưa nội dung nhạy cảm vào badge.

Một sự kiện có một ID và trạng thái đọc/đã xử lý dùng chung giữa các kênh; không gửi lặp âm thanh/nhắc cùng lúc. Nếu kênh không khả dụng, lưu thông báo có ý nghĩa trong trung tâm thông báo; hành động nguy hiểm vẫn chờ người dùng hoặc tuân theo chế độ tự động đã bật. Không coi việc đóng, hết hạn, bỏ lỡ, không hiển thị hoặc không nghe thấy thông báo là sự đồng ý.

### 14.3. Loại thông báo và hành vi mặc định

| Loại | Ví dụ | Cách xử lý mặc định |
| --- | --- | --- |
| Thành công thông thường | Đã lưu một tab | Toast trong Tabspace; tự ẩn; không phát âm mặc định. |
| Có thể hoàn tác | Đã lưu & đóng một lượt | Toast có Hoàn tác; tự ẩn nhưng thao tác vẫn tìm được trong lịch sử trong thời hạn cho phép. |
| Cần quyết định | Preset ở chế độ hỏi trước | Thẻ lưu trong trung tâm thông báo; có Xem & dọn, Nhắc lại, Bỏ qua. Không phản hồi thì không đóng. |
| Cảnh báo/lỗi quan trọng | Lưu lỗi, thiếu quyền, tác vụ chỉ thành công một phần | Banner hoặc mục tồn tại đến khi xem/xử lý; tóm tắt rõ, mở chi tiết từng tab. Không chỉ dùng màu hoặc âm thanh. |
| Tự động hoàn tất | Preset tự động đã chạy | Mục lịch sử kèm số thành công/bỏ qua/lỗi và Hoàn tác nếu còn khả dụng; thông báo ngoài ứng dụng theo cài đặt. |

Không hiển thị toast thành công khi thực tế chỉ thành công một phần. Không làm mất tùy chọn hoàn tác chỉ vì toast đã biến mất. Mỗi thông báo có mức ưu tiên; gom nhiều sự kiện tương tự, giới hạn tần suất, không xếp chồng che nội dung. Cài đặt cho từng loại: kênh, âm, có thông báo hệ điều hành hay không; có tạm dừng, giờ yên lặng, nhắc lại và xóa lịch sử theo thời hạn. Thông báo quan trọng vẫn được ghi nhận trong ứng dụng trong giờ yên lặng, không vượt chế độ tập trung của hệ điều hành.

### 14.4. Âm thanh và âm tùy chỉnh

- **Mặc định:** tắt âm; có công tắc tổng và lựa chọn theo loại thông báo, âm lượng, nút nghe thử, giờ yên lặng và chống phát lặp. Không phát khi chỉ mở popup/trang hay sau khi người dùng đã xử lý sự kiện ở kênh khác.
- **Âm tích hợp:** một số âm ngắn, nhẹ, có tên và nghe thử; không dùng âm thanh là dấu hiệu duy nhất. Mọi hành động quan trọng vẫn có thông báo bằng chữ.
- **Âm tùy chỉnh:** đề xuất cho phép chọn tệp âm thanh cục bộ, xem tên, thời lượng, dung lượng, nghe thử, xóa/khôi phục mặc định và chọn âm theo loại. Không tải lên máy chủ. Kiểm tra định dạng thực sự được Chrome hỗ trợ, thời lượng/dung lượng và xử lý tệp lỗi trước khi lưu; giới hạn cụ thể sẽ quyết định sau kiểm thử. Không hứa mọi định dạng đều phát được.
- **Sao lưu:** bản sao lưu mặc định cần ghi rõ có bao gồm âm tùy chỉnh hay không. Đề xuất tùy chọn đưa tệp âm vào bản xuất đầy đủ sau khi cảnh báo dung lượng; bản xuất không bao gồm âm chỉ lưu lựa chọn/cấu hình và khi nhập mà thiếu tệp thì dùng âm mặc định hoặc im lặng, báo rõ. Không xuất đường dẫn tệp cục bộ nhạy cảm.
- **Hạn chế kỹ thuật:** âm thanh nền có thể bị hạn chế bởi chính sách autoplay, vòng đời Manifest V3, quyền, hệ điều hành hoặc chế độ im lặng. Nút nghe thử do người dùng bấm không chứng minh mọi âm nền sẽ phát. Cần kiểm chứng cơ chế phát phù hợp Chrome; không hứa luôn phát khi không có trang extension mở. Nếu không phát được, không coi là lỗi của tác vụ chính; lưu thông báo và cho biết trạng thái nếu có thể phát hiện. Không tự mở tab/cửa sổ gây gián đoạn chỉ để phát âm.

### 14.5. Toàn màn hình và không làm phiền

Phân biệt ít nhất: cửa sổ Chrome phóng toàn màn hình, một trang/video dùng Fullscreen API, và ứng dụng khác đang toàn màn hình. Khả năng nhận biết và hiển thị phụ thuộc Chrome, website, hệ điều hành và quyền; không giả định extension luôn phát hiện chính xác mọi trường hợp.

- Mặc định **không cố ép overlay lên trang/video hay rời toàn màn hình**, không chuyển cửa sổ và không mở dialog cưỡng bức để hỏi.
- Nếu Tabspace nhận biết được trạng thái toàn màn hình hoặc hệ điều hành đang chặn thông báo, tùy chọn mặc định là trì hoãn thông báo không khẩn và âm thanh đến khi người dùng quay lại; nếu không nhận biết được, không hứa tránh mọi gián đoạn. Tất cả thông báo cần xem vẫn có trong trung tâm thông báo.
- Với preset **hỏi trước**, không thấy hoặc không trả lời thì không đóng. Không bắt đầu đếm ngược tự đóng sau khi thoát toàn màn hình.
- Với preset **tự động opt-in**, mặc định đề xuất bỏ qua/hoãn khi phát hiện trạng thái toàn màn hình; người dùng có thể chỉnh trong Nâng cao, nhưng do phát hiện không hoàn hảo, bảo vệ theo tab/website vẫn là lớp chính. Khi không thể xác định trạng thái với độ tin cậy cần thiết, chế độ an toàn là hoãn, ghi lý do; cần kiểm chứng kỹ thuật trước khi hứa chức năng này. Không áp dụng ngầm cho các tác vụ người dùng chủ động khởi chạy.
- Khi trở lại, gom các thông báo bị trì hoãn thành một bản tóm tắt; không phát dồn âm. Cho tắt âm hoàn toàn hoặc đặt giờ yên lặng độc lập với phát hiện toàn màn hình.

### 14.6. Animation và chuyển động

Chuyển động phục vụ định hướng, không để trang trí gây chậm: phản hồi nút/focus tức thì; mở/đóng menu, toast và mở rộng nhóm nhẹ, thời lượng đề xuất khoảng 120–200 ms; chuyển trạng thái lớn không khóa tương tác lâu. Danh sách dài ưu tiên hiệu năng; không animate hàng nghìn phần tử cùng lúc. Tiến trình dài có chỉ báo và thông tin bằng chữ, không dùng animation vô hạn làm tín hiệu duy nhất.

Tôn trọng `prefers-reduced-motion`: bỏ hoặc giảm chuyển động không thiết yếu, thay bằng chuyển trạng thái tức thời; thêm lựa chọn hệ thống/bật/giảm trong cài đặt. Không nhấp nháy gây khó chịu; thông báo nguy hiểm, xác nhận và lỗi không dựa vào animation để được nhận biết.

### 14.7. Kiểm thử bổ sung

- Popup đóng, trang quản lý không mở, quyền thông báo bị từ chối, thông báo hệ điều hành bị chặn hoặc bỏ lỡ: không mất quyết định đang chờ và không tự đóng ở chế độ hỏi.
- Toàn màn hình Chrome, video/fullscreen trong trang, ứng dụng khác toàn màn hình và chế độ tập trung: kiểm tra từng nền tảng/phiên bản Chrome; ghi nhận trường hợp không thể phát hiện hoặc hiển thị thay vì tuyên bố hỗ trợ tuyệt đối.
- Âm thanh tắt, giờ yên lặng, tệp lỗi/quá lớn, âm tùy chỉnh thiếu sau nhập, playback bị chặn và nhiều sự kiện đồng thời: không phát dồn và không ảnh hưởng tác vụ chính.
- Toast hết hạn vẫn tìm được hoàn tác theo chính sách; lỗi một phần không bị thông báo thành công che lấp. Kiểm thử đọc màn hình, bàn phím, zoom và giảm chuyển động.

## 15. Tự động cho nghỉ tab theo mức tiêu hao tài nguyên

**Trạng thái:** đã có nền tảng ở 15.1–15.5 (tiến độ 0.115, bộ đo nền ở 0.116, cửa chặn RAM hệ thống ở 0.117, thẻ Cần chú ý ở 0.118, bản ghi lượt ở 0.119, sao lưu ở 0.120, nhãn Chỉ gợi ý ở 0.121, danh sách ở Sức khỏe tab ở 0.122, lượt Tự động ở 0.123, nhường giờ yên lặng và toàn màn hình ở 0.124, cổng đó thành fail-closed ở 0.125, nút xin quyền đọc tiến trình (tùy chọn) ở 0.126, kết quả lượt Tự động vào nhật ký và bản tin trên trang ở 0.127): module `auto-discard.js` quyết định theo ngưỡng rời từng tài nguyên, khối cài đặt thu gọn trong trang quản lý, `AutoDiscard.run()` chạy theo chu kỳ trong service worker với đúng các cổng chặn của một lượt nghỉ — và từ 0.123 lượt nền ở mức Tự động có đường nghỉ riêng sau một lần xác nhận rủi ro; hai mức kia vẫn chỉ đo và đếm, kết quả một lượt hiện thành thẻ trong Cần chú ý (0.118) hoặc danh sách ở *Sức khỏe tab* (0.122). Đã xong ở 15.6: quyền vẫn chưa xin (chủ đích), số đo không ra khỏi máy, và cấu hình vào sao lưu theo lựa chọn kèm buộc tắt khi nhập (0.120). **Chưa triển khai:** thông báo kết quả lượt Tự động qua kênh hệ điều hành, quyền `system.memory` (chỉ xin nếu nó mở thêm nguồn số thật), và đường ước lượng `performance.memory` trong trang. `processes` từ 0.126 có xin, nhưng chỉ là **quyền tùy chọn** do người dùng bấm trong khối — không nằm trong `permissions`, không xin lúc cài. Toàn bộ mục này vẫn phụ thuộc một khả năng chưa kiểm chứng (mục 12.9): Chrome không cho extension mọi kênh ổn định để đo tài nguyên của từng tab. Nơi nào không có nguồn đo đáng tin, giao diện nói "không đo được" và tính năng không chạy — không thay bằng số suy đoán.

Mục này chỉ thêm **một nguồn ứng viên mới** cho bộ điều phối: tab đang tiêu hao nhiều (RAM, CPU, mạng) thay vì tab khớp quy tắc URL như preset. Chính sách bảo vệ, phân tầng cài đặt, điều phối, thông báo, giới hạn và xử lý lỗi dùng lại mục 6, 7, 8, 14; không tạo cơ chế thứ hai song song.

### 15.1. Nguồn đo và giới hạn

| Tín hiệu | Nguồn dự kiến | Bản chất và giới hạn |
| --- | --- | --- |
| Bộ nhớ | `chrome.processes` → `privateMemory` (qua `getProcessInfo(..., true)` hoặc `onUpdatedWithMemory`) | Cần quyền `processes`; theo tài liệu Chrome, API này chỉ khả dụng trên kênh Dev. Số đo thuộc về **tiến trình renderer**, không phải tab: nhiều tab cùng nguồn gốc có thể chung một tiến trình, nên phải hiển thị "tiến trình chung N tab" thay vì chia đều cho từng tab. |
| CPU | `chrome.processes` → `cpu` | Tỷ lệ của **một lõi CPU** cho mọi luồng của tiến trình, trên máy nhiều lõi có thể vượt 100%; chỉ có trong sự kiện cập nhật; là giá trị tức thời, không phải trung bình của tab. |
| Heap JavaScript | `chrome.processes` → `jsMemoryUsed`, hoặc `performance.memory` trong trang | Chỉ tính heap V8, bỏ qua DOM/canvas/GPU nên thường thấp hơn RAM thật nhiều lần; `performance.memory` đã bị deprecated. Được phép hiển thị như **ước lượng**, không là căn cứ cho hành động tự động. |
| Mạng | `chrome.processes` → `network` (byte/giây) | Là tín hiệu "đang hoạt động", không phải "hao tài nguyên". Giá trị cao thường là lý do **không nên** nghỉ tab. |
| Áp lực bộ nhớ hệ thống | `chrome.system.memory` (toàn hệ thống, không theo tab) | Chỉ dùng làm điều kiện "khi nào chạy". Không quy cho tab, không hiển thị như số của tab. |

- Không nội suy số tài nguyên từ số tab, tiêu đề, tên miền, favicon hay các API toàn hệ thống. Không có nguồn → không có số.
- Không gọi `chrome.processes.terminate()`: nó giết cả tiến trình và mọi tab dùng chung. Phạm vi mục này chỉ là `tabs.discard`.
- Lấy số bộ nhớ làm Chrome tốn thêm CPU, nên Tabspace không đăng ký listener `onUpdatedWithMemory` thường trực: đo theo chu kỳ ở 15.3, chỉ khi tính năng bật, và ngừng ngay khi tắt.
- Mỗi giá trị đi kèm **nguồn** và **thời điểm đo**. Mẫu đo cũ hơn hai lần chu kỳ đo, tiến trình không đọc được, hoặc tab đã đổi URL/cửa sổ kể từ khi đo → coi là **không rõ** và bị loại khỏi mọi lượt tự động.

### 15.2. Khi nào một tab vào diện sẽ nghỉ

Ứng viên phải đồng thời thỏa: (1) vượt ngưỡng của tài nguyên **được chọn** theo đúng quy tắc kết hợp đã cấu hình; (2) không được xem trong khoảng thời gian chờ; (3) còn tồn tại và giữ nguyên URL, cửa sổ, tiến trình so với mẫu đo, được kiểm tra lại ngay trước khi nghỉ; (4) vượt qua toàn bộ lớp bảo vệ và điều phối ở 6.3, 7.2, 7.3 — tab đang xem, ghim, phát âm thanh, đã nghỉ, website/URL được bảo vệ, tab vừa mở trong thời gian miễn, giờ yên lặng, toàn màn hình, tạm dừng tự động hóa.

- "Vượt ngưỡng" so trên giá trị của lần đo gần nhất; với CPU phải vượt trong **đủ số chu kỳ liên tiếp** đã chọn, để một đợt tải trang ngắn không đủ kích hoạt.
- Chỉ nguồn đo thật (bảng ở 15.1, cột `chrome.processes`) được phép dẫn tới hành động tự động. Ước lượng heap chỉ dùng cho gợi ý và bản xem trước có nhãn "ước lượng".
- Không suy ra "có biểu mẫu chưa lưu" hay "đang chạy tác vụ nền" từ tài nguyên; tab CPU thấp vẫn có thể giữ nội dung chưa lưu.
- Một tab đang nằm trong lượt preset, chuyển workspace hoặc thao tác hàng loạt chưa kết quả thì lượt nghỉ bỏ qua; mỗi tab chỉ do một lượt xử lý, theo 7.3.

### 15.3. Cấu hình

Chỉ những lựa chọn thay đổi hẳn hành vi có mặt ở đây. Danh sách bảo vệ website/URL, thời gian miễn sau mở tab, giờ yên lặng, hoãn khi toàn màn hình, nút tạm dừng toàn bộ tự động hóa, kênh thông báo và âm báo **không** có bản sao riêng cho tính năng này; tất cả kế thừa theo phân tầng ở 7.1 và hiển thị nguồn đang áp dụng.

**Từ 0.125:** cổng giờ yên lặng/toàn màn hình của đường tự nghỉ nằm trong một hàm duy nhất (`holdReason`), hỏi **thắt** trạng thái cửa sổ như `auto-close.js` — không để `deferFullscreenNotifications` (vốn chỉ nói về thông báo) mở đường cho việc nghỉ tab — và tự giữ lượt khi chính nó không có cách hỏi. Vòng đo vẫn chạy: thiết lập "không làm phiền" không được phép làm số đo hỏng hạn dùng.

| Lựa chọn | Mặc định | Giá trị và ý nghĩa |
| --- | --- | --- |
| Bật tính năng | Tắt | Khi Chrome không cho nguồn đo thật, khối ghi "Không đo được tài nguyên trên Chrome này" và không cho bật Hỏi trước/Tự động; chỉ còn đường tắt thủ công ở Tab đang mở. |
| Cách xử lý | Hỏi trước | **Chỉ gợi ý**: hiện trong Sức khỏe tab, không lời nhắc. · **Hỏi trước**: thẻ trong Cần chú ý với Xem & nghỉ, Nhắc lại, Bỏ qua. · **Tự động**: bật riêng, phải xác nhận rủi ro một lần; không hỏi lại từng lượt. Không phản hồi ở Hỏi trước → không nghỉ tab nào. |
| Tài nguyên được xét | Bộ nhớ, CPU | Chọn rời từng thứ: **Bộ nhớ**, **CPU**, **Heap JavaScript (ước lượng)**, **Mạng/hoạt động nền**. Không gộp thành một điểm số tổng. |
| Ngưỡng từng tài nguyên | RAM ≥ 500 MB · CPU ≥ 50% một lõi · heap ≥ 200 MB · mạng ≥ 20 MB/phút | RAM 50–10000 MB; CPU 5–800%; heap 50–4000 MB; mạng 1–1000 MB/phút. Tài nguyên không được chọn thì ngưỡng bị ẩn và không tham gia quyết định. |
| Kết hợp | Một ngưỡng bất kỳ | **Vượt một ngưỡng bất kỳ** hoặc **vượt mọi ngưỡng đã chọn**. |
| Số chu kỳ liên tiếp (CPU) | 3 | 1–10; chỉ áp dụng cho tài nguyên biến thiên nhanh như CPU. |
| Chỉ xét tab không được xem trong | 12 giờ | 15 phút – 30 ngày, tính theo `lastAccessed` của Chrome; thiếu hoặc ở tương lai → không rõ → bỏ qua. |
| Giới hạn mỗi lượt | 10 tab | 1–100. |
| Chu kỳ đo | 5 phút | 1–60 phút; ngắn hơn làm Chrome tốn thêm CPU. |
| Chỉ chạy khi hệ thống thiếu bộ nhớ | Tắt | Khi bật, chỉ xử lý nếu RAM khả dụng của hệ thống dưới ngưỡng đã chọn (5–50%). |

- Không có lịch riêng: tính năng chạy theo chu kỳ đo và dùng chung lịch kiểm tra của bộ điều phối; không chạy bù cho chu kỳ bị lỡ (6.2).
- Không có ghi đè theo từng tab. Ngoại lệ đi qua đường sẵn có: bỏ qua trong bản xem trước cho lượt hiện tại, hoặc thêm website vào danh sách bảo vệ.

### 15.4. Phát hiện, xem trước và kết quả

Mỗi chu kỳ đo tạo một danh sách ứng viên có dấu vết riêng: ID tab, ID cửa sổ, URL, ID tiến trình, giá trị từng tài nguyên đã chọn, thời điểm đo, nguồn. Sau bước lọc ở 15.2:

1. **Chỉ gợi ý:** danh sách hiển thị ở Sức khỏe tab; mỗi hàng nêu lý do ("RAM 1,4 GB · đo 14:32 · tiến trình chung 2 tab"), có Xem & nghỉ, Bỏ qua gợi ý này, Tắt gợi ý. Không tự chọn tab nào.
   - Từ 0.122 danh sách đã có ở *Sức khỏe tab*. **Xem & nghỉ** ở đây là nút *Chọn N tab để xem trước*: nó đánh dấu sẵn ở Tab đang mở và việc nghỉ vẫn qua bản xem trước có xác nhận, nên trang không cần một đường nghỉ riêng. **Tắt gợi ý** dẫn sang khối cài đặt thay vì đặt một công tắc thứ hai — mỗi thiết lập chỉ có một nơi bật/tắt. **Bỏ qua gợi ý này** đi theo đúng luật của thẻ Hỏi trước: chỉ có hiệu lực với lượt đo hiện tại.
2. **Hỏi trước:** một thẻ trong Cần chú ý ("12 tab đang vượt ngưỡng · đo 4 phút trước") với Xem & nghỉ, Nhắc lại, Bỏ qua. Áp dụng 14.3 cho thông báo bị bỏ lỡ, đã đọc hoặc hết hạn: không phản hồi thì không nghỉ tab nào.
3. **Tự động:** không hỏi, nhưng vẫn dựng bản xem trước nội bộ, áp dụng bảo vệ và giới hạn, ghi kết quả từng tab, báo theo kênh đã bật.
   - Từ 0.123 đường này đã có: "bản xem trước nội bộ" là kế hoạch hành động do `plan()` dựng theo đúng chính sách (khác bản đếm dùng cho gợi ý), việc nghỉ đi qua `DiscardTools.request` như nút thủ công, và kết quả từng tab nằm trong `autoDiscardAction`. Từ 0.127 việc "báo theo kênh đã bật" dùng hai kênh sẵn có của ứng dụng: nhật ký sự kiện (`NotificationHistory`, qua `AutoDiscard.resultEvent`) và bản tin trên trang (`PageNotice`, kind `results`). **Chưa có** thông báo hệ điều hành cho lượt tự nghỉ; người dùng vẫn xem kết quả chi tiết ở *Sức khỏe tab* và tiêu đề khối. Hộp xác nhận rủi ro một lần là `autoDiscardAck`, một khóa riêng để file sao lưu không bao giờ mang theo sự đồng ý.

Bản xem trước dùng chung cho cả ba đường và cho nút nghỉ thủ công: nhóm theo cửa sổ, chọn/bỏ chọn từng tab hoặc toàn bộ, mỗi hàng ghi giá trị đo + nguồn + thời điểm; tab không rõ trạng thái bị khóa kèm lý do; tab vừa mở trong thời gian miễn để trống nhưng vẫn được nghỉ nếu người dùng tự đánh dấu rõ (theo 7.2 và mục 16, tiến độ 0.114). Nếu tab hoặc mẫu đo đổi sau bước kiểm tra cuối, tab đó bị bỏ qua; nếu toàn bộ dữ liệu đổi, lượt dừng và yêu cầu xem lại.

Kết quả: **không gọi là hoàn tác.** Tab không bị đóng nên không có bản lưu để khôi phục; tải lại một tab đã nghỉ vẫn làm mất nội dung chưa lưu. Lượt ghi vào nhật ký sự kiện với số đã nghỉ, số bị bỏ qua kèm lý do và số không xác nhận được; mục không xác nhận không tự thử lại.

### 15.5. Khối cài đặt thu gọn

Toàn bộ lựa chọn ở 15.3 nằm trong **một khối thu gọn "Tự động cho nghỉ tab"** tại Cài đặt & sao lưu → Tự động hóa, để không nhô lên màn hình thường dùng:

- Mặc định **thu gọn**. Hàng tiêu đề khi thu gọn phải tự đủ ý: trạng thái (Tắt / Chỉ gợi ý / Hỏi trước / Tự động), số tab đang vượt ngưỡng, tuổi dữ liệu đo, và cảnh báo khi nguồn đo không khả dụng hoặc Chrome không cho phép tự động. Không dùng màu làm tín hiệu duy nhất; có nhãn bằng chữ.
- Một nút duy nhất mở rộng/thu gọn, có `aria-expanded`; focus trở về nút khi thu gọn; `Esc` chỉ thu gọn khi phần thân đang mở và không có thao tác nào đang chạy; hoạt động đầy đủ bằng bàn phím.
- Thứ tự bên trong: bật/tắt + cách xử lý → tài nguyên và ngưỡng (mỗi tài nguyên một dòng: ô chọn, ngưỡng, đơn vị) → phạm vi (thời gian im lặng, giới hạn mỗi lượt) → đo (chu kỳ, chỉ khi hệ thống thiếu bộ nhớ) → lối tắt **Xem danh sách tab đang vượt ngưỡng**, **Khôi phục mặc định**, **Giới hạn và rủi ro**.
- Khi đang thu gọn, trạng thái chạy vẫn cập nhật ở tiêu đề (đang đo, đang chờ phản hồi, lượt cần kiểm tra); dữ liệu mới về trong lúc tải không xóa nội dung cũ.
- Kiểu khối này là mẫu chung cho các mục nâng cao khác: một hàng tiêu đề có trạng thái, phần thân là biểu mẫu, không hộp thoại lồng trong hộp thoại.
- Hiệu ứng mở/đóng 120–200 ms, tôn trọng `prefers-reduced-motion` (14.6). Ở cửa sổ hẹp, nhãn xuống dòng dưới trạng thái; không cắt số đếm và nút.

### 15.6. Quyền, dữ liệu và sao lưu

- Quyền mới: `processes` (đọc số đo tiến trình — kèm khả năng dừng cả tiến trình mà Tabspace cam kết không dùng) và `system.memory` (số toàn hệ thống). Cả hai phải được giải thích trước khi xin, nêu lý do và hệ quả, và khi người dùng từ chối thì tính năng tự thu gọn về mức an toàn: mất phần đo, không mất phần quản lý tab.
- Đường ước lượng từ trong trang (`performance.memory`) là tùy chọn nâng cao riêng, mặc định tắt: cần cấp quyền đọc/thay đổi dữ liệu cho các website cụ thể, chỉ bật cho website người dùng chọn, và không bao giờ đủ điều kiện cho chế độ Tự động.
- Số đo mới nhất giữ trong `chrome.storage.session` (mất khi Chrome khởi động lại); cấu hình giữ trong `storage.local`. Không ghi số đo vào log công khai, không đưa vào nhật ký thông báo.
- Sao lưu: cấu hình được phép chọn để xuất như các tính năng khác; khi nhập, tính năng luôn ở trạng thái **tắt** cho tới khi người dùng bật lại tại chỗ, theo 9. Không xuất giá trị đo.
- Lời nhắc, thông báo hệ điều hành và badge không chứa tên tab hay URL; tên và URL chỉ xuất hiện trong bản xem trước mà người dùng chủ động mở (14.2, 14.3).

### 15.7. Tiêu chí kiểm thử riêng

- Không có `chrome.processes` (kênh ổn định thông thường): khối nêu rõ lý do, không hiện số, không cho bật Hỏi trước/Tự động; các nút nghỉ thủ công vẫn hoạt động.
- Nhiều tab dùng chung một tiến trình: số đo được gán cho cả nhóm và ghi rõ "tiến trình chung"; không hiển thị số riêng cho từng tab, không suy ra tab nào nặng hơn.
- Ngưỡng biên (đúng bằng ngưỡng, thấp hơn 1 đơn vị), CPU ở chu kỳ 1/2/3, đổi cấu hình giữa chu kỳ, mẫu đo cũ hơn hai lần chu kỳ, tab đổi URL/cửa sổ/tiến trình sau khi đo: mỗi trường hợp có kết quả xác định.
- Tab đang xem, ghim, phát âm thanh, đã nghỉ, được bảo vệ, vừa mở trong thời gian miễn, giờ yên lặng, toàn màn hình, tạm dừng tự động hóa: không bị nghỉ ở cả ba chế độ (giờ yên lặng và toàn màn hình chỉ thật sự chặn lượt Tự động từ 0.124, chặn trước khi ghi báo cáo, còn việc đo thì không bị giữ); tab ước lượng không bao giờ bị nghỉ ở chế độ Tự động.
- Hỏi trước mà không phản hồi, phản hồi trễ, tắt popup, từ chối quyền: không tab nào bị nghỉ; lời nhắc còn tìm lại được.
- Lượt Tự động đạt giới hạn mỗi lượt, một phần thất bại hoặc không xác nhận: báo đúng số từng loại, không báo thành công toàn bộ, không tự thử lại.
- Khối thu gọn: đủ nghĩa khi thu gọn, điều hướng bằng bàn phím, `aria-expanded` đúng, tôn trọng giảm chuyển động, không cắt nội dung ở cửa sổ hẹp và khi zoom.
- Đo không chạy khi tính năng tắt; chu kỳ đo dài nhất và ngắn nhất đều không làm tăng liên tục số listener hoặc bộ đếm đang chờ.

## 16. Nhật ký tiến độ

### Tiến độ 0.84 — âm báo thử nghiệm
Âm báo tùy chọn cho kết quả tự động đóng, chỉ trong trang quản lý đang mở; không phát lại hoặc mở tài liệu nền. Giờ yên lặng và toàn màn hình làm bỏ qua, giới hạn tần suất và ghi dấu trước khi thử phát. Âm tùy chỉnh tối đa 1 MB/5 giây, kiểm tra giải mã, lưu cục bộ, không xuất sao lưu. Chrome có thể chặn âm. Âm cho lời nhắc và thông báo phủ trang vẫn chưa triển khai.

### Tiến độ 0.85 — thông báo website thử nghiệm
Opt-in, xin quyền Chrome riêng theo website, danh sách tối đa 20 origin; thử hiển thị bản tin chung cho lời nhắc mới và kết quả dọn tự động trên tab thường đang xem. Không phát bù, có giới hạn tần suất, tránh giờ yên lặng và toàn màn hình, không có thao tác nguy hiểm. Tắt/bỏ website không thu hồi quyền; website có thể quan sát DOM. Các kênh chưa dùng hệ thống trạng thái đọc chung; đây chưa phải trung tâm thông báo đầy đủ.

### Tiến độ 0.86 — trạng thái đọc dùng chung từng phần
Lời nhắc đang chờ được định danh theo preset và thời điểm chờ, kết quả theo mã lượt tự động; trong Cần chú ý có đánh dấu từng mục hoặc tất cả. Đã đọc tách biệt với xử lý và badge. Lọc thông báo hệ điều hành đang chờ và âm kết quả chưa phát; không thu hồi thứ đã gửi, không phát lại khi đánh dấu chưa đọc, kênh có thể chạy đồng thời. Chưa có lịch sử thông báo tổng quát hoặc trạng thái đọc cho các loại khác.

### Tiến độ 0.87 — chuyển động và cửa sổ hẹp
Bổ sung lựa chọn theo hệ thống/bật/giảm, có hiệu ứng xuất hiện ngắn cho hộp thoại và toast; chế độ bật là ghi đè rõ ràng. Lựa chọn cùng giao diện được xuất/nhập, tương thích sao lưu cũ. Điều hướng cửa sổ hẹp giữ nhãn và nhóm bằng hàng cuộn ngang. Chưa thay thế kiểm thử thủ công Chrome, bàn phím, zoom và đọc màn hình.

### Tiến độ 0.88 — rà soát chuyển workspace
Thêm chọn/bỏ chọn hàng loạt riêng cho tab cũ và bản lưu đích; tab cũ mặc định bỏ chọn, mục không đủ điều kiện bị khóa. Không đóng nếu không xác định rõ trạng thái tab; kiểm tra pending URL, workspace và nhóm đích ở bước hai và ngay trước đóng. Không khẳng định loại bỏ được mọi race của Chrome hay bảo toàn nội dung chưa lưu.

### Tiến độ 0.89 — hiệu năng và trạng thái giao diện
Gộp sự kiện tab/nhóm/storage trong trang quản lý và popup, giới hạn thời gian chờ trong đợt sự kiện và chạy tiếp khi có sự kiện trong lúc đang tải; thao tác chủ động vẫn đọc và kiểm tra lại ngay. Tối ưu lọc lựa chọn tab, tránh dựng lại sidebar không đổi, cố giữ focus khi xác định được mục tương đương và vị trí cuộn popup. Cần kiểm thử thủ công Chrome với danh sách lớn và bàn phím; chưa có benchmark trên trình duyệt.

### Tiến độ 0.90 — khôi phục phiên
Bổ sung chọn/bỏ chọn toàn bộ, tùy chọn bỏ URL đã mở hoặc trùng trong lượt (đều mặc định tắt), xác thực danh sách trước khi mở, kiểm tra lại tab trước ghim và tạo nhóm, và dừng khi trạng thái mở không rõ. Bản tóm tắt phân biệt tab bị bỏ qua, không thử, chưa xác nhận và nhóm bị bỏ qua; không tự thử lại. Cửa sổ/nhóm có thể thay đổi nếu bỏ trùng; vẫn không phục hồi nội dung trang chưa lưu.

### Tiến độ 0.91 — thời hạn thùng rác và lịch sử
Cấu hình cục bộ để gợi ý quá hạn; mặc định tắt, hiện tại chỉ dọn bằng xem trước/chọn/xác nhận, không tự xóa. Giới hạn 200 mục cũ nhất mỗi lượt, loại trừ lịch sử không hoàn tất/không rõ và lượt được báo cáo tự động tham chiếu; kiểm tra lại từng mục, dừng khi trạng thái thay đổi hoặc xóa không xác nhận. Tự động hết hạn chưa triển khai.

### Tiến độ 0.92 — tự dọn quá hạn thử nghiệm
Bổ sung chế độ riêng opt-in, mặc định tắt, chọn thùng rác và/hoặc lịch sử đủ điều kiện, tối đa 20 mục mỗi 1–30 ngày. Ghi danh sách ứng viên trước khi xóa, xác minh thời hạn/cấu hình và từng mục, ngừng khi thay đổi hoặc kết quả mơ hồ; lượt gián đoạn yêu cầu kiểm tra và xác nhận lại. Không chạy bù và tôn trọng tạm dừng toàn cục. Cảnh báo xóa vĩnh viễn trong popup, banner và cài đặt; tên trong danh sách lượt gần nhất có thể nhạy cảm, không nằm trong sao lưu. Cần kiểm thử Chrome thực tế.

### Tiến độ 0.93 — âm lời nhắc
Thêm lựa chọn âm riêng cho lời nhắc preset mới, mặc định tắt và tương thích thiết lập cũ. Chỉ thử phát khi trang quản lý đang mở, kiểm tra trạng thái đọc/lịch/tạm dừng và giờ yên lặng, khóa liên trang, giới hạn tần suất chung và ghi dấu trước khi phát. Lời nhắc đồng thời gộp một âm, không phát bù; Chrome có thể chặn. Chưa kiểm thử Chrome thực tế.

### Tiến độ 0.94 — danh sách thông báo hiện tại
Gộp lời nhắc preset đang chờ và kết quả đóng tự động theo thời gian; thêm lọc loại/chưa đọc và tìm kiếm kết quả. Giữ các thao tác và trạng thái đọc hiện có; đánh dấu tất cả gồm mục bị lọc ẩn, thao tác hoãn/bỏ nhiều vẫn dựa vào tìm kiếm và chọn trong hộp thoại. Các lượt dọn và tự động chưa hoàn tất vẫn riêng. Đây chưa phải lịch sử thông báo tổng quát, không lưu thêm sự kiện mới. Cần kiểm thử Chrome thực tế.

### Tiến độ 0.95 — bảo vệ mở workspace
Bổ sung kiểm tra workspace và fingerprint nhóm đích trước từng tab trong cả mở workspace lẫn bước mở sau chuyển; nếu không đọc được hoặc thay đổi thì dừng và báo từng mục, không thu hồi tab đã mở. Bổ sung chọn/bỏ chọn tất cả và số lượng trong hộp mở bản lưu. Theo thiết kế mục 104, chuyển workspace vẫn yêu cầu xem trước và chọn tab, chưa tự đóng không xác nhận. Các kiểm tra không loại bỏ mọi race. Cần kiểm thử Chrome thực tế.

### Tiến độ 0.96 — cảnh báo số lượng và chọn nhiều
Ngưỡng mở nhiều tab cấu hình 1–500, mặc định 20; xác nhận bổ sung khi số được chọn vượt ngưỡng, trước thao tác mở bản lưu, khôi phục phiên/lịch sử và trước cả bước đóng của chuyển workspace. Đếm trước bỏ trùng; hủy hoặc không đọc được cấu hình không thực hiện. Ngưỡng lưu cục bộ không backup, không áp dụng ngoài các luồng nêu trên. Thêm chọn/bỏ tất cả và đếm trong hộp lưu tab và khôi phục lịch sử. Cần kiểm thử Chrome thực tế.

### Tiến độ 0.97 — nhắc phân loại Hộp để sau
Nhắc phân loại là gợi ý opt-in, mặc định tắt, tuổi 1–365 ngày, đếm theo thời gian lưu hợp lệ; hiển thị Hộp để sau và popup, hoãn 1/3/7/30 ngày hoặc bỏ hoãn. Không chuyển/xóa/mở, không âm hoặc thông báo OS; tôn trọng tạm dừng toàn cục và tính lại khi giao diện mở/làm mới. Cấu hình và thời gian hoãn chỉ lưu cục bộ, không backup. Cần kiểm thử Chrome thực tế.

### Tiến độ 0.98 — mặc định mở bản lưu và phiên
Cho cấu hình cửa sổ mở bản lưu, bỏ URL đang mở/trùng cho bản lưu và riêng cho phiên, cùng tùy chọn khôi phục nhóm phiên. Chỉ đặt sẵn hộp xác nhận, sửa được từng lượt; chuyển workspace và lịch sử giữ lựa chọn riêng. Mặc định ban đầu tương thích phiên bản cũ, cấu hình chỉ lưu local, không backup; URL so nguyên văn và bỏ tab có thể thay đổi cấu trúc phiên. Cần kiểm thử Chrome thực tế.

### Tiến độ 0.99 — nhắc sao lưu và dung lượng
Nhắc sao lưu opt-in, mặc định tắt, chu kỳ 1–365 ngày và hoãn; hiển thị trong trang quản lý khi mở/làm mới và tôn trọng tạm dừng toàn cục. Người dùng tự xác nhận đã kiểm tra, lưu bản sao ngoài profile để đặt lịch mới; không coi thao tác xuất là đã sao lưu thành công. Xem kích thước storage.local do Chrome báo, không giả định đó là kích thước file sao lưu. Trạng thái nhắc chỉ lưu cục bộ, không xuất. Cần kiểm thử Chrome thực tế.

### Tiến độ 0.100 — cụm nhật ký sự kiện thông báo
Nhật ký cục bộ opt-in, mặc định tắt, cho lời nhắc preset mới và kết quả đóng tự động quan sát được, không ghi tên/URL hay ID nguồn nguyên văn, lưu tối đa 200 và tự bỏ mục cũ nhất. Trong Cần chú ý có lọc, tìm kiếm, xóa nhiều; không đổi trạng thái đã đọc hay nguồn. Ghi best-effort, không làm dừng tính năng chính khi lỗi, không chứng minh thông báo/âm đã phát và chưa là lịch sử mọi loại. Không sao lưu; cần kiểm thử Chrome thực tế.

### Tiến độ 0.101 — kế thừa mặc định mở nhóm/workspace
Bổ sung kế thừa từng lựa chọn nơi mở, bỏ URL đang mở và bỏ trùng lượt từ thiết lập mở chung, có ghi đè riêng theo nhóm hoặc workspace, hiển thị nguồn và cho đổi từng lượt. Chỉ áp dụng nút mở tương ứng, không áp dụng chuyển workspace, mở nhiều đối tượng, phiên hay lịch sử. Thiết lập cục bộ không sao lưu, giữ khi vào thùng rác, có xóa toàn bộ và giới hạn 1.000 đối tượng. Đây mới là một phần của mô hình kế thừa toàn bộ tính năng; cần kiểm thử Chrome thực tế.

### Tiến độ 0.102 — chọn nhiều trong bảng lệnh
Thêm checkbox và Ctrl+Space cho tab web đang mở hoặc nhóm/tab đã lưu, giữ lựa chọn khi tìm kiếm, tối đa 100, không trộn hai loại. Chuyển lựa chọn sang màn hình tương ứng sau khi đọc lại dữ liệu, xác thực ID/URL/cửa sổ, bỏ mục thay đổi và xác nhận thay lựa chọn cũ. Không mở/đóng ở bước chọn; các thao tác sau vẫn theo xem trước và bảo vệ. Lựa chọn mất khi đóng bảng; cần kiểm thử bàn phím, focus và trình đọc màn hình thực tế trên Chrome.

### Tiến độ 0.103 — lọc tuổi và tên miền
Tab đang mở có lọc theo lastAccessed Chrome, coi thiếu/tương lai là không rõ; bộ lọc động tab lưu bổ sung tên miền chính xác/bao gồm tên miền con và tuổi bản lưu tối thiểu/tối đa, kết hợp AND với từ khóa/tag. Khoảng thời gian tính 24 giờ, không suy ra mức độ an toàn hoặc lần truy cập từ ngày lưu. Bộ lọc mới có trong sao lưu; phiên bản cũ có thể bỏ qua điều kiện mới. Cần kiểm thử Chrome thực tế.

### Tiến độ 0.104 — sao lưu cá nhân tùy chọn
Bổ sung tùy chọn xuất mặc định mở chung, ngưỡng cảnh báo và thiết lập âm; file âm tùy chỉnh chọn riêng, mặc định không xuất. Có xem trước/lựa chọn áp dụng khi nhập, kiểm tra cấu hình hiện tại chưa thay đổi, giải mã và kiểm tra âm nhập trước khi ghi; âm luôn tắt sau nhập. Nếu không có file âm tùy chỉnh vì được bỏ khỏi bản xuất thì dùng âm mặc định. Không bao gồm ghi đè theo đối tượng hay tự động hóa, giới hạn nhập 10 MB; cần kiểm thử Chrome thực tế.

### Tiến độ 0.105 — chọn hàng loạt và tiếp cận bàn phím
Bổ sung bỏ chọn riêng phần đang thấy cho tab mở và các danh sách hàng loạt; giữ mục ẩn, làm rõ nút bỏ chọn tất cả, thông báo số lượng và đưa focus về nút chọn khi thanh lựa chọn tab biến mất. Sửa đặt lại bộ lọc còn sót thời gian. Hộp thoại có tên truy cập từ tiêu đề, bộ đếm lựa chọn là vùng thông báo; phím / không chiếm phím khi ô tìm kiếm bị ẩn ở Cài đặt. Chưa thay thế kiểm thử Chrome, zoom hoặc trình đọc màn hình thực tế.

### Tiến độ 0.106 — nhật ký kênh website và hệ điều hành
Mở rộng nhật ký opt-in với kết quả xử lý thông báo website và lần thử gửi hệ điều hành, phân biệt lọc, ghi thời gian/trạng thái và ID ngẫu nhiên băm, không ghi đích hoặc nội dung. Không thay đổi chính sách gửi, không ghi khi tính năng website tắt hoặc khi hệ điều hành chưa thử gửi; lỗi nhật ký không ngăn gửi. Không chứng minh hiển thị, không bao gồm âm và có thể mất khi Chrome gián đoạn. Dữ liệu mới không tương thích trình đọc nhật ký cũ; chưa kiểm thử Chrome thực tế.

### Tiến độ 0.107 — sao lưu mặc định riêng và nhật ký âm
Thêm lựa chọn xuất/nhập ghi đè mặc định mở cho nhóm/workspace đang hoạt động, ánh xạ ID mới, giữ thiết lập Hộp để sau hiện tại khi gộp, kiểm tra thay đổi và giới hạn trước khi ghi; không xuất ghi đè đối tượng trong thùng rác. Bổ sung nhật ký âm opt-in cho kết quả phát/từ chối, dùng khóa ghi chung sau khi nhả khóa âm, không lưu dữ liệu nhạy cảm, không ghi nghe thử hoặc các lượt bỏ qua. Tiếp tục không đảm bảo hiển thị/phát thực tế, không xuất nhật ký; cần kiểm thử Chrome thực tế.

### Tiến độ 0.108 — dữ liệu cá nhân an toàn hơn khi sao lưu
Thêm xuất/nhập opt-in số ngày nhắc phân loại, nhắc sao lưu và gợi ý thời hạn; nhập tắt nhắc/gợi ý, đặt lại trạng thái hoãn/xác nhận và không nhập tự dọn. Cấu hình thời hạn đổi làm guard tự dọn dừng; kiểm tra cài đặt không đổi trước khi ghi. Khi xuất quá 10 MB yêu cầu xác nhận trước khi tải vì giới hạn nhập, vẫn cho lưu ra ngoài nếu người dùng chủ động chọn. Cần kiểm thử trên Chrome thực tế.

### Tiến độ 0.109 — an toàn nhập dữ liệu
Kiểm tra dữ liệu đích thay thế và thiết lập được chọn không đổi kể từ khi mở hộp nhập; gộp vẫn dùng dữ liệu mới nhất. Cảnh báo số tham chiếu nhóm workspace/preset không còn hoạt động trước khi nhập, kể cả nhóm trong thùng rác. Từ chối ID phiên/workspace/preset trùng, ID trùng v1 ở nhóm/tab; file cũ thiếu ID vẫn được phép. Tiếp tục dùng khóa dữ liệu chung, không coi đó là giao dịch nguyên tử đối với phần mềm bên ngoài; chưa kiểm thử Chrome thực tế.

### Tiến độ 0.110 — quản lý tham chiếu nhóm
Thêm kiểm tra tham chiếu thiếu từ Workspace/Preset, phát hiện nhóm có bản trong thùng rác, chọn nhiều để gắn lại cùng nhóm hoặc gỡ; không tự khôi phục, di chuyển, mở hay đóng tab. Mỗi lượt hiển thị tối đa 200, không chọn trước, chống thay đổi trong lúc xác nhận; preset đổi đích được tắt lịch, guard phiên bản tự động đóng yêu cầu xác nhận lại. Xóa nhóm đơn/hàng loạt và xóa vĩnh viễn nhóm trong thùng rác báo số workspace/preset liên quan; kiểm tra trạng thái trước thao tác. Xóa preset/workspace và xóa nhiều phiên/nhóm/tab/thùng rác có thêm kiểm tra dữ liệu cũ. Chưa thay thế kiểm thử Chrome, phím và trình đọc màn hình thực tế.

### Tiến độ 0.111 — chọn nhiều và nghỉ nhanh từ popup
Popup chọn tối đa 100 tab web, chọn/bỏ phần hiển thị, giữ và đếm lựa chọn ẩn; cảnh báo lựa chọn cũ khi tab đổi. Có xem trước cho nghỉ và chọn lại từng mục, kiểm tra bảo vệ và trạng thái trước từng lượt, dừng khi không rõ, báo kết quả từng mục. Chuyển lựa chọn sang trang quản lý qua storage.session, token ngẫu nhiên, một lần, hiệu lực 2 phút, kiểm tra tab hai lần, không tự đóng/mở. Popup bị đóng có thể gián đoạn lượt nghỉ; cần kiểm tra Chrome. Dữ liệu phiên chưa nhận có lịch dọn và được kiểm tra khi worker khởi động; nếu Chrome trì hoãn hoặc lỗi, có thể còn đến khi Chrome kết thúc. Chưa kiểm thử Chrome, popup nhỏ, bàn phím và đọc màn hình thực tế.

### Tiến độ 0.112 — lưu nhiều tab trong popup và dọn dữ liệu chuyển tạm
Bổ sung xem trước lưu nhiều bản sao tới nhóm đã có hoặc Hộp để sau, bỏ chọn từng tab, cho phép URL trùng, không đóng tab; kiểm tra nhóm đích và tab, kiểm tra lại danh sách Chrome trước ghi, ghi một lần dưới khóa chung và báo lỗi không rõ không tự thử lại. Nút và lựa chọn khóa trong lúc xử lý. Dữ liệu chuyển từ popup được dọn khi nhận, qua alarm sau thời hạn và khi worker khởi động; việc dọn best-effort có thể trễ/lỗi. Chưa kiểm thử Chrome thực tế.

### Chọn và chỉnh phiên (0.113)
Trong Tab đang mở, chọn tab rồi bấm **Lưu thành phiên…** để xem trước, kể cả lựa chọn đang bị lọc ẩn. Cũng có thể chọn tab theo cửa sổ khi lưu phiên hiện tại. Chỉ lưu URL/metadata tab thường http/https, không đóng tab; tab đổi URL, cửa sổ, vị trí, ghim hoặc nhóm trong lúc kiểm tra bị bỏ qua. Khi đọc được metadata nhóm, thay đổi tên/màu/thu gọn nhóm khiến tab liên quan bị bỏ qua; nếu không đọc được nhóm, phiên được lưu không có metadata nhóm và có thông báo. Chrome vẫn có thể thay đổi sau lần kiểm tra cuối, nên đây không phải thao tác nguyên tử. Kiểm tra danh sách phiên trước khi thử lại nếu không xác nhận được ghi.

Trong **Phiên đã lưu → Chỉnh phiên…**, đổi tên hoặc chọn giữ/bỏ tab của phiên thủ công; bỏ tab cần xác nhận, không ảnh hưởng tab Chrome và không thể hoàn tác từng tab qua thùng rác. Xuất sao lưu trước nếu cần; xóa cả phiên bằng nút xóa để chuyển vào thùng rác. Snapshot tự động và điểm khôi phục không cho chỉnh. Nếu phiên thay đổi trong lúc mở hộp thoại, thao tác dừng; kiểm tra lại trước khi thử. Không khôi phục nội dung trang hoặc form chưa lưu.

### Thời gian miễn trong thao tác nghỉ (0.114)

Thời gian miễn sau mở tab trước đây chỉ áp dụng cho mô phỏng và tự động đóng. Nay bản xem trước cho nghỉ thủ công cũng dùng nó. Trong **Tab đang mở → Cho tab nghỉ** và **Xem & nghỉ** ở popup, tab vừa mở hoặc không xác định được thời điểm mở vẫn được nghỉ nhưng **để trống** trong danh sách; dòng đó ghi lý do và số phút còn lại của thời gian miễn, đầu danh sách nêu số tab cần đánh dấu rõ. Với nút **Nghỉ** ở một tab, hộp xác nhận nêu cùng lý do và bạn vẫn xác nhận được. Tab đang xem, ghim, phát âm thanh, đã nghỉ hoặc thuộc website được bảo vệ vẫn bị bỏ qua như trước; nếu không đọc được thiết lập hay dữ liệu phiên của thời gian miễn, mọi tab được coi là cần đánh dấu rõ nên thao tác không bị chặn. Thời gian miễn không áp dụng cho đóng tab hoặc lưu & đóng, và không phải dấu hiệu trang an toàn: nội dung chưa lưu vẫn có thể mất. Mốc mở tab chỉ nằm trong `chrome.storage.session` của phiên Chrome, không ghi URL; khởi động lại Chrome hoặc tải lại extension bắt đầu lại thời gian miễn cho tab chưa có mốc. Cần kiểm thử Chrome thực tế.

### Khối đo tài nguyên và hẹn nghỉ theo ngưỡng (0.115)

Mục 15 bắt đầu từ phần an toàn nhất. Module `auto-discard.js` giữ ngưỡng **rời từng tài nguyên** (RAM, CPU, heap ước lượng, mạng/hoạt động nền) — không có điểm tổng nào; kèm cách kết hợp "vượt một ngưỡng bất kỳ"/"vượt mọi ngưỡng đã chọn", số chu kỳ liên tiếp cho tài nguyên thay đổi nhanh, mẫu đo cũ hơn hai chu kỳ, tab đổi cửa sổ hoặc đổi tiến trình sau khi đo. Mọi trường hợp không đọc được đều đưa tab về "không rõ" và loại khỏi danh sách, không suy số từ tên miền, tiêu đề hay số lượng tab. Nhiều tab chung một tiến trình renderer được ghi rõ "tiến trình chung N tab" thay vì chia đều.

Trong **Cài đặt & sao lưu** có một khối thu gọn **Tự động cho nghỉ tab theo tài nguyên**: khi thu gọn, tiêu đề tự đủ ý (trạng thái Tắt/Chỉ gợi ý/Hỏi trước/Tự động, số tab vượt ngưỡng, tuổi dữ liệu đo, cảnh báo khi Chrome không cho đo); phần thân là biểu mẫu một khối, mặc định thu gọn, có `aria-expanded`, Esc chỉ thu gọn khi không có thao tác nào đang chạy, và có lối tắt **Đo lại và xem danh sách…**, **Khôi phục mặc định** (chỉ đổi biểu mẫu, phải bấm Lưu). Việc lưu đi qua khóa ghi chung và dừng nếu thiết lập đã đổi ở nơi khác.

Chưa xin quyền `processes`, chưa có thẻ "Cần chú ý", chưa có lượt nghỉ tự động (thẻ đã có ở 0.118, lượt tự nghỉ đã có ở 0.123; quyền vẫn chưa xin): trên Chrome ổn định khối nêu "Không đo được tài nguyên trên Chrome này" và **từ chối bật** tính năng thay vì bật rồi im lặng, nên đường thủ công ở Tab đang mở giữ nguyên. Danh sách ứng viên không nghỉ tab nào; nút ở cuối hộp thoại chỉ đánh dấu tab để bạn xem trước và xác nhận như cũ. Số đo chỉ nằm trong `chrome.storage.session` (mất khi khởi động Chrome, không kèm URL); thiết lập chưa được đưa vào file sao lưu (từ 0.120 mới có ô chọn riêng). **Chưa kiểm thử trên Chrome thực tế**: cần xác nhận hành vi trên Chrome kênh Dev có quyền `processes`, bàn phím, `prefers-reduced-motion` và cửa sổ hẹp.

### Bộ đo nền theo chu kỳ (0.116)

Số đo không chỉ lấy lúc mở khối Cài đặt nữa. `AutoDiscard.run()` là điểm vào chung: trang quản lý gọi khi bấm **Đo lại và xem danh sách…**, còn service worker gọi trong chu kỳ mỗi phút sẵn có, chạy cùng lịch với các việc nền khác; khoảng giữa hai lần đo là **Chu kỳ đo (phút)** trong khối. Ở đường nền, một lượt chỉ đọc số và ghi lại bao nhiêu tab vượt ngưỡng — không tab nào được nghỉ, chưa xin quyền `processes`/`system.memory`, nên con số trong tiêu đề là số đếm theo ngưỡng, không phải số tab sẽ nghỉ.

Lịch đo đi theo đúng những gì Chrome cho phép. Chu kỳ bị bỏ lỡ (máy ngủ, tiện ích chưa kịp chạy) được nêu rõ "có chu kỳ đo đã bỏ lỡ, không chạy bù" thay vì đo dồn cho kịp; dữ liệu cũ hơn hai chu kỳ bị coi là hết hiệu lực và tiêu đề báo "dữ liệu đo đã cũ, hãy đo lại". Tab đóng hoặc chuyển trang mất mẫu đo ngay lập tức, mẫu chỉ nằm trong `chrome.storage.session` và không kèm URL hay tiêu đề; khi cả hai đường đo đều có kết quả thì kết quả mới hơn được hiển thị.

Trước mỗi lượt, các cổng chặn vẫn được kiểm tra lại và mỗi cổng có lý do riêng: tính năng tắt, tạm dừng tự động hóa, cấu hình hoặc danh sách bảo vệ không đọc được, và (từ 0.117) hệ thống chưa thiếu bộ nhớ; khi một cổng giữ lượt đo thì không có số liệu nào được ghi. Tùy chọn "Chỉ chạy khi hệ thống thiếu bộ nhớ" nay bị từ chối ngay lúc lưu nếu Chrome không cho đọc `chrome.system.memory`, thay vì chấp nhận rồi không bao giờ chạy. **Chưa kiểm thử trên Chrome thực tế**: cần xác nhận chu kỳ đo chạy đều khi để tiện ích chạy nền, không đo bù sau khi thức máy, và số trong tiêu đề khớp danh sách đo.

### Cửa chặn RAM hệ thống và hộp giới hạn (0.117)

Lựa chọn "Chỉ chạy khi hệ thống thiếu bộ nhớ" trước đây mới chỉ bị chặn khi Chrome không cho đọc `chrome.system.memory`, còn con số RAM khả dụng thì chưa thật sự được dùng. Từ bản này mỗi chu kỳ đọc `getInfo()` rồi so với ngưỡng đã chọn (5–50%): RAM khả dụng còn **từ ngưỡng trở lên** thì lượt đo bỏ qua và nêu rõ "RAM khả dụng còn 50%, chưa thấp hơn ngưỡng 12%"; số đọc được không hợp lệ (thiếu, âm, lớn hơn tổng dung lượng) hoặc API báo lỗi thì lượt đo **dừng** kèm lý do, không đoán hộ. Khi một cửa chặn giữ lượt đo, không có số liệu nào được ghi nên tiêu đề khối giữ nguyên số cũ. Nút **Đo lại và xem danh sách…** vẫn đo, vì đó là yêu cầu trực tiếp của bạn.

Trong khối, thứ tự ô làm theo 15.5: phạm vi (thời gian không được xem, giới hạn mỗi lượt) đứng trước phần đo (chu kỳ đo, số chu kỳ liên tiếp, ngưỡng RAM); không thêm lựa chọn mới. Nút **Giới hạn và rủi ro** ở cuối khối mở hộp giải thích thẳng những gì số đo không chứng minh được: số là của tiến trình renderer chứ không của riêng tab, heap chỉ là ước lượng, tài nguyên không cho biết trang còn nội dung chưa lưu, cho nghỉ tab không tạo bản lưu để khôi phục, và bản này chưa có lượt nghỉ tự động. Hộp chỉ để đọc, không đổi thiết lập và không ghi gì. (Từ 0.123 đoạn đó trong hộp đã nói khác: mức Tự động có đường nghỉ riêng, sau một lần bạn xác nhận rủi ro trên máy này.)

Hai phần còn lại của mục 15 được nêu ở bản sau: danh sách **Chỉ gợi ý** cần Sức khỏe tab (mục 5.7 lúc đó chưa tồn tại trong ứng dụng; 0.121 ghi rõ điều đó ngay trong hộp thoại cài đặt, và 0.122 đã dựng trang này), và việc đưa cấu hình vào file sao lưu kèm buộc tính năng ở trạng thái tắt khi nhập (đã làm ở 0.120). Đường nghỉ Tự động của 15.4.3 có từ 0.123; quyền `processes` vẫn chưa xin, chủ đích như vậy. **Chưa kiểm thử trên Chrome thực tế**: cần xác nhận `chrome.system.memory.getInfo()` trả số như tài liệu và một chu kỳ bị cửa chặn RAM giữ lại không để lại số mới nào trên tiêu đề khối.

### Thẻ vượt ngưỡng trong Cần chú ý (0.118)

Số đo nền có chỗ đứng ngoài Cài đặt. Khi **Cách xử lý** là Hỏi trước, mục **Cần chú ý** thêm một thẻ "N tab đang vượt ngưỡng · đo X phút trước", kèm số tab bị chặn bởi danh sách bảo vệ hoặc đang được xem, và thẻ này được tính vào nhãn ở thanh bên. Ba nút đúng theo 15.4: **Xem & nghỉ** chỉ đánh dấu những tab còn sống trong danh sách rồi chuyển sang Tab đang mở để dùng bản xem trước sẵn có — bấm nút này không nghỉ tab nào; **Bỏ qua lần đo này** ẩn thẻ; **Hiện lại thẻ** bỏ ẩn.

Quyết định "có thẻ hay không" nằm trong `AutoDiscard.attention()` và được tiêu đề khối, thẻ cùng bộ đếm sidebar dùng chung, nên ba chỗ không thể nói khác nhau. Không có thẻ khi: tính năng tắt, cách xử lý là Chỉ gợi ý hay Tự động, Chrome không cho nguồn đo, không còn tab nào trên ngưỡng, danh sách rỗng, hoặc số đo cũ hơn hai chu kỳ — đúng quy tắc từ chối dữ liệu cũ ở 15.2. Việc ẩn thẻ chỉ là một ghi chú trên chính bản ghi lần đo, nên lượt đo kế tiếp xoá nó: không có danh sách bỏ qua nào lớn dần và vẫn không có ghi đè theo từng tab (15.3). Không phản hồi thẻ không phải sự đồng ý — không tab nào bị nghỉ.

### Kết quả đo sống cùng phiên Chrome (0.119)

Bản ghi "lần đo gần nhất" — số tab vượt ngưỡng, số tab bị chặn, danh sách ID để mở bản xem trước và ghi chú đã bỏ qua thẻ — trước đây nằm trong `chrome.storage.local`, tức sống sót qua khởi động lại Chrome trong khi các tab nó trỏ tới thì không. Bản này chuyển bản ghi sang `chrome.storage.session`, đúng theo 15.6: mất khi Chrome khởi động lại, không ra khỏi máy, không nằm trong file sao lưu; các mẫu đo theo tiến trình vẫn ở chỗ cũ. Trang quản lý đọc bản ghi song song với các dữ liệu khác và nghe `storage.onChanged` vùng `session`, nên tiêu đề khối cùng thẻ trong Cần chú ý cập nhật mà không cần tải lại trang. `AutoDiscard.run()` cũng xoá bản ghi cũ do bản trước để lại ở `storage.local`, và từ chối đo khi `chrome.storage.session` không khả dụng thay vì đo xong bỏ số đi. **Chưa kiểm thử trên Chrome thực tế**: cần xác nhận khởi động lại Chrome làm mất thẻ, và một lượt đo nền trong lúc trang quản lý đang mở cập nhật được tiêu đề mà không phải bấm lại.

### Ngưỡng tài nguyên vào sao lưu theo lựa chọn (0.120)

Theo 15.6, hộp **Xuất dữ liệu JSON** có thêm ô chọn "Thêm ngưỡng tài nguyên cho nghỉ tab (khi nhập luôn ở trạng thái tắt)". Chỉ cấu hình đi theo: bật/tắt, cách xử lý, cách kết hợp, ngưỡng rời từng tài nguyên, số chu kỳ liên tiếp, thời gian không được xem, giới hạn mỗi lượt, chu kỳ đo và cửa RAM hệ thống. Không có số đo nào vào file — bản ghi lần đo nằm ở `chrome.storage.session` nên phần xuất không nhìn thấy, và file cũng không chứa tên hay URL tab.

Khi nhập, hộp xem trước chỉ hiện ô "Áp dụng ngưỡng tài nguyên trong file" nếu file có mục đó; không chọn thì cấu hình hiện tại giữ nguyên. Khi chọn, `BackupOptions.resource()` luôn ghi `enabled:false`, và mức **Tự động** trong file bị hạ về **Hỏi trước**, vì lời xác nhận rủi ro ở 15.3 không thể đi nhờ file. Mục này cũng nằm trong danh sách kiểm tra "dữ liệu đã thay đổi ở nơi khác": nếu cấu hình tài nguyên bị sửa lúc hộp nhập đang mở, việc nhập dừng và không ghi gì.

### Chu kỳ đo tự quyết định lại, và nhãn thành thật (0.121)

Bản này ghi thẳng vào hộp thoại **Thái độ tài nguyên** rằng mức **Chỉ gợi ý** chỉ đổi *cách đếm và cách nhắc*: danh sách đề xuất riêng ở *Sức khỏe tab* (5.7) vẫn chưa tồn tại, nên đừng hiểu mức này là một cách an toàn hơn để tab tự nghỉ — muốn tab thật sự nghỉ phải có mức **Tự động**, và mức đó vẫn đang tắt.

Ba chỉnh sửa còn lại chỉ là kiểm chứng, không đổi hành vi:
- mỗi chu kỳ **quyết định lại từ chuỗi mẫu hiện hành**, nên đổi ngưỡng hay đổi *Chu kỳ đo* có hiệu lực ngay ở lần chạy kế tiếp (mẫu cũ quá *Chu kỳ đo* thì tab rơi khỏi danh sách ngay chu kỳ sau), không cần nạp lại extension;
- test mạch báo thức giờ chạy thẳng module thật `AutoDiscard.run` thay vì callback giả: với *Chu kỳ đo* 60 phút, bốn phút tick chỉ hỏi Chrome **một** lần; với 1 phút thì đo cả bốn lần;
- phần đo không tự thêm `chrome.alarms`/`setTimeout`/`setInterval` nào và không đụng `chrome.tabs` — nếu về sau có ai chèn một lệnh nghỉ tab vào module, test báo đỏ.

### Sức khỏe tab có danh sách "được đề xuất nghỉ" (0.122)

Mức **Chỉ gợi ý** (15.3) cuối cùng cũng có chỗ của nó: trang **Sức khỏe tab** ngay trong thanh bên, gọi được cả bằng bảng lệnh. Trang này là điểm hẹn của các loại gợi ý theo 5.7 — **Tab trùng**, **Lâu chưa truy cập**, **Đã lưu nhưng còn mở** mỗi loại vẫn có trang riêng nên ở đây chỉ là đường dẫn kèm số đếm; dòng **Quy tắc chồng lấn** nói thẳng bản này chưa so sánh preset với nhau, thay vì để trống cho có.

Phần **Được đề xuất nghỉ** liệt kê đúng những gì lượt đo gần nhất đã thấy, mỗi hàng một dòng số đo: `RAM 1,4 GB · đo 14:32 · tiến trình chung 2 tab · nguồn: tiến trình Chrome`.

- Mỗi lượt đo giờ lưu thêm **dấu vết** cho từng ứng viên (ID tab, ID cửa sổ, ID tiến trình, các giá trị vượt ngưỡng, thời điểm, nguồn) trong `chrome.storage.session`, tối đa 20 hàng; nhiều hơn thì trang ghi "N tab khác cũng vượt ngưỡng nhưng không có trong danh sách" thay vì âm thầm cắt. Dấu vết **không chứa URL hay tiêu đề**, nên không có gì để rò rỉ và cũng không sống dai hơn phiên Chrome.
- Quyết định "có gì để gợi ý không" nằm trong `AutoDiscard.health()`: danh sách, nhãn ở thanh bên và lý do vì sao trang trống đều đọc từ một chỗ đó, nên ba nơi không thể nói khác nhau. Luật hết hạn hai chu kỳ không bị sao chép: ở mức Hỏi trước trang này chỉ đường sang *Cần chú ý*, ở mức Tự động nó báo là bản này chưa làm.
- **Chọn N tab để xem trước** chỉ đánh dấu ở *Tab đang mở* rồi để bản xem trước quen thuộc xin xác nhận; **Bỏ qua gợi ý này** chỉ ẩn danh sách của lượt đo hiện tại và **Hiện lại gợi ý** bỏ ẩn đó. Không có nút nào cho nghỉ ngay, và cả trang không gọi `chrome.tabs.discard`.

### Mức Tự động có đường nghỉ riêng, sau một lần xác nhận rủi ro (0.123)

Mục 15.4.3 chạy được: khi **Cách xử lý** là **Tự động**, mỗi chu kỳ đo dựng thêm một *kế hoạch hành động* theo đúng chính sách (bản đếm dùng cho gợi ý và thẻ nhắc vẫn tính như cũ), rồi `AutoDiscard.apply()` cho nghỉ từng tab theo kế hoạch đó qua `DiscardTools.request` — mỗi tab được đọc lại ngay trước khi nghỉ, nên tab đã đổi URL, đổi cửa sổ, bị ghim, đang được xem, đang phát âm thanh, ở chế độ ẩn danh, đã nghỉ, hoặc vừa được thêm vào danh sách bảo vệ đều bị bỏ qua và ghi lại là bị bỏ qua.

Những gì quanh nó:
- **một lần xác nhận, không phải mỗi lượt**: chọn **Tự động** rồi Lưu mở hộp "Bạn sắp để Tabspace tự cho nghỉ tab?" nêu số tab tối đa mỗi lượt, rằng số đo là của tiến trình renderer, và rằng tab đã nghỉ không có bản lưu để khôi phục. Xác nhận đó là khóa riêng `autoDiscardAck` trong `chrome.storage.local`, **không nằm trong cấu hình** — file sao lưu không mang theo sự đồng ý, và nhập file cũng không xóa được nó;
- `chrome.tabs.discard` không xuất hiện trong `background.js`: worker chỉ gọi `AutoDiscard.run` rồi `AutoDiscard.apply` và đưa `DiscardTools` vào như một phụ thuộc, nên không có đường nghỉ thứ hai;
- kết quả mỗi lượt ghi vào `autoDiscardAction` (số đã nghỉ, số bị bỏ qua, **số không xác nhận được**, từng tab một). Đây là mục duy nhất của tính năng nằm trong `storage.local`, vì nó mô tả một việc đã xảy ra chứ không phải một con số đo còn hạn sử dụng; trang *Sức khỏe tab* và tiêu đề khối cùng đọc một nhãn `AutoDiscard.actionLabel()` nên không thể nói khác nhau;
- một lượt không xác nhận được kết quả thì lượt sau **chờ 10 phút** thay vì thử lại mỗi phút; lượt không có gì để làm thì không bị chờ;
- không ghi được nhật ký trước khi hành động thì **từ chối nghỉ tab**, và không có hoàn tác: tab vẫn còn đó, tải lại là mất nội dung chưa lưu.

Chưa làm, và tài liệu không nói là đã làm: thông báo kết quả qua kênh hệ điều hành, cùng quyền `processes`. Chrome ổn định không cho extension số đo theo tab nên ở máy đó mức Tự động vẫn không bật được — `assertUsable` từ chối lưu khi không có nguồn đo, thay vì bật rồi im lặng.

### Lượt Tự động nhường giờ yên lặng và toàn màn hình (0.124)

15.3 ghi rõ khối này **không** có bản sao riêng của giờ yên lặng và "hoãn khi toàn màn hình" — nó dùng cơ chế chung của ứng dụng. Trước bản này điều đó chỉ đúng với lời nhắc, còn lượt nghỉ Tự động thì không: `AutoDiscard.apply()` có thể cho nghỉ tab giữa một buổi trình chiếu. Đây là chỗ tài liệu nói một đường, mã đi một đường, và câu trong khối Cài đặt vẫn cam kết "dùng theo thiết lập chung".

Bổ sung nằm ngay sau các cổng đồng hồ trong `apply()` và trước khi nhật ký được ghi:

- `Đang giờ yên lặng nên lượt Tự động nhường; chưa tab nào bị nghỉ.` — `ReminderTools.isQuiet(data.quietHours,now)`;
- `Đang toàn màn hình hoặc không xác định được trạng thái cửa sổ; chưa tab nào bị nghỉ.` — `ReminderTools.deferFullscreen(api,data.deferFullscreenNotifications)`, tức là cả trường hợp Chrome không cho biết trạng thái cửa sổ cũng **giữ**, giống cách `auto-close.js` đang chặn cứng.

Cả hai trả `status:'waiting'` **trước** khi ghi `autoDiscardAction`, nên một lượt bị giữ không để lại báo cáo giả và cũng không được tính là một lượt đã chạy; không có hoàn tác nào được hứa. Việc đo không bị ảnh hưởng: số đo vẫn lấy theo chu kỳ, **Đo lại ngay** vẫn chạy, vì giữ một hành động khác với giấu một con số. Điểm này có test riêng (`auto-discard-run.test.js`), kể cả hai trường hợp "không đọc được đồng hồ" và "không đọc được cửa sổ" — thà nhường còn hơn đoán là an toàn.

### Lượt Tự động nhường theo cách không đoán già (0.125)

0.124 đã để `apply()` hỏi giờ yên lặng và toàn màn hình, nhưng còn hai chỗ dựa vào điều may mắn: `if(deps.reminders)` nghĩa là **không có** checker thì cổng biến mất, còn `deferFullscreen(api,data.deferFullscreenNotifications)` nghĩa là một **tùy chọn về thông báo** có thể mở đường cho việc nghỉ tab. Bản này siết cả hai:

- phép kiểm tra gộp về một hàm `AutoDiscard.holdReason(api,deps,now,data)` (có trong exports, có test riêng). `apply()` gọi nó ngay trước tab đầu tiên và giữ nguyên hai câu trả lời của 0.124: `Đang giờ yên lặng nên lượt Tự động nhường; chưa tab nào bị nghỉ.` và `Đang toàn màn hình hoặc không xác định được trạng thái cửa sổ; chưa tab nào bị nghỉ.`;
- thiếu `deps.reminders`, hoặc checker không đủ hai hàm `isQuiet`/`deferFullscreen` → `Không có nguồn kiểm tra giờ yên lặng và toàn màn hình nên lượt Tự động nhường; chưa tab nào bị nghỉ.` Không còn đường nào để "quên mà vẫn chạy";
- toàn màn hình luôn được hỏi **thắt** (`deferFullscreen(api,true)`) cho đúng như `auto-close.js` vẫn làm: tắt "Trì hoãn khi phát hiện Chrome toàn màn hình" nay chỉ còn nghĩa là thông báo không phải chờ, chứ không phải là tab cứ việc bị nghỉ. Đường này không đọc `deferFullscreenNotifications` nữa;
- vòng đo **không** bị giữ, và có pin cho cả hai chiều: giờ yên lặng không làm số đo cũ đi, nên khi hết giờ yên lặng chu kỳ kế tiếp vẫn còn streak CPU và danh sách nóng, chứ không phải chờ ba chu kỳ đo lại từ đầu;
- hộp **Giới hạn và rủi ro** nêu ba trường hợp giữ lượt và nói rõ khối không có công tắc riêng; hộp **Giờ yên lặng & toàn màn hình** không còn nói mình chỉ ảnh hưởng thông báo, mà khai thêm vế về mức Tự động.

Không có quyền mới, không có hoàn tác, không thêm số đo nào rời khỏi máy.

### Khối có nút xin quyền đọc tiến trình, và đó là quyền tùy chọn (0.126)

15.1 ghi rõ API số đo theo tab chỉ có trên kênh Dev, còn quyền `processes` thì bản cũ không bao giờ xin — nghĩa là trên mọi máy Chrome ổn định, cả mục 15 chỉ là lý thuyết. Bản này thêm đường xin thật, xin đúng cách: `processes` nằm trong `optional_permissions`, **không** nằm trong `permissions`, nên lúc cài extension Chrome không được hứa thêm gì; chỉ khi bấm **Xin quyền đọc tiến trình** trong khối thì Chrome mới hỏi.

- một chỗ gọi duy nhất: `autoDiscardPermission()` trong `dashboard.js`, qua `chrome.permissions.request({permissions:['processes']})`; `background.js` không xin quyền nào;
- ba câu trả lời, không có im lặng: Chrome từ chối cả yêu cầu → "Chrome không cho phép xin quyền này trên bản Chrome đang chạy; vẫn chỉ còn đường cho nghỉ thủ công."; người dùng bấm từ chối → "Chưa có quyền đọc tiến trình, nên vẫn không có số đo theo tab."; được cấp mà `chrome.processes` vẫn không tồn tại (kênh ổn định) → "Không đo được tài nguyên trên Chrome này. Quyền đọc tiến trình đã bật nhưng Chrome này không có API số đo theo tab." `AutoDiscard.capability(api,granted)` tách hai sự kiện "được cấp" và "đo được", vì gộp chúng lại là hứa một con số trình duyệt không đưa;
- nút biến mất khi đã có số đo thật, hoặc khi máy này vừa trả lời "có" ngay trong trang hiện tại; bị từ chối thì nút còn đó để bấm lại. Cờ `autoDiscardPermissionGranted` chỉ là chuyện của trang — không có gì được ghi xuống `storage.local`, vì sự đồng ý là của Chrome chứ không phải của file cấu hình;
- `assertUsable` vẫn từ chối lưu khi `chrome.processes` không tồn tại, kể cả khi quyền đã bật: bật một tính năng không có số đo thì vẫn bị chặn như cũ.

Câu chữ "Tabspace vẫn chưa xin quyền đọc tiến trình" trong khối và trong hộp **Giới hạn và rủi ro** đã thay bằng mô tả đúng: có nút xin trong khối, và Chrome kênh ổn định không cấp quyền đó.

Chưa làm: `processes` không phải quyền mặc định (chủ đích) và không xin lúc cài; thông báo kết quả lượt Tự động qua kênh hệ điều hành vẫn chưa có.

### Lượt Tự động có kết quả được ghi vào kênh riêng của ứng dụng (0.127)

15.4.3 hứa "báo theo kênh đã bật" cho mức Tự động. Từ bản này lời hứa đó đi qua đúng hai kênh mà ứng dụng đã có, không mở kênh mới, không thêm công tắc:

- **nhật ký sự kiện** — `AutoDiscard.resultEvent(report)` sinh `{id:'discard:<id lượt>',kind:'result',at,status}` với `status` chỉ nằm trong bảng từ vựng mà `NotificationHistory` nhận (`complete` / `blocked` / `uncertain`), rồi `background.js` đưa vào `NotificationHistory.record`. Việc dịch từ `report.status` sang bảng đó nằm một chỗ duy nhất: `complete` → complete, `partial`/`uncertain`/`running` → uncertain, `journalFailed` → blocked, `empty` → **không có sự kiện** (một lượt không nghỉ tab nào không phải một kết quả để báo);
- **bản tin ngay trên trang** — `deliverPageNotice('results')`, tức là dùng luôn bộ lọc origin, giờ yên lặng, toàn màn hình, cooldown 60 giây và nút tạm dừng mà kết quả tự động đóng vẫn dùng.

Những gì bản này không làm, và tài liệu nói đúng như vậy: **không** phát thông báo hệ điều hành cho lượt tự nghỉ (`notifications.create` vẫn chỉ có một chỗ, phục vụ lời nhắc), **không** có hàng đợi riêng kiểu `autoCloseNoticePending`, và **không** tự thử lại khi một kết quả còn mơ hồ. Hộp **Giới hạn và rủi ro** nêu thẳng cả ba.

Hai chi tiết nhỏ nhưng là thứ khiến nó đáng tin: id sự kiện suy ra từ chính lượt đo (`discard:` + id lượt) nên một worker gửi lại cũng không nhân đôi nhật ký; và nếu `NotificationHistory.record` ném lỗi, worker báo đúng một lần `console.error`, bản tin trên trang vẫn đi, lịch rehearsal vẫn chạy.
