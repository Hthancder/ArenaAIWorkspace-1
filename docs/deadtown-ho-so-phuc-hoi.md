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

### Thử compile GML hiện tại vào VM disposable

CI `44890519123` dựng một bản dữ liệu VM **chỉ để chẩn đoán**, không tạo IPA.
Bộ kiểm đã sửa và đối chiếu SHA-256 thật của `assets/game.droid`; lần thử đầu
`44890283800` thất bại vì chuỗi hash trong workflow bị gõ sai, không phải vì
đã tìm được lỗi game. Bản thử dùng APK đã ghim, UndertaleModTool 0.9.2.0 và
runner desktop tại `e7121381d38b03a24242812fc22b0a7386d545c6`.

- UTMT báo compile thành công 138 file script nguồn và 538 body sự kiện chuyển
  từ GMX; 503 sự kiện được gắn vào object cùng tên, 35 liên kết bỏ qua vì
  object/đích collision không có. Có 68 script APK vắng tên trong nguồn, 14
  script nguồn không có tên trong APK, và 68 tham chiếu native không giải quyết
  được bị xóa khỏi bản thử. Đó không phải logic đã phục hồi.
- Thứ tự/tên 402 sprite, 240 object, 15 room cùng metadata/mask sprite được
  phép so kiểm và 6 atlas PNG giữ như APK; bảng script thành 206 thay vì 192.
  Thử nghiệm **không dùng PNG overlay của source**, không chứng minh GameMaker
  sẽ gán ID hoặc dựng tài nguyên như thế.
- Headless boot báo tới frame 300 tại `rom_lobby`, 15 instance; kịch bản cưỡng
  bức chuyển sang `rom_play` báo frame 360, 1.682 instance. Cả hai báo 0 draw
  call ở điểm đo headless, vì vậy không có bằng chứng hình ảnh hay UI tại đây.
  Không có dòng lỗi GML/unknown function được ghi trong các bước chạy này;
  không có nghĩa là tất cả event chạy hoặc không có lỗi trong gameplay khác.
  Runner báo 2 hàm chưa hỗ trợ (`audio_debug`, `draw_enable_drawevent`) và
  nhiều extension trả giá trị giả; danh sách chi tiết nằm trong log/report CI.
- Runner có thể bắt lỗi GML rồi tiếp tục và log có thể bị hạn chế. Hai kịch bản
  không kiểm các màn chơi/tương tác/save hay hành vi tự nhiên; số instance cũng
  không khẳng định đúng hay sai nếu chưa có mốc đối chiếu. Không xem CI xanh là
  chứng nhận gameplay, va chạm, sửa sprite/vệt màu hoặc kiểm thử iPhone.

Nguồn đầy đủ và IPA đạt yêu cầu vẫn chưa có; cần khôi phục logic thiếu dựa trên
bằng chứng và kiểm thật trên thiết bị sau khi có bản đủ điều kiện.

### Đối chiếu cấu hình và vị trí room

`tools/deadtown_room_evidence.py` đọc ROOM của APK ghim (GMS 1, bytecode 15)
so với các room được khai báo trong GMX. Có 7 room chung, còn thiếu theo tên:
`rom_multi_lobby`, `rom_multi_login`, `rom_multi_room`, `rom_play_defence`,
`rom_play_sewer`, `rom_setting_display`, `rom_setting_effect`, `rom_setting_save`.
So sánh giá trị tĩnh đã chọn, view, background và đa tập vị trí/biến đổi của
instance, tile; không so ID/thứ tự instance hoặc tile, pixel tile, mã khởi tạo,
physics, logic runtime hay iOS.

Trong `rom_play`, view 0 APK bắt đầu với view **1232×693**, port **1334×750**;
GMX cũ ghi view **1334×750**, cùng port. Đã đổi đúng hai số wview/hview trong
source sang giá trị APK, giữ nguyên port và các view khác. `sys_view` nguồn
đọc các giá trị ban đầu rồi có thể tính lại theo tỉ lệ màn hình và resize
surface: thay đổi này có thể ảnh hưởng khung nhìn/zoom, nhưng chưa được kiểm
trong GameMaker hoặc iPhone, không chứng minh là nguyên nhân hay cách sửa lỗi
sprite lệch/vệt màu ở IPA test 1–3. Không thay đổi các bản IPA đã gửi.

Sau thay đổi, 8 view và background trong 7 room chung khớp theo các trường đã
so. Room chơi có 1.664 instance APK, 1.658 trong GMX, 1.658 trùng đa tập thuộc
tính đã chọn; APK có thêm bốn `obj_sewer_door1`–`4`, `sys_game_type`,
`sys_test`. 17.175 tile room chơi trùng đa tập vị trí, background, vùng nguồn,
kích thước, depth, scale và màu; không so ID/thứ tự hoặc pixel. Room lobby:
13 APK so với 7 GMX, 5 placement trùng; setting: 10 so với 14, 3 trùng; shop:
7 và 7, 6 trùng. Không tự thêm/thay instance vì có object/logic bị thiếu và các
thay đổi offline có chủ đích; không suy ra hai bản gameplay tương đương.

Local chạy 144 test, 12 bỏ qua do đầu vào tùy chọn; workspace materialize vẫn
`INCOMPLETE_NOT_FOR_RELEASE`. Báo cáo chi tiết được workflow source tạo lại;
chưa có IPA mới.

### Object cha và các phụ thuộc room còn thiếu

Đối chiếu trường mặc định OBJT với các object **khai báo** trong project qua
`tools/deadtown_object_evidence.py`: sprite, visible, solid, depth, persistent,
parent, mask và cờ physics. Tên tham chiếu được giải theo bảng từng bên, không
giả định ID sau biên dịch trùng APK. Trước thay đổi 146 object cùng tên có 5
khác các trường này; hai object `obj_gps` và `obj_trap` có parent APK là
`par_action_nosolid`, nhưng GMX không có parent đó.

Đã thêm `par_action_nosolid` vào cuối danh sách object GMX, với các trường đã
so khớp APK; 12 nhóm sự kiện trong OBJT APK đều có 0 event và bản nguồn cũng
không khai báo event. Gắn parent đó cho `obj_gps` và `obj_trap`. Việc này chỉ
phục hồi cấu trúc/hệ phân cấp ban đầu, **không** khôi phục các phần logic mới
sử dụng nhóm này; source `obj_player` cũ vẫn xét nhóm `par_action`, không suy
ra tương đương APK. Thứ tự khai báo không bảo đảm ID GameMaker; chưa build bằng
GameMaker hay kiểm hành vi/va chạm. Không coi đây là sửa lỗi hình ảnh iPhone.

