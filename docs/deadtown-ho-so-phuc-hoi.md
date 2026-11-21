# Hồ sơ phục hồi Dead Town — thông tin cần giữ lại

> **Trạng thái:** CHƯA HOÀN THÀNH. Đây là hồ sơ nghiên cứu, không phải cam kết
> game đã giống bản gốc, không phải hướng dẫn gửi IPA cho người dùng. Cập nhật
> hồ sơ này khi có bằng chứng mới. Không xóa hai báo cáo gốc hay các công cụ
> được dẫn bên dưới: chúng chứa chi tiết, địa chỉ, cách tái lập và giới hạn mà
> bản tổng hợp này tham chiếu.

## 1. Mục tiêu và chỉ dẫn của người dùng

- Phục hồi **Dead Town: Zombie survival** theo APK do người dùng cung cấp,
  hướng tới IPA iOS 15 miễn phí, dùng offline, cài bằng TrollStore, không quảng
  cáo, Google Play hoặc thông báo; cố gắng mở nội dung và hỗ trợ mod qua Tệp.
- Giữ âm thanh gốc, **không chuyển đổi định dạng/encode lại**.
- APK là chuẩn đối chiếu; nguồn GMX cũ không được giả định cùng phiên bản.
- Người dùng yêu cầu mổ sâu nhất; **không gửi build lẻ hoặc yêu cầu thử IPA**
  cho đến khi logic đầy đủ, UI không lệch và các chi tiết trong game không lỗi
  theo yêu cầu của họ. Đừng coi biên dịch hoặc vài kịch bản thành công là đủ.
  Khi thực sự có IPA đạt yêu cầu, cung cấp tệp tải trực tiếp trong hội thoại,
  không bắt người dùng đăng nhập GitHub.
- Không thể bảo đảm tuyệt đối không có lỗi chỉ từ phân tích tĩnh hoặc CI. Cần
  ghi rõ phần nào đã chứng minh, phần nào suy luận và phần nào chưa kiểm chứng.

## 2. Nơi lưu chi tiết — giữ cả các tệp này

- [`deadtown-original-re.md`](deadtown-original-re.md): báo cáo RE chính, số
  liệu, địa chỉ ARM, kiểm tra ngôn ngữ, poison, bảng dữ liệu, sprite/mask,
  UI, giới hạn và gate. Đây là phần chi tiết bổ sung cho hồ sơ này.
- [`deadtown-ios-investigation.md`](deadtown-ios-investigation.md): điều tra
  GMX, âm thanh, offline, GameMaker import, runner và lịch sử IPA. Tệp ghi nhật
  ký theo thời điểm; các câu cũ như “chưa có IPA” chỉ đúng tại thời điểm mục
  đó được viết, **không phải trạng thái mới nhất**.
- `tools/`, `tests/`, `.github/workflows/deadtown-*.yml`: mã phân tích, kiểm
  thử và pipeline có thể chạy lại. Các tệp này và tài liệu đã được theo dõi
  trong Git; `.cache/`, log tạm, dữ liệu VM và báo cáo được tạo cục bộ không
  phải bản lưu bền vững.
- Nhánh làm việc: `arena/78062d86-arenaaiworkspace-1`. Không đổi nhánh khi
  tiếp tục; lịch sử Git chứa các mốc nghiên cứu và bản vá đã thực hiện.

## 3. Đầu vào cố định và tính toàn vẹn

| Đầu vào | Vị trí / phiên bản | SHA-256 |
|---|---|---|
| APK do người dùng cung cấp | commit `8643abdda26944002384bc216bf555717a9e1e42`, `Dead+Town+-+Zombie+survival_1.4.2_APKPure.apk` | `bc8fa1990cb2cdde8d184f2a942fe4010820f0592d88a36e1cbee0a6aac081fb` |
| Dữ liệu APK | `assets/game.droid` | `0900da067462bd48040da6e217a86e2d5411397b05f07d55d13c58440b82a7b8` |
| Thư viện APK ARM32 | `lib/armeabi-v7a/libyoyo.so` | `7f3895e245d83edc498859d0869017acf55ec1e92fc801cb734f7fe8315e1c23` |
| Nguồn GMX | `https://github.com/kjs104901/deadtown`, commit `5e3d798f914c8cd3b066c8289323005d63111f37`, `deadtown.gmx` | Git commit cố định |
| Runner nghiên cứu | `https://github.com/andronep/gmrunner`, commit `e7121381d38b03a24242812fc22b0a7386d545c6`, GPL-3.0-or-later | Git commit cố định |
| UTMT CLI Ubuntu | `UnderminersTeam/UndertaleModTool` bản `0.9.2.0` | `d182f00c0e5ced8d9252aa1f796374cfee077a3889a658e70b68685f9cd559c7` |
| Underanalyzer của UTMT | commit `4ff50a866b4c1a7acee8cebe6a56d6a48709b453` | Git commit cố định |
| SDL cho runner iOS | commit `5d249570393f7a37e037abf22cd6012a4cc56a71` | Git commit cố định |

APK là bản người dùng đưa, tên/chứng chỉ trong APK không tự chứng minh nguồn
phát hành; chưa đối chiếu chứng chỉ với fingerprint tin cậy. `LICENSE` upstream
GMX không quy định rõ quyền tái sử dụng/phân phối; cần xác minh quyền riêng
trước khi phát hành. Game Unity `com.Ccentury.DeadTownSurvival` là remake khác,
**không** phải bản này.

## 4. Điều cốt lõi: vì sao chưa thể khôi phục nguyên vẹn

- APK dùng GameMaker **YYC**: các chunk `CODE`, `VARI`, `FUNC` trong
  `game.droid` rỗng; logic là mã máy ARM32 Android trong `libyoyo.so`. Không
  thể trực tiếp chạy ELF Android như bytecode trên runner iOS ARM64.
- APK có 192 script, 240 object, 15 room và 859 khóa event được export; nguồn
  cũ gồm 138 file script, 165 file object, 539 event và 7 room khai báo. Trùng
  tên: 124 script, 146 object, 490 event. Thiếu so với nguồn: **68 script, 94
  object, 369 event**; nguồn có 49 event không thấy trong export native. Trùng
  tên không chứng minh trùng hành vi.
