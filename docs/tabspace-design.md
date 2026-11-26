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

## 12. Bổ sung đặc tả — nghỉ tự động theo tài nguyên và thao tác nhanh (chưa triển khai)

Phần này là yêu cầu thiết kế và tiêu chí triển khai, **không mô tả tính năng đã có**. Ưu tiên thao tác thường dùng ít bước, nhưng không đánh đổi sự rõ ràng về phạm vi, dữ liệu và rủi ro. Các đề xuất mặc định dưới đây có thể điều chỉnh sau kiểm thử; không đưa thêm công tắc chỉ để phơi bày chi tiết kỹ thuật.

### 12.1 Nghỉ tự động theo từng loại tài nguyên

**Mục đích:** đề xuất hoặc cho nghỉ những tab thực sự có dấu hiệu tiêu hao cao, thay vì chỉ dựa vào tuổi tab. Cho phép chọn riêng **RAM**, **CPU**, và các loại khác nếu sau này có nguồn đo phù hợp; không gộp tất cả thành một điểm duy nhất hoặc tự bật thêm tài nguyên. Bật tính năng là opt-in; mặc định **tắt**, khi bật lần đầu chọn **Hỏi trước**. Tab nghỉ bằng cơ chế discard của Chrome, không phải đóng; trang có thể tải lại và mất dữ liệu chưa lưu. Không hứa giải phóng được một lượng RAM/CPU cụ thể.

