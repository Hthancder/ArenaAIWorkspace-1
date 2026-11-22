# Ứng viên cài đặt và kết nối gamepad

Phân tích APK Android ghim: `gp_connect_check` tại `0x38d470`, 2.144 byte,
SHA-256 `0049e77f4c24a987b9df43d3454b78e918ee5339a7eb79ca177e31366efdf84d`.
Nó đọc global slot 88, so `os_type` với số 4 (có epsilon), chuyển slot sang
số nguyên trước khi so > 0, kiểm gamepad được hỗ trợ, đếm thiết bị một lần,
duyệt index tăng dần, đặt deadzone 0,2 cho **mọi** thiết bị kết nối và trả 1
nếu có ít nhất một thiết bị; nếu không trả 0.

Dấu vết độc lập trong `setting_load` (`0x2ec430`) và `setting_save`
(`0x2ee0e0`) cho thấy cùng global slot 88 được đọc/ghi dưới section `control`,
key `gamepad`; mặc định đọc là 0 và nhánh thiết lập mới gán 0. Tên gốc của biến
không có đủ bằng chứng: source dùng alias mới `global.__dt_setting_gamepad`.
Có script ứng viên và thêm riêng hai dòng thiết lập/persistence, không tuyên bố
các phần còn lại của setting_load/save khớp native. Các UI settings và sự kiện
gọi script trên bản mới vẫn chưa có trong source; không có bằng chứng phần UI
cũ có thể bật setting này.

`tools/deadtown_gamepad_connect_evidence.py` ghim hash các export, đối chiếu
relocation, các nhánh và INI key. Probe VM dùng builtins gamepad **giả**, gồm
thay `os_type` bằng biến test; nó không kiểm thiết bị thật. Việc so slot với
`>= 1` chỉ tương ứng phép chuyển int trong miền giá trị thông thường (nhất là
0 và 1); các giá trị bất thường/ngoài miền, epsilon và enum OS sau compile
chưa xác minh. Không giả định số 4 mang cùng ý nghĩa trên mọi runtime; chưa kiểm
compiler GameMaker, Android đang chạy, cài đặt/gameplay hoặc iOS.
