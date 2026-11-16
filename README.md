# Tabspace

Thiết kế: [docs/tabspace-design.md](docs/tabspace-design.md). Bản thử nghiệm Chrome extension nằm trong `extension/`; hướng dẫn cài đặt và giới hạn tại [extension/HUONG-DAN.md](extension/HUONG-DAN.md).

Đóng gói: `cd extension && zip -r ../tabspace-extension.zip .`.

### Âm báo thử nghiệm (0.84)
Trong **Cài đặt & sao lưu → Âm báo**, có thể bật riêng âm lời nhắc preset mới, kết quả đóng tự động thành công hoặc bị chặn/không rõ, chọn hai âm có sẵn hoặc file âm cục bộ (tối đa 1 MB, 5 giây), chỉnh âm lượng và nghe thử. Mặc định tắt. Chỉ cố phát khi trang quản lý đang mở và chứng kiến lượt chuyển trạng thái; không mở trang phát âm, không phát bù khi trang đóng hoặc âm bị bỏ qua. Chrome có thể chặn phát tự động ngay cả khi nghe thử được. Giờ yên lặng, tùy chọn toàn màn hình và tạm dừng tự động hóa có hiệu lực; âm bị bỏ qua, không phát dồn. Âm tùy chỉnh và thiết lập âm lưu cục bộ; chỉ đưa vào sao lưu nếu chọn khi xuất, và có thể xóa trong cài đặt.

### Thông báo trên website thử nghiệm (0.85)
Tại **Cài đặt & sao lưu → Thông báo trên website**, có thể bật riêng lời nhắc mới và kết quả đóng tự động, rồi thêm từng website và cho phép Chrome truy cập. Mặc định tắt; Chrome có thể cấp quyền đọc/thay đổi dữ liệu trên mọi đường dẫn và cổng của tên miền đã chọn. Tabspace chỉ cố hiển thị đúng giao thức, tên miền và cổng đã chọn, trên tab thường đang hoạt động trong cửa sổ Chrome đang tập trung. Thông báo chỉ có câu chữ chung, website có thể quan sát, tự biến mất sau 10 giây, có nút đóng, không thực hiện thao tác đóng tab. Không bảo đảm hoạt động trên mọi trang, trang hạn chế hoặc toàn màn hình. Trong giờ yên lặng, toàn màn hình, tạm dừng tự động, hoặc khi quá gần thông báo trước, thông báo bị bỏ qua và không phát bù; các kênh OS và âm báo vẫn độc lập. Bỏ website/tắt tính năng không thu hồi quyền Chrome: quản lý quyền trong chi tiết extension. Thiết lập không xuất/nhập sao lưu.

### Đánh dấu thông báo đã đọc (0.86)
Trong **Cần chú ý**, đánh dấu đã đọc/chưa đọc từng lời nhắc preset đang chờ hoặc kết quả tự động; có nút đánh dấu tất cả thông báo hiện tại, kể cả mục bị tìm kiếm ẩn. Đã đọc không đồng nghĩa đã xử lý, không bỏ lời nhắc, không xóa báo cáo và không thay đổi badge. Trạng thái này dùng chung khi xem trong Tabspace và khi xét thông báo hệ điều hành còn chờ; âm lời nhắc hoặc kết quả chưa phát cũng được kiểm tra. Không thể thu hồi thông báo hoặc âm đã gửi, và thông báo đến đồng thời vẫn có thể xuất hiện. Đánh dấu chưa đọc không cố gửi lại thông báo cũ. Khi nhắc lại sau hoãn, lần nhắc mới là sự kiện chưa đọc riêng. Trạng thái lưu cục bộ, không xuất sao lưu; mục không còn tồn tại được dọn khi thay đổi trạng thái đọc. Đây chưa phải lịch sử đầy đủ cho mọi loại thông báo.

### Chuyển động và cửa sổ hẹp (0.87)
Trong **Cài đặt & sao lưu → Giao diện**, chọn chuyển động theo hệ thống (mặc định), bật hiệu ứng nhẹ hoặc giảm chuyển động. Khi chọn bật, Tabspace ghi đè tùy chọn giảm chuyển động của hệ điều hành; chọn theo hệ thống để tự thích ứng. Áp dụng cho trang quản lý và popup, lưu cùng giao diện trong sao lưu. Bản sao lưu cũ không có tùy chọn này mặc định theo hệ thống. Ở cửa sổ quản lý hẹp, thanh điều hướng và lối tắt nhóm được bố trí thành hàng cuộn ngang, vẫn giữ tên và nút tạo nhóm.

### Chuyển workspace an toàn và chọn hàng loạt (0.88)
Bản xem trước chuyển workspace có nút chọn/bỏ chọn toàn bộ cho từng danh sách cùng số lượng được chọn; tab bị bảo vệ hoặc không xác định trạng thái vẫn bị vô hiệu hóa. Tab cũ vẫn không được chọn mặc định. Cả chuyển một lượt và bước lưu & đóng hai bước đều kiểm tra lại trạng thái bảo vệ, URL đang tải và thông tin workspace; nếu dữ liệu thay đổi hoặc không xác định được kết quả, dừng và kiểm tra nhóm, Lịch sử dọn và Chrome trước khi thử lại. Việc lưu URL không bảo toàn nội dung trang chưa lưu; Chrome vẫn có thể thay đổi trạng thái ngoài Tabspace.

### Làm mới khi nhiều tab thay đổi (0.89)
Trang quản lý và popup gộp các sự kiện thay đổi gần nhau để giảm số lần đọc dữ liệu và vẽ lại; vẫn làm mới tiếp khi có sự kiện mới trong lúc đang tải. Màn hình có thể cập nhật chậm một chút, đặc biệt nếu Chrome đang bận. Các thao tác quan trọng vẫn kiểm tra dữ liệu trực tiếp trước khi thực hiện. Khi danh sách được vẽ lại, Tabspace cố giữ focus bàn phím nếu cùng nút/ô vẫn còn và xác định rõ, giữ vị trí cuộn danh sách popup; thanh nhóm không bị dựng lại nếu không đổi. Không đảm bảo luôn giữ focus nếu mục biến mất hoặc thay đổi.