- Room APK bổ sung: `rom_setting_display`, `rom_setting_effect`,
  `rom_setting_save`, `rom_multi_login`, `rom_multi_lobby`, `rom_multi_room`,
  `rom_play_sewer`, `rom_play_defence`. Các script/đối tượng thiếu gồm
  `item_grind`, `get_enchant_price`, `get_enchant_my_money`, `gp_*`,
  `obj_grinder`, `obj_enchanter`, điều khiển save slot và defence. Multiplayer
  và tính năng dựa vào server phải được tính riêng với mục tiêu offline.
- Probe bytecode đã biên dịch 138 script và 539 thân event nguồn cũ, liên kết
  504 event, bỏ qua 35 event không có đích và xóa 68 tham chiếu mã native không
  phân giải để tuần tự hóa. Những mục bị xóa/bỏ qua **không được phục hồi**.
  Chạy được lobby hoặc ép chuyển sang gameplay không chứng minh game hoàn chỉnh.
- `sys_view` Step native gọi các script `gp_*` không có trong nguồn; `sys_UI`
  Draw GUI gọi các script enchant thiếu. Call graph quét tĩnh có 1.051 hàm,
  793 cạnh ứng viên, không theo toàn bộ CFG hoặc lời gọi gián tiếp; literal
  pool có thể bị đọc nhầm thành lệnh. Không dùng nó làm bằng chứng đầy đủ.

## 5. Âm thanh, staging, offline và iOS

- Đã trích **90 payload âm thanh** từ APK (87 Ogg, 3 WAV, tổng 2.214.484 byte),
  không chuyển đổi; 90/90 giải mã bằng ffmpeg ra null thành công, 89 khớp tên
  descriptor nguồn và `snd_eating` không được GMX liệt kê. Đã thay descriptor
  trong bản staged để khớp định dạng thật. Điều này không chứng minh phát âm
  thanh đúng khi chơi, và âm thanh APK không nhất thiết là tệp nguồn ban đầu.
- GMX gốc thiếu 89 tệp âm thanh được liệt kê và hai extension descriptor
  GooglePlayServices/UnityAds. Bản offline là bản sao kiểm tra hash, loại bỏ
  các tham chiếu dịch vụ, tắt quảng cáo/social/store/thông báo, giữ tiến trình
  achievement cục bộ; thưởng quảng cáo và dịch vụ online không có. Tạm đặt
  giá shop bằng 0 và cấp cờ mua 5–13 trong bộ nhớ sau khi tải. **Chưa chứng minh
  đã mở mọi nội dung**, chưa chứng minh không tác dụng phụ.
- ProjectTool `2024.14.165` import được bản sao trong run `44493423659`; có
  534 dòng cảnh báo/lỗi dạng thiếu thuộc tính Options cũ. Job iOS dừng ở kiểm
  tra GameMaker access key; import thành công không chứng minh GML hay iOS chạy.
  Không yêu cầu người dùng trả tiền cho CI license.
- Runner iOS 15 tùy biến đã build unsigned ARM64; cấu hình
  `.github/workflows/gmrunner-ios15.yml`, launcher
  `tools/gmrunner-ios15/Launcher.swift`. Launcher sao chép BundledGame vào
  Documents/Dead Town một lần và không tự ghi đè dữ liệu đã có. Build runner
  hoặc kiểm tra Mach-O iOS 15 không chứng minh gameplay, touch, save, mod hay
  cài đặt trên thiết bị. Cần kiểm tra cả cập nhật, tệp cũ và an toàn dữ liệu.
- Đã có các IPA thử nghiệm trước khi người dùng đặt gate hiện tại (bao gồm
  `deadtown-ios15-landscape-test-2` và `deadtown-ios15-re-test-3`); chúng là
  bản **không đầy đủ, không được coi là bản hoàn thiện**. Có phản hồi ảnh từ
  một IPA cũ cho thấy lỗi hiển thị/scaling; các bản sau chưa được xác nhận
  trên iPhone. Không gửi lại hay yêu cầu thử khi gate chưa đạt.

## 6. UI, input và chữ `str:`

- Event `sys_UI` KeyPress Q ở nguồn cũ có
  `ui_message_type("str:"+string(random(100000)))`; không thấy event Q tương
  ứng trong danh sách native. Offline patch xóa đúng event debug nguồn-only,
  không xóa các thông báo nhặt vật phẩm. Forced desktop run
  [44517643086](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44517643086)
  vẽ `str:43680.18` ở bản cũ và không vẽ ở bản đã sửa. Đây là nguyên nhân có
  thể giải thích trực tiếp chuỗi `str:`, **không** chứng minh đường touch trên
  iPhone hay rằng ảnh thực tế có dấu `:`.
- Runner có overlay gamepad ảo của riêng nó; không suy ra đó là UI gốc.
  Runner báo `os_type=0`, các API display, window và raw touch dùng không gian
  tọa độ khác nhau. Desktop run
  [44547797982](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44547797982)
  đo `display=1280x720`, `gui=1334x750`, `window=1334x750`,
  `viewport=1232x693`, `os_type=0`. Sai khác này chưa xác định được mức ảnh
  hưởng trên iOS; chưa áp dụng sửa UI dựa trên phỏng đoán.
- Cần ảnh tham chiếu APK gốc, đo layout, hitbox, multitouch, rotation, safe
  area và aspect ratio; desktop headless không thể xác nhận giao diện iPhone.

## 7. Bảng native và ngôn ngữ

- `sys_global` Create tại `0x3b7330`: phân tích GOT/ARM giải được **857 ứng
  viên, 0 unresolved**: weapon 35, equip 27, use 22, etc 65, skill 23, craft
  91, spawn 129, `lang_add` 465. Đây là quét tĩnh tuyến tính, không chứng
  minh thứ tự/nhánh chạy hoặc runtime. Một số resource ID/schema có thể khác.
  Ví dụ ứng viên native: Dagger attack 45 so với 40 ở GMX; Cotton clothes
  defense 2 so với 1; Raw meat food 15 so với 20. Craft nguồn có 76 tuple
  distinct, 71 chung native; spawn nguồn 127 call, 126 distinct, 109 chung.
- `lang_get` native tại `0x2df86c`: selector global index 62, case 0 trả
  argument 0; case 1–3 dùng các global index 63–65 để `ds_map_exists` rồi
  `ds_map_find_value`, nếu không tồn tại trả argument 0. Các đích fallback là
  `0x2dfcb8`, `0x2dfcd0`, `0x2dfce8`. Chưa chứng minh tên đăng ký global,
  selector ngoài 0–3 hay việc chạy native.
