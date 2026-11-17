# Kiểm thử & debug trên máy thật

> Trạng thái: `.deb` arm64 đã build và kiểm tra cấu trúc trong sandbox,
> **chưa chạy trên thiết bị**. Tài liệu này là checklist để bạn tự verify.

## 0. Chuẩn bị

```bash
# trên máy Mac/Linux
make package
scp packages/com.hthancder.siribridge_0.1.0_iphoneos-arm64.deb root@<IP>:/var/mobile/
ssh root@<IP>
dpkg -i /var/mobile/com.hthancder.siribridge_0.1.0_iphoneos-arm64.deb
```

Kiểm tra đã cài đúng chỗ (rootless → `/var/jb`):

```bash
ls -l /var/jb/Library/MobileSubstrate/DynamicLibraries/SiriBridge.*
ls -l /var/jb/Library/PreferenceBundles/SiriBridgePrefs.bundle/
```

## 1. Xem log

```bash
# trên máy
log stream --predicate 'eventMessage CONTAINS "[SiriBridge]"' --level debug
# hoặc qua ssh từ Mac
idevicesyslog | grep SiriBridge
```

Sau khi respring và mở Siri, **phải** thấy:

```
[SiriBridge] load vào com.apple.SiriViewService trên iOS 15.x
[SiriBridge] hooks đã cài (AFUISiriSession)
[SiriBridge] hook dự phòng SRSiriViewController đã cài
```

Nếu không thấy `load vào …`: filter plist hoặc injection chưa hoạt động
(kiểm tra jailbreak đã bật tweak injection cho SiriViewService).

Nếu thấy `thiếu method …`: bản iOS của bạn có selector khác — ghi lại tên,
ta sẽ thêm path dự phòng.

## 2. Test không cần micro (khuyến nghị)

Bật **Settings → Accessibility → Siri → Type to Siri**, rồi:

1. Giữ nút nguồn (hoặc nút side) để mở Siri, hiện bàn phím.
2. Gõ `hello` → Enter.

Kỳ vọng: log `xử lý lượt: hello` → `POST https://…` → `answer: …` →
chữ hiện trong Siri → giọng đọc.

## 3. Test từng lớp

| Lớp | Cách kiểm | Kỳ vọng |
|---|---|---|
| Injection | `log stream` sau respring | có dòng `load vào com.apple.SiriViewService` |
| Hook | nói/gõ 1 câu | có `xử lý lượt:` |
| Chặn Siri | đặt câu hỏi kiến thức | **không** thấy câu trả lời kiểu "Đây là những gì tôi tìm thấy trên web" |
| LLM | xem log `POST` + `answer:` | có nội dung |
| UI | nhìn màn hình Siri | chữ xuất hiện, không bị chồng 2 câu |
| TTS on-device | TTSMode=0 | nghe thấy, log không lỗi audio |
| TTS endpoint | TTSMode=1 | audio phát sau ~1s |
| Tools | "mở cài đặt" | Settings mở ra |
| Dismiss | bật DismissAfterAnswer | Siri tự đóng sau khi đọc xong |

## 4. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Xử lý |
|---|---|---|
| Siri im lặng hoàn toàn, không có chữ, không đóng | `completion` của `receivedCommand` không được gọi / LLM treo | xem log có `chặn command` rồi `POST`; tăng timeout, kiểm tra mạng. Nếu kẹt: tắt Replace trong Settings rồi mở lại Siri |
| Hai câu trả lời chồng nhau | `ReplaceSiri = NO`, hoặc hook `receivedCommand` bị miss | bật Replace; kiểm tra log `chặn command` |
| Không nghe thấy gì | audio session bị Siri giữ; voice chưa tải | đổi TTSMode sang 2 để test; chọn voice khác; tăng volume |
| Đọc 2 lần | TTSMode=2 **và** SpeakAnswer=YES cùng SBTTS chạy | dùng TTSMode 0/1 (mặc định), hoặc tắt SpeakAnswer khi dùng mode 2 |
| `HTTP 401` | key sai / endpoint cần header khác | log có body lỗi 300 ký tự; kiểm tra `Headers phụ` |
| `Không đọc được câu trả lời` | `Response field` sai | log in 400 ký tự response; sửa đường dẫn JSON |
| SpringBoard respring loop | hook lỗi trong SpringBoard | boot vào safe mode (giữ volume-up), gỡ gói: `dpkg -r com.hthancder.siribridge` |
| App nào đó crash | tweak inject nhầm | kiểm tra `SiriBridge.plist` chỉ có 2 bundle |

## 5. Gỡ

```bash
dpkg -r com.hthancder.siribridge
killall -9 SpringBoard
# xoá prefs
rm -f /var/mobile/Library/Preferences/com.hthancder.siribridge.plist
```

## 6. Test những thứ dễ vỡ

1. **Cuộc gọi đến khi Siri đang mở** — không được crash.
2. **Báo thức đang kêu, gọi Siri** — Siri phải nhường audio.
3. **Khoá máy rồi gọi Siri** (nếu bật "Cho phép Siri khi khoá") — AddViews vẫn phải hiện.
4. **Mất mạng giữa lượt** — phải hiện "Lỗi: …" chứ không treo.
5. **Nói câu rất dài** (>200 ký tự) — token limit; kiểm tra bị cắt đúng.
6. **Bật/tắt tweak trong Settings khi Siri đang mở** — `notify_post` reload ngay.