### Mở lại phiên và chọn hàng loạt (0.90)
Khi lưu hoặc mở lại phiên, có thể chọn/bỏ chọn tất cả tab hoặc chọn theo cửa sổ. Trong **Xem & mở lại phiên**, tùy chọn bỏ qua URL đã mở/đang tải hoặc URL trùng trong lượt mặc định tắt để giữ cấu trúc phiên; bật khi cần giảm tab trùng. So sánh URL nguyên văn gồm query và fragment, không xét ẩn danh; việc bỏ qua có thể làm số cửa sổ, thứ tự hoặc nhóm khác phiên gốc và không ngăn mọi trùng do Chrome thay đổi đồng thời. Tabspace kiểm tra lại tab trước khi ghim tab đầu và tạo nhóm Chrome; nếu trạng thái không rõ, dừng mở tiếp, không tiếp tục nhóm, hiển thị kết quả và yêu cầu kiểm tra Chrome trước khi thử lại. Phiên chỉ lưu URL/metadata, không khôi phục form chưa lưu.

### Gợi ý dữ liệu quá hạn (0.91)
Trong **Cài đặt & sao lưu → Thời hạn lưu dữ liệu**, có thể đặt riêng số ngày cho thùng rác và lịch sử dọn. Gợi ý mặc định tắt và bản thân nó không tự xóa: mở bản xem trước, chọn từng mục hoặc chọn tất cả và xác nhận rủi ro để xóa vĩnh viễn. Danh sách tối đa 200 mục cũ nhất mỗi lần, không phụ thuộc tìm kiếm; ngày tính theo 24 giờ. Lượt có trạng thái chưa xử lý/lỗi/không rõ hoặc được báo cáo tự động tham chiếu không được gợi ý. Nếu dữ liệu thay đổi, hoặc kết quả xóa không rõ, thao tác dừng; kiểm tra lại trước khi thử. Xóa lịch sử làm mất khả năng mở lại từ lượt đó; hãy xuất sao lưu trước. Thiết lập thời hạn không có trong file sao lưu.

### Tự dọn quá hạn thử nghiệm (0.92)
Chế độ riêng trong **Cài đặt & sao lưu → Thời hạn lưu dữ liệu → Tự dọn quá hạn** mặc định **tắt**. Nếu bật và xác nhận rủi ro, Tabspace có thể xóa vĩnh viễn thùng rác và/hoặc lịch sử đủ điều kiện **không hỏi lại**. Hãy xuất sao lưu và xem gợi ý trước khi bật. Chọn 1–30 ngày giữa các lượt và tối đa 1–20 mục mỗi lượt; lần đầu sau khoảng thời gian đã chọn. Không xóa tab đang mở hay nhóm đang lưu, nhưng lịch sử bị xóa không còn dùng mở lại URL và thùng rác bị xóa không khôi phục được. Không tự xóa lịch sử chưa hoàn tất/lỗi hoặc được báo cáo tự động tham chiếu. Lịch lỡ không chạy bù, tạm dừng tự động hóa ngăn lượt mới. Nếu thời hạn thay đổi, phải xác nhận lại; nếu lượt bị gián đoạn hoặc kết quả không rõ, tự dọn dừng cho đến khi bạn kiểm tra và bật lại. Trang quản lý và popup hiển thị trạng thái; danh sách lượt gần nhất có thể chứa tên hoặc URL nhạy cảm, chỉ lưu cục bộ, không xuất sao lưu. Không đảm bảo phát hiện mọi thay đổi đồng thời hoặc khôi phục dữ liệu đã xóa.

Âm lời nhắc là lựa chọn riêng mặc định tắt, dùng chung âm và giới hạn tần suất với kết quả tự động. Nhiều lời nhắc đến cùng lúc chỉ cố phát một âm; lời nhắc đã đọc, bị tạm dừng hoặc bị bỏ qua không phát bù. Trang quản lý phải đang mở và Chrome có thể chặn phát.

### Danh sách thông báo hiện tại (0.94)
Trong **Cần chú ý**, lời nhắc preset đang chờ và kết quả tự động được gộp theo thời gian mới nhất, có lọc tất cả/chưa đọc/lời nhắc/kết quả và tìm kiếm. Bộ lọc chỉ thay đổi danh sách, không xóa hay xử lý mục; nút đánh dấu tất cả vẫn bao gồm cả mục bị ẩn. Hoãn/bỏ nhiều lời nhắc dựa vào tìm kiếm, không theo bộ lọc thông báo; hãy kiểm tra các ô trong hộp xác nhận. Các lượt đang xử lý hoặc dọn chưa rõ vẫn nằm ở phần riêng bên dưới. Đây là góc nhìn từ dữ liệu hiện tại, không phải lịch sử vĩnh viễn của mọi kênh: lời nhắc đã bỏ/hoãn và báo cáo đã xóa không còn hiện.

### Mở và chuyển workspace (0.95)
Khi mở bản lưu, có thể chọn hoặc bỏ chọn tất cả và xem số lượng được chọn. Khi mở workspace hoặc mở đích sau bước chuyển, Tabspace kiểm tra lại workspace và các nhóm đích trước mỗi lần mở; nếu phát hiện thay đổi hoặc không đọc được, dừng các mục tiếp theo và báo kết quả từng mục. Các tab đã mở vẫn giữ nguyên, hãy kiểm tra Chrome trước khi thử lại. Kiểm tra này không ngăn mọi thay đổi đồng thời. Chuyển workspace vẫn cần xem trước và xác nhận, không âm thầm đóng tab.