- `lang_add` tại `0x2df3cc` dùng argument 0 làm key; global index 63, 64, 65
  nhận lần lượt argument 1, 2, 3 qua `g_FUNC_ds_map_add` tại `0x2df548`,
  `0x2df5d8`, `0x2df660`. Đây là đối chiếu cấu trúc tĩnh, không phải execution.
- 465 call ứng viên, 463 key distinct, so với 362 call GMX. Trong 340 key tên/
  mô tả distinct từ các bảng ứng viên, 52 vắng ở GMX cũ; cả 340 có mặt trong
  candidates. Tất cả trường tiếng Trung/Nhật là chuỗi rỗng, tiếng Hàn không
  rỗng. Giá trị tồn tại nhưng rỗng **khác** key không tồn tại: không tự thay
  bằng tiếng Anh. Hai key trùng `Light machine gun` và `Heavy machine gun` có
  các giá trị Hàn khác nhau; chưa xác minh thứ tự chèn và cách xử lý trùng của
  Android gốc.
- Forced VM [44669577897](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44669577897)
  dùng thứ tự quét giả định và gmrunner giữ giá trị đầu: ba map mỗi map 463
  key, so sánh đầy đủ các key/value với candidates; giá trị đầu cho hai key là
  `라이트 머신건`, `헤비 머신건`. Key rỗng và key thiếu được thử riêng.
  Đây chỉ là kết quả của VM chưa hoàn chỉnh, **không** xác nhận Android/iOS.

## 8. Poison, save/load và các phép thử VM

- Native `db_use_add` nhận 10 argument so với 9 của nguồn; ứng viên Gas mask
  có cột 9 bằng 3, 21 item còn lại bằng 0. `item_use` đọc field 9 và nhân
  `30*60`; buff Step truy cập player object ID 142 và global/instance index 32
  ứng viên. Save/load thường ghép key `player/buffpoison` với index 171,
  `player/buffpoisonprotect` với index 32; các địa chỉ cụ thể trong báo cáo RE.
  Tên/đăng ký index và thứ tự runtime chưa được chứng minh đầy đủ.
- Ứng viên player Create có bound protection 18.000 step và HP max 100,
  poison damage chia 4.500 thay vì GMX `0.06`; skill 20 có nhánh giảm một nửa.
  `g_GMLMathEpsilon` ban đầu 1e-10 nhưng có thể thay đổi; 15 room speed 30.
- Forced VM [44565506937](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44565506937):
  Gas mask tạo protection 5.400 step, cap 18.000, tiêu stack, hết poison;
  save/load thường round-trip 321/2; damage nhân 4.500 là 100 khi skill 20=0,
  50 khi skill 20=1. Khi cố ý đặt poison và protection đồng thời, candidate
  mất HP ở bước đầu và không mất ở bước sau. Không chứng minh thứ tự hoặc
  semantics khi chạy APK gốc, các save mode khác hay iOS.
- Không suy map instance từ `g_Vars+0x60`: slot 32 của `g_Vars` là
  `g_VAR_pointer`, còn `nGlobalVariables=212`, `nInstanceVariables=1247`.
  `#0x20` tại `obj_boss2_Step_0` `0x71365c` là argument của
  `view_effect_closeup`, không phải player variable index.

## 9. Lỗi compiler và inventory/crafting

- UTMT 0.9.2.0/Underanalyzer hạ cú pháp DS-map `[? ...]` của nguồn cũ thành
  array accessor trong các probe bytecode. `item_use` bản cũ đã gây truyền
  array thay map handle trong VM; source Underanalyzer có TODO xử lý non-array
  accessor. Chưa loại trừ lỗi runner khác. Có 17 dòng cú pháp này trong năm
  script `item_use`, `item_get`, `item_drop`, `item_equip`, `item_make`.
- Bốn script sau được biên dịch bản cũ thành entry không liên kết để đối chiếu;
  cả bốn đều có array accessor vào `target_inven`. Candidate chỉ dùng trong
  nghiên cứu thay bằng `ds_map_find_value`/`ds_map_replace`, kiểm tra SHA
  nguồn và không sửa project/release. `item_use` có workaround riêng cho probe
  poison. Không coi đây là sửa lỗi native hay chuyển đổi GML tổng quát.
- Forced VM [44671590170](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44671590170):
  thêm 2 rồi 3 được 5; drop item thiếu trả 0, drop item có trả 1 và giảm số
  lượng, drop cuối xóa key; equip và đổi vũ khí trả lại đồ cũ; chế tạo với
  nguyên liệu thiếu không thay stack, đủ ba loại tạo 2 item, recipe tổng hợp
  có hai slot số lượng 0 và stack đầu ra có sẵn cũng chạy. Đây là các kịch bản
  ép trong VM từ **nguồn cũ**, không chứng minh logic APK, mọi loại trang bị,
  ID, UI, input hay iOS.
- Phát hiện khác biệt quan trọng ở `item_equip` native `0x1a0d8c`:
  argument key được chia lấy `floor` và `fmod` với global index 18; source GMX
  cũ không có tách này. `sys_global_Create_0` có lệnh gán global 18 bằng
  100000.0 (`0x3f4dc4`); chưa chứng minh lệnh được chạy, thứ tự hay giá trị
  tại thời điểm equip. Nếu còn bằng 100000, key nguyên 100001 tách thành phần
  thương 1 và dư 1. Nhánh vũ khí có điều kiện gọi `item_get(1, global[5] +
  global[6] * global[18], 1)` rồi cập nhật global 5/6 bằng dư/thương; chưa xác
  minh tên đăng ký hay giá trị lúc chạy. Nếu type gần 2, trường
  cột 4 của global array index 19 gần 4, và `item_check_pet` của native xác
  định phần dư nằm trong khoảng 17–22 (theo epsilon), cờ slot 8 được đặt 1;
  khi epsilon runtime nhỏ hơn 1, nhánh này bỏ qua khối trừ inventory. Source
  cũ luôn trừ trước. Đây là phân tích tĩnh có điều kiện, **chưa chạy APK**;
  tên đăng ký global, schema, giá trị divisor, tác động equip đầy đủ và đường
  chạy thực tế còn chưa rõ. Công cụ `tools/deadtown_item_equip_evidence.py`.
