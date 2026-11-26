# Debug đồng đội, input và tham khảo Duality

## Hai tùy chọn độc lập

Trong Main, `Nhắm đồng đội (debug; cả địch)` thuộc Aim — Target selection; `Nhắm bom vào đồng đội (debug; cả địch)` thuộc Grenade Aim. Cả hai mặc định **tắt**, lưu độc lập. Bật chỉ bổ sung người được xác định chắc chắn cùng đội vào danh sách địch hiện có; không chọn bản thân hoặc người chưa rõ đội. Mục tiêu vẫn phải qua FOV, tầng, điều kiện sống, prediction và wallcheck/đường bom tương ứng; đồng đội khác vẫn có thể chắn đường. Tùy chọn súng cũng áp dụng cho lựa chọn melee hiện dùng chung pipeline; bom có Preview/Assist/Lock và Auto Throw vẫn giữ các điều kiện an toàn/cancel riêng.

Đây chỉ là debug hướng ngắm, không thay đổi luật server. Source ghim `server/src/game/objects/player.ts` `damage()` thường chặn sát thương giữa đồng đội còn kết nối; Combat Stimulants có thể chữa đồng đội bằng súng. Source không đảm bảo mọi deployment/chế độ giống nhau; không suy ra hit chỉ từ lượng máu.

## Input và chế độ

Script vẫn chuẩn bị trước activation nhưng không tự bắn. Direct native mouse là transaction tạm thời trên vector input, khôi phục dữ liệu người chơi; sender đã được xác thực chỉnh bản sao packet ngay trước native serialization. Lúc có `shootStart`, sender tính lại kế hoạch thay vì tin cache; khi chuột vật lý thay đổi sau frame, sender cũng tính lại, kể cả lúc đang giữ Fire. Nếu thiếu contract/bị chặn thì trả quyền native; không tự trì hoãn hay tạo Fire để chờ lock. Không hook driver/OS và không thể đảm bảo bắt mọi input hay server chấp nhận.

Lock hướng tới nghiệm, có thể tắt Human-like để tức thời; nếu bật thì smooth vẫn có thể chưa hội tụ khi bạn bắn. Assist giữ logic pha trộn hướng chuột thật với hướng mục tiêu, không nhớ controller hay ép dính khi người chơi di chuyển chuột; lực 0 không chỉnh, 100 gần như Lock. Chưa thay công thức Assist vốn có. Grenade Assist cũng blend hướng và khoảng cách; Auto Throw chỉ Lock, mặc định off.

## Đối chiếu tĩnh Duality Client 4.1

`docs/duality_client.js` là file người dùng cung cấp; chỉ phân tích tĩnh chuỗi JavaScript nhúng, không chạy. Duality chọn theo FOV/layer/team, lấy 20 mẫu vị trí hiển thị, vận tốc đầu-cuối và ping/2 để lead; khi thiếu mẫu hoặc nghiệm dùng hướng hiện tại. Smooth dùng cubic ease-out, duration 45 ms cộng phần phụ thuộc góc/khoảng cách và slider; cài accessor trên `mousePos.x/y` để giữ tọa độ thật và trả tọa độ mô phỏng. Sender của nó còn **tạm chặn rồi phát lại Fire** khi đang smooth/đầu Fire. Không có cơ sở từ code này để khẳng định trúng hơn trên live.

Không chép cơ chế trì hoãn/phát lại Fire vì yêu cầu ưu tiên thao tác khai hỏa người dùng; không chép accessor vĩnh viễn vì có rủi ro tương tác với input và script khác. Bản này giữ SmoothDamp đã kiểm thử, không khẳng định tốt hơn Duality. Cần benchmark có dữ liệu thực và kiểm thử gameplay trước khi thay predictor/controller. Diagnostics `aimEvidence` trong Help chỉ cho thấy forwarding phía client, không phải xác nhận server hay hit.