### Cảnh báo mở nhiều tab và chọn nhanh (0.96)
Trong **Cài đặt & sao lưu → Mở nhiều tab**, chỉnh ngưỡng cảnh báo từ 1–500; mặc định hỏi xác nhận thêm khi chọn **hơn 20 tab**. Áp dụng khi mở bản lưu, phiên, mở lại từ lịch sử và chuyển workspace; chuyển workspace hỏi trước cả bước lưu & đóng. Số đếm là số đã chọn trước khi bỏ trùng, vì vậy số thực mở có thể ít hơn. Hủy xác nhận không bắt đầu thao tác; nếu không đọc được cấu hình, lượt mở dừng. Ngưỡng lưu cục bộ và chỉ xuất sao lưu nếu chọn; không áp dụng cho thao tác ngoài Tabspace hoặc mở một tab đơn lẻ. Hộp lưu tab và mở lại lịch sử có thêm chọn/bỏ chọn tất cả và đếm lựa chọn.

### Nhắc phân loại Hộp để sau (0.97)
Trong **Hộp để sau → Nhắc phân loại**, có thể bật lời nhắc tùy chọn (mặc định tắt) và đặt tuổi từ 1–365 ngày. Tabspace đếm bản lưu đủ tuổi, kể cả mục bị tìm kiếm ẩn, và hiển thị gợi ý tại Hộp để sau và popup. Có thể hoãn 1, 3, 7 hoặc 30 ngày, hoặc bỏ hoãn. Đây chỉ là gợi ý trên giao diện: không tự mở, chuyển hay xóa và không phát âm hoặc gửi thông báo hệ điều hành. Tạm dừng tự động hóa ẩn lời nhắc; gợi ý được tính lại khi mở hoặc làm mới giao diện, không gửi bù. Mục thiếu thời gian lưu hợp lệ hoặc có thời gian trong tương lai không được tính. Chỉ số ngày có thể được chọn để xuất; trạng thái bật và thời gian hoãn không được sao lưu.

### Mặc định khi mở (0.98)
Trong **Cài đặt & sao lưu → Mặc định khi mở**, chọn cửa sổ mặc định và hành vi bỏ URL trùng cho bản lưu, cùng các lựa chọn riêng khi khôi phục phiên. Thiết lập chỉ điền sẵn hộp xem trước; vẫn có thể đổi từng lượt, và bản lưu không bị xóa. Bỏ URL đã mở cũng bỏ URL đã được mở trong cùng lượt; so sánh URL nguyên văn, không xét ẩn danh và không tránh được mọi thay đổi đồng thời. Tùy chọn bỏ trùng có thể thay đổi cấu trúc phiên. Các mặc định này không áp dụng cho hộp chuyển workspace hoặc mở lại lịch sử; lưu trên thiết bị và chỉ đưa vào sao lưu nếu chọn khi xuất.

### Nhắc sao lưu và dung lượng (0.99)
Trong **Cài đặt & sao lưu → Nhắc sao lưu**, bật lời nhắc tùy chọn (mặc định tắt), chọn chu kỳ 1–365 ngày hoặc hoãn 1, 7, 30 ngày. Gợi ý xuất hiện trong trang quản lý khi mở hoặc làm mới, không gửi thông báo hệ điều hành và tôn trọng tạm dừng tự động hóa. Sau khi tự xuất, kiểm tra file và lưu ở nơi an toàn ngoài profile Chrome, có thể bấm **Tôi đã sao lưu** để đặt lại lịch; đây chỉ là xác nhận của bạn, Tabspace không thể kiểm tra file hoặc việc tải xuống. Bấm Xuất dữ liệu không tự xác nhận. Chỉ chu kỳ có thể được chọn để xuất; trạng thái bật và thời điểm xác nhận không được sao lưu.

Nút **Xem dung lượng** cho biết số byte Chrome báo của toàn bộ storage.local của extension tại thời điểm kiểm tra; không phải kích thước file xuất hay toàn bộ profile. Xem dung lượng không xóa dữ liệu.

### Nhật ký sự kiện thông báo (0.100)
Trong **Cần chú ý → Nhật ký thông báo**, có thể bật ghi sự kiện tùy chọn, mặc định tắt. Nhật ký ghi lời nhắc preset đến hạn, kết quả đóng tự động và một số kết quả xử lý thông báo website, lần thử thông báo hệ điều hành và âm báo mà Tabspace quan sát được sau khi bật; không lưu tên preset, URL hay ID nguồn nguyên văn. Lưu tối đa 200 mục và tự bỏ mục cũ nhất khi đầy. Có lọc loại, tìm kiếm, chọn và xóa nhiều; xóa nhật ký không bỏ lời nhắc, xóa báo cáo hoặc đổi trạng thái đã đọc. Tắt ghi không xóa mục cũ.

Đây **không phải lịch sử đầy đủ mọi kênh** và không xác nhận thông báo hệ điều hành, trang web hay âm thanh đã phát; có thể thiếu sự kiện nếu Chrome gián đoạn hoặc ghi lỗi. Không ghi bù sự kiện trước khi bật. Nhật ký và thiết lập lưu cục bộ, không xuất sao lưu.

### Mặc định mở riêng cho nhóm và workspace (0.101)
Ở mỗi nhóm hoặc workspace, nút **Mặc định mở…** cho phép từng lựa chọn dùng mặc định chung hoặc ghi đè riêng: cửa sổ mở, bỏ URL đang mở và bỏ URL trùng trong lượt. Thay đổi mặc định chung ảnh hưởng các lựa chọn đang kế thừa; hộp mở cho biết nguồn chung/riêng và vẫn cho sửa từng lượt. Cài đặt nhóm chỉ dùng khi mở cả nhóm; cài đặt workspace chỉ dùng khi **Xem & mở** workspace. Mở nhiều đối tượng, chuyển workspace, mở lại lịch sử và khôi phục phiên vẫn có lựa chọn riêng. Không tự mở hay đóng tab.