- Forced VM [44730980693](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44730980693)
  cho candidate cũ equip key tổng hợp 100001: key được lấy khỏi map, key 1
  cũ được trả thêm một, nhưng global và instance vũ khí giữ nguyên 100001,
  không tách; đã hoàn nguyên pointer trước Step. Kịch bản chỉ chứng minh
  candidate, không chứng minh APK chấp nhận key hay hoạt động runtime. Static
  CI [44730980746](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44730980746) đạt.
- Forced VM [44727391503](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44727391503)
  thử candidate nguồn cũ với hai item trang bị key 17: equip xong còn một,
  global và instance deco đều 17; probe hoàn nguyên state. Điều này xác nhận
  candidate cũ có trừ trong kịch bản ép, không xác nhận APK chạy thế nào hay
  điều kiện guard native có xảy ra thật. Static CI
  [44727391462](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44727391462) đạt.
- Đối chiếu ARM mới cho `item_drop` tại `0x1a31e0` cho thấy selector 1–4
  chọn `g_pGlobal` index 0–3, ghi vào instance slot 7; argument 1 làm key.
  Nhánh key thiếu trả 0; nhánh có giá trị đọc, trừ 1, gọi native
  `ds_map_set`, đọc lại, có thể `ds_map_delete` rồi trả 1. Chưa chứng minh
  đăng ký tên các index/slot, hành vi selector không hợp lệ hay chạy Android.
- Phân tích native cho thấy nhánh xóa so sánh với `g_GMLMathEpsilon`, khởi
  tạo trong ELF bằng 1e-10 nhưng có thể đổi lúc chạy. gmrunner mặc định 1e-5.
  Forced VM [44681106676](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44681106676)
  với stack phân số tổng hợp 1.000001: epsilon mặc định thì xóa sau trừ 1,
  epsilon 1e-10 thì giữ; probe hoàn nguyên epsilon sau đó. Nếu APK vẫn dùng
  giá trị khởi tạo, nhánh ARM cho kết quả như trường hợp thứ hai; chưa chạy
  native để xác minh. Không kết luận stack phân số có trong gameplay bình
  thường và không tự đổi epsilon toàn game. Bốn selector cũng đã được thử
  trên các map riêng trong VM. Công cụ tĩnh: `tools/deadtown_item_drop_evidence.py`.
- Phân tích `item_get` native tại `0x19f528`: selector 1–4 chọn global index
  0–3. Sau lời gọi `ui_message_type`, khi target so bằng global index 3, năm
  nhánh item index 44–48 lần lượt cộng argument số lượng vào global index
  12–16, trả 0 và bỏ qua vòng xử lý map thông thường. So sánh item dùng
  epsilon runtime, ELF khởi tạo 1e-10; nguồn GMX cũ dùng cùng các item index
  và đặt tên counter là đạn thường, shotgun, machinegun, tên và dầu. Chưa
  xác minh đăng ký tên global native, runtime hoặc giá trị phi hữu hạn.
  Công cụ tĩnh `tools/deadtown_item_get_evidence.py`; không sửa release hoặc
  coi source cũ đã tương đương APK.
- Nhánh `item_get` thông thường: lấy size và key đầu, duyệt bằng `find_next`;
  nếu tìm thấy key thì `find_value` cộng số lượng và `ds_map_set`, còn nhánh
  cờ chưa tìm thấy gọi `ds_map_add`. Bộ verifier pin vector, các call, nhánh
  và instance slot 2/3/4, không đoán tên slot. `YYCompareVal` nhận epsilon
  runtime; thứ tự duyệt map, loại key, điều kiện bất thường, giá trị trả về
  thường và hành vi chạy Android/iOS chưa được chứng minh.
- Forced VM [44718892668](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44718892668)
  cho candidate nguồn cũ: thêm key 0/1/2 với 2/4/6, tăng key 2 thêm 3 và
  key 1 thêm 5, rồi thêm key 3 với 8; map tạm có bốn key với giá trị
  2/9/9/8. Đã xóa map tạm và hoàn nguyên handle; đây chỉ là case số nguyên
  trong gmrunner, không chứng minh thứ tự duyệt hoặc tương đương APK/iOS.
  Static CI [44718892746](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44718892746) đạt.
- Forced VM [44715781079](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44715781079)
  thử riêng candidate nguồn cũ: năm counter 100/200/300/400/500 lần lượt
  thành 102/203/304/405/506 sau khi lấy index 44–48 với số lượng 2–6; năm
  lời gọi trả 0 và map etc tạm vẫn rỗng. Probe hoàn nguyên counter và handle;
  đây không phải chạy native hay chứng minh tương đương Android/iOS. Static CI
  [44715781099](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44715781099) đạt.
- Đối chiếu độc lập trong native normal save `game_save_protect` tại
  `0x1d97f8`: global index 0, 1, 2, 3 được `ds_map_write` rồi ghi vào các
  key `inventory/weapon`, `inventory/equip`, `inventory/use`, `inventory/etc`
  tương ứng. Điều này củng cố ý nghĩa bốn selector của `item_drop`, nhưng
  không chứng minh tên đăng ký biến hay đường chạy native.
- Native normal load `game_load_protect` tại `0x21a4a8`: cùng bốn global
  index được đưa vào `ds_map_clear` (`0x21e410`, `0x21e4a4`, `0x21e538`,
  `0x21e5cc`); tiếp đó kết quả `ini_read_string` bốn key trên được đưa cùng
  map tương ứng vào `ds_map_read` (`0x21e718`, `0x21e8ac`, `0x21ea44`,
  `0x21ebdc`). Bộ kiểm tĩnh xác nhận literal, con trỏ và vector đối số; các
  nhánh cleanup gần đó chỉ bỏ qua giải phóng RValue, không bỏ qua các lời gọi
  này. Chưa chứng minh thực sự vào được đoạn đó hoặc toàn bộ CFG. Mỗi literal
  mặc định trỏ tới một byte BSS ban đầu bằng 0, phù hợp chuỗi rỗng, nhưng vùng
  này ghi được nên chưa quan sát giá trị khi chạy. Không suy ra hành vi khi
  key thiếu/hỏng, định dạng save gốc hay tính tương thích iOS. Vị trí khối
  inventory native khác thứ tự đầu script GMX cũ; xem báo cáo RE chi tiết.