Sau thay đổi: 147 object khai báo cùng tên, 144 khớp các trường đã chọn; ba
khác biệt còn giữ nguyên gồm sprite của `obj_lobby_ach`, `obj_lobby_leader`
(sprite APK chưa có trong source) và cờ solid của `sys_player_equipment` (chưa
đổi vì ảnh hưởng hành vi chưa được kiểm). Trong toàn bộ file nguồn, 93 object
APK còn thiếu theo tên; 369 event key, 68 script và 111 sprite vẫn thiếu. Tên
trùng không xác nhận event/logic giống nhau.

Báo cáo room mở rộng để liệt kê phụ thuộc các room chưa có: ví dụ
`rom_play_defence` có 56 instance/239 tile trong APK, 29 instance tham chiếu
các object chưa khai báo; `rom_play_sewer` có 14 instance, 6 instance thiếu
object tương ứng. Ba room settings thiếu 3, 7 và 14 instance tương ứng theo
object chưa khai báo. Không thêm room rỗng hoặc object giả chỉ để giảm số thiếu;
không phục hồi được hành vi từ vị trí tĩnh.

### Ba object không có event riêng và sprite nhà phòng thủ

Trong 93 object APK chưa có theo tên ở mốc trước, có ba object mà cả 12 danh
sách event OBJT đều rỗng: `par_defence_shop`, `par_map_door`,
`obj_defence_house`. Đã thêm cả ba vào cuối danh sách object GMX; giá trị tĩnh
sprite/mask/parent/visible/solid/depth/persistent/physics được so với APK.
`par_defence_shop` kế thừa `par_action_nosolid`, dùng `mask_24_24` đã có;
`par_map_door` không có parent; `obj_defence_house` kế thừa `par_solid` và dùng
sprite mới `spr_defence_house`. Không có event riêng không có nghĩa là không có
hành vi: object nhà kế thừa event từ parent, mà logic parent GMX chưa chứng
minh tương đương native, và những object con khác vẫn chưa được phục hồi.

Sprite `spr_defence_house` có kích thước 501×276, gốc (250,138), một frame;
PNG được dựng lại từ vùng atlas không scale, pixel được kiểm so sánh với APK.
Native có một mask không đều; mô hình tĩnh MSB-first từ alpha PNG > 128 cho
bytes giống mask APK, với SHA-256
`8551330a71c1e9b6890af57a11ec08fd39aa25e78b3ec69dd761d8cc13ff2f5e`.
Descriptor đặt `colkind=0`, `coltolerance=128`, `sepmasks=-1` như một **ứng
viên**, không khẳng định GameMaker sẽ tạo lại cùng mask hay các va chạm đúng;
phải kiểm đầu ra compiler và runtime. PNG đã mã hóa lại và RGB trong suốt ngoài
vùng atlas không xác định.

Trong project mới, còn thiếu theo tên 90 object, 110 sprite, 68 script, 369
khóa event; 8 room chưa có. `rom_play_defence` vẫn thiếu 28 instance do object
không khai báo; chưa thêm room và không khẳng định tính năng phòng thủ hoạt
động. 292 sprite chung, 810 cặp frame được so: 293 RGBA trùng bản dựng atlas,
517 chỉ khác RGB tại alpha 0. Trong 150 object khai báo cùng tên, 3 vẫn khác
trường mặc định được so. Việc thêm sprite vào cuối XML không làm xáo trộn thứ
tự khai báo cũ nhưng làm 191 vị trí tương đối và 379 cặp đảo so với thứ tự APK
trong tập 292 tên chung; XML ordinal không phải ID compiler được quan sát.
Cần kiểm build thật trước khi đánh giá an toàn hoặc equivalence.

Chưa có kiểm trên GameMaker/iPhone, chưa chứng minh sửa lỗi sprite/vệt màu,
và chưa có IPA mới.

### Bộ ứng viên sprite và bốn mask chưa giải quyết

Tiếp tục theo hướng có thể đối chiếu lại, đã thêm 105 sprite còn thiếu gồm 206
frame atlas **không scale**. Với từng sprite, dữ liệu APK có đúng một mask, dạng
chữ nhật khớp bbox theo cách đọc bit MSB-first; hợp alpha khác 0 của các frame
cũng có bbox khớp. `tools/deadtown_rect_sprite_candidates.py` tạo ứng viên vào
thư mục mới không ghi đè và kiểm descriptor/ảnh trong source với APK đã ghim.
105 descriptor chọn colkind chữ nhật, tolerance 0 và metadata đã đọc; đây là
**giả thuyết compile**, không xác nhận compiler tạo mask, cách texture packing,
ID hoặc render giống APK. Ảnh PNG được mã hóa lại, RGB trong suốt ngoài vùng
atlas không xác định. Những sprite này vẫn không có nghĩa là object/logic sử
dụng chúng đã được phục hồi; sprite multiplayer không biến game thành online.

Sprite `mask_noone` là trường hợp scale: atlas 32×32 hướng tới vùng 1×1, nhưng
cả vùng atlas RGBA và native packed mask đều toàn byte 0. Đã tạo ảnh nguồn
32×32 trong suốt và descriptor ứng viên, với bộ kiểm chuyên biệt; so frame tổng
quát vẫn phân loại **scaled_not_compared**, không tự tuyên bố đã so phép scale
hay mask do compiler tạo. Vẫn cần kiểm output compiler và runtime.

Bốn sprite chưa được khai báo trong project: `spr_map_info`, `ih_slingshot`,
`spr_multi_slot_kind`, `spr_player_kind`. 12 frame và bốn mask nguyên gốc của
chúng được lưu riêng trong `deadtown-source/unresolved/sprites/` với manifest và
`RESEARCH-ONLY.txt`; tool `deadtown_unresolved_sprites.py` kiểm lại với APK.
Trong mô hình tĩnh hợp alpha các frame với mọi ngưỡng 0–255, sai số nhỏ nhất so
với native mask lần lượt 1007, 380, 1125, 246 bit; không tự chọn mask chữ nhật
hoặc precise rồi coi là đúng. Các file lưu riêng không được materialize như
sprite hoạt động. Đây không loại trừ cách dựng mask khác hoặc công cụ phù hợp.

Tính đến mốc này project có 398/402 sprite APK theo tên, 1.017 frame chung:
499 RGBA khớp bản dựng atlas, 517 chỉ khác RGB dưới alpha 0, 1 frame scale chưa
được phép so tổng quát. Có 279 ảnh ứng viên trong overlay (271 frame bổ sung,
8 frame cũ được thay) cho 130 sprite, đã tính cả `mask_noone`; bốn sprite
nghiên cứu riêng không được tính vào project. 12 sprite chung vẫn khác metadata
được so; 90 object, 68 script, 369 event key và 8 room chưa có tương ứng.
Trong 398 tên sprite chung, thứ tự XML có 396 thứ hạng tương đối khác và 7256
cặp đảo so với APK; thêm ở cuối XML giữ thứ tự XML cũ nhưng không chứng minh ID
compiler, do vậy không thể kết luận an toàn khi build. Không tự thay sprite của
các object lobby tương ứng chỉ vì đã có ảnh: code cũ dùng index 3/9 và 4/10,
trong khi hai sprite mới chỉ có hai frame.