Thiết lập riêng lưu cục bộ, có thể chọn xuất/nhập cho nhóm và workspace đang hoạt động; được giữ cả khi đối tượng vào thùng rác. Có thể đặt từng lựa chọn về dùng mặc định chung hoặc xóa toàn bộ thiết lập riêng trong Cài đặt. Tối đa 1.000 đối tượng có ghi đè; đây mới là kế thừa cho thao tác mở, chưa bao phủ mọi cấp trong thiết kế.

### Chọn nhiều trong bảng lệnh (0.102)
Mở bảng lệnh bằng **Alt+K**, tìm rồi dùng checkbox hoặc **Ctrl+Space** trên kết quả đang chọn. Có thể đổi từ khóa mà vẫn giữ lựa chọn (tối đa 100 mục); chỉ chọn cùng loại: tab web đang mở, hoặc nhóm/tab đã lưu. Bấm **Xem các mục đã chọn** để chuyển sang danh sách phù hợp; Tabspace kiểm tra lại ID, URL và cửa sổ hoặc bản lưu, bỏ mục đã đổi và thông báo. Bước này không mở, đóng hay thay đổi tab. Nếu trang quản lý đã có lựa chọn, cần xác nhận thay thế. Để dùng Enter thực hiện lệnh khác, hãy áp dụng hoặc bỏ lựa chọn trước. Lựa chọn trong bảng mất khi đóng bảng; một số mục đã chọn có thể nằm trong nhóm đang thu gọn.

### Lọc theo thời gian và nhóm thông minh (0.103)
Ở **Tab đang mở**, lọc theo lần kích hoạt gần nhất do Chrome cung cấp: trong 7 ngày, từ 7/30/90 ngày hoặc không rõ. Một ngày là 24 giờ; thời gian thiếu hoặc trong tương lai được coi là không rõ. Bộ lọc chỉ là gợi ý, không chứng minh tab an toàn để đóng. Chọn cả cửa sổ hoặc nhóm Chrome vẫn bao gồm tab bị lọc ẩn như nhãn nút nêu rõ.

**Nhóm thông minh** có thể kết hợp từ khóa, tag, tên miền chính xác hoặc gồm tên miền con, và khoảng số ngày đã lưu. Các điều kiện áp dụng đồng thời; tuổi tính theo thời gian tạo bản lưu trong Tabspace, không phải lần truy cập, có thể khác sau nhập hoặc sao chép. Khi dùng lọc tuổi, mục thiếu ngày hoặc có ngày tương lai không khớp. Bộ lọc không di chuyển hay đóng tab, được xuất trong sao lưu. Phiên bản Tabspace cũ có thể bỏ qua các điều kiện mới khi nhập sao lưu, làm kết quả rộng hơn; hãy kiểm tra bộ lọc nếu hạ phiên bản.

### Sao lưu tùy chọn cài đặt cá nhân (0.104)
Khi **Xuất dữ liệu JSON**, có thể chọn thêm mặc định mở và ngưỡng cảnh báo, thiết lập âm, riêng file âm tùy chỉnh, và ngưỡng tài nguyên cho nghỉ tab. Tất cả lựa chọn bổ sung mặc định bỏ chọn. File âm có thể chứa thông tin nhạy cảm và tăng kích thước file; nếu không kèm âm tùy chỉnh, bản xuất dùng âm mặc định và ghi rõ đã bỏ file. File xuất vẫn có thể chứa URL, query và ghi chú nhạy cảm.

Khi nhập, các mục cá nhân phải được chọn riêng để thay thiết lập hiện tại. Âm luôn **tắt sau khi nhập**; nếu có file âm, Chrome phải giải mã được và thời lượng tối đa 5 giây, kích thước tối đa 1 MB. Nếu file âm bị bỏ khỏi bản sao, lựa chọn dùng âm mặc định. Nếu thiết lập hiện tại thay đổi khi hộp nhập đang mở, thao tác dừng để tránh ghi đè. Thiết lập riêng của đối tượng trong thùng rác, tự động hóa, website và nhật ký thông báo vẫn không được xuất. Bản cũ không có mục cá nhân vẫn nhập bình thường; giới hạn nhập file vẫn là 10 MB.

### Chọn và bỏ chọn theo phần đang thấy (0.105)
Ở danh sách tab đang mở và các màn hình có chọn hàng loạt, dùng **Bỏ chọn tab/mục đang thấy** để chỉ bỏ những ô hiện diện sau tìm kiếm hoặc lọc; các mục đã chọn nhưng đang ẩn vẫn được giữ. **Bỏ chọn tất cả** xóa cả lựa chọn ẩn. Thanh lựa chọn cho biết số mục ẩn; hãy kiểm tra trước khi thao tác. Có thể dùng Tab và Enter để đến và kích hoạt các nút này. Nút Đặt lại trong bộ lọc tab đang mở đưa cả bộ lọc thời gian về mặc định, không xóa từ khóa tìm kiếm hay lựa chọn.

### Nhật ký kênh thông báo (0.106)
Khi đã bật nhật ký, Cần chú ý có thêm bộ lọc **Website** và **Hệ điều hành**. Website ghi kết quả xử lý: đã thử, bỏ qua vì giờ yên lặng/giới hạn tần suất, hoặc không khả dụng/không rõ. Hệ điều hành chỉ ghi khi thực sự thử gọi Chrome, không ghi từng lượt đang chờ quyền hay giờ yên lặng. “Đã thử hiển thị” không chứng minh người dùng nhìn thấy; Chrome, website hoặc hệ điều hành có thể chặn. Không ghi tên website, URL, nội dung hoặc ID nguồn nguyên văn; tối đa 200 sự kiện chung, cục bộ và không sao lưu. Không ghi bù và có thể thiếu khi Chrome gián đoạn hoặc lưu lỗi. Không hạ về bản cũ nếu cần giữ khả năng đọc nhật ký mới.