- Forced VM [44683394932](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44683394932)
  lưu bốn map với key 0 mang giá trị 11/22/33/44, cố ý đổi giá trị và thêm
  key 900, rồi tải lại: bốn giá trị được khôi phục và key 900 bị xóa. Bộ kiểm
  tra độc lập giải mã save tạm để đối chiếu. gmrunner dùng định dạng riêng
  `GMRM`; **chưa chứng minh tương thích save Android/GameMaker hoặc iOS**.
  Không sử dụng save thật của người dùng. Công cụ tĩnh
  `tools/deadtown_inventory_save_evidence.py`; checker
  `tools/check_deadtown_inventory_save.py`.

## 10. Hình, frame và collision mask

- APK 402 sprite vs 291 tên GMX; 291 chung, 111 chỉ APK. Trong sprite chung,
  267 khớp metadata được so sánh, 24 khác, 17 khác số frame. Ví dụ APK/GMX:
  `spr_item_use` 22/20, `spr_item_etc` 65/49, `spr_item_weapon` 35/30,
  `spr_ui_buff` 7/6, `spr_action_button` 11/10, `spr_ui_health` 6/4;
  `spr_setting_cradits` rộng 107/247.
- Trong 746 cặp frame cùng chỉ số: 221 giống RGBA, 517 chỉ khác RGB ở alpha 0,
  5 khác pixel nhìn thấy (`ih_dagger[0]`, `spr_event_eng[0]`,
  `spr_event_kor[0]`, `spr_gps_sign[0]`, `spr_ui_day[0]`), 3 khác kích thước
  (`spr_part_bull[0]`, `spr_setting_cradits[0,1]`). 63 frame APK bổ sung ở
  các tên chung. RGB trong suốt vẫn có thể ảnh hưởng texture filtering.
- Bộ trích sprite nghiên cứu xuất 402 sprite, 1.029 frame reference, 402 raw
  mask tổng 1.033.038 byte. 1.028 frame unscaled được kiểm tra RGBA; trường
  hợp `mask_noone[0]` atlas 32×32/target 1×1 chưa đoán bộ lọc resampling.
  PNG là tái mã hóa, khác yêu cầu giữ **âm thanh** nguyên byte; export này
  không sửa game và không chứng minh kết quả vẽ/collision runtime.
- Với giả định MSB-first theo gmrunner (chưa xác minh Android): 62 mask đầy,
  302 rectangle nhỏ, 37 irregular, 1 rỗng; padding bit đều 0, 398 bbox nonempty
  khớp. Ba sai khác là `mask_zombie` 0–36 vs bbox 0–37, `mask_boss3` 0–118
  vs 0–119, `mask_boss4` 0–48 vs 0–49 trên cả hai trục. `mask_player` có
  225 bit trong 15×15. Không tự sửa bbox dựa trên giả định này.

## 11. Tái tạo cache và kiểm thử

Các lệnh dùng đường dẫn mới; tool staging/extract/patch từ chối ghi đè. Không
xóa cache hay dữ liệu người dùng để chạy lại: chọn thư mục đích mới. Phải có
commit APK trong Git và truy cập được GitHub; khi thiếu commit, fetch đúng mã
đó từ `origin` trước. Các lệnh sau chạy từ gốc repository:

```sh
mkdir -p .cache
# Nếu chưa có commit APK: git fetch --no-tags origin 8643abdda26944002384bc216bf555717a9e1e42
python -c 'import pathlib,subprocess; p=pathlib.Path(".cache/deadtown-original.apk"); data=subprocess.check_output(["git","show","8643abdda26944002384bc216bf555717a9e1e42:Dead+Town+-+Zombie+survival_1.4.2_APKPure.apk"]); f=p.open("xb"); f.write(data); f.close()'
printf '%s  %s\n' bc8fa1990cb2cdde8d184f2a942fe4010820f0592d88a36e1cbee0a6aac081fb .cache/deadtown-original.apk | sha256sum -c
# Dùng đường dẫn checkout mới nếu .cache/deadtown đã tồn tại.
git clone https://github.com/kjs104901/deadtown.git .cache/deadtown
git -C .cache/deadtown checkout --detach 5e3d798f914c8cd3b066c8289323005d63111f37
python -m pip install --target .cache/re-pylibs capstone==5.0.6 pyelftools==0.32 Pillow==11.3.0
python tools/recover_deadtown_audio.py extract .cache/deadtown-original.apk .cache/deadtown-audio
python tools/stage_deadtown_gmx.py .cache/deadtown/deadtown.gmx .cache/deadtown-staged || test "$?" -eq 1
python tools/recover_deadtown_audio.py apply .cache/deadtown-staged .cache/deadtown-audio
python tools/prepare_deadtown_offline.py .cache/deadtown-staged .cache/deadtown-offline
python tools/deadtown_event_probe.py .cache/deadtown-offline .cache/events.json
PYTHONPATH=.cache/re-pylibs python -m unittest discover -s tests -v
```

Lệnh tạo APK mở tệp ở chế độ độc quyền và từ chối ghi đè; chọn tên mới nếu
cần. `stage` có thể trả 1 vì thiếu tham chiếu trước bước phục hồi audio. Mọi lệnh
sau phải dùng đúng đường dẫn mới đã chọn. Workflow
`.github/workflows/deadtown-native-re.yml` và
`.github/workflows/deadtown-poison-probe.yml` chứa các bước tự động đầy đủ hơn,
các phiên bản dependency đã pin và chỉ xuất log/report nghiên cứu. Artifacts
CI có thời hạn ngắn nên không coi là bản sao lưu duy nhất.

Các công cụ chính: `deadtown_native_inventory.py`, `deadtown_native_callgraph.py`,
`deadtown_native_tables.py`, `deadtown_native_lang.py`,
`deadtown_lang_fallback_evidence.py`, `deadtown_lang_coverage.py`,
`deadtown_poison_evidence.py`, `deadtown_item_drop_evidence.py`,
`deadtown_item_get_evidence.py`, `deadtown_item_equip_evidence.py`,
`deadtown_inventory_save_evidence.py`, `deadtown_sprite_metadata.py`,
`deadtown_sprite_pixels.py`, `deadtown_sprite_masks.py`,
`recover_deadtown_sprites.py`, `recover_deadtown_audio.py`,
`prepare_deadtown_offline.py`, `prepare_deadtown_poison_probe.py`,
`prepare_deadtown_lang_table_probe.py`, `prepare_deadtown_inventory_probe.py`
và các `check_deadtown_*`/`.csx` tương ứng. Đọc help/docstring trước khi dùng;
các probe candidate chỉ dành cho dữ liệu tạm, không được đưa vào IPA.