Đã kiểm tra thêm hai bản sao nguồn công khai tìm được: nhánh `main` của
`Workspaacing/deadtown` cùng commit `5e3d798f914c8cd3b066c8289323005d63111f37`
như input cũ. Tree `lmppgms/deadtown` commit
`a6baa018914f0e6e7f8ac1cb69b89ce3fd4834a4` có 2.406 file dưới `deadtown.gmx`:
2.030 file input cũ đều có Git blob ID giống nhau, 376 file còn lại là bổ sung,
bao gồm audio nguồn/extension, không phải bằng chứng có GML 1.4.2 mới. Không
thay audio APK đã trích bằng audio từ bản sao này và không lấy extension ads
vào project. Phép tìm kiếm không chứng minh không tồn tại nguồn khác.

Chưa có source đầy đủ hay IPA đạt yêu cầu; chưa kiểm GameMaker/iPhone hoặc sửa
được lỗi sprite lệch và vệt màu trên thiết bị.

### Âm thanh thứ 90

Đã thêm descriptor ứng viên `snd_eating` vào source và đặt WAV trích trực tiếp
APK trong `assets/sound/audio/snd_eating.wav`. Bytes khớp payload APK, SHA-256
`27d5de6a73dee0cfcc2e604d2c14cf68a0a5fa88080054f8941f89807deb4cfe`;
WAV PCM mono 16-bit 44.100 Hz, 9.585 mẫu, không chuyển mã. Native SOND báo
flags 101, effects 0, volume 1, pitch 0, audio group 1; descriptor thử chọn
không nén/không stream và group 1. Các cờ/thiết lập khi GameMaker compile và
việc phát đúng trong game/iOS chưa được xác nhận. Chưa thêm code sử dụng sound.

Dựng workspace hiện báo 90 sound có file tham chiếu; `status.json` vẫn đếm 89
ở trường `audio_descriptors_populated_without_transcoding`, vì đó là số sound
cấp tự động cho nền GMX trước khi overlay, không tính WAV mới. Kiểm thử so
byte file kết quả với overlay; 90 sound theo tên không chứng minh runtime hay
trật tự ID sound sau compile.

### Lưu dữ liệu tĩnh tám room chưa phục hồi

`deadtown-source/unresolved/rooms/rooms.json` lưu riêng các trường tĩnh đã đọc
của tám room chưa có trong project: thứ tự và index room native, caption,
kích thước/tốc độ/các cờ được chọn, views, backgrounds, 120 instance và 239
tile theo thứ tự, gồm ID và index tham chiếu code. Tất cả tám room và 120
instance có index code −1 trong APK; điều này không khôi phục hoặc chứng minh
hành vi các object, vốn có sự kiện và nhiều object vẫn thiếu. 239 tile đều
thuộc `rom_play_defence` (56 instance); `rom_play_sewer` có 14 instance.

Bộ kiểm `tools/deadtown_unresolved_rooms.py verify` đọc lại APK ghim, so toàn
bộ dữ liệu đã lưu; extraction không ghi đè thư mục đã có. Các trường chưa đọc
(bao gồm physics/flags khác), tile pixels, nội dung GML, mã native, trạng thái
runtime và ID sau compiler không được kiểm chứng. Đây là dữ liệu nghiên cứu,
không phải GMX room, không materialize vào project; vẫn thiếu 8 room theo tên.

### Đối chiếu metadata và alpha cho 12 sprite cũ

Đã cập nhật các giá trị bbox lưu trong GMX cho `ih_dagger`, `spr_item_use`,
`spr_item_use_small`, `spr_parcel`, `spr_save_button`, `spr_skills`,
`spr_ui_buff`, `spr_ui_health` theo metadata APK. Các descriptor vẫn giữ
`bboxmode=0`, `colkind=1`, tolerance 0 như trước. Trên workspace được materialize,
đối chiếu alpha của mọi frame với atlas APK và tính hộp bao hợp alpha khác 0:
89 frame đều có alpha giống atlas và tám bbox hợp khớp số APK. Việc sửa số
lưu trong descriptor không chứng minh compiler sẽ sử dụng hay sinh ra cùng mask.
Đặc biệt native masks của `spr_item_use`, `spr_item_use_small`, `spr_ui_buff`
được đọc là không hình chữ nhật, vì vậy không coi cài đặt `colkind=1` cũ là
bằng chứng mask hoặc va chạm khớp; giữ lại cờ cũ, không đoán kiểu collision.

Bốn sprite `mask_200_100`, `mask_40_40`, `mask_arrow`, `mask_player` có một
frame không scale, alpha toàn 255 và native mask kín canvas theo mô hình bit
MSB-first. Đã điều chỉnh `sepmasks` của hai sprite đầu và `bboxmode` của hai
sprite sau (cùng `sepmasks` của `mask_arrow`) để khớp giá trị đã đọc từ APK;
giữ `colkind`/tolerance cũ. Đây vẫn là ứng viên, không xác nhận ý nghĩa đầy đủ
của các cờ sau biên dịch hay hành vi collision trên thiết bị.

`tools/check_deadtown_bbox_candidates.py` kiểm tra 12 descriptor, alpha của
93 frame đã materialize, bbox hợp và các điều kiện của bốn mask đơn frame;
test cũng sửa alpha/metadata để xác nhận công cụ báo sai. Metadata được so của
398 sprite cùng tên hiện đều bằng APK; vẫn có 4 sprite chưa khai báo, và so
metadata **không** đồng nghĩa khôi phục hoàn toàn hình ảnh, mask, animation,
resource ID, renderer hoặc iOS.

### Ứng viên End Step boss 2 theo khoảng cách

Native `obj_boss2:Step:2` tại `0x712520` lấy `x,y` của instance và
`x,y` của object ID 142 (`obj_player`), gọi `point_distance` và hủy boss
khi khoảng cách lớn hơn 8000 theo ngưỡng epsilon hiện hành. Đã thêm event
End Step ứng viên; verifier `tools/deadtown_boss2_distance_evidence.py` ghim
hash export, OBJT, relocation, thứ tự 4 tham số, hằng số và nhánh hủy. So sánh
native dùng epsilon (khởi tạo tĩnh 1e-10), nên GML có thể khác gần ranh giới;
không thêm guard tồn tại player vì native không cho thấy guard trong event này.
Chưa xác minh trường hợp thiếu player, NaN, thừa kế, gameplay hay iOS. Probe
VM cô lập thay Create/Step/Destroy của player và boss bằng stub; không đại diện
toàn bộ gameplay. CI `45025948709` probe boss 2 pass.