### Sao lưu mặc định riêng và nhật ký âm (0.107)
Khi xuất, có thể chọn thêm mặc định mở riêng của nhóm/workspace **đang hoạt động**; mặc định không chọn. Khi nhập, phải chọn áp dụng riêng; thiết lập được gắn với ID mới của đối tượng nhập, không thay mặc định của nhóm/workspace cũ. Khi nhập thêm vào Hộp để sau đang tồn tại, thiết lập hộp hiện tại được giữ; khi thay thế, hộp nhập dùng thiết lập trong file hoặc mặc định chung. Thiết lập riêng của đối tượng trong thùng rác không được xuất; dữ liệu thùng rác vẫn được sao lưu như trước. Giới hạn 1.000 thiết lập riêng vẫn áp dụng, kể cả thiết lập hiện có; nhập dừng nếu vượt giới hạn hoặc dữ liệu không hợp lệ.

Nhật ký thông báo opt-in thêm bộ lọc **Âm báo** cho các lần Chrome chấp nhận phát hoặc từ chối phát âm lời nhắc/kết quả khi trang quản lý đang mở. Không ghi phát thử, lượt bị bỏ qua hoặc trang quản lý đang đóng; không ghi URL, tên hoặc file âm. Chrome chấp nhận phát không chứng minh người dùng nghe được. Ghi nhật ký là best-effort, không làm chậm hay thay đổi quyết định phát âm và có thể thiếu sự kiện.

### Sao lưu thời hạn và nhắc nhở (0.108)
Khi xuất có thể chọn thêm số ngày nhắc phân loại, chu kỳ nhắc sao lưu và thời hạn gợi ý thùng rác/lịch sử. Khi nhập phải chọn áp dụng riêng: các gợi ý và lời nhắc được đặt **tắt**, thời gian hoãn/lần xác nhận được đặt lại; không nhập hoặc bật tự dọn. Nếu tự dọn hiện đang bật, thay đổi chính sách thời hạn khiến tự dọn dừng đến khi xác nhận lại. Các lựa chọn còn lại, gồm lịch chạy và trạng thái tự động hóa, không được sao lưu.

Khi file xuất vượt **10 MB**, Tabspace hỏi trước khi tải vì phiên bản hiện tại không thể nhập lại file đó. Có thể hủy hoặc vẫn tải để lưu trữ/xử lý bên ngoài; Tabspace không xác minh file tải thành công.

### Kiểm tra trước khi nhập sao lưu (0.109)
Hộp nhập cảnh báo nếu workspace hoặc preset tham chiếu nhóm không có trong danh sách nhóm đang hoạt động của file; nhóm có thể đang ở thùng rác hoặc đã thiếu. Sau nhập cần kiểm tra lại trước khi dùng. File có ID trùng gây mơ hồ trong phiên, workspace hoặc preset sẽ bị từ chối; file cũ không có ID vẫn được hỗ trợ.

Khi chọn **thay thế**, nếu dữ liệu sẽ bị thay thế đổi trong lúc hộp xác nhận mở, Tabspace dừng và yêu cầu mở lại file. Giao diện, bảo vệ và các thiết lập cá nhân được chọn nhập cũng được kiểm tra thay đổi. Chế độ **thêm** vẫn gộp với dữ liệu mới nhất; thùng rác và lịch sử hiện có được giữ trong cả hai chế độ. Hãy tự xuất và kiểm tra bản sao lưu trước khi thay thế.

### Kiểm tra và sửa tham chiếu nhóm (0.110)
Trong **Workspace** hoặc **Preset dọn tab**, chọn **Kiểm tra nhóm thiếu** để xem các nhóm không còn hoạt động và số workspace/preset liên quan. Nếu nhóm còn trong thùng rác, bạn có thể khôi phục nhóm gốc; hoặc chọn một hay nhiều dòng để gắn cùng vào nhóm hiện có, hoặc gỡ tham chiếu. Không có dòng nào được chọn sẵn; tối đa 200 dòng hiển thị mỗi lượt. Thao tác không di chuyển, mở, đóng tab hay xóa dữ liệu trong thùng rác.

Preset bị sửa sẽ **tắt lịch nhắc**; tự động đóng liên quan cần kiểm tra và xác nhận lại. Nếu workspace đã chứa nhóm đích, chỉ giữ một tham chiếu. Nếu dữ liệu liên quan thay đổi khi hộp đang mở, thao tác dừng để bạn xem lại. Khi xóa nhóm đơn lẻ hoặc hàng loạt, Tabspace báo số workspace/preset bị ảnh hưởng; xóa vĩnh viễn nhóm trong thùng rác cũng báo tham chiếu liên quan. Các thao tác xóa kiểm tra lại dữ liệu trước khi thực hiện.

### Chọn nhiều tab trong popup (0.111)
Trong popup, đánh dấu tối đa 100 tab web; có nút chọn/bỏ chọn các tab **đang thấy**, còn lựa chọn bị tìm kiếm hoặc phân trang ẩn vẫn được giữ và có số đếm. Tab thay đổi sau khi chọn được đánh dấu là lựa chọn cũ; có thể bỏ chọn rồi chọn lại.