Kết quả gần nhất: **105 unittest local đạt**; run VM `44730980693` đạt,
static RE `44730980746` đạt. CI/địa chỉ trong báo cáo là dấu vết có thể đối
chiếu, không thay thế dữ liệu/bằng chứng cần tái tạo.

## 12. Các việc chưa xong và gate

1. Khôi phục/có bằng chứng về logic và các event/script/object/room còn thiếu,
   kể cả các tên trùng nhưng nội dung khác; không suy từ số tên trùng.
2. Đối chiếu Android gốc về điều khiển, UI, tài sản, collision, gameplay,
   combat, spawning, chế tạo, inventory, equip, progression và mọi chế độ save.
   Giải quyết giới hạn UTMT/runner và các ID/schema trước khi tích hợp.
3. Xác minh offline, ads, thông báo, unlock, âm thanh không đổi byte và phát
   được, mod bằng Tệp; lưu/cập nhật không làm mất save hoặc mod. Làm rõ phạm vi
   multiplayer/server và quyền phân phối.
4. Kiểm chứng layout, touch đa điểm, safe area và xoay ở nhiều aspect ratio
   theo bản gốc; kiểm thử iOS 15 thực tế khi đạt gate. Không chuyển các probe
   chưa xác minh thành build phát hành.
5. Không hứa thời điểm hay khẳng định “hoàn toàn không lỗi” khi chưa có chứng
   cứ; **không gửi IPA / yêu cầu người dùng thử** trước khi đáp ứng chỉ dẫn.

### Tiếp tục: lưu và tải vũ khí (phân tích tĩnh)

Nhánh save/load thường trong binary gốc ghi riêng `equip/weapon` (global 5)
 và `equip/weaponlevel` (global 6); khi tải dùng mặc định lần lượt -1 và 0.
Sau đó binary so sánh global 24 với level qua `YYCompareVal` và, nếu kết quả
âm, chép global 24 vào level. Mã Create tĩnh khởi tạo global 24 bằng 20.0;
chưa chứng minh giá trị lúc chạy hay ngữ nghĩa toàn bộ phép so sánh. Mã GMX cũ
chỉ lưu `weapon`, không có trường level. Điều này củng cố việc không thể coi
bản nguồn cũ là tương đương bản gốc. Probe VM với khóa giả 100001 chỉ là phép
thử cô lập, không chứng minh tương thích save hoặc hành vi Android/iOS. Chi
tiết và giới hạn trong `docs/deadtown-original-re.md`.

Đã kiểm tra: 107 test cục bộ và CI phân tích tĩnh `44732951476` đạt; VM cô lập
`44733479785` cũng đạt với khóa giả 100001 được tải lại nguyên vẹn vào global
và pointer của instance mới, rồi đặt lại trước Step. Hai lượt đầu thất bại do
checker chưa xử lý dấu ngoặc kép của giá trị INI, đã sửa và thêm test. Kết quả
VM không chứng minh hành vi native hay tương thích tệp lưu.

### IPA iOS do người dùng bổ sung

Người dùng đưa hai phần `Dead Town-1.4.2.zip.001/.002` ở commit
`d111b8605447c0aa65832b574c77645101340b73`; ghép theo thứ tự thu được IPA
SHA-256 `0212db7196f54894476d902bf8832e2e1db9f6de2121757c2740ec46283b0c09`.
IPA ghi version 1.4.2, chứa framework bên thứ ba được chèn; người dùng yêu cầu
bỏ qua framework khi nghiên cứu. Chưa chạy hay xác nhận bản này an toàn/nguyên
vẹn. Dữ liệu GameMaker nằm trong executable, không phải file `game.ios` nhỏ.

So sánh tĩnh IPA và APK: 90 sound, 402 sprite, 30 background, 192 script,
1 font, 240 object và 15 room cùng tên theo cùng thứ tự; 402 metadata sprite và
packed masks giống nhau. Tái dựng 1.028 frame không scale cho RGBA giống nhau;
1 frame `mask_noone` scale chưa so. 3/90 âm thanh giống byte gốc; cả 90 giống
sau khi chỉ bỏ qua serial và CRC từng trang Ogg (không kiểm CRC hay phát âm
thanh). Điều này hữu ích để đối chiếu, **không chứng minh code iOS giống
Android**. Mã so sánh `tools/deadtown_ios_compare.py` và kết quả/giới hạn đầy
đủ ở `docs/deadtown-original-re.md`.

Kiểm tra đối chiếu và CI phân tích tĩnh `44763810611` đã đạt. Lượt cục bộ chạy
110 test, 20 test bỏ qua do thiếu đầu vào tùy chọn. Phân tích này không tạo hay
sửa IPA; chưa có bằng chứng chạy game trên iOS.

### Phản hồi hình ảnh trên iPhone

Người dùng xác nhận cả test 1, 2 và 3 đều bị lệch sprite và có vệt màu khi
nhân vật di chuyển. Chưa có video tái hiện. Kiểm tĩnh riêng
RE-test3 (`tools/deadtown_test3_graphics_evidence.py`) thấy 6 PNG atlas, 402
metadata sprite, texture-page entries và masks giống APK từng byte ở các mục
đã so; ba room gameplay có cờ vẽ màu nền mặc định được bật. Không thể từ đó
kết luận lỗi không phải renderer, camera, event hay state khi chạy. Runner có
nhánh không clear application surface cho GMS1 và phụ thuộc `bgShowColor`/nội
dung được vẽ; đây mới là giả thuyết, không chứng minh nguyên nhân. Chi tiết
và giới hạn ở `docs/deadtown-original-re.md`; chưa có bản sửa hay IPA mới.

CI kiểm tra tĩnh RE-test3 `44766640996` đạt; không có thử render hay iPhone.

Cả ba workflow đóng gói dùng cùng runner từ run `44509744633`; test 1 và 2
dùng cùng data, test 3 là data debug-fix riêng. Đây là các điểm chung cần
điều tra, chưa xác nhận nguyên nhân lỗi trên iPhone.

### Kết quả tìm nguyên nhân vệt màu

