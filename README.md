# Tabspace

Thiết kế: [docs/tabspace-design.md](docs/tabspace-design.md). Bản thử nghiệm Chrome extension nằm trong `extension/`; hướng dẫn cài đặt và giới hạn tại [extension/HUONG-DAN.md](extension/HUONG-DAN.md).

Đóng gói: `cd extension && zip -r ../tabspace-extension.zip .`.

### Âm báo thử nghiệm (0.84)
Trong **Cài đặt & sao lưu → Âm báo**, có thể bật riêng âm lời nhắc preset mới, kết quả đóng tự động thành công hoặc bị chặn/không rõ, chọn hai âm có sẵn hoặc file âm cục bộ (tối đa 1 MB, 5 giây), chỉnh âm lượng và nghe thử. Mặc định tắt. Chỉ cố phát khi trang quản lý đang mở và chứng kiến lượt chuyển trạng thái; không mở trang phát âm, không phát bù khi trang đóng hoặc âm bị bỏ qua. Chrome có thể chặn phát tự động ngay cả khi nghe thử được. Giờ yên lặng, tùy chọn toàn màn hình và tạm dừng tự động hóa có hiệu lực; âm bị bỏ qua, không phát dồn. Âm tùy chỉnh và thiết lập âm không có trong bản sao lưu; lưu cục bộ và có thể xóa trong cài đặt.

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
Trong **Cài đặt & sao lưu → Mở nhiều tab**, chỉnh ngưỡng cảnh báo từ 1–500; mặc định hỏi xác nhận thêm khi chọn **hơn 20 tab**. Áp dụng khi mở bản lưu, phiên, mở lại từ lịch sử và chuyển workspace; chuyển workspace hỏi trước cả bước lưu & đóng. Số đếm là số đã chọn trước khi bỏ trùng, vì vậy số thực mở có thể ít hơn. Hủy xác nhận không bắt đầu thao tác; nếu không đọc được cấu hình, lượt mở dừng. Ngưỡng chỉ lưu cục bộ và không xuất sao lưu; không áp dụng cho thao tác ngoài Tabspace hoặc mở một tab đơn lẻ. Hộp lưu tab và mở lại lịch sử có thêm chọn/bỏ chọn tất cả và đếm lựa chọn.

### Nhắc phân loại Hộp để sau (0.97)
Trong **Hộp để sau → Nhắc phân loại**, có thể bật lời nhắc tùy chọn (mặc định tắt) và đặt tuổi từ 1–365 ngày. Tabspace đếm bản lưu đủ tuổi, kể cả mục bị tìm kiếm ẩn, và hiển thị gợi ý tại Hộp để sau và popup. Có thể hoãn 1, 3, 7 hoặc 30 ngày, hoặc bỏ hoãn. Đây chỉ là gợi ý trên giao diện: không tự mở, chuyển hay xóa và không phát âm hoặc gửi thông báo hệ điều hành. Tạm dừng tự động hóa ẩn lời nhắc; gợi ý được tính lại khi mở hoặc làm mới giao diện, không gửi bù. Mục thiếu thời gian lưu hợp lệ hoặc có thời gian trong tương lai không được tính. Thiết lập và thời gian hoãn lưu cục bộ, không xuất sao lưu.

### Mặc định khi mở (0.98)
Trong **Cài đặt & sao lưu → Mặc định khi mở**, chọn cửa sổ mặc định và hành vi bỏ URL trùng cho bản lưu, cùng các lựa chọn riêng khi khôi phục phiên. Thiết lập chỉ điền sẵn hộp xem trước; vẫn có thể đổi từng lượt, và bản lưu không bị xóa. Bỏ URL đã mở cũng bỏ URL đã được mở trong cùng lượt; so sánh URL nguyên văn, không xét ẩn danh và không tránh được mọi thay đổi đồng thời. Tùy chọn bỏ trùng có thể thay đổi cấu trúc phiên. Các mặc định này không áp dụng cho hộp chuyển workspace hoặc mở lại lịch sử; lưu trên thiết bị, không nằm trong sao lưu.

### Nhắc sao lưu và dung lượng (0.99)
Trong **Cài đặt & sao lưu → Nhắc sao lưu**, bật lời nhắc tùy chọn (mặc định tắt), chọn chu kỳ 1–365 ngày hoặc hoãn 1, 7, 30 ngày. Gợi ý xuất hiện trong trang quản lý khi mở hoặc làm mới, không gửi thông báo hệ điều hành và tôn trọng tạm dừng tự động hóa. Sau khi tự xuất, kiểm tra file và lưu ở nơi an toàn ngoài profile Chrome, có thể bấm **Tôi đã sao lưu** để đặt lại lịch; đây chỉ là xác nhận của bạn, Tabspace không thể kiểm tra file hoặc việc tải xuống. Bấm Xuất dữ liệu không tự xác nhận. Thiết lập và thời điểm xác nhận lưu cục bộ, không nằm trong sao lưu.