**Xem & nghỉ** hiển thị danh sách trước, cho bỏ chọn, bỏ qua tab đang xem, ghim, phát âm thanh, đã nghỉ hoặc website được bảo vệ. Sau xác nhận Tabspace kiểm tra lại từng tab và bảo vệ; nếu kết quả không rõ hoặc không đọc được bảo vệ thì dừng phần còn lại, hiển thị kết quả từng mục. Giữ popup mở trong lúc xử lý; nếu đóng popup hoặc kết quả không rõ, hãy kiểm tra Chrome trước khi thử lại. Tab nghỉ sẽ tải lại và có thể mất dữ liệu chưa lưu.

**Xem tại quản lý** chuyển lựa chọn để tiếp tục xem trước lưu, đóng hoặc thao tác khác; bước chuyển không tự mở hay đóng tab. Tab đã đổi URL/cửa sổ hoặc biến mất bị bỏ qua. Lựa chọn truyền tạm qua bộ nhớ phiên của Chrome, chỉ dùng một lần và có hiệu lực tối đa hai phút; Tabspace cố dọn dữ liệu tạm khi trang nhận hoặc sau hai phút bằng lịch Chrome; nếu Chrome trì hoãn hoặc dọn lỗi, dữ liệu có thể còn đến khi phiên Chrome kết thúc. Không truyền URL lên máy chủ. Đóng popup trước khi chuyển sẽ mất lựa chọn.

### Lưu nhiều tab ngay trong popup (0.112)
Chọn các tab web rồi bấm **Xem & lưu**: xem từng tab, bỏ chọn nếu cần và chọn nhóm đích hoặc Hộp để sau. Chỉ tạo bản sao, **không đóng hoặc cho nghỉ tab**; URL trùng vẫn được giữ. Có thể lưu bản sao của tab đang xem, ghim, phát âm thanh hoặc website được bảo vệ.

Tabspace kiểm tra lại tab và nhóm trước khi ghi; tab đã đổi hoặc biến mất được bỏ qua. Nếu nhóm đích đổi thông tin hoặc kết quả ghi không xác nhận được, hãy kiểm tra nhóm trước khi mở lại xem trước; không tự thử lại để tránh tạo bản trùng. Giữ popup mở đến khi thấy kết quả. Không có giao dịch nguyên tử giữa thao tác trong Chrome và bộ nhớ extension, nên vẫn cần kiểm tra khi Chrome gián đoạn.

Dữ liệu chuyển lựa chọn sang trang quản lý được xóa khi nhận; nếu không được nhận, Tabspace cố dọn sau hai phút bằng lịch Chrome và khi service worker khởi động. Chrome có thể trì hoãn lịch hoặc gặp lỗi; dữ liệu còn sót chỉ ở bộ nhớ phiên và sẽ mất khi phiên Chrome kết thúc.

### Chọn và chỉnh phiên (0.113)
Trong Tab đang mở, chọn tab rồi bấm **Lưu thành phiên…** để xem trước, kể cả lựa chọn đang bị lọc ẩn. Cũng có thể chọn tab theo cửa sổ khi lưu phiên hiện tại. Chỉ lưu URL/metadata tab thường http/https, không đóng tab; tab đổi URL, cửa sổ, vị trí, ghim hoặc nhóm trong lúc kiểm tra bị bỏ qua. Khi đọc được metadata nhóm, thay đổi tên/màu/thu gọn nhóm khiến tab liên quan bị bỏ qua; nếu không đọc được nhóm, phiên được lưu không có metadata nhóm và có thông báo. Chrome vẫn có thể thay đổi sau lần kiểm tra cuối, nên đây không phải thao tác nguyên tử. Kiểm tra danh sách phiên trước khi thử lại nếu không xác nhận được ghi.

Trong **Phiên đã lưu → Chỉnh phiên…**, đổi tên hoặc chọn giữ/bỏ tab của phiên thủ công; bỏ tab cần xác nhận, không ảnh hưởng tab Chrome và không thể hoàn tác từng tab qua thùng rác. Xuất sao lưu trước nếu cần; xóa cả phiên bằng nút xóa để chuyển vào thùng rác. Snapshot tự động và điểm khôi phục không cho chỉnh. Nếu phiên thay đổi trong lúc mở hộp thoại, thao tác dừng; kiểm tra lại trước khi thử. Không khôi phục nội dung trang hoặc form chưa lưu.

### Thời gian miễn trong thao tác nghỉ (0.114)

Thời gian miễn sau mở tab trước đây chỉ áp dụng cho mô phỏng và tự động đóng. Nay bản xem trước cho nghỉ thủ công cũng dùng nó. Trong **Tab đang mở → Cho tab nghỉ** và **Xem & nghỉ** ở popup, tab vừa mở hoặc không xác định được thời điểm mở vẫn được nghỉ nhưng **để trống** trong danh sách; dòng đó ghi lý do và số phút còn lại của thời gian miễn, đầu danh sách nêu số tab cần đánh dấu rõ. Với nút **Nghỉ** ở một tab, hộp xác nhận nêu cùng lý do và bạn vẫn xác nhận được. Tab đang xem, ghim, phát âm thanh, đã nghỉ hoặc thuộc website được bảo vệ vẫn bị bỏ qua như trước; nếu không đọc được thiết lập hay dữ liệu phiên của thời gian miễn, mọi tab được coi là cần đánh dấu rõ nên thao tác không bị chặn. Thời gian miễn không áp dụng cho đóng tab hoặc lưu & đóng, và không phải dấu hiệu trang an toàn: nội dung chưa lưu vẫn có thể mất. Mốc mở tab chỉ nằm trong `chrome.storage.session` của phiên Chrome, không ghi URL; khởi động lại Chrome hoặc tải lại extension bắt đầu lại thời gian miễn cho tab chưa có mốc. Cần kiểm thử Chrome thực tế.

### Khối đo tài nguyên và hẹn nghỉ theo ngưỡng (0.115)