Event cha `par_boss:Step:2` tại `0x709a30` dùng khoảng cách đến `xstart,ystart`,
nếu vượt 8000 theo epsilon thì hủy instance rồi gọi
`ui_message_type(lang_get("The boss fled"))`. Verifier ghim cả export cha,
relocation, thứ tự tham số, thông điệp và call; đã thêm event ứng viên. Chưa
có probe VM cho event cha hoặc xác minh thực thi sau `instance_destroy` trên
native/iOS. `obj_boss2` có End Step riêng, không tự thêm `event_inherited()`;
hành vi thừa kế ở runner chưa được xác minh. Audit sau thay đổi thiếu 357 event
key; trùng key không chứng minh toàn bộ logic đã phục hồi.

### Sáu ứng viên dọn ánh sáng khi Destroy

Đã thêm Destroy 0 cho `obj_bettery`, `obj_lightaction`, `obj_cooker`,
`obj_craftdesk`, `obj_craftdesk_pro`, `obj_brazier_electric`: kiểm tra light
được liên kết còn tồn tại rồi hủy các instance được tham chiếu. Native ARM32
của cả sáu event cùng có chuỗi `instance_exists`, with iterator,
`instance_destroy`; hai object đầu dùng slot 344, bốn object sau dùng slot
1162. Step native của từng object có cùng mẫu dọn, khớp với đoạn source cũ
sử dụng `light_obj` hoặc `craft_light_obj`. Ánh xạ tên là **ứng viên**,
không phải tên biến native được chứng minh. Bộ kiểm
`tools/deadtown_light_cleanup_evidence.py` ghim hash của 12 export, call,
instruction, inventory và source; test sửa từng event. Probe desktop riêng
thay Create của object và light bằng stub, không chạy gameplay thật. CI VM
`45025085073` xác nhận cả sáu light tồn tại trước và không còn sau khi hủy
owner; native `45025085016` và workbench `45025084992` cũng pass. Thứ tự
Destroy/Step, hiệu ứng dọn trùng, lifecycle Android/iOS và toàn bộ object
vẫn chưa được xác minh. Audit sau thay đổi thiếu 359 event key; khớp key
không chứng minh khôi phục đầy đủ sự kiện.

### Ứng viên đảo hướng tạm thời của xúc tu boss 2

APK ARM32 `obj_boss2_ten:Create:0` tại `0x714ef4` đặt slot instance 1201
về 0, sau đó chọn từ bảng hằng `[1,0,0]`; khi kết quả > 0,5, slot thành 1 và
`alarm[0]` được đặt 20. `Alarm:0` tại `0x715b08` đặt slot này về 0.
Trong `Step:0` tại `0x715bd8`, slot 1201 > 0,5 khiến slot 1088 nhân -1
trước khi tiếp tục tính tọa độ. Mẫu khởi tạo slot 1088 về 0, gán từ slot được
khởi tạo 18, rồi sử dụng như góc bù khớp cấu trúc `go_dir`/`body_angle_max`
trong source cũ. Ánh xạ đó là **ứng viên**, không phải tên native chứng minh.

Đã thêm `__dt_reverse_turn` (alias tự đặt), nhánh khởi tạo, một đoạn đảo
`go_dir` và event Alarm 0. Bộ `tools/deadtown_boss2_turn_evidence.py` ghim
hash ba export, các lệnh ARM, relocation và bảng hằng chọn, đồng thời kiểm
vị trí các fragment source. Probe VM dùng `choose` giả và chạy fragment riêng,
không chạy toàn event hay bộ lập lịch thật. CI `45019864629` pass các marker
fragment; CI workbench `45019864696` và native `45019864590` cũng pass.
Probe scheduler desktop riêng chạy Alarm 0, với Create rút còn fragment,
ép nhánh chọn 1, bỏ Step và đặt instance persistent. CI `45020401098` pass:
bắt đầu `1:20`, cờ về 0 ở bước 20, giá trị alarm vừa quan sát trước đó là 1;
trong frame kích hoạt, runner báo alarm 0. CI trước `45020208679` fail vì
checker giả định alarm lúc đó phải là -1; checker đã sửa để chấp nhận 0 hoặc
-1, không sửa gameplay. Đối chiếu tiếp Create cho thấy slot 180 khởi tạo 8;
Step cộng slot này vào slot được khởi tạo 0 và so với slot độ dài 35, phù hợp
với `move_position += move_speed` trong source cũ. Sau lựa chọn đảo hướng,
native gọi chọn riêng từ bảng `[1,0,0,0,0]`; nếu > 0,5 thì đặt slot 180 bằng 9.
Source ứng viên vì vậy cập nhật `move_speed` 7 thành 8 và thêm nhánh 9, đặt sau
nhánh đảo hướng. Bộ kiểm ARM ghim instruction, call và relocation của cả hai
bảng; probe VM ép kết quả lựa chọn, không kiểm phân bố RNG thật. Ánh xạ tên
biến vẫn là suy luận có bằng chứng. CI workbench `45021888216` và VM
`45021888187` và native `45021888168` pass cho thay đổi tốc độ.

Đối chiếu tiếp cho thấy Create ghi slot 1197 bằng 0, slot 1199 bằng 7
và slot 1200 bằng 0,4;
nhánh Step so slot 1197 gần 0 rồi trừ slot 1200 chia 2 khỏi slot 28 của
object 142 (`obj_player`). Bộ poison evidence độc lập liên hệ slot 28 với
key lưu `hp`. Đây là bằng chứng một phần để ánh xạ các biến source cũ
`type`, `blood_speed`, `obj_player.hp`; đã sửa `blood_speed` từ 0,5 thành
0,4. Verifier ghim hash export, lệnh ghi/đọc, phép chia/trừ, object ID và
fragment source nhánh type 0; test sửa giá trị và nhánh. So sánh native dùng
ngưỡng epsilon, và các nhánh type 1/2, điều kiện dẫn tới sát thương, hành vi
runtime và phần còn lại Create/Step chưa được xác minh hoàn toàn. Không suy ra
boss, RNG, gameplay hay iOS đã hoạt động đúng. Audit mới thiếu 56
script, 90 object, 357 event key, 4 sprite và 8 room theo tên/key; 0 file tham
chiếu thiếu. Trùng key không chứng minh toàn event tương đương.

### Bổ sung ứng viên cài đặt hiệu ứng và gate particle

