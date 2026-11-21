# Dead Town: mã nguồn đang phục hồi — CHƯA HOÀN CHỈNH

Đây là **nền GMX cũ có thể sửa**, chưa phải mã nguồn 1.4.2 đầy đủ và chưa phải
bản có thể phát hành. Các file `project/**/*.gml` và `project/**/*.gmx` được
lưu trong Git để có thể sửa và theo dõi thay đổi. Tên trùng với APK không chứng
minh logic trùng; 68 script, 94 object và 369 event native vẫn chưa có khóa
nguồn tương ứng ở mốc ban đầu. Nguồn hiện vẫn thiếu 111 sprite APK theo tên;
12 sprite cùng tên còn khác metadata được so. Không dùng project hiện tại để
tuyên bố game hoàn chỉnh hoặc đem phát hành IPA.

Đã bổ sung 63 frame thiếu và thay 8 frame cũ khác pixel hoặc kích thước bằng
ảnh dựng lại từ atlas APK: tổng 71 ảnh cho 23 sprite, lưu dưới
`assets/sprites/images/` và tham chiếu trong descriptor. Ảnh cũ vẫn có trong
đầu vào GMX ghim, không bị sửa. Kiểm tra tĩnh xác nhận RGBA dựng lại khớp vùng
atlas đã giải mã; 8 sprite vẫn có bbox khác APK và được giữ nguyên, các trường
metadata còn lại trong nhóm này khớp theo phép so số. RGB trong suốt ngoài vùng
cắt không xác định, PNG được mã hóa lại. Mask va chạm, tốc độ animation, render,
logic sử dụng frame và iPhone chưa được kiểm chứng. Việc khôi phục các frame này
không có nghĩa là sửa được lỗi hiển thị đã báo.

## Chỉnh sửa và quản lý tài nguyên

- Chỉnh GML trong `project/scripts/`, sự kiện trong `project/objects/`, và các
  descriptor GMX khác trong `project/`. Cây này là nguồn chuẩn: file GMX/GML
  bị xóa ở đây sẽ **không** tự lấy lại từ nguồn cũ khi dựng lại.
- Tài nguyên gốc lớn không được chép vào Git: công cụ dưới đây bổ sung tệp
  ảnh cũ và âm thanh APK vào bản làm việc mới. Muốn sửa ảnh/âm thanh, đặt
  file đã sửa tại `deadtown-source/assets/` với đường dẫn tương đối giống
  project, ví dụ `assets/sprites/images/spr_player_0.png`; khi dựng nó thay
  tệp cùng đường dẫn. Nếu muốn lưu mod vào Git, tự thêm các file trong
  `assets/`. Không đặt chứng chỉ, khóa ký hoặc provisioning profile ở đây.
- Nguồn gốc đã được áp dụng các thay đổi offline thử nghiệm: loại tham chiếu
  extension, tắt ads/dịch vụ, xóa event Q debug, giá shop 0 và cấp một số cờ
  mua. Đây **không phải** mã gốc, và chưa chứng minh mọi nội dung đều mở hoặc
  hành vi game đúng. Xem `tools/prepare_deadtown_offline.py` và hồ sơ.
- Các thay đổi chỉ trong thư mục kết quả sẽ không tự trở lại Git. Hãy lưu mã
  vào `project/` và tài nguyên đã chỉnh vào `assets/` trước khi dựng lần nữa.

## Dựng một bản làm việc mới (không tạo IPA)

Cần Python 3.9+, `git`, `curl`, `tar`, `nm`; tự cung cấp APK và GMX đúng phiên
bản hoặc lấy từ các vị trí đã xác định trong hồ sơ. Ví dụ tại gốc repo:

```sh
mkdir -p .cache/gmx
curl -fsSL 'https://codeload.github.com/kjs104901/deadtown/tar.gz/5e3d798f914c8cd3b066c8289323005d63111f37' | tar xz -C .cache/gmx --strip-components=1
git fetch --no-tags origin 8643abdda26944002384bc216bf555717a9e1e42
git show '8643abdda26944002384bc216bf555717a9e1e42:Dead+Town+-+Zombie+survival_1.4.2_APKPure.apk' > .cache/deadtown-original.apk
python3 tools/materialize_deadtown_source.py .cache/gmx/deadtown.gmx .cache/deadtown-original.apk .cache/deadtown-workbench
```

Đích không được tồn tại trước: công cụ không ghi đè dự án/save hiện có. Nguồn
GMX được kiểm toàn cây, APK được kiểm SHA-256. `project/deadtown.project.gmx`
là project làm việc; `status.json`, `comparison.json` và `sprite-metadata.json`
là kết quả đối chiếu. 89 descriptor âm thanh được cấp file gốc không encode
lại; APK có âm thanh thứ 90 nhưng project cũ chưa khai báo. Công cụ không đưa
các tệp ký hoặc archive extension quảng cáo cũ vào project kết quả.

Thư mục `.cache/` là tạm thời: đừng dùng nó làm nơi lưu mod duy nhất. Nếu có
lỗi giữa chừng, thư mục kết quả có `INCOMPLETE.txt`; kiểm tra và tự xóa hoặc
chọn đích mới, không xóa bản sửa của người dùng.

## Trước khi có IPA tốt

Cần phục hồi và kiểm chứng các logic/asset còn thiếu, kiểm tra renderer, camera,
input touch, UI, save, âm thanh và gameplay so với bản gốc; sau đó kiểm tra
build và cài/chạy trên iPhone. GameMaker iOS toolchain có yêu cầu riêng về
truy cập; runner thay thế cũng chưa được xác nhận tương thích hoàn chỉnh.
Tệp so sánh tĩnh chỉ là danh sách công việc, không phải chứng nhận đúng hành vi.
Không thể bảo đảm hoàn toàn không có lỗi, kể cả sau kiểm thử.