Mục 15 bắt đầu từ phần an toàn nhất. Module `auto-discard.js` giữ ngưỡng **rời từng tài nguyên** (RAM, CPU, heap ước lượng, mạng/hoạt động nền) — không có điểm tổng nào; kèm cách kết hợp "vượt một ngưỡng bất kỳ"/"vượt mọi ngưỡng đã chọn", số chu kỳ liên tiếp cho tài nguyên thay đổi nhanh, mẫu đo cũ hơn hai chu kỳ, tab đổi cửa sổ hoặc đổi tiến trình sau khi đo. Mọi trường hợp không đọc được đều đưa tab về "không rõ" và loại khỏi danh sách, không suy số từ tên miền, tiêu đề hay số lượng tab. Nhiều tab chung một tiến trình renderer được ghi rõ "tiến trình chung N tab" thay vì chia đều.

Trong **Cài đặt & sao lưu** có một khối thu gọn **Tự động cho nghỉ tab theo tài nguyên**: khi thu gọn, tiêu đề tự đủ ý (trạng thái Tắt/Chỉ gợi ý/Hỏi trước/Tự động, số tab vượt ngưỡng, tuổi dữ liệu đo, cảnh báo khi Chrome không cho đo); phần thân là biểu mẫu một khối, mặc định thu gọn, có `aria-expanded`, Esc chỉ thu gọn khi không có thao tác nào đang chạy, và có lối tắt **Đo lại và xem danh sách…**, **Khôi phục mặc định** (chỉ đổi biểu mẫu, phải bấm Lưu). Việc lưu đi qua khóa ghi chung và dừng nếu thiết lập đã đổi ở nơi khác.

Chưa xin quyền `processes`, chưa có thẻ "Cần chú ý", chưa có lượt nghỉ tự động: trên Chrome ổn định khối nêu "Không đo được tài nguyên trên Chrome này" và **từ chối bật** tính năng thay vì bật rồi im lặng, nên đường thủ công ở Tab đang mở giữ nguyên. Danh sách ứng viên không nghỉ tab nào; nút ở cuối hộp thoại chỉ đánh dấu tab để bạn xem trước và xác nhận như cũ. Số đo chỉ nằm trong `chrome.storage.session` (mất khi khởi động Chrome, không kèm URL); thiết lập chưa được đưa vào file sao lưu (từ 0.120 mới có ô chọn riêng). **Chưa kiểm thử trên Chrome thực tế**: cần xác nhận hành vi trên Chrome kênh Dev có quyền `processes`, bàn phím, `prefers-reduced-motion` và cửa sổ hẹp.

### Bộ đo nền theo chu kỳ (0.116)

Số đo không chỉ lấy lúc mở khối Cài đặt nữa. `AutoDiscard.run()` là điểm vào chung: trang quản lý gọi khi bấm **Đo lại và xem danh sách…**, còn service worker gọi trong chu kỳ mỗi phút sẵn có, chạy cùng lịch với các việc nền khác; khoảng giữa hai lần đo là **Chu kỳ đo (phút)** trong khối. Ở đường nền, một lượt chỉ đọc số và ghi lại bao nhiêu tab vượt ngưỡng — không tab nào được nghỉ, chưa xin quyền `processes`/`system.memory`, nên con số trong tiêu đề là số đếm theo ngưỡng, không phải số tab sẽ nghỉ.

Lịch đo đi theo đúng những gì Chrome cho phép. Chu kỳ bị bỏ lỡ (máy ngủ, tiện ích chưa kịp chạy) được nêu rõ "có chu kỳ đo đã bỏ lỡ, không chạy bù" thay vì đo dồn cho kịp; dữ liệu cũ hơn hai chu kỳ bị coi là hết hiệu lực và tiêu đề báo "dữ liệu đo đã cũ, hãy đo lại". Tab đóng hoặc chuyển trang mất mẫu đo ngay lập tức, mẫu chỉ nằm trong `chrome.storage.session` và không kèm URL hay tiêu đề; khi cả hai đường đo đều có kết quả thì kết quả mới hơn được hiển thị.

Trước mỗi lượt, các cổng chặn vẫn được kiểm tra lại và mỗi cổng có lý do riêng: tính năng tắt, tạm dừng tự động hóa, cấu hình hoặc danh sách bảo vệ không đọc được, và (từ 0.117) hệ thống chưa thiếu bộ nhớ; khi một cổng giữ lượt đo thì không có số liệu nào được ghi. Tùy chọn "Chỉ chạy khi hệ thống thiếu bộ nhớ" nay bị từ chối ngay lúc lưu nếu Chrome không cho đọc `chrome.system.memory`, thay vì chấp nhận rồi không bao giờ chạy. **Chưa kiểm thử trên Chrome thực tế**: cần xác nhận chu kỳ đo chạy đều khi để tiện ích chạy nền, không đo bù sau khi thức máy, và số trong tiêu đề khớp danh sách đo.

### Cửa chặn RAM hệ thống và hộp giới hạn (0.117)

Lựa chọn "Chỉ chạy khi hệ thống thiếu bộ nhớ" trước đây mới chỉ bị chặn khi Chrome không cho đọc `chrome.system.memory`, còn con số RAM khả dụng thì chưa thật sự được dùng. Từ bản này mỗi chu kỳ đọc `getInfo()` rồi so với ngưỡng đã chọn (5–50%): RAM khả dụng còn **từ ngưỡng trở lên** thì lượt đo bỏ qua và nêu rõ "RAM khả dụng còn 50%, chưa thấp hơn ngưỡng 12%"; số đọc được không hợp lệ (thiếu, âm, lớn hơn tổng dung lượng) hoặc API báo lỗi thì lượt đo **dừng** kèm lý do, không đoán hộ. Khi một cửa chặn giữ lượt đo, không có số liệu nào được ghi nên tiêu đề khối giữ nguyên số cũ. Nút **Đo lại và xem danh sách…** vẫn đo, vì đó là yêu cầu trực tiếp của bạn.