**Giới hạn khả thi là điều kiện bắt buộc, không phải chi tiết giấu trong Nâng cao:** cần kiểm chứng nguồn dữ liệu trên phiên bản/kênh Chrome, Manifest V3 và môi trường hỗ trợ trước khi triển khai. [API `chrome.system.memory`](https://developer.chrome.com/docs/extensions/reference/api/system/memory) cung cấp tổng và RAM khả dụng của **hệ thống**, không phải RAM từng tab. [API `chrome.processes`](https://developer.chrome.com/docs/extensions/mv2/reference/processes) mô tả dữ liệu tiến trình và ghi nhận đo bộ nhớ tốn thêm CPU; tài liệu được dẫn thuộc MV2, không chứng minh API khả dụng cho extension MV3 trên Chrome ổn định. Tiến trình có thể được nhiều tab chia sẻ hoặc một tab dùng nhiều tiến trình; dữ liệu tiến trình không mặc nhiên là số đo riêng chính xác của tab. Không quảng cáo đã đo RAM/CPU từng tab, không dùng tên miền, tuổi tab hay con số ngẫu nhiên làm số đo, không kết luận tab tiêu hao cao khi không có nguồn đủ tin cậy. Không yêu cầu người dùng chuyển kênh Chrome hoặc cài phần mềm ngoài một cách mặc định.

- Trước khi bật, giao diện kiểm tra khả năng từng loại: **Khả dụng**, **Không hỗ trợ/quyền chưa cấp**, hoặc **Chưa đủ dữ liệu**; giải thích phạm vi số đo, quyền, thời gian mẫu, độ trễ và sai số khi biết. Tùy chọn không hỗ trợ vẫn hiện nhưng bị vô hiệu hóa kèm lý do, không làm như đang hoạt động. Một loại đang chạy mà mất dữ liệu thì báo dừng điều kiện đó; không tự chuyển sang tiêu chí khác hoặc dùng RAM hệ thống để gán mức RAM cho từng tab.
- Nếu chỉ có tín hiệu tổng hệ thống, có thể thiết kế riêng điều kiện **máy thiếu RAM** để kích hoạt gợi ý dựa trên các tín hiệu tab khác, ghi rõ đó **không** phải phát hiện tab dùng RAM cao; tính năng này không thay thế tiêu chí RAM/tab và cần được người dùng chọn riêng. Tín hiệu tuổi/trạng thái tab có thể giúp lọc ứng viên, nhưng không được dán nhãn RAM/CPU hay mặc định kích hoạt khi người dùng chỉ chọn tài nguyên.
- Nếu về sau có nguồn đo chia sẻ theo tiến trình, chỉ sử dụng để tự nghỉ khi chứng minh được quy tắc quy thuộc tab đủ tin cậy; nếu không, chỉ hiển thị mức tiến trình/nhóm và đề xuất kiểm tra thủ công, không tự nghỉ mọi tab liên quan. Thông tin không chắc, thiếu, cũ hoặc bị từ chối quyền là **không xác định**, không coi bằng 0 hoặc bằng mức cao. Tránh tự mở các tab đã nghỉ để đo.

**Thiết lập gọn tại Cài đặt → Tự động hóa → Cho tab nghỉ**, đặt trong một thẻ có thể thu gọn/mở rộng; thẻ đóng hiển thị tóm tắt như “Tắt” hoặc “Hỏi trước · RAM ≥ … · CPU ≥ …”, có nút bật/tắt và trạng thái khả dụng. Mở thẻ mới thấy:

1. **Loại tài nguyên**: checkbox RAM, CPU, sau này thêm loại đo được; mỗi loại có nhãn nguồn/phạm vi. Chỉ cấu hình những loại đã chọn.
2. **Mức tiêu hao cao**: mỗi loại có chế độ **Tự xác định** hoặc **Ngưỡng riêng**, không dùng chung ngưỡng cho RAM và CPU. Ngưỡng riêng hiển thị đơn vị rõ (ví dụ MB cho RAM, % CPU kèm định nghĩa theo lõi hay toàn máy từ nguồn đo); kiểm tra phạm vi, không suy đoán đơn vị. Nút khôi phục đề xuất; không tự áp giá trị ví dụ như số liệu thực tế.
3. **Khi phát hiện**: radio **Hỏi trước** (mặc định) hoặc **Tự cho nghỉ không hỏi**. Tự động chỉ sau opt-in và xác nhận một lần giải thích mất trạng thái, giới hạn API và các bảo vệ; việc đổi về hỏi/tắt có hiệu lực ngay. Hỏi trước tạo gợi ý trong Cần chú ý, xem danh sách và chọn; không phản hồi/không thấy thông báo thì không nghỉ, không có đếm ngược tự đồng ý.
4. **Phạm vi**: cửa sổ hiện tại hoặc mọi cửa sổ thường; với tác vụ nền không có khái niệm cửa sổ hiện tại ổn định thì cấu hình phải xác định rõ, không chọn lại ngầm theo cửa sổ focus tại lúc chạy. Mặc định đề xuất mọi cửa sổ thường nhưng chỉ tab nền đủ điều kiện. Tùy chỉnh ngoại lệ website dùng bảo vệ chung, không tạo danh sách trùng lặp.
5. Trong **Tùy chọn nâng cao** thu gọn: chọn khớp **ít nhất một** (OR, mặc định) hoặc **tất cả** (AND) trong các loại đã chọn; khoảng đo/tính bền vững, thời gian tab không hoạt động tối thiểu và giới hạn số tab mỗi lượt. OR chỉ coi khớp khi có ít nhất một loại được đo tin cậy và vượt ngưỡng; thiếu loại khác được ghi rõ. AND chỉ khớp khi tất cả loại có dữ liệu hợp lệ và vượt ngưỡng. Không có loại khả dụng hoặc không có loại được chọn thì không thể bật quy tắc. Không cho giới hạn/bảo vệ rủi ro bị vô hiệu hóa chỉ vì bật một chạm.

**Tự xác định** là cách chọn ngưỡng, không phải tự cấp quyền hay tự bật tự động nghỉ. Khi có nguồn đo hợp lệ, thiết kế đề xuất dựa trên phân bố mẫu gần đây của *chính loại tài nguyên đó*, có tối thiểu mẫu/tab, loại mẫu cũ, ngưỡng sàn và trần; công bố khoảng quan sát và tiêu chí thực tế khi triển khai, có khả năng hiệu chỉnh. Nếu chưa đủ dữ liệu hoặc phân bố không đủ phân biệt, hiện “Đang học/chưa đủ dữ liệu”, không phát hiện cao và không tự nghỉ. Không tự thay đổi ngưỡng riêng của người dùng. Ngưỡng tự động phải ổn định qua nhiều mẫu, có hysteresis/cooldown để tránh nhấp nháy, đo có giới hạn tần suất/chi phí; service worker MV3 có thể ngủ, nên không cam kết theo dõi liên tục hay xử lý chính xác theo thời gian thực.

**Quy trình an toàn:** dựa trên tín hiệu đủ mới và vượt ngưỡng đủ lâu, lọc tab; bỏ qua active ở mọi cửa sổ, ghim, đang phát âm thanh, đang nghỉ, ẩn danh, URL không được hỗ trợ, website được bảo vệ, tab mới hoạt động/khôi phục trong thời gian miễn và trạng thái không xác định. Tái kiểm tra tab, trạng thái bảo vệ, ngưỡng và độ mới phép đo ngay trước khi yêu cầu Chrome; quyền/trạng thái lỗi thì bỏ qua hoặc dừng an toàn. Một tab đã đổi URL/cửa sổ/trạng thái sau khi đề xuất phải đánh giá lại, không hành động theo ID cũ. Nếu kết quả Chrome không rõ, dừng xử lý tiếp và báo kiểm tra trước khi thử lại. Tôn trọng tạm dừng tự động hóa chung và khóa điều phối; không tự chạy bù sau gián đoạn. Bảo vệ không chứng minh an toàn cho form, cuộc gọi, upload hay tác vụ nền; cho phép bảo vệ website và tab, giải thích rủi ro trước opt-in.

**Gợi ý và kết quả:** một mục gộp theo đợt thay vì thông báo mỗi tab, liệt kê tab, từng loại vượt ngưỡng, số đo/đơn vị/nguồn và thời điểm đo, lý do bỏ qua; không lưu lịch sử đo dài hạn mặc định. Xem trước cho bỏ chọn từng tab và chọn theo cửa sổ; kiểm tra lại trước khi nghỉ. Tự động không hỏi vẫn có kết quả gộp thành công/bỏ qua/lỗi/không rõ, kèm lối xem tab và tạm dừng. Không ghi URL hoặc số đo nhạy cảm vào nhật ký thông báo chung nếu chưa có chính sách lưu/opt-in riêng. Quyền cảm biến là tùy chọn và giải thích trước khi xin; thu hồi quyền thì dừng phần phụ thuộc. Nhập sao lưu cấu hình tự động phải mặc định tắt/đòi xác nhận lại, không cấp quyền hay tự chạy; thống nhất quy tắc này trong thiết kế nhập/xuất khi triển khai.

### 12.2 Thao tác nhanh cho nhiều tab — không hỏi lặp khi người dùng chọn

Đặt một cụm **Thao tác nhanh** trong popup và lối tương đương tại trang Tab đang mở; nút chính dễ thấy, các biến thể nằm trong menu ngắn thay vì thêm nhiều nút ngang. Phím và nhãn dễ phân biệt “Lưu bản sao” với “Lưu & đóng” và “Cho nghỉ”. Popup hiện tab gần đây vẫn là danh sách riêng; các lệnh “tất cả” phải truy vấn toàn bộ phạm vi Chrome đã chọn, **không chỉ các dòng đang hiển thị**, và báo số lượng/phạm vi rõ ràng.

**Chọn nguồn:** mặc định cửa sổ chứa tab được người dùng gọi lệnh; tùy chọn chuyển sang mọi cửa sổ thường, hoặc dùng tập checkbox hiện có (kể cả chọn ẩn, hiển thị số ẩn). Cung cấp hai lựa chọn rõ “Tất cả tab trong phạm vi” và “Các tab khác, trừ tab hiện tại”; có thể chọn lại từng tab trong xem trước. Với nhiều cửa sổ, “tab hiện tại” là tab đang hoạt động trong cửa sổ phát lệnh, được chụp tại lúc khởi chạy; không đồng nghĩa loại mọi tab active ở các cửa sổ khác. Nếu không xác định chắc tab/cửa sổ phát lệnh, yêu cầu chọn rõ hoặc dừng, không đoán từ trang quản lý của extension. Đối với nghỉ, bảo vệ active ở mọi cửa sổ vẫn có hiệu lực và được báo là bỏ qua, kể cả khi người dùng chọn “tất cả”. Tab đóng/đổi trạng thái khi lệnh chạy được kiểm tra lại; tab mới sau thời điểm chụp không tự thêm.

**Lưu bản sao nhanh:**
- Chọn **Hộp để sau**, **nhóm đã lưu** gần đây/yêu thích, hoặc **Tạo nhóm mới…** và nhập tên (màu/icon có mặc định, không bắt mở form dài). Chọn “trừ tab hiện tại” hoặc “gồm tab hiện tại” trước khi chạy. Lưu URL/metadata hỗ trợ, giữ nguyên mọi tab đang mở, không nghỉ hay đóng; tab Chrome nội bộ, ẩn danh và URL không hỗ trợ được bỏ qua có giải thích. URL trùng là các bản sao riêng trừ khi người dùng chủ động chọn chính sách khác; không tự gộp/xóa.
- **Preset** là bộ quy tắc và đích, không phải thùng chứa riêng. Khi chọn preset, UI phải nói “Lưu vào nhóm đích của [tên preset]” và cho xem/đổi đích nếu hợp lệ. Lệnh lưu bản sao không chạy lịch, không áp dụng hành động tự động đóng của preset; nếu có tùy chọn áp dụng bộ lọc preset thì phải nêu rõ và hiển thị số được lọc. Đích thiếu/đã xóa thì dừng, yêu cầu chọn đích, không tự tạo hoặc chuyển sang Hộp để sau.
- Sau khi chọn nhanh nguồn và đích, tùy chọn **Lưu ngay, không hỏi lại** dành riêng cho lưu bản sao; mặc định vẫn xem trước theo chính sách hiện hành, có thể bật và đổi lại trong Cài đặt thao tác nhanh. Cho nút “Xem trước” ngay cạnh lệnh khi cần. Tạo nhóm mới yêu cầu nhập tên, nhưng không cần hộp xác nhận thứ hai nếu đã bật lưu ngay. Thông báo sau lưu cho biết số đã lưu/bỏ qua, đích và nút xem; hoàn tác chỉ đề xuất nếu có thể xác định chính xác các bản ghi được tạo, kiểm tra chúng chưa bị sửa và hoàn tác không xóa dữ liệu khác. Không hứa hoàn tác nguyên tử.

**Nghỉ các tab còn lại:** lệnh rõ tên **Cho nghỉ các tab khác…**, mặc định phạm vi cửa sổ phát lệnh và luôn giữ tab hiện tại, đồng thời bảo vệ các tab active ở cửa sổ khác khi chọn nhiều cửa sổ. Không lưu hoặc đóng các tab. Bản xem trước mặc định hiển thị tổng ứng viên/bị bảo vệ, cảnh báo trang có thể tải lại và mất dữ liệu chưa lưu; có thể chọn/bỏ tab. Trong Cài đặt thao tác nhanh có tùy chọn riêng **Cho nghỉ ngay không hỏi** (mặc định tắt), bật sau cảnh báo và xác nhận một lần, có thể tắt bất kỳ lúc nào; không dùng tùy chọn lưu ngay để tự cho phép nghỉ. Một chạm vẫn kiểm tra bảo vệ và trạng thái trước từng tab, không bỏ qua vì người dùng đã chọn; hiển thị kết quả và tab bị bỏ qua. Không gọi nghỉ lại các tab vừa có kết quả không rõ. Tab được nghỉ có thể được Chrome tải lại khi kích hoạt, không đảm bảo phục hồi form hay tác vụ nền.

**Tình huống minh họa:** (1) Trong cửa sổ làm việc, “Lưu tab khác → Tạo nhóm → Nghiên cứu” tạo bản sao cho các tab đủ điều kiện, giữ tab hiện tại và các tab khác mở. (2) “Lưu tất cả → Hộp để sau” gồm cả tab hiện tại, không đóng/nghỉ; nếu đã bật lưu ngay thì không hiện thêm xác nhận. (3) “Cho nghỉ tab khác” giữ tab hiện tại, bỏ qua các tab được bảo vệ; nếu đã bật nghỉ ngay thì thực hiện không hỏi lại. Chuyển sang mọi cửa sổ phải hiển thị số tab và phạm vi trước khi bấm lệnh cuối, không âm thầm mở rộng phạm vi vì lựa chọn lưu từ lần trước.

**Xung đột và giới hạn:** thao tác thủ công dùng khóa dữ liệu chung; xác định nguồn/đích và kiểm tra lại trước ghi hoặc nghỉ. Nếu lưu không xác nhận được, không tự thử lại và yêu cầu kiểm tra đích trước khi thử; nếu dữ liệu nhóm thay đổi hoặc đích mất, dừng. Khóa chỉ phối hợp các thành phần Tabspace, không bảo đảm nguyên tử với Chrome/extension khác. Thông báo kết quả không khẳng định tác vụ đã hoàn tất khi API trả lỗi không rõ. Với lựa chọn rất lớn, UI phải phản hồi theo đợt và công bố giới hạn thực tế, không âm thầm cắt danh sách.

### 12.3 Tiêu chí nghiệm thu và lộ trình

- Kiểm chứng khả năng đo và quyền trên Chrome stable/MV3 trước khi hứa hỗ trợ từng loại; test cả không hỗ trợ, mất quyền, dữ liệu cũ/thiếu, tiến trình chia sẻ, CPU/RAM độc lập, OR/AND, không đủ mẫu tự động và chi phí đo. Không có nguồn đủ tin cậy thì giao diện báo không khả dụng và không tự nghỉ theo loại đó.
- Test tắt/hỏi/tự động, tắt trong lúc chạy, thay đổi ngưỡng/chính sách, giới hạn theo lượt, bảo vệ tab active/ghim/âm thanh/site, thời gian miễn, service worker ngừng, Chrome từ chối hoặc kết quả không rõ, dữ liệu trang chưa lưu; không phản hồi lời nhắc không tạo hành động.
- Test lưu và nghỉ với tab hiện tại, nhiều cửa sổ, focus thay đổi, lựa chọn ẩn, tab mới/biến mất/đổi URL, đích bị xóa, preset có hành động đóng, URL trùng, lỗi ghi mơ hồ và tải lại UI lỗi. Kiểm tra rằng lưu nhanh không bao giờ đóng/nghỉ, nghỉ nhanh không tạo bản lưu/đóng, các chế độ không hỏi được bật riêng và có thể thu hồi.
- Kiểm thử thực tế popup, bàn phím/trình đọc màn hình, cửa sổ hẹp và Chrome với tab đang hoạt động, form chưa lưu, media/call, nhóm và hàng trăm tab; đo độ trễ/tải của chính tính năng. Lộ trình: trước tiên thiết kế/kiểm chứng khả năng; tiếp theo thao tác lưu nhanh và nghỉ thủ công có bảo vệ; sau đó mới đo tài nguyên và hỏi trước nếu khả thi; chỉ cuối cùng mới cho phép tự động không hỏi sau đánh giá an toàn. Không xem đặc tả này là cam kết chức năng hiện đã triển khai.

### Thao tác nhanh nhiều tab (0.114)
Trong popup mở **Thao tác nhanh nhiều tab**: chọn cửa sổ hiện tại hoặc mọi cửa sổ thường, lưu bản sao tất cả hoặc trừ tab hiện tại vào Hộp để sau, nhóm hiện có, nhóm mới hoặc nhóm đích của preset. Chọn preset chỉ lấy nhóm đích, không chạy quy tắc preset, không tự đóng/nghỉ; bản sao trùng URL vẫn được lưu. Nút **Cho tab khác nghỉ** luôn loại tab hiện tại và bỏ qua tab active ở các cửa sổ khác, tab ghim, âm thanh, đã nghỉ và website được bảo vệ. Trang nghỉ có thể tải lại và mất nội dung chưa lưu hoặc tác vụ nền.

Mặc định hỏi trước bằng hộp xác nhận tổng số; trong phần thu gọn **Tùy chọn thao tác nhanh**, bật riêng lưu ngay hoặc nghỉ ngay nếu muốn bỏ bước hỏi. Đổi mỗi lựa chọn cần xác nhận rủi ro. Mỗi lượt tối đa 100 tab web; nếu vượt giới hạn không xử lý một phần, hãy chọn từng nhóm tab. Không phụ thuộc số tab hiển thị trong popup; tab ẩn danh không xử lý. Giữ popup mở đến khi xong; nếu đóng popup hoặc kết quả không rõ, kiểm tra nhóm đích/Chrome trước khi thử lại. Không đảm bảo nguyên tử với Chrome hoặc extension khác.

**Tự động nghỉ theo RAM/CPU chưa triển khai**: không có nguồn đo riêng từng tab đã được kiểm chứng cho bản extension này, nên mục giải thích trong popup chỉ báo chưa khả dụng, không giả số liệu và không tự nghỉ. Cần kiểm chứng API, quyền và bảo vệ trước khi hỗ trợ.

### Xem trước thao tác nhanh và nhiều tab hơn (0.115)
Thao tác nhanh mặc định mở danh sách xem trước: chọn/bỏ từng tab hoặc tất cả, tab không đủ điều kiện cho nghỉ bị vô hiệu hóa kèm lý do. Lưu và nghỉ kiểm tra lại ngay trước khi thực hiện. Người đã bật tùy chọn riêng lưu ngay/nghỉ ngay vẫn bỏ qua xem trước; nếu thiết lập thay đổi từ nơi khác, đóng và mở lại popup trước khi dùng. Phần thao tác nhanh hỗ trợ tối đa **500 tab web/lượt**, không âm thầm cắt danh sách; lựa chọn checkbox trong danh sách popup vẫn giới hạn 100. Giữ popup mở trong lúc xử lý, đặc biệt với nhiều tab. Đây là các hành động thủ công; tự động nghỉ theo RAM/CPU vẫn chưa khả dụng.

### Chọn nhanh trong trang quản lý và rà an toàn (0.116)
Trong **Tab đang mở**, nút **Chọn nhanh nhiều tab…** chọn tab web ở cửa sổ chứa trang quản lý hoặc mọi cửa sổ thường, không phụ thuộc tìm kiếm/lọc. Có thể chỉ định rõ một tab không chọn; vì trang quản lý chính là tab hiện tại, Tabspace không đoán tab bạn muốn giữ. Lựa chọn mới thay thế lựa chọn cũ nhưng chưa lưu, đóng hay nghỉ; tiếp tục bằng các nút trên thanh lựa chọn. Tab thay đổi URL/cửa sổ hoặc đang chuyển trang bị bỏ qua, tab giữ lại thay đổi thì dừng. Tab mới sau lúc mở hộp không được tự thêm.

Nghỉ nhiều tab từ trang quản lý kiểm tra lại trạng thái và bảo vệ, dừng lượt khi không đọc được bảo vệ hoặc không rõ kết quả, giữ lựa chọn chưa xử lý và hiển thị kết quả ngay cả khi làm mới thất bại; tối đa 500 tab đủ điều kiện/lượt. Lưu từ trang quản lý dừng nếu thông tin nhóm đích thay đổi, bỏ qua tab đang chuyển sang URL khác. Chrome hoặc extension khác vẫn có thể thay đổi trạng thái đồng thời; nếu không chắc kết quả hãy kiểm tra Chrome/nhóm đích trước khi thử lại. Chưa kiểm thử trên Chrome thực tế.

### Lưu hoặc cho nghỉ, trừ các tab đã chọn (0.117)
Trong popup, đánh dấu các tab muốn giữ lại; tìm kiếm và thu gọn không xóa lựa chọn. Mở **Thao tác nhanh nhiều tab**, chọn phạm vi rồi chọn **Tất cả, trừ các tab đã chọn** riêng cho nguồn lưu hoặc nguồn cho nghỉ. Cũng có thể chọn **Chỉ các tab đã chọn**. Lưu tạo bản sao vào đích và không đóng/nghỉ; khi cho nghỉ, tab đang xem ở mọi cửa sổ, tab ghim, có âm thanh và website được bảo vệ vẫn được giữ dù không đánh dấu. Số tab chọn gồm cả mục đang ẩn, hiển thị trong popup; nếu chưa chọn hoặc một tab đã chọn thay đổi/biến mất, thao tác dừng thay vì hiểu là xử lý tất cả.

Trong trang quản lý **Tab đang mở → Chọn nhanh nhiều tab…**, nguồn tương tự gồm tất cả, chỉ các tab đã chọn trước đó hoặc trừ các tab đó, kể cả lựa chọn ẩn; thao tác này thay thế lựa chọn hiện tại nhưng chưa tự lưu/nghỉ. Sau đó dùng nút lưu hoặc cho nghỉ. Kiểm tra phạm vi cửa sổ, xem trước và kết quả; tùy chọn thao tác ngay vẫn áp dụng riêng cho từng hành động trong popup. Giới hạn lựa chọn popup 100 tab, thao tác nhanh tối đa 500 tab web; dữ liệu trang chưa lưu có thể mất khi nghỉ, và Chrome có thể thay đổi đồng thời.

### Làm mới giao diện (0.118)
Trang quản lý và popup dùng bảng màu xanh trầm, hệ thống nút và bề mặt thống nhất hơn; thông tin tổng quan gọn để dành chỗ cho danh sách tab, bộ lọc và thao tác. Các trạng thái sáng/tối, mật độ và giảm chuyển động vẫn dùng lựa chọn đã lưu. Thêm lối tắt bàn phím đến nội dung chính; bố cục hẹp giữ điều hướng có tên và cuộn ngang. Không thay đổi dữ liệu hay hành vi lưu, đóng, nghỉ.

Tham khảo các nguyên tắc từ [taste-skill](https://github.com/Leonxlnx/taste-skill/blob/main/skills/taste-skill/SKILL.md), điều chỉnh cho giao diện công cụ thay vì áp dụng cấu trúc trang quảng bá. Đã xem giao diện bằng Chromium headless với dữ liệu và Chrome API giả lập ở kích thước rộng/hẹp, sáng/tối; điều này không thay thế kiểm thử extension trên Chrome thực tế.

### Sửa nền popup khi cuộn (0.118.1)
Đồng bộ nền của trang popup, vùng nội dung và danh sách tab trong cả chế độ sáng và tối; chỉnh màu thanh cuộn theo nền. Đã kiểm tra màu thực tế khi cuộn bằng Chromium headless với Chrome API giả lập; vẫn cần kiểm tra bản extension trong Chrome.

### Thao tác nhanh gọn hơn (0.119)
Trong popup → **Thao tác nhanh nhiều tab**, chọn **Lưu bản sao** hoặc **Cho nghỉ** để chỉ hiện các trường cần cho việc đó; phạm vi và các lựa chọn của từng hành động vẫn độc lập. Chế độ không hỏi vẫn tách riêng và mặc định xem trước. Khi đích lưu được chọn bị đổi tên, thay đổi hoặc biến mất lúc làm mới danh sách, cần chọn lại thay vì tự chuyển sang đích khác.

Dưới danh sách tab, **Chọn thêm…** có thể chọn nhanh toàn bộ tab web trong cửa sổ hiện tại hoặc mọi cửa sổ thường, kể cả tab không nằm trong phần đang hiển thị. Giữ các lựa chọn trước đó và báo tổng số; nếu vượt 100 lựa chọn hoặc gặp tab đã chọn thay đổi, không thay đổi lựa chọn. Phần thao tác nhanh vẫn xử lý tối đa 500 tab web/lượt nếu chọn nguồn toàn bộ/trừ tab, không cần đánh dấu từng tab. Không tự lưu, đóng hay cho nghỉ khi dùng lệnh chọn. Tab ẩn danh, trang không phải web và tab đang chuyển URL bị bỏ qua.
