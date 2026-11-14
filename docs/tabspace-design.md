# Tabspace — đặc tả thiết kế sản phẩm

**Trạng thái:** đề xuất thiết kế, chưa triển khai.  
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

Gợi ý tab trùng, lâu không truy cập (chỉ khi có dữ liệu), đã lưu nhưng còn mở, quy tắc chồng lấn. Mỗi gợi ý có lý do, xem trước, bỏ qua/tắt; không tự coi tab cũ là rác. Không dùng ước lượng RAM như số đo.

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

**Giai đoạn 3 — mở rộng:** workspace, nhóm thông minh, sức khỏe tab, so sánh phiên, tự động hóa nâng cao. Đồng bộ, tìm nội dung trang, AI đề xuất là nghiên cứu tương lai, không phải cam kết.

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

## 12. Các điểm cần xác minh trước hoặc trong triển khai

1. **Chrome API và quyền:** phiên bản Chrome hỗ trợ, khả năng truy xuất metadata/tín hiệu, màu nhóm native, hạn chế URL, ẩn danh và hành vi discard/khôi phục thực tế. Không suy ra quyền hoặc khả năng từ bản thiết kế.
2. **Tính bền vững của lưu trữ và điều phối MV3:** kiểm thử worker bị dừng giữa lưu và đóng; định nghĩa lưu thành công theo cơ chế lưu thực tế và khôi phục trạng thái không chắc chắn.
3. **Thời gian truy cập và miễn xử lý:** nguồn dữ liệu khả dụng, giới hạn sau restart, đồng hồ thay đổi và trường hợp tab có cùng URL. Nếu không xác định tin cậy, chọn bỏ qua tự động thay vì đoán.
4. **Lịch chạy và thông báo:** kiểm thử alarms, trạng thái Chrome đóng, quyền thông báo và hành vi nhắc lại trên phiên bản Chrome mục tiêu.
5. **Phạm vi workspace và snapshot:** xác định chính xác metadata nào có thể tái tạo; thiết kế UI thể hiện sai lệch khi khôi phục.
6. **Quy mô:** đo hiệu năng tìm kiếm, storage, xuất/nhập và UI với hàng nghìn bản ghi; chọn giới hạn phù hợp sau kiểm thử, không giả định con số.
7. **Chuẩn URL:** kiểm thử IDN, cổng mặc định, encoding, redirect, fragment và URL đặc biệt; mô tả điều kiện khớp trong UI trước khi bật tự động.
8. **Thời hạn lưu/khôi phục:** chọn mặc định sau thử nghiệm; phải công bố giới hạn và cho cấu hình thay vì hứa hoàn tác vô hạn.

## 13. Tham khảo định hướng

Khảo sát ban đầu chỉ mang tính đại diện, không phải đánh giá mọi sản phẩm hay xác nhận tất cả tính năng hiện tại của đối thủ: [so sánh OneTab, Workona, Toby, Session Buddy và Tabli](https://botab.net/blog/best-chrome-edge-tab-managers-2026); [ví dụ thực tế về giới hạn tab discard và khôi phục](https://github.com/mahant3595/tabUnloader-ChromeExtension). Cần kiểm tra tài liệu Chrome chính thức và thử nghiệm API khi triển khai.

## 14. Đặc tả bổ sung: giao diện, thông báo, âm thanh và toàn màn hình

### 14.1. Mức độ hoàn thiện thiết kế giao diện

Các phần trên là định hướng sản phẩm và bố cục, **chưa phải bộ mockup, prototype hay design system hoàn chỉnh**. Trước khi triển khai giao diện cần thiết kế và duyệt thêm màn hình thực tế, trạng thái và khả năng tiếp cận; không coi sơ đồ chữ là thiết kế visual cuối cùng.

- **Hệ thống thiết kế:** định nghĩa token cho màu nền/chữ/viền/trạng thái, spacing, typography, bán kính, bóng, icon, focus và độ tương phản trong sáng/tối. Màu nhóm tùy chỉnh phải có cách hiển thị đọc được trên cả hai nền; không phụ thuộc màu để truyền tải trạng thái.
- **Thành phần thống nhất:** nút chính/phụ/nguy hiểm, trường nhập, bộ lọc, checkbox, menu, dialog, toast, banner, danh sách, tab, bảng tiến trình và trạng thái lỗi/rỗng. Cùng một hành động phải có tên, icon và hậu quả nhất quán ở popup, trang quản lý và command palette.
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