Trong khối, thứ tự ô làm theo 15.5: phạm vi (thời gian không được xem, giới hạn mỗi lượt) đứng trước phần đo (chu kỳ đo, số chu kỳ liên tiếp, ngưỡng RAM); không thêm lựa chọn mới. Nút **Giới hạn và rủi ro** ở cuối khối mở hộp giải thích thẳng những gì số đo không chứng minh được: số là của tiến trình renderer chứ không của riêng tab, heap chỉ là ước lượng, tài nguyên không cho biết trang còn nội dung chưa lưu, cho nghỉ tab không tạo bản lưu để khôi phục, và bản này chưa có lượt nghỉ tự động. Hộp chỉ để đọc, không đổi thiết lập và không ghi gì.

Hai phần còn lại của mục 15 được nêu ở bản sau: danh sách **Chỉ gợi ý** cần Sức khỏe tab (mục 5.7 chưa tồn tại trong ứng dụng), và việc đưa cấu hình vào file sao lưu kèm buộc tính năng ở trạng thái tắt khi nhập. **Chưa kiểm thử trên Chrome thực tế**: cần xác nhận `chrome.system.memory.getInfo()` trả số như tài liệu và một chu kỳ bị cửa chặn RAM giữ lại không để lại số mới nào trên tiêu đề khối.

### Thẻ vượt ngưỡng trong Cần chú ý (0.118)

Số đo nền có chỗ đứng ngoài Cài đặt. Khi **Cách xử lý** là Hỏi trước, mục **Cần chú ý** thêm một thẻ "N tab đang vượt ngưỡng · đo X phút trước", kèm số tab bị chặn bởi danh sách bảo vệ hoặc đang được xem, và thẻ này được tính vào nhãn ở thanh bên. Ba nút đúng theo 15.4: **Xem & nghỉ** chỉ đánh dấu những tab còn sống trong danh sách rồi chuyển sang Tab đang mở để dùng bản xem trước sẵn có — bấm nút này không nghỉ tab nào; **Bỏ qua lần đo này** ẩn thẻ; **Hiện lại thẻ** bỏ ẩn.

Quyết định "có thẻ hay không" nằm trong `AutoDiscard.attention()` và được tiêu đề khối, thẻ cùng bộ đếm sidebar dùng chung, nên ba chỗ không thể nói khác nhau. Không có thẻ khi: tính năng tắt, cách xử lý là Chỉ gợi ý hay Tự động, Chrome không cho nguồn đo, không còn tab nào trên ngưỡng, danh sách rỗng, hoặc số đo cũ hơn hai chu kỳ — đúng quy tắc từ chối dữ liệu cũ ở 15.2. Việc ẩn thẻ chỉ là một ghi chú trên chính bản ghi lần đo, nên lượt đo kế tiếp xoá nó: không có danh sách bỏ qua nào lớn dần và vẫn không có ghi đè theo từng tab (15.3). Không phản hồi thẻ không phải sự đồng ý — không tab nào bị nghỉ.

### Kết quả đo sống cùng phiên Chrome (0.119)

Bản ghi "lần đo gần nhất" — số tab vượt ngưỡng, số tab bị chặn, danh sách ID để mở bản xem trước và ghi chú đã bỏ qua thẻ — trước đây nằm trong `chrome.storage.local`, tức sống sót qua khởi động lại Chrome trong khi các tab nó trỏ tới thì không. Bản này chuyển bản ghi sang `chrome.storage.session`, đúng theo 15.6: mất khi Chrome khởi động lại, không ra khỏi máy, không nằm trong file sao lưu; các mẫu đo theo tiến trình vẫn ở chỗ cũ. Trang quản lý đọc bản ghi song song với các dữ liệu khác và nghe `storage.onChanged` vùng `session`, nên tiêu đề khối cùng thẻ trong Cần chú ý cập nhật mà không cần tải lại trang. `AutoDiscard.run()` cũng xoá bản ghi cũ do bản trước để lại ở `storage.local`, và từ chối đo khi `chrome.storage.session` không khả dụng thay vì đo xong bỏ số đi. **Chưa kiểm thử trên Chrome thực tế**: cần xác nhận khởi động lại Chrome làm mất thẻ, và một lượt đo nền trong lúc trang quản lý đang mở cập nhật được tiêu đề mà không phải bấm lại.

### Ngưỡng tài nguyên vào sao lưu theo lựa chọn (0.120)

Theo 15.6, hộp **Xuất dữ liệu JSON** có thêm ô chọn "Thêm ngưỡng tài nguyên cho nghỉ tab (khi nhập luôn ở trạng thái tắt)". Chỉ cấu hình đi theo: bật/tắt, cách xử lý, cách kết hợp, ngưỡng rời từng tài nguyên, số chu kỳ liên tiếp, thời gian không được xem, giới hạn mỗi lượt, chu kỳ đo và cửa RAM hệ thống. Không có số đo nào vào file — bản ghi lần đo nằm ở `chrome.storage.session` nên phần xuất không nhìn thấy, và file cũng không chứa tên hay URL tab.

Khi nhập, hộp xem trước chỉ hiện ô "Áp dụng ngưỡng tài nguyên trong file" nếu file có mục đó; không chọn thì cấu hình hiện tại giữ nguyên. Khi chọn, `BackupOptions.resource()` luôn ghi `enabled:false`, và mức **Tự động** trong file bị hạ về **Hỏi trước**, vì lời xác nhận rủi ro ở 15.3 không thể đi nhờ file. Mục này cũng nằm trong danh sách kiểm tra "dữ liệu đã thay đổi ở nơi khác": nếu cấu hình tài nguyên bị sửa lúc hộp nhập đang mở, việc nhập dừng và không ghi gì.