Đã đối chiếu bảy global slot với key INI và mặc định, thêm alias trung tính
vào setting_load/save. Slot 49 tương ứng `effect/particle` cũng được bốn script
particle đọc trước khi vào phần xử lý; source cũ thêm gate 0,5. Thêm gate
bóng ở tám Draw event (`par_solid`, `par_vehicle`, `obj_parcel`, `par_building`,
`obj_player` và ba object `par_action`) theo slot 86; không tắt các lệnh vẽ foreground.
Ứng viên Draw của player cũng gate feedback di chuyển bằng slot 82 và kết quả
`gp_connect_check`. Room Start của `sys_global` có ứng viên truyền slot 83 vào
`texture_set_interpolation`. Script `draw_line_crosshair` cũng đã có ứng viên
riêng từ ARM32, nhưng chưa được nối vào Draw GUI cũ. Kiểm tĩnh và VM mock, cùng giới hạn, được trình bày tại
[deadtown-settings-particle.md](deadtown-settings-particle.md). Ở commit
`b81a274`, 221 test local đạt (12 bỏ qua); CI source VM `45003419408`,
workbench `45003419357` và ARM `45003419430` đạt. Audit so tên/key còn thiếu
56 script, 90 object, 366 event key, 4 sprite và 8 room, không báo file tham
chiếu bị thiếu. Đây không xác nhận UI, hiệu ứng thực, gameplay hay iOS.

### Bổ sung ứng viên cài đặt và kết nối gamepad

Đã đối chiếu global slot 88 với key INI `control/gamepad` trong ARM của
`setting_load`/`setting_save` và thêm alias trung tính cùng script ứng viên
`gp_connect_check`. Script quét mọi thiết bị kết nối, đặt deadzone 0,2 và trả
cờ có thiết bị; nó chỉ chạy theo gate native `os_type == 4` và cài đặt. CI ARM `44983267378`, workbench `44983267306` và VM giả lập
`44983566301` đạt; kiểm toán tại mốc đó thiếu 57 script, 90 object, 367 event key,
4 sprite và 8 room so tên/key. Xem
[deadtown-gamepad-connect.md](deadtown-gamepad-connect.md) về giới hạn enum,
giá trị bất thường, UI thiếu và kiểm thử giả lập; không suy ra iOS hoạt động.

### Kiểm tra bổ sung lịch item

VM desktop đã kiểm 900 bước trong điều kiện cô lập: hai instance thử persistent,
Step item bị thay no-op chỉ trong probe; item có cờ biến mất tại bước 900,
item không cờ còn sau bước 905. Chi tiết và giới hạn trong
[deadtown-item-alarm-schedule.md](deadtown-item-alarm-schedule.md); chưa chứng minh
lịch runtime native, gameplay hay iOS, và Alarm 1 vẫn chưa phục hồi.

### Dấu vết một script kiểm room trong ARM32

`tools/deadtown_room_check_evidence.py` ghim APK/library, xác nhận export
`check_room_is_multiplay_room`, relocation `g_VAR_room`, lời gọi đọc giá trị,
so sánh và hai nhánh trả real 0/1. Với giá trị hữu hạn, mã ARM so
`abs(room - 14)` với epsilon hiện tại; initializer tĩnh của epsilon là `1e-10`,
nhưng có thể đổi khi chạy. ROOM table APK đặt `rom_play_defence` ở index 14.
Tên script không đủ chứng minh mục đích hoặc toàn bộ hành vi multiplayer.
Callgraph tĩnh còn ghi hai lời gọi ứng viên từ `multi_logic_play` và
`multi_logic_room`, không chứng minh đường chạy thực tế.

Tại mốc phân tích này chưa thêm script vì `rom_play_defence` và logic tương
ứng còn thiếu, ID native 14 không bảo đảm giữ nguyên khi compile GMX, và phép
so tĩnh không xác nhận Android/iOS runtime. Sau đó đã thêm ứng viên dùng tên
room, không dùng số 14; xem mục “Kiểm tra room phòng thủ ứng viên” bên dưới.
Script vẫn chưa được coi là phục hồi hoàn chỉnh.

### Bốn event collision rỗng

Tiếp tục đối chiếu các event chưa có trong source: bảng OBJT của APK ghi
`obj_player` có collision với object index 184 (`par_action`) và một action
code; export ARM32 `gml_Object_obj_player_Collision_184` dài 4 byte và chỉ là
`bx lr` (không có thân lệnh). Đã thêm event tương ứng vào GMX với một code
comment-only, theo định dạng event rỗng sẵn có trong project. Phân biệt event
rỗng với không khai báo event là quan trọng khi có cơ chế kế thừa/dispatch,
nhưng chưa xác nhận GameMaker biên dịch hoặc dispatch tương đương.

Đã mở rộng kiểm tra sang ba event rỗng vốn có trong source: `obj_zombie4` với
`obj_player_body` (index 144), `obj_zombie5` với `par_action_door` (187) và
`par_action` (184). Cả ba export đều dài 4 byte `bx lr`, OBJT chứa một action
code và source chứa một comment-only action. `tools/deadtown_empty_collision_evidence.py`
kiểm SHA APK/library, event target, action tĩnh, export cùng bốn byte ARM và
source cho cả bốn event; test từ chối APK khác, descriptor bị đổi và ELF sai.
Đây không kiểm dispatch collision thực tế, behavior kế thừa, iOS hay gameplay.
Tại mốc bổ sung event player trước đây còn thiếu 368 event native, 90 object và
68 script theo tên/key; số hiện tại ở mục kiểm toán phía trên.

### Đối chiếu toàn bộ 90 sound của workspace

`tools/check_deadtown_sound_evidence.py` kiểm APK ghim và project đã materialize:
90 tên/descriptor, tham chiếu file và toàn bộ payload audio đều khớp byte APK;
`audioGroup`, `effects`, `volume` tương ứng cũng khớp. Phân bố group native
là 0:2, 1:86, 2:2; flags native 101:3, 103:87. Cấu hình GMX có 3 WAV không nén
và 87 Ogg nén tương ứng theo mô hình ứng viên, không suy ra ý nghĩa đầy đủ của
flags hoặc thiết lập compiler. Bộ test xác nhận phát hiện khi payload, group
hoặc cờ candidate bị thay đổi.

Phép so byte không decode audio, không xác nhận pitch runtime, audio group
loading, âm thanh sau GameMaker encode, thứ tự ID hoặc phát trên iPhone.
`audio_descriptors_populated_without_transcoding` trong status vẫn là 89 vì
đếm ở bước nền trước overlay, dù 90 file kết quả đã được so riêng.

### Background `tile_sewer` từ atlas

Đối chiếu BGND tìm thấy 30 tên trong APK, trong khi project cũ chỉ khai báo
29 và thiếu `tile_sewer`. Đã dựng ảnh 130×130 từ atlas 4 tại (1092,1384),
không scale/cắt bớt; pixel RGBA ảnh kết quả khớp vùng gốc. Ảnh PNG được mã hóa
lại. Thêm descriptor và khai báo background trong project; chia tile 128×128,
offset 0 được mượn từ `tile_basic` cùng kích thước, **chỉ là ứng viên** vì BGND
GMS1 không cung cấp các thiết lập editor đó. Không thêm hoặc khôi phục code
`sewer_map_init` hay room sewer, do đó ảnh hiện không chứng minh chế độ sewer
hoạt động.

