# 08 · Không thấy mục SiriBridge trong Cài đặt

Mục trong Cài đặt do **PreferenceLoader** tạo ra từ file
`…/Library/PreferenceLoader/Preferences/SiriBridge.plist`; file entry phải trỏ đúng
`SiriBridgePrefs` và controller `SBRootListController`. Bản hiện tại khai báo rõ
`isController=true`; CI cũng đọc plist entry và `Info.plist` của bundle để bắt lỗi
đường dẫn/class ngay khi đóng gói. Không hiện thường do một trong các nguyên nhân dưới.

Định dạng entry tham khảo implementation của [PreferenceLoader](https://github.com/ArtikusHG/PreferenceLoader/blob/master/Tweak.xm)
(và API `specifiersFromEntry` trong [Theos headers](https://github.com/theos/headers/blob/master/libprefs/prefs.h)).

## A. Cài nhầm bản (hay gặp nhất)

| Máy | Đường dẫn cài | File phải dùng |
|---|---|---|
| rootless (Dopamine, palera1n rootless) | `/var/jb/Library/…` | `*_iphoneos-arm64.deb` |
| roothide (Bootstrap) | `/Library/…` (gốc) | `*_iphoneos-arm64e.deb` |

Cài sai bản thì file nằm sai chỗ → Settings không quét tới.

Kiểm tra:

```bash
ls /var/jb/Library/PreferenceBundles/    # phải thấy SiriBridgePrefs.bundle
ls /Library/PreferenceBundles/          # roothide mới có ở đây
```

Sửa: `dpkg -r com.hthancder.siribridge` rồi cài lại đúng file.

## B. Không có PreferenceLoader

Không có nó thì **mọi** tweak đều biến mất khỏi Cài đặt, không riêng gì
SiriBridge. Kiểm tra:

```bash
ls /var/jb/Library/MobileSubstrate/DynamicLibraries/ | grep -i preference
```

Không có → cài `PreferenceLoader` từ repo (rootless: Procursus; roothide: Bootstrap).
Từ v0.1.2 gói đã khai báo `Depends: …, preferenceloader` nên trình quản lý sẽ
tự kéo theo.

## C. Đang ở SAFE MODE

Trong safe mode **tất cả** tweak bị tắt. Dấu hiệu: các tweak khác cũng mất mục
trong Cài đặt. Thoát safe mode rồi respring.

## D. Cờ safe mode của SiriBridge đang bật

```bash
rm /var/mobile/Library/Preferences/com.hthancder.siribridge.safemode
rm /var/mobile/Library/Preferences/com.hthancder.siribridge.state.plist
killall -9 SpringBoard
```

## E. Bundle lỗi (quyền / thiếu symbol)

```bash
ls -l /var/jb/Library/PreferenceBundles/SiriBridgePrefs.bundle/
# SiriBridgePrefs phải là 755, Info.plist 644
```

Từ v0.1.2 `postinst` tự `chmod` lại cho đúng.

## F. Chẩn đoán tự động

```bash
sh /var/jb/usr/share/siribridge/sb-doctor.sh
```

Script kiểm tra: môi trường (rootless/roothide), file, quyền,
PreferenceLoader, cờ safe mode, entry plist, log tweak, dpkg — và chỉ ra
nguyên nhân cụ thể.

## G. Log của panel

Khi mở được panel, `SBRootListController` ghi:

```
[SiriBridge] prefs: viewDidLoad (class SBRootListController)
[SiriBridge] prefs: viewWillAppear — bundle ĐÃ load
```

Nếu **không** có 2 dòng đó trong `/var/mobile/Library/Logs/SiriBridge.log`
thì PreferenceLoader chưa load bundle (mục A/B/C/D). Nếu có dòng
`buildUI exception` thì giao diện có lỗi — gửi log để sửa.
