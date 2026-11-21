# Kiểm tra lịch Alarm 0 của item ứng viên

Đây là kiểm tra bổ sung trong VM desktop riêng, không phải phục hồi mới hay
xác minh trò chơi gốc. `tools/deadtown_item_schedule_vm_probe.py` tạo hai
instance `obj_item` với Create và Alarm 0 từ source ứng viên. Một instance có
`__dt_item_timed = 1`, instance kia giữ 0. Để cách ly khỏi logic nhặt/di chuyển
và việc chuyển room, probe thay Step của item bằng no-op và đặt hai instance
thành persistent chỉ trong bản diagnostic. Event source thật không bị sửa.

CI [44927589736](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44927589736),
commit `a5f9ed4`, chạy 930 frame trên runner desktop riêng. Marker:

```text
ITEM_SCHEDULE_VM:init:900:900
ITEM_SCHEDULE_VM:expired:900:1:1
ITEM_SCHEDULE_VM:after:0:1:-1
```

Tại Step 900, item có cờ biến mất sau khi Alarm đếm từ 900; item không cờ vẫn
còn sau Step 905 với alarm −1. Đây là hành vi đo trong thử nghiệm đã cô lập;
không chứng minh lịch native Android/iOS, item gameplay bình thường, quá trình
spawn/nhặt hay Alarm 1 còn thiếu. Thử nghiệm ban đầu
[44927490105](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44927490105)
thất bại khi cả hai instance bị hủy lúc chuyển room sau 71 bước; thay đổi
persistent ở bản thử giải quyết yếu tố nhiễu đó, không sửa gameplay project.
Local `unittest discover`: 209 tests, OK, 12 skip.