`tools/deadtown_background_evidence.py` so 30 ảnh BGND đã materialize theo tên:
cả 30 RGBA exact với atlas, không có tên thiếu, nhưng không kiểm pixel sau
compile, padding, sampler, thiết lập editor, render hoặc gameplay. `tile_sewer`
ở native index 0 và ở vị trí XML 29: có 29 cặp đảo trong thứ tự XML so với APK.
Thêm ở cuối giữ nguyên thứ tự XML cũ, nhưng không chứng minh ID compiler hoặc
an toàn khi code dùng số ID trực tiếp; phải kiểm khi build. CI và test có đối
chiếu ảnh, thử đổi pixel và đường dẫn; không kiểm trên iOS.

Để tránh bỏ sót nhóm tài nguyên như trên, `status.json` của các workspace dựng
mới giờ còn báo số tên native thiếu cho background, room và sound. Hiện các số
này lần lượt là 0, 8 và 0; đếm tên không kiểm texture, âm thanh hoặc logic.

### Phục hồi atlas và bảng glyph font_24

FONT trong APK khai báo `font_24`, tên hiển thị `나눔고딕 ExtraBold`, cỡ 24,
2.499 glyph duy nhất; GMX cũ có 490 glyph và 490 ký tự là tập con của native.
Đối chiếu 490 glyph chung: kích thước, shift và offset giống nhau, pixel RGBA
trong từng hình chữ cũng giống; chỉ vị trí đóng gói atlas khác. Còn 2.009 glyph
native chưa có trong GMX cũ, phần lớn là Hangul/Jamo.

Đã dựng descriptor GMX ứng viên chứa đủ 2.499 bản ghi `(character, x, y, w, h,
shift, offset)` theo bảng native và 1.615 khoảng ký tự gộp; lưu font atlas
2048×2048 từ vùng FONT TPAG trong `assets/fonts/font_24.png`. Không đưa thêm
TTF vào project; PNG được mã hóa lại. Atlas candidate có SHA-256 trên raw RGBA
`6dd099d5bae4d540fe553890965f3f245927200718e0d0894bbf78cd795ee733`.
`tools/recover_deadtown_font.py` kiểm APK ghim, 490 glyph cũ, đọc lại toàn bộ
bảng native và atlas, sau đó kiểm candidate; test cố tình đổi glyph/atlas để
phát hiện sai. Audit hiện kiểm luôn file `font_data` mà descriptor tham chiếu.

Đây là phục hồi bitmap và metadata tĩnh, không phải font TTF gốc; chưa chứng
minh GameMaker giữ atlas này hay có font hệ thống phù hợp khi build, chưa kiểm
text shaping, cách đóng gói, runtime/iOS hay hiển thị tiếng Hàn trên thiết bị.

### Hai script phân loại vật phẩm ứng viên

Đã thêm `item_check_pet` và `item_check_skin` dựa trên phân tích ARM32 của
APK ghim. Với chỉ số số nguyên, hai hàm lần lượt trả 1 cho 17–22 và 23–26,
kể cả hai đầu; ngoài khoảng trả 0. Công cụ `tools/deadtown_item_kind_evidence.py`
kiểm export, địa chỉ, lời gọi chuyển REAL, chuỗi lệnh so sánh và relocation của
`g_GMLMathEpsilon` cùng giá trị khởi tạo `1e-10`. Quy tắc tĩnh với số hữu hạn
là `lower - value <= epsilon` và `value - upper <= epsilon`; epsilon có thể
thay đổi lúc chạy. GML dùng toán tử GameMaker thay vì hard-code epsilon, nên
không khẳng định tương đương với số thực sát biên, NaN, kiểu khác số hoặc
trường hợp thiếu đối số. Các phép thử Python kiểm mô hình và biên số nguyên;
workflow source VM có probe headless riêng cho các chỉ số nguyên quanh khoảng.
Probe chỉ chạy bản VM desktop bị instrument và thiếu nhiều hành vi; không phải
thực thi native Android, GameMaker compiler hay bằng chứng iOS/gameplay.
Số tên script native chưa có trong project là 66; trùng tên không chứng minh
hành vi, thứ tự resource hoặc tính tương thích toàn bộ.

### Màu GPS ngẫu nhiên ứng viên

Phân tích `gps_colour_random` ARM32: gọi `YYGML_irandom(255)`, chuyển kết quả
sang real, rồi truyền ba RValue theo thứ tự vào `g_FUNC_make_colour_hsv`: giá
trị vừa sinh, hằng 180 và hằng 120. Đã thêm GML ứng viên tương ứng và khai
báo trong project. `tools/deadtown_gps_colour_evidence.py` kiểm SHA APK, export,
bytes hàm, các lệnh tạo mảng đối số, relocation của hàm legacy và nội dung hai
RValue hằng. Đây là đối chiếu tĩnh, không chứng minh tương đương thuật toán RNG,
chuyển đổi HSV, compiler, ID resource hay runtime/iOS. Tên script native còn
thiếu hiện là 65; các code gọi GPS còn thiếu, chưa phục hồi gameplay.

### Chuỗi cơ bản ứng viên

`generate_basic_string` bắt đầu bằng chuỗi rỗng và nối chữ `A` 20 lần trong
ARM32; GML ứng viên trả chuỗi cố định 20 chữ A cho đường chạy bình thường.
Công cụ `tools/deadtown_basic_string_evidence.py` kiểm export, bytes hàm,
relocation và dữ liệu hai chuỗi, giá trị 20, nhánh vòng lặp và lời gọi tạo/nối
chuỗi. Kiểm tra này không chứng minh xử lý lỗi cấp phát, internals chuỗi, native
runtime, GameMaker compiler hoặc iOS. Probe VM desktop chỉ kiểm giá trị trả về
trong bản diagnostic bị instrument, không phải game hoàn chỉnh. Tên script
native còn thiếu trong project hiện là 64.

### Chuỗi ngẫu nhiên ứng viên

`generate_random_string` ARM32 bắt đầu bằng chuỗi rỗng, lặp 20 lần. Trong mỗi
lần lặp, native gọi lần lượt `irandom_range(65,90)`, `(97,122)`, `(48,57)`,
sau đó `choose` trong ba kết quả theo thứ tự ấy, gọi legacy `chr` rồi nối.
Ứng viên GML dùng ba biến tạm để giữ thứ tự phát sinh ngay cả khi compiler xử
lý đối số biểu thức khác nhau. `tools/deadtown_random_string_evidence.py` kiểm
hash, export, relocation `chr`, chuỗi rỗng, luồng lặp, thứ tự các lệnh và lời
gọi. Đây là phân tích tĩnh đường bình thường, không chứng minh thuật toán RNG,
`choose`, `chr`, xử lý lỗi, thứ tự resource hay hành vi của compiler/iOS.

