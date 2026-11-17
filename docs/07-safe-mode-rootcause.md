# 07 · Root cause: vì sao cài xong respring là vào safe mode

Triệu chứng: cài `.deb`, respring → máy vào **safe mode** ngay, log chưa kịp có gì.

## Nguyên nhân 1 — binary không có chữ ký (nguyên nhân chính)

Toolchain dùng để build trên Linux/CI là `zig cc`. Nó **không ký ad-hoc** file
Mach-O, và trong repo `TARGET_CODESIGN` trỏ tới `tools/bin/ldid` — một shim
`exit 0`. Kết quả: `.dylib` phát hành **không có `LC_CODE_SIGNATURE`**.

Kiểm chứng trước khi sửa:

```
$ python3 - <<'PY'   # đếm load command
LC_CODE_SIGNATURE present: False
PY
```

Trên iOS 15 (và với ElleKit), dylib inject vào process hệ thống phải có chữ ký
ad-hoc hợp lệ. Không có → dyld/amfid từ chối, process chết trong lúc load.
Vì `SiriBridge.plist` inject cả **SpringBoard**, process chết là SpringBoard
⇒ respring loop / safe mode.

### Sửa

* `tools/sb_codesign.py` — ký ad-hoc thuần Python: thêm `LC_CODE_SIGNATURE`,
  dựng `SuperBlob` + `CodeDirectory` (version `0x20100`, `hashType=2` SHA-256,
  page 4096), cập nhật `__LINKEDIT` cho bao trùm phần chữ ký.
* `tools/bin/ldid` — shim gọi script trên khi Theos ký.
* `-Wl,-headerpad,0x1000` trong `zigcc-wrap.sh` và `*_LDFLAGS` để có chỗ thêm
  load command.
* CI verify: hash **từng trang** được tính lại và so với CodeDirectory
  (`tools/verify_deb.py --strict`).

## Nguyên nhân 2 — phụ thuộc `MSHookMessageEx`

`%hook` của Logos sinh lời gọi `MSHookMessageEx`. Symbol này **không có** trên
hệ thống — nó do substrate/ElleKit cung cấp. Ta link với
`-Wl,-undefined,dynamic_lookup`, nên lúc link không báo lỗi; lỗi xuất hiện ở
**dyld bind time**. Nếu libhooker nạp chậm hơn dylib → bind lỗi → process chết.

### Sửa

Bỏ Logos hoàn toàn. `Sources/Tweak.x` hook bằng API công khai của libobjc:

```objc
Method m = class_getInstanceMethod(cls, sel);
IMP orig = class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(m));
```

Kiểm chứng: `strings SiriBridge.dylib | grep MSHook` → rỗng, và danh sách
undefined symbol chỉ còn framework hệ thống.

## Nguyên nhân 3 — inject vào SpringBoard mà không hook gì

`SiriBridge.plist` lọc cả `com.apple.springboard`, nhưng mọi hook đều nằm trên
class của Siri. Inject vào SpringBoard chỉ tăng bề mặt rủi ro: bất kỳ lỗi nào
lúc load đều làm SpringBoard chết.

### Sửa

Filter chỉ còn `com.apple.SiriViewService`. CI từ chối gói còn chữ `springboard`
trong plist filter.

## Nguyên nhân 4 — constructor làm việc nặng

`%ctor` cũ gọi ngay `[SBConfig reload]` (CFPreferences), ghi log, `dlopen`
(via `SBPaths` khi log), và `CFNotificationCenterAddObserver`. Chạy trên main
thread trong lúc SpringBoard đang khởi động: chỉ cần một exception hoặc một
lần I/O chậm là bị watchdog giết.

### Sửa

* `%ctor` chỉ đọc 1 file cờ nhỏ, rồi `dispatch_after(1.5s)` mới làm phần còn lại.
* Toàn bộ thân hook bọc `@try/@catch` — exception không thể lọt ra runloop.
* **Crash-loop guard**: ghi `loading` trước, `ctor-ok` sau. Nếu lần sau vẫn thấy
  `loading`, tự chạy safe mode (không cài hook).
* Người dùng có thể tắt hẳn bằng file cờ `…siribridge.safemode`.

## Nguyên nhân 5 — KVC trên ACE object

`[view setValue:answer forKey:@"text"]` ném `NSUnknownKeyException` nếu key
không tồn tại trên object đó (Siri đổi schema giữa các bản iOS). Không bọc
`@try` ⇒ crash.

### Sửa

`SBSetSafe(obj, key, value)` — luôn bọc `@try`, trả `BOOL`, log khi lỗi.

## Nguyên nhân 6 — âm thanh

`[AVAudioSession setCategory:…]` khi Siri đang giữ `.playAndRecord` có thể
làm mất micro hoặc sinh assertion. Chỉ cần `setActive:YES`.

Ngoài ra nếu `AVSpeechSynthesizer` không gọi delegate (voice lỗi), `SBEngine`
kẹt `busy` mãi ⇒ thêm timeout theo độ dài câu.

## Nguyên nhân 7 — cắt chuỗi theo byte

`[[NSString alloc] initWithData:data].substringToIndex:MIN(300, data.length)`
dùng **số byte** cho **số ký tự** ⇒ `NSRangeException` với tiếng Việt (UTF-8
nhiều byte). Sửa: cắt theo `string.length`.

## Checklist test trên máy

1. Cài gói, respring. Máy KHÔNG vào safe mode.
2. `cat /var/mobile/Library/Preferences/com.hthancder.siribridge.state.plist`
   → `com.apple.SiriViewService` có `state = ready`.
3. `tail -20 /var/mobile/Library/Logs/SiriBridge.log` thấy `cài hook: THÀNH CÔNG`.
4. Settings → SiriBridge → bật công tắc, nhập endpoint, bấm **Kiểm tra kết nối**.
5. Gọi Siri một câu → câu trả lời của LLM hiện trong transcript.
6. Nếu sai, tạo file `.safemode` rồi respring: tweak tắt hẳn, máy bình thường.