Probe desktop `44773983060` cho nhân vật di chuyển bằng phím trong room ép:
`background_showcolor=1`, view và application surface 1232×693, góc camera
-56,32°. Kiểm tra có kiểm soát `44775942814` tô sẵn màu thử rồi chỉ đo ngay sau
lệnh vẽ màu nền: ở góc 0° còn 0 pixel màu thử, ở -56,3189° còn 276.119/853.776
pixel (32,34%). Khi **chỉ trong phép thử** vẽ màu nền không xoay rồi khôi phục
camera, còn 0 pixel màu thử. Đây chứng minh runner desktop có trường hợp nền
không phủ hết viewport khi camera xoay, và có hướng sửa cần khảo sát thêm.

Không được coi đây là bằng chứng lỗi iPhone đã được sửa: game có thể vẽ đè
vùng trống, iOS và sprite lệch chưa được kiểm tra, sửa thử chỉ cho một lượt vẽ
trên desktop. Chưa đưa thay đổi vào IPA, chưa yêu cầu người dùng thử. Bộ kiểm
tra: `tools/deadtown-motion-diagnostic.csx`,
`tools/check_deadtown_motion_probe.py`, `tools/prepare_deadtown_background_probe.py`,
`tools/check_deadtown_background_probe.py`; workflow chỉ xuất log nghiên cứu.

Thử tiếp theo dõi màu thử qua cả lượt vẽ room và lượt kế tiếp. Lúc đứng yên
`44778152971`, còn 60.360 pixel sau lượt đầu và 60.357 pixel trong số đó vẫn
cùng vị trí sau lượt sau. Lúc cho nhân vật thực sự di chuyển bằng phím trong
probe desktop `44778680557`, hai vị trí đo cách nhau 6,50 đơn vị; còn 87.009
pixel màu thử sau lượt đầu và 78.759 pixel trong số đó vẫn cùng vị trí sau lượt
sau. Khi chỉ thử vẽ nền không xoay ở lượt sau, số pixel còn lại là 0 trong cả
hai tình huống. Toàn bộ 117 test cục bộ đạt, 20 test bỏ qua vì thiếu đầu vào
tùy chọn; CI probe đạt.

Màu được cố ý tô trước, game chạy trong room ép với VM desktop chưa đầy đủ;
đo ở application surface sau room draw, không phải toàn bộ các bước xuất hình.
Vì vậy đây là bằng chứng vệt thử có thể tồn tại trong cấu hình desktop, **không
phải** bằng chứng vệt tự nhiên hoặc nguyên nhân trên iPhone, cũng không xác
nhận đã sửa sprite lệch. Chưa thay runner sản phẩm hay tạo IPA mới.

### Tiếp tục kiểm tra sprite lệch

Nguồn GMX cũ vẽ nhân vật thành nhiều lớp: chân, thân, vũ khí và các lớp khác;
bóng ban ngày và chân có vị trí lệch chủ ý so với `x,y`. Vì vậy cần phân biệt
lớp nào bị lệch thay vì chỉ nhìn một sprite hay atlas.

So sánh tĩnh bằng `tools/deadtown_draw_call_evidence.py`: sự kiện Draw của
nhân vật có 12 điểm gọi `draw_sprite_ext` trực tiếp dạng ứng viên trong mã
Android và 12 lệnh trong nguồn cũ; Draw GUI của `sys_view` có 13 ứng viên so
với 8 lệnh nguồn. Đây chỉ là **đếm tĩnh**, không kiểm đối số, thứ tự hay tọa
độ thực thi; tối ưu biên dịch và gọi gián tiếp cũng có thể làm số khác nhau.
Số bằng nhau không chứng minh vị trí đúng, số khác nhau không tự chứng minh
lỗi. Android không phải binary iOS; nguồn cũ cũng chưa được xác nhận tương
đương sự kiện thực của bản thử. Chưa xác định nguyên nhân sprite lệch trên
máy, chưa sửa game hay tạo IPA.

CI nghiên cứu `44874094290` đạt; chạy cục bộ 121 test, bỏ qua 6 do thiếu đầu
vào tùy chọn. Chi tiết và giới hạn khác ở `docs/deadtown-original-re.md`.

### Đo tọa độ các lớp nhân vật khi chạy desktop

Probe `44881439577` chạy data test3 trong runner desktop dùng riêng để đo,
không tô màu thử. Trong 45 lượt Draw của nhân vật ở mỗi tình huống đứng yên
và nhấn D, nó ghi 180 lệnh vẽ: thân, hai chân và bóng. Chưa thấy sprite vũ
khí trong đúng tình huống này nên chưa đo được lớp vũ khí. Khi di chuyển,
nhân vật lệch tối đa 195,04 đơn vị so với lượt đứng yên tương ứng.

Trong những mẫu đó, tọa độ gọi vẽ thân trùng `x,y` nhân vật; tọa độ hai chân
khớp `x,y` cộng biến lệch chân đang lưu. Khoảng cách từ điểm neo chân tới thân
thay đổi khoảng 0,20–23,25 đơn vị với chân trái và 0,07–14,25 với chân phải.
Đây là biến thiên **được mã của bản thử yêu cầu**, không tự chứng minh bất kỳ
lớp nào đúng hay sai so với game gốc. Tọa độ bốn góc CPU khớp phép tính lại
cùng công thức của runner, không phải kiểm hình ảnh thực tế.

Phép đo chỉ là VM desktop chưa đầy đủ, room ép, một chuỗi điều khiển và một
lượt Draw; chưa đo ảnh GPU cuối, camera sau trình bày, iPhone hay vị trí theo
bản gốc. Chưa xác định hay sửa lỗi sprite lệch/vệt màu. CI probe đạt; 124 test
cục bộ đạt, 23 test bỏ qua do thiếu đầu vào tùy chọn. Không tạo IPA mới.

### Yêu cầu mới: phục hồi mã nguồn để sửa/mod và build IPA

Người dùng yêu cầu tiếp tục phục hồi một mã nguồn đầy đủ, có thể chỉnh sửa,
sau đó build IPA tốt. Đây thay đổi việc tạm dừng chuyển game trước đó; tuy
nhiên không đồng nghĩa game đã đầy đủ hoặc cho phép khẳng định không lỗi.

Đã đặt 872 file GMX/GML nền cũ và chỉnh sửa offline vào
`deadtown-source/project/`, kèm hướng dẫn `deadtown-source/README.md`. Công cụ
`tools/materialize_deadtown_source.py` dựng một bản làm việc mới từ nguồn và
APK đã ghim hash, ghép 89 file âm thanh không encode lại, cho phép asset mod
ở `deadtown-source/assets/`, không ghi đè thư mục kết quả đã có và loại tệp
ký cùng archive extension quảng cáo cũ. Không tự đồng bộ sửa đổi từ bản dựng
về source Git. Công cụ không build IPA; nếu dừng giữa chừng giữ dấu chưa xong.