Workflow VM có một bản dữ liệu **riêng** instrument `sys_global` để đặt lại
bốn seed, gọi hàm và lấy số ngẫu nhiên tiếp theo; so với chương trình tham
chiếu C++ dùng `Random.h` của runner desktop đã ghim. Cả hai phép thử dựa trên
cùng runner desktop, không chứng minh chuỗi hoặc trạng thái RNG của Android hay
iOS. Probe thay đổi seed và không được đóng gói thành game. Tên script native
còn thiếu theo đối chiếu project là 63; vẫn còn thiếu logic sử dụng chúng.

### Kiểm tra room phòng thủ ứng viên

`check_room_is_multiplay_room` native kiểm `room` với native room index 14;
bảng APK tại index đó là `rom_play_defence`, với tên room duy nhất trong bảng.
Không dùng số 14 trong GMX vì ID sau compile có thể khác. GML ứng viên dùng
`room_get_name(room) == "rom_play_defence"`; với room hợp lệ, tên room duy nhất
và epsilon mặc định `1e-10`, kết quả khớp phép so native trên 15 ID nguyên.
Nếu runtime đổi epsilon đủ lớn hoặc room/name lookup khác thường thì cách này
không nhất thiết tương đương; chưa kiểm compiler GameMaker hay native/iOS.
Project vẫn thiếu chính room phòng thủ và các hành vi multiplayer; thêm hàm
không làm chế độ này hoạt động. Công cụ static kiểm export, relocation epsilon,
bảng room và GML ứng viên. Workflow diagnostic có probe trên bản VM riêng với
room từ APK, thử chuyển cưỡng bức tới room phòng thủ; không phục hồi behavior
room đó. Tên script native chưa có trong project là 62.

### Bằng chứng deactivate_all_auto, chưa thêm script

ARM32 `deactivate_all_auto` đọc một slot 48 từ `g_pGlobal`, chuyển sang real và,
với giá trị hữu hạn lớn hơn 0,5, lần lượt gọi `instance_deactivate_all(1)`,
`instance_activate_object` với native object 38 (`sys_global`) và 74
(`sys_multi`). `tools/deadtown_deactivate_auto_evidence.py` ghim bytes, branch,
relocation của hai hàm và ba RValue hằng, đối chiếu bảng tên object APK. Không
xác định được tên global từ slot này, `sys_multi` cũng thiếu trong project; vì
vậy chưa thêm GML suy đoán. Các ID native không portable, và phân tích tĩnh
không chứng minh semantics active/deactive, thứ tự event hay runtime/iOS.

### Ứng viên một phần: item từ parcel có thời hạn

Đã phục hồi một nhánh nhỏ liên quan item rơi, không coi toàn bộ lifecycle là
hoàn chỉnh. `obj_item` native Create khởi tạo slot instance 1096 bằng 0, slot
1097 bằng real 900, đặt Alarm 0 theo slot 1097 và Alarm 1 bằng 1. Alarm 0 đọc
slot 1096, với real hữu hạn lớn hơn 0,5 gọi `instance_destroy()` trên self.
Trong một đường `obj_parcel` Step, native tạo object index 161 (`obj_item`),
giữ instance ID trả về và đặt slot 1096 của instance đó bằng 1. Tool
`tools/deadtown_item_lifetime_evidence.py` ghim SHA, export và bytes ba event,
đối chiếu object ID, các lệnh, call, và thanh ghi giữ ID giữa Create và setter.

Trong source, thêm biến **mới** `__dt_item_timed` làm alias nội bộ cho subset
này: Create đặt 0, Alarm 0 được đặt 900, parcel đặt 1 cho item mới, và Alarm 0
hủy item nếu cờ đúng. Đây không phải tên biến native đã được xác định; không
suy từ vị trí `g_Vars`. Các đường khác của native cũng có thể đặt cờ, native
Alarm 1 và logic item/parcel khác chưa được phục hồi hoặc chứng minh tương
đương. Probe VM riêng tạo ba item và gọi Alarm 0 **thủ công** để kiểm flag 0,
0,5, 1; kiểm giá trị alarm ban đầu 900. Nó không kiểm lịch chạy 900 bước,
luồng parcel đầy đủ, save, Android, GameMaker compiler hay iOS. 900 bước chỉ
khoảng 30 giây ở 30 bước/giây ổn định, không phải thời gian đo thực tế. Sau
khi thêm một event key, còn thiếu 367 key theo so tên; trùng key không chứng
minh event hoàn chỉnh.

Kết quả tại commit `1a436fd`: bộ kiểm thử local 202 test, 12 skip;
CI native `44913067792`, source-workbench `44913067864` và source-VM
`44913068178` thành công. VM xác nhận marker của phép gọi Alarm thủ công;
540 thân event dịch, 505 liên kết, 35 bỏ qua. Audit workbench không thấy file
được tham chiếu nào thiếu, nhưng vẫn thiếu 62 script, 90 object, 367 event key,
4 sprite và 8 room khi so tên/key với APK. Các số này không bảo đảm logic đã
khớp. Chưa build IPA mới, chưa xác minh gameplay hoặc iPhone.

### Ứng viên wrapper gamepad

Bốn export Android ARM32 `gp_button_check`, `gp_button_check_pressed`,
`gp_button_check_released`, `gp_axis_value` mỗi cái dài 1.812 byte, cùng cấu
trúc điều khiển. Khi `gamepad_is_supported()` đúng, native lấy số thiết bị một
lần, duyệt index tăng dần bắt đầu từ 0 và trả kết quả builtin tương ứng với
`(index, argument0)` ngay khi thiết bị đầu tiên báo kết nối. Nếu không hỗ trợ
hoặc không có thiết bị kết nối, native đi tới cuối mà không thấy lệnh ghi kết
quả rõ ràng. Source ứng viên cũng không thêm `return 0` vào đường này; giá trị
trả ngầm và tương thích compiler/runtime cần nghiên cứu tiếp.

`tools/deadtown_gamepad_evidence.py` ghim SHA của từng export và kiểm các
relocation builtin, lệnh/nhánh, truyền tham số; không thực thi native. Probe
VM riêng thay builtin bằng mock trong **bản sao tạm**, kiểm trường hợp không
hỗ trợ, số thiết bị 0 và hai thiết bị 1, 3 cùng kết nối: script phải dừng ở
thiết bị 1 và mỗi lần chỉ đọc số thiết bị một lần. Probe không kiểm tay cầm
thật, giá trị trả ngầm, native Android hay iOS; kết quả CI phải xem riêng.
Không có gọi tên trực tiếp bốn script này trong source hiện tại, nên không coi
chúng đã khôi phục điều khiển game. Dự kiến còn thiếu 58 script so tên, các
số khác giữ nguyên; so tên không chứng minh tương đương logic.

