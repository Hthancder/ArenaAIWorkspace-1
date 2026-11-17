# 09 · Vì sao chuyển hẳn sang macOS runner

## Triệu chứng

Hai lỗi tưởng như khác nhau:

1. Respring → vào **safe mode**.
2. Cài xong nhưng **không có mục SiriBridge trong Cài đặt**, dù tweak khác vẫn hiện
   và PreferenceLoader đã cài.

## Nguyên nhân: cùng một chỗ

Dump load command của binary do `zig cc` sinh ra:

```
$ python3 -c "..."   # đọc Mach-O header
SiriBridgePrefs: filetype=6 (MH_DYLIB) LC_LOAD_DYLINKER present=True
SiriBridge.dylib: filetype=6 (MH_DYLIB) LC_LOAD_DYLINKER present=True
```

Hai lỗi cấu trúc, cả hai đều do linker của zig:

### 1. `LC_LOAD_DYLINKER` trong một `MH_DYLIB`

`LC_LOAD_DYLINKER` chỉ được phép có trong **executable** (nó nói "dùng dyld ở
đường dẫn này"). Đặt nó vào một dylib là Mach-O **không hợp lệ**. dyld của iOS
từ chối file → process chết ngay khi load. Với tweak inject vào SpringBoard/Siri
thì đó chính là **safe mode**.

Không phải do thiếu chữ ký. Chữ ký có (tự ký bằng script), hash từng trang đúng,
mà vẫn chết — vì lỗi nằm ở header, không ở chữ ký.

### 2. Mạch load command bị hỏng

Từ load command thứ 15 trở đi, `cmd`/`size` đọc ra rác (`0x52800020`, offset
nhảy vượt cuối file). Nguyên nhân: zig **sửa tại chỗ** load command cuối thành
`LC_LOAD_DYLINKER` sau khi đã chốt `sizeofcmds`, và không cập nhật lại header.
Bất kỳ công cụ nào duyệt tuần tự load command (dyld, `codesign`, WinterBoard,
PreferenceLoader) đều dừng hoặc đọc sai.

Với bundle PreferenceBundles, hệ quả là bundle **không dlopen được** → Settings
bỏ qua im lặng → "không thấy mục". Đúng triệu chứng số 2.

## Vì sao vá bằng script không ổn

Có thể xóa `LC_LOAD_DYLINKER` và tính lại `sizeofcmds`, nhưng:

* phải tính lại offset của mọi thứ phía sau (không khó), **và**
* mỗi lần zig đổi phiên bản là mỗi lần có thể sinh lỗi mới. Trước đó đã phải tự
  viết lại code-signing (SuperBlob, CodeDirectory, `__LINKEDIT`) từ đầu — chỉ để
  bù cho việc không có `ldid`.

Đó là đang tự viết lại ld64 + codesign. Không đáng, và không thể đảm bảo đúng.

## Cách làm mới

`.github/workflows/build.yml` chạy trên **`macos-14`**:

| Thành phần | Trước (Linux/zig) | Sau (macOS) |
| --- | --- | --- |
| Compiler | `zig cc` | `clang` của Apple |
| Linker | `zig`'s ld | `ld64` của Apple |
| Ký ad-hoc | `tools/sb_codesign.py` tự viết | `ldid -S` thật |
| Đóng gói | `dpkg-deb` | `dpkg-deb` (brew) |

Nhờ vậy `LC_LOAD_DYLINKER` không bao giờ xuất hiện trong dylib, mạch load
command luôn hợp lệ, và chữ ký do chính `ldid` tạo — thứ mà mọi jailbreak đã
kiểm chứng.

`build.sh --linux` giờ **báo lỗi kèm hướng dẫn** thay vì build ra gói hỏng.

## Chốt chặn trong CI

`tools/verify_deb.py` giờ kiểm tra thêm:

```
OK SiriBridge.dylib: 11 load command hợp lệ, không có LC_LOAD_DYLINKER
```

Cụ thể:

* quét toàn bộ load command, mọi `size` phải ≥ 8 và không vượt cuối file;
* `32 + sizeofcmds` phải bằng đúng offset kết thúc khi quét;
* **không** được có `LC_LOAD_DYLINKER` trong file không phải executable;
* `filetype` phải là `MH_DYLIB` hoặc `MH_BUNDLE`.

Gói lỗi kiểu cũ sẽ **fail CI**, không lọt ra Release.

## Kiểm chứng bằng gói cũ

```
$ python3 tools/verify_deb.py com.hthancder.siribridge_0.1.2_iphoneos-arm64.deb iphoneos-arm64 --strict
LỖI: SiriBridge.dylib: có LC_LOAD_DYLINKER trong MH_DYLIB — dyld sẽ từ chối file này
```

Đúng gói bạn đã cài. Đây chính là lý do.
