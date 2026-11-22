# Dead Town: mã nguồn đang phục hồi — CHƯA HOÀN CHỈNH

Đây là **nền GMX cũ có thể sửa**, chưa phải mã nguồn 1.4.2 đầy đủ và chưa phải
bản có thể phát hành. Các file `project/**/*.gml` và `project/**/*.gmx` được
lưu trong Git để có thể sửa và theo dõi thay đổi. Tên trùng với APK không chứng
minh logic trùng; 68 script, 94 object và 369 event native vẫn chưa có khóa
nguồn tương ứng ở mốc ban đầu. Nguồn hiện còn thiếu 56 script, 90 object,
365 event key, 4 sprite và 8 room APK theo tên hoặc key;
398 sprite cùng tên hiện khớp các trường metadata tĩnh được so, nhưng không
chứng minh mask khi biên dịch hoặc hành vi. Không dùng project hiện tại để tuyên
bố game hoàn chỉnh hoặc đem phát hành IPA.

Đã bổ sung 271 frame thiếu và thay 8 frame cũ khác pixel hoặc kích thước:
279 ảnh cho 130 sprite, lưu trong `assets/sprites/images/` và tham chiếu trong
descriptor. Hầu hết được dựng lại từ atlas không scale; riêng `mask_noone` có
vùng atlas scale nhưng toàn bộ RGBA và mask native bằng 0, nên được lưu làm ảnh
trong suốt 32×32, chưa kiểm phép dựng thực tế sau compile. Ảnh cũ trong đầu vào
GMX ghim không bị sửa. RGB trong suốt ngoài vùng atlas cắt không xác định, PNG
được mã hóa lại. Đã cập nhật bbox của 8 sprite cũ và một số cờ của 4 sprite
mask một frame theo số liệu tĩnh APK; kiểm alpha và mask gốc được mô tả trong
hồ sơ. Các thay đổi này là ứng viên, chưa kiểm mask được compiler tạo.

105 sprite mới là ứng viên mask chữ nhật: bitmask APK có hình chữ nhật khớp
bbox theo phép đọc tĩnh và bbox của alpha khác 0 khớp số liệu APK. Descriptor
GMX là giả thuyết, chưa kiểm mask do compiler tạo, đóng gói texture, ID, tốc độ
animation, logic sử dụng frame hay iPhone. Bốn sprite còn thiếu trong project
đã lưu frame và mask gốc riêng tại `unresolved/sprites/`; chưa thêm descriptor
vì chưa chứng minh cách tạo mask native. Các bước này không có nghĩa là sửa lỗi
hiển thị đã báo.

`rom_play` view 0 đã đổi kích thước khởi tạo từ 1334×750 sang 1232×693 theo
cấu hình tĩnh trong APK, giữ port 1334×750. `sys_view` có thể tính lại kích
thước khi chạy; thay đổi này chưa được chứng minh là sửa lỗi iPhone hoặc đúng
với mọi tỉ lệ màn hình. So sánh room qua `tools/deadtown_room_evidence.py` chỉ
kiểm dữ liệu tĩnh, không khôi phục code hay xác nhận gameplay. Với tám room
còn thiếu, `unresolved/rooms/rooms.json` lưu riêng một số trường, danh sách
instance/tile theo thứ tự và ID native để nghiên cứu; không khai báo chúng vào
project vì còn thiếu object và logic. Kiểm lại bằng:

```sh
python3 tools/deadtown_unresolved_rooms.py verify .cache/deadtown-original.apk deadtown-source/unresolved/rooms
```

Đây không phải room có thể chạy, không bao gồm mọi trường room/physics hay nội
dung code, và ID native không bảo đảm dùng được sau biên dịch.

Đã bổ sung background ứng viên `tile_sewer`: ảnh 130×130 dựng lại từ atlas
APK, descriptor chia tile 128×128 mượn từ `tile_basic`, chưa chứng minh thiết
lập gốc hay cách dùng trong game. Cả 30 background cùng tên có pixel tĩnh khớp
atlas APK. Native đặt `tile_sewer` ở đầu bảng còn XML thêm ở cuối để giữ thứ tự
XML cũ; không coi thứ tự XML là ID sau compile hoặc bảo đảm tương thích ID.

Font `font_24` đã cập nhật từ 490 lên 2.499 glyph theo bảng FONT APK; atlas
2048×2048 và 2.499 bộ số liệu glyph được đối chiếu tĩnh. Không có TTF gốc;
GameMaker có thể tự tạo lại hoặc đóng gói font khác, chưa kiểm build, cách
hiển thị chữ hay iPhone. PNG font nằm trong `assets/fonts/` để dựng workspace.

Đã thêm `par_action_nosolid` không có sự kiện theo bảng APK và đặt lại object
cha của `obj_gps`/`obj_trap` theo APK. Thêm ba object không có event riêng:
`par_defence_shop`, `par_map_door`, `obj_defence_house`, cùng sprite nhà được
trích dựng từ atlas. Mask ước tính từ alpha được so với bitmask APK, nhưng chưa
chứng minh compiler tạo mask tương đương; `obj_defence_house` kế thừa `par_solid`
của nguồn cũ. Đây là phục hồi cấu trúc tĩnh, không tự khôi phục code sử dụng
những object này hay bảo đảm hành vi và ID sau biên dịch. Đã bổ sung event
collision comment-only của `obj_player` với `par_action` dựa trên một event
native có thân lệnh ARM `bx lr`; chưa kiểm cách GameMaker xử lý collision,
kế thừa và runtime trên thiết bị.

