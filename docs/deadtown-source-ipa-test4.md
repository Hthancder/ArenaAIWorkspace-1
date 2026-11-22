# Dead Town iOS 15 — thử nghiệm source 4

Đây là IPA **chưa ký, không hoàn chỉnh, chưa kiểm trên iPhone**, không phải
bản phát hành hay bản game gốc. Build từ revision
`ea13c7a659a334d22ecdab3c215c2ce9f787f9ba` bằng Actions
[45043018147](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/45043018147).
Đã công bố [link tải thử nghiệm](https://github.com/Hthancder/ArenaAIWorkspace-1/releases/download/deadtown-ios15-source-test4/DeadTown-iOS15-source-test4.ipa) dưới dạng prerelease. Artifact Actions lưu 7 ngày; IPA cũng được lưu dưới
Git blob không gắn vào nhánh `9f321080b3126cfc76ecf5d4c2e27ef12f70c9a0`.

- IPA `DeadTown-iOS15-source-test4.ipa`: SHA-256
  `2918742162a98f541c56941d1f4b26ffbb43d9183409fbd0b022f3daa5f85284`.
- `data.win` SHA-256
  `f57b93d464a7b2e2c105fa6e435a114a14a7ef86de219cf7110da8720dfc818d`.
- ARM64, iOS tối thiểu 15.0; app ID `org.gmrunner.deadtown.sourcetest4`,
  tách biệt bản test3. Không tự chuyển save; sao lưu dữ liệu trước khi thử.
- Runner lấy từ IPA test3 ghim hash, thay dữ liệu game bằng bản biên dịch
  các script và event của project hiện tại trên container APK. Đây là chuyển
  đổi thử nghiệm, không phải build GameMaker gốc: event/script thiếu vẫn bị
  bỏ trống, một số event không được gắn, room code native bị xóa tham chiếu,
  và asset/resource table dùng container APK. Không chèn các event giả lập
  của các probe VM vào bản này.
- Các diagnostic desktop trước đây không đảm bảo gameplay, điều khiển, save,
  âm thanh hoặc đồ họa iOS. Các IPA test trước đã có lỗi vệt màu khi di chuyển;
  chưa chứng minh bản này sửa lỗi đó. Build thành công chỉ chứng minh việc biên
  dịch và đóng gói, không chứng minh cài hoặc chạy thành công trên thiết bị.
- IPA chưa ký: cần phương thức cài phù hợp với thiết bị, ví dụ TrollStore nếu
  thiết bị tương thích, hoặc ký lại bằng công cụ/tài khoản của người dùng.
  Không yêu cầu hay thu thập thông tin đăng nhập, khóa ký hoặc chứng chỉ.

Runner: <https://github.com/andronep/gmrunner>, commit
`e7121381d38b03a24242812fc22b0a7386d545c6`, GPL-3.0-or-later;
chỉnh sửa launcher và quy trình build trong repo này.