Tại `f7b71c7`, 206 test local thành công (12 skip), CI native
`44914925038`, source-workbench `44914924947` và VM `44914924944` thành công;
probe gamepad mock cũng qua ba marker. Audit thực tế xác nhận 58 script thiếu
so tên. VM dịch 148 file script, liên kết 505 event, bỏ qua 35. Không có kết
quả này chứng minh tay cầm vật lý, gameplay hoặc iOS.

### Mở rộng ứng viên item có thời hạn: zombie3

`obj_zombie3:Alarm:6` Android ARM32 tại `0x668a38`, 6.936 byte, SHA-256
`f758909f83cc6499d0c57ee11307573e4322428823586af099589e2d8ad2a757`, có hai
đường tạo `obj_item` index 161 rồi ghi real 1 vào slot 1096 của instance vừa
tạo, sau ghi số lượng và trước hướng/động lượng. Một nhánh quantity nhỏ hơn 1
có thêm phép thử random; nhánh kia dùng quantity từ mảng. Verifier item ghim
hash, kiểm phân nhánh, identity, dữ liệu và thanh ghi giữ handle cho từng đường.
Đã thêm `ins.__dt_item_timed = 1` vào hai nhánh tương ứng ở source cũ. Alias
này không phải tên biến native đã được biết; phần còn lại của event chưa được
chứng minh tương đương, và các đường item khác vẫn có thể thiếu setter.

Probe VM mới trích đúng fragment hai nhánh từ source, thay **chỉ** `random(1)`
bằng 0 để ép tình huống, chạy trong `sys_global` trên bản VM dùng một lần;
kiểm quantity 0 không tạo item, 0,5 tạo item số lượng 1 và 2 tạo số lượng 2,
cả hai có cờ 1. Đây không chạy toàn bộ Alarm 6, không xác minh RNG, sự kiện,
lịch 900 bước, gameplay, Android native hoặc iOS. Cần chờ kết quả CI riêng.

Tại `5cdccc9`, kiểm thử local chạy 207 test, 12 skip; CI native
`44923636384`, source-workbench `44923636244` và VM `44923636328` thành công.
VM qua ba marker của fragment zombie3; các giới hạn nêu trên vẫn áp dụng.

### Mở rộng ứng viên item có thời hạn: zombie2

`obj_zombie2:Step:0` tại `0x658910`, 40.784 byte, SHA-256
`9a7cb64db9fe3a7c94ac56f0b69c095899cf32f1b0f37c6077d512f5f1e5f1f5` cũng có
hai đường tạo object 161 rồi ghi real 1 vào slot 1096 của item vừa tạo. Đã thêm
hai assignment alias tương ứng vào source. Verifier ghim bytes, nhánh, handle
và giá trị cho cả hai đường. Probe fragment VM mở rộng để kiểm cả zombie2 và
zombie3 với đầu vào 0, 0,5, 2; phép thử random vẫn bị ép 0, không chạy event
đầy đủ. Chưa xác định tên native hoặc chứng minh các zombie khác, toàn bộ
lifecycle, compiler chính thức, gameplay, Android thực thi hay iOS. Cần xem
kết quả CI mới cho thay đổi zombie2.

Tại `9560179`, kiểm thử local 207 test (12 skip); CI native `44924020730`,
source-workbench `44924020845` và source-VM `44924020725` thành công. VM qua
sáu marker fragment zombie2/zombie3; các giới hạn về event và thiết bị vẫn giữ
nguyên. Audit vẫn thiếu 58 script, 90 object, 367 event key, 4 sprite và 8 room
so tên/key; đây không phải phép đo tương đương gameplay.

### Mở rộng ứng viên item có thời hạn: zombie4 và zombie5

Phân tích tĩnh hai event Android `obj_zombie4:Step:0` (`0x679698`, 37.992
byte, SHA-256 `ada019456226f637c40f2282afa0405870bd09217a6a5c22dd405cf2cb06cb78`)
và `obj_zombie5:Step:0` (`0x687fc8`, 34.880 byte, SHA-256
`9f5f3373755778960b45ec66a04ca27771deefe88443ccbcb2ff0db9cd500b0d`). Trong mỗi
event, hai đường rơi item tạo object 161, ghi slot 1096 bằng real 1 trên handle
đó. Verifier ghim hash, nhánh, giá trị, ID và lệnh truyền handle; kiểm thanh
ghi giữ handle/giá trị không bị thay trong các đoạn liên quan. Source cũ thêm
cờ alias vào hai nhánh ở mỗi zombie, nhưng không khẳng định các phần còn lại
của Step khớp native.

Probe fragment VM mở rộng chạy các nhánh của bốn zombie 2/3/4/5 với random(1)
được thay bằng 0 và chỉ kiểm kết quả trong môi trường mô phỏng. Chưa chạy toàn
bộ event, chưa xác minh RNG, các zombie khác, Android runtime, gameplay hoặc
iOS. Kết quả CI của thay đổi zombie4/5 cần xem riêng.

Tại `29355cc`, 207 test local thành công (12 skip); CI VM `44924671784` đã
chạy thành công 12 marker fragment của bốn zombie. CI native và workbench
được theo dõi riêng; không suy ra gameplay hoặc iOS từ các kết quả này.

### Mở rộng ứng viên item có thời hạn: zombie thường

`obj_zombie:Step:0` Android tại `0x647a08`, 44.536 byte, SHA-256
`422271b0202040eb4b4e79c905e54428183f744b40a5943a8c119a1e5c89dd05`: hai
đường drop theo mảng và hai đường theo database đều tạo object 161 và đặt slot
1096 của item mới bằng 1. Verifier ghim nhánh, lời gọi database, handle và
real 1 cùng thanh ghi; source thêm bốn assignment alias vào các đường tương
ứng. Phần còn lại event không được chứng minh tương đương.

Probe fragment nay kiểm thêm zombie thường: tách đường mảng và đường database,
thay random(1) bằng 0 và các truy vấn database bằng input giả (cả min và max
bằng cùng giá trị). Nó không thực thi cơ sở dữ liệu thực, toàn bộ event, RNG
thực hay lifecycle. Chưa kiểm Android runtime, gameplay và iOS; CI mới cần
được xem riêng. Những zombie 6/7 không có source object tương ứng nên chưa
được phục hồi bằng thay đổi này.

Tại `29355cc`, CI native `44924671799` và workbench `44924671796` cũng thành
công. Tại `b8c15c6`, kiểm thử local 207 test (12 skip), CI native
`44925050055`, workbench `44925050088`, VM `44925050182` đều thành công; VM
qua 18 marker fragment, bao gồm nhánh database đã giả lập, không phải database
thật. Audit không đổi: thiếu 58 script, 90 object, 367 event key, 4 sprite và
8 room so tên/key. Chưa build IPA mới hoặc kiểm gameplay trên iPhone.