Đã thêm `item_check_pet` và `item_check_skin` ứng viên theo phép so sánh
native Android cho chỉ số số nguyên: lần lượt từ 17 đến 22 và 23 đến 26,
bao gồm hai đầu. Chưa chứng minh hành vi đối với giá trị khác số, số thực sát
ngưỡng hay trên iOS; đây không khôi phục logic sử dụng hai script còn thiếu.
Thêm `gps_colour_random` ứng viên theo lời gọi native tạo màu HSV từ hue
ngẫu nhiên và hai hằng số 180, 120; chưa kiểm tương đương bộ sinh số ngẫu
nhiên hay chuyển đổi màu trên thiết bị. `generate_basic_string` là ứng viên
trả 20 chữ A theo đường chạy thông thường trong native; chưa kiểm runtime gốc.
`generate_random_string` ứng viên tạo chuỗi 20 ký tự từ ba nhóm chữ hoa,
chữ thường và chữ số; đã giữ thứ tự các lệnh sinh ngẫu nhiên như trong ARM32,
nhưng chưa chứng minh RNG, mã hóa hay kết quả trên Android/iOS. Script ứng
viên `check_room_is_multiplay_room` dùng tên room thay cho ID Android không
portable; room phòng thủ và phần multiplayer vẫn chưa có trong project. Chi
tiết và phạm vi kiểm tra nằm trong hồ sơ phục hồi.

Có ứng viên một phần cho item rơi từ parcel: Create đặt cờ nội bộ bằng 0 và
alarm 900 bước; parcel đặt cờ 1; Alarm 0 hủy item khi cờ đúng. Cờ
`__dt_item_timed` là tên mới do dự án đặt, **không phải tên native đã xác
định**. Các đường tạo item khác và Alarm 1 còn thiếu; chưa chứng minh thời gian,
save, dispatch hoặc gameplay trên thiết bị. Hai nhánh rơi item trong Alarm 6
của `obj_zombie`, `obj_zombie2`, `obj_zombie3`, `obj_zombie4` và `obj_zombie5` cũng có ứng viên
đặt cờ này; các zombie và đường rơi khác
không tự động được coi là đã phục hồi.

Bốn script `gp_button_check`, `gp_button_check_pressed`,
`gp_button_check_released`, `gp_axis_value` là ứng viên theo native Android:
chọn thiết bị gamepad đầu tiên được báo kết nối. Giá trị trả về ngầm khi không
có thiết bị, compiler, tay cầm thật và iOS vẫn chưa được xác minh.

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
là kết quả đối chiếu. 89 descriptor nền được cấp file APK không encode lại;
`snd_eating` thứ 90 có descriptor ứng viên và WAV APK nguyên byte trong overlay.
`status.json` vẫn báo 89 vì chỉ đếm bước cấp audio cho nền cũ, không đếm override;
project kết quả khai báo 90 sound. `tools/check_deadtown_sound_evidence.py` so
90 payload của project mới với APK và kiểm nhóm, effects, volume cùng các thiết
lập ứng viên. Chưa chứng minh decode hoặc thiết lập âm thanh sau compile.
Công cụ không đưa các tệp ký hoặc archive extension quảng cáo cũ vào kết quả.

Thư mục `.cache/` là tạm thời: đừng dùng nó làm nơi lưu mod duy nhất. Nếu có
lỗi giữa chừng, thư mục kết quả có `INCOMPLETE.txt`; kiểm tra và tự xóa hoặc
chọn đích mới, không xóa bản sửa của người dùng.

## Kiểm tra VM thử nghiệm

Workflow `.github/workflows/deadtown-source-vm-diagnostic.yml` compile GML hiện
có bằng UndertaleModTool và chạy headless trong runner desktop trên một bản dữ
liệu **chỉ để chẩn đoán**. Nó xóa tham chiếu native không giải quyết được, bỏ
qua một số liên kết sự kiện, dùng sprite/mask/atlas từ APK thay vì ảnh trong
source; không phải bản GameMaker hay iOS. Kết quả CI đạt nghĩa là phép thử chạy
xong, không phải game đạt chất lượng. Chi tiết và số lượng thiếu nằm trong hồ sơ
`docs/deadtown-ho-so-phuc-hoi.md`.

## Trước khi có IPA tốt

Cần phục hồi và kiểm chứng các logic/asset còn thiếu, kiểm tra renderer, camera,
input touch, UI, save, âm thanh và gameplay so với bản gốc; sau đó kiểm tra
build và cài/chạy trên iPhone. GameMaker iOS toolchain có yêu cầu riêng về
truy cập; runner thay thế cũng chưa được xác nhận tương thích hoàn chỉnh.
Tệp so sánh tĩnh chỉ là danh sách công việc, không phải chứng nhận đúng hành vi.
Không thể bảo đảm hoàn toàn không có lỗi, kể cả sau kiểm thử.
