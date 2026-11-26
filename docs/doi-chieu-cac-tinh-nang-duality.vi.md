# Đối chiếu tính năng với Duality Client 4.1

Đối chiếu tĩnh `docs/duality_client.js` (bundle do người dùng cung cấp), không chạy nó. Tập trung vào mã game entry, state, ticker, event và sender; phần thư viện UI đóng gói không quyết định gameplay. Đối chiếu thêm source Survev được ghim tại `3edee7e8`. Đây không phải cam kết mọi tính năng trùng hệt hay đã thử trong trận live.

| Nhóm | Duality | Cách dự án xử lý / quyết định |
|---|---|---|
| Aim, sticky, prediction, smooth | Chọn theo FOV/team/layer, lịch sử 20 mẫu, nội suy cubic; accessor chuột, ghi rotation body sau update; sender có trì hoãn/phát lại Fire | Lock/Assist độc lập, predictor theo snapshot/vũ khí, chuột tách intent, rotation sau native; không trì hoãn/phát lại Fire. Wallcheck không sao chép phân loại chỉ wall/spread của Duality vì yêu cầu kiểm tra mọi vật chắn. |
| Melee Lock / auto melee | Chọn người gần, di chuyển và hướng aim khi giữ Fire; cùng controller chuột/rotation với gun | Giữ tầm dựa kích thước vũ khí và kiểm tra nguồn/team/wall. Bản này giữ ownership chuột và đồng bộ body cho melee, kể cả khi gun aim tắt; không thể nắm ownership thì không chèn hướng/di chuyển melee. Nhả Fire trả quyền. |
| Semi Auto / Auto Switch | Semi có can thiệp sender; switch dựa thay đổi ammo, equip | Dùng native bind repeat theo fireMode/cooldown; không lặp grenade, auto/burst; switch có hàng đợi, đợi slot xác nhận và nhường equip thủ công. Không giả định bypass cooldown. |
| Mobile Movement | Chuyển input phím thành touch direction, nội suy | Chuyển và chuẩn hóa theo protocol, bỏ smoothing ngay khi thả; melee được ưu tiên. |
| ESP / lines / indicator | Tên native, đường, điểm aim, vòng FOV | Dùng tên native và overlay; phân biệt ally/enemy/unknown, giữ giới hạn dữ liệu được server replicate, khôi phục giá trị khi tắt. |
| X-Ray / smoke / ceilings | Sửa sprite, alpha/tint trực tiếp | Theo def/source và pool, có khôi phục; smoke tint/alpha qua contract được kiểm tra; không sao chép chỉnh property nội bộ PIXI bừa bãi. |
| Zoom / layer / minimap | Ghi đè zoom khi cuộn, layer theo phím; thay dữ liệu minimap qua hook global sort | Zoom có giới hạn và khôi phục; layer chỉ visual; minimap hook tại method phù hợp, clone shape, không sửa `Array.prototype.sort` hoặc dữ liệu dùng chung. |
| Grenade / projectile / flashlight | Timer một số bom hardcode 4s, preview/quỹ đạo theo ước lượng | Dùng fuse/physics và kiểm tra source; timer chỉ ước lượng, grenade aim/release có gate riêng và không tự bắt đầu Fire, không hứa hit. |
| Auto Loot | Đặt mobile trong Join | Giữ chế độ mobile tùy chọn và native nearby pickup; tạm nghỉ sau drop, không ép bật trên mọi Join. |

Không chép các hook toàn cục/ẩn console/patch Error của bundle. Cài đặt hiện tại ưu tiên trạng thái native, xử lý khôi phục và an toàn khi thiếu contract, chứ không đồng nhất với mọi hành vi của Duality. Test gồm unit/integration theo source và các biến thể minified; không phải kết quả thực tế trên deployment live.