Nút **Xem dung lượng** cho biết số byte Chrome báo của toàn bộ storage.local của extension tại thời điểm kiểm tra; không phải kích thước file xuất hay toàn bộ profile. Xem dung lượng không xóa dữ liệu.

### Nhật ký sự kiện thông báo (0.100)
Trong **Cần chú ý → Nhật ký thông báo**, có thể bật ghi sự kiện tùy chọn, mặc định tắt. Nhật ký chỉ ghi lời nhắc preset đến hạn và kết quả đóng tự động mà Tabspace quan sát được sau khi bật; không lưu tên preset, URL hay ID nguồn nguyên văn. Lưu tối đa 200 mục và tự bỏ mục cũ nhất khi đầy. Có lọc loại, tìm kiếm, chọn và xóa nhiều; xóa nhật ký không bỏ lời nhắc, xóa báo cáo hoặc đổi trạng thái đã đọc. Tắt ghi không xóa mục cũ.

Đây **không phải lịch sử đầy đủ mọi kênh** và không xác nhận thông báo hệ điều hành, trang web hay âm thanh đã phát; có thể thiếu sự kiện nếu Chrome gián đoạn hoặc ghi lỗi. Không ghi bù sự kiện trước khi bật. Nhật ký và thiết lập lưu cục bộ, không xuất sao lưu.

### Mặc định mở riêng cho nhóm và workspace (0.101)
Ở mỗi nhóm hoặc workspace, nút **Mặc định mở…** cho phép từng lựa chọn dùng mặc định chung hoặc ghi đè riêng: cửa sổ mở, bỏ URL đang mở và bỏ URL trùng trong lượt. Thay đổi mặc định chung ảnh hưởng các lựa chọn đang kế thừa; hộp mở cho biết nguồn chung/riêng và vẫn cho sửa từng lượt. Cài đặt nhóm chỉ dùng khi mở cả nhóm; cài đặt workspace chỉ dùng khi **Xem & mở** workspace. Mở nhiều đối tượng, chuyển workspace, mở lại lịch sử và khôi phục phiên vẫn có lựa chọn riêng. Không tự mở hay đóng tab.

Thiết lập riêng lưu cục bộ, không xuất/nhập sao lưu; được giữ cả khi đối tượng vào thùng rác. Có thể đặt từng lựa chọn về dùng mặc định chung hoặc xóa toàn bộ thiết lập riêng trong Cài đặt. Tối đa 1.000 đối tượng có ghi đè; đây mới là kế thừa cho thao tác mở, chưa bao phủ mọi cấp trong thiết kế.

### Chọn nhiều trong bảng lệnh (0.102)
Mở bảng lệnh bằng **Alt+K**, tìm rồi dùng checkbox hoặc **Ctrl+Space** trên kết quả đang chọn. Có thể đổi từ khóa mà vẫn giữ lựa chọn (tối đa 100 mục); chỉ chọn cùng loại: tab web đang mở, hoặc nhóm/tab đã lưu. Bấm **Xem các mục đã chọn** để chuyển sang danh sách phù hợp; Tabspace kiểm tra lại ID, URL và cửa sổ hoặc bản lưu, bỏ mục đã đổi và thông báo. Bước này không mở, đóng hay thay đổi tab. Nếu trang quản lý đã có lựa chọn, cần xác nhận thay thế. Để dùng Enter thực hiện lệnh khác, hãy áp dụng hoặc bỏ lựa chọn trước. Lựa chọn trong bảng mất khi đóng bảng; một số mục đã chọn có thể nằm trong nhóm đang thu gọn.

### Lọc theo thời gian và nhóm thông minh (0.103)
Ở **Tab đang mở**, lọc theo lần kích hoạt gần nhất do Chrome cung cấp: trong 7 ngày, từ 7/30/90 ngày hoặc không rõ. Một ngày là 24 giờ; thời gian thiếu hoặc trong tương lai được coi là không rõ. Bộ lọc chỉ là gợi ý, không chứng minh tab an toàn để đóng. Chọn cả cửa sổ hoặc nhóm Chrome vẫn bao gồm tab bị lọc ẩn như nhãn nút nêu rõ.

**Nhóm thông minh** có thể kết hợp từ khóa, tag, tên miền chính xác hoặc gồm tên miền con, và khoảng số ngày đã lưu. Các điều kiện áp dụng đồng thời; tuổi tính theo thời gian tạo bản lưu trong Tabspace, không phải lần truy cập, có thể khác sau nhập hoặc sao chép. Khi dùng lọc tuổi, mục thiếu ngày hoặc có ngày tương lai không khớp. Bộ lọc không di chuyển hay đóng tab, được xuất trong sao lưu. Phiên bản Tabspace cũ có thể bỏ qua các điều kiện mới khi nhập sao lưu, làm kết quả rộng hơn; hãy kiểm tra bộ lọc nếu hạ phiên bản.