Đối chiếu mốc ban đầu: không thiếu file theo tham chiếu của project cũ nhưng
so APK vẫn thiếu theo tên 68 script, 94 object và 369 event, thiếu 111 sprite
và 24 sprite cùng tên khác metadata. Đây chỉ là đối chiếu tên/file/metadata,
không phải bằng chứng hành vi bằng nhau. CI workbench `44885131061` đạt, local
129 test đạt, 12 bỏ qua do thiếu đầu vào tùy chọn. Sprite lệch/vệt màu trên
thiết bị và gameplay/iOS vẫn chưa được xửa hoặc xác nhận; chưa có IPA mới.

### Phục hồi nhóm frame còn thiếu trong source

Đã bổ sung 47 frame từ atlas APK vào 9 sprite đã tồn tại trong nền GMX:
`spr_action_button`, `spr_item_equip`, `spr_item_equip_small`, `spr_item_etc`,
`spr_item_etc_small`, `spr_item_weapon`, `spr_item_weapon_small`,
`spr_zombie_foot_left` và `spr_zombie_foot_right`. Các frame cũ cùng index của
9 sprite này đã được so trước: giống RGBA hoặc chỉ khác RGB tại alpha 0;
metadata đã so chỉ khác số frame. Không tự sửa `spr_ui_day` vì frame cũ đã khác
pixel nhìn thấy dù metadata chỉ khác số frame.

Các frame mới là PNG dựng lại từ các vùng atlas **không scale**, không phải
PNG gốc trước khi đóng gói. `tools/check_deadtown_restored_frames.py` kiểm cả
47 PNG, thứ tự/đường dẫn frame và các trường metadata đã chọn so với APK;
`tools/deadtown_sprite_pixels.py` kiểm thêm trong project được materialize.
CI `44885569922` đạt. Metadata khác nhau giảm từ 24 xuống 15 sprite có cùng
tên; vẫn thiếu theo tên 111 sprite, 68 script, 94 object và 369 event. Local
133 test đạt, 12 bỏ qua do thiếu đầu vào tùy chọn.

Đây mới là dữ liệu hình ảnh và đối chiếu tĩnh: chưa xác nhận collision mask
sau biên dịch, thời gian animation, UI, logic game, kết quả render hay iPhone.
RGB trong suốt ngoài vùng atlas cắt là không biết; không coi việc này là sửa
lỗi sprite lệch/vệt màu. Bản source và IPA hoàn chỉnh vẫn chưa có.

### Tiếp tục các frame của sprite đã có

Đã bổ sung thêm 16 frame cho 8 sprite còn thiếu frame cùng tên, gồm nhóm item
use, parcel, save button, skills, UI buff, UI health và UI day. Với 7 sprite
có bbox số khác APK, giữ bbox GMX cũ và ghi rõ khác biệt, không tự suy ra mask
va chạm. `spr_ui_day` có frame 0 cũ khác pixel nhìn thấy: ảnh đó được thay
bằng bản dựng lại từ atlas APK trong asset overlay, còn ảnh cũ trong đầu vào
GMX ghim không bị sửa.

Bốn frame 0 cũ khác pixel nhìn thấy của `ih_dagger`, `spr_event_eng`,
`spr_event_kor`, `spr_gps_sign` cũng được thay bằng ảnh dựng lại trong overlay;
bbox khác của `ih_dagger` vẫn giữ nguyên. Tổng cộng từ đầu đợt đã thêm 63 frame
thiếu và thay 5 frame cũ, kiểm tĩnh 68 ảnh của 21 sprite. Các PNG được mã hóa
lại; RGB trong suốt ngoài vùng atlas không biết.

CI `44886967353` đạt: trong **291 sprite cùng tên**, không còn frame thừa ở
một trong hai phía theo phép so số frame; 289 cặp frame RGBA giống bản dựng
atlas, 517 chỉ khác RGB ở pixel alpha 0 và 3 cặp khác kích thước. Không kết
luận từ đó rằng 111 sprite thiếu theo tên đã được phục hồi. Còn 14 sprite cùng
tên khác các trường metadata được kiểm; collision mask/timing/render và game
iPhone chưa kiểm. 133 test local đạt, 12 bỏ qua do thiếu đầu vào tùy chọn;
chưa tạo IPA, chưa chứng minh sửa lỗi sprite lệch/vệt màu.

### Kích thước hai sprite và thứ tự tài nguyên

Đã thay ảnh, kích thước, điểm neo và bbox số của `spr_part_bull` và
`spr_setting_cradits` trong project thử bằng các giá trị đối chiếu được từ APK;
3 frame PNG được dựng lại từ atlas không scale. Đây là thay đổi có thể ảnh
hưởng kích thước/va chạm và bố cục, chưa xác nhận đúng trong game sau biên
dịch. Ảnh cũ trong đầu vào ghim vẫn được giữ nguyên. Trong 291 sprite cùng tên,
809 cặp frame hiện phân loại thành 292 RGBA khớp bản dựng atlas và 517 chỉ khác
RGB tại alpha 0; không còn cặp khác kích thước trong phép so này. 12 sprite
cùng tên vẫn khác một số metadata. 111 sprite APK chưa có tên trong project.

Trước khi thêm các sprite thiếu, `tools/deadtown_sprite_order_evidence.py` so
thứ tự bảng SPRT APK với thứ tự khai báo XML GMX: trong 291 tên chung có 32 tên
khác vị trí tương đối, 188 cặp đảo thứ tự; ví dụ `spr_player` ở index APK 182
và thứ tự khai báo GMX 154. **Thứ tự XML không được chứng minh là ID do
GameMaker biên dịch**, nên không được dùng phép so này để tự ý đổi ID hay kết
luận lỗi trên iPhone. Cần quan sát project sau biên dịch và kiểm những chỗ dùng
ID số trước khi đưa thêm nhóm tài nguyên lớn.

CI source `44888154327` đạt; local 137 test đạt, 12 bỏ qua do thiếu đầu vào tùy
chọn. Vẫn thiếu logic native, chưa kiểm collision/animation/UI/gameplay trên
thiết bị, chưa có source hoàn chỉnh hoặc IPA mới.
