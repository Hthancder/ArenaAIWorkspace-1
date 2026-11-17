# Nếu bị safe mode

SiriBridge có 3 lớp bảo vệ và 1 đường thoát thủ công.

## 1. Tự chẩn đoán

Ngay khi load, tweak ghi trạng thái vào:

```
/var/mobile/Library/Preferences/com.hthancder.siribridge.state.plist
```

Mỗi process một mục (`com.apple.SiriViewService`) với `state`:

| state | nghĩa |
|---|---|
| `loading` | đang khởi tạo (nếu còn `loading` ở lần sau ⇒ lần trước chết) |
| `ctor-ok` | constructor chạy xong |
| `ready` | đã cài hook xong |
| `safemode` | lần này bỏ qua, không cài hook |
| `error` | có exception, xem `detail` |

## 2. Tự chuyển safe mode

Nếu lần load trước dừng ở `loading`, lần này tweak **không cài hook**
⇒ máy không thể rơi vào vòng respring vì tweak nữa.

## 3. Tắt hẳn bằng file cờ

```bash
touch /var/mobile/Library/Preferences/com.hthancder.siribridge.safemode
killall -9 SpringBoard
```

Bật lại:

```bash
rm /var/mobile/Library/Preferences/com.hthancder.siribridge.safemode
rm /var/mobile/Library/Preferences/com.hthancder.siribridge.state.plist
killall -9 SpringBoard
```

## 4. Xem log

```
/var/mobile/Library/Logs/SiriBridge.log     (tự xoay vòng ở 300 KB)
```

Hoặc Console.app / `idevicesyslog | grep SiriBridge`.

Các mốc log cần thấy khi mọi thứ bình thường:

```
[SiriBridge/com.apple.SiriViewService] load vào com.apple.SiriViewService (iOS 15.x)
... khởi tạo xong trong com.apple.SiriViewService
... cài hook: THÀNH CÔNG
```
