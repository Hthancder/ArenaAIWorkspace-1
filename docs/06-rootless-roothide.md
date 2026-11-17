# 06 · Build rootless & roothide (không rootful)

## Chọn scheme

```bash
make package                   # rootless  → /var/jb
make package SCHEME=roothide   # roothide  → jbroot động
```

`common-scheme.mk` (include từ cả `Makefile` và `Prefs/Makefile`) sẽ:

1. lấy `SCHEME` (hoặc `THEOS_PACKAGE_SCHEME`), mặc định `rootless`;
2. `$(error …)` nếu giá trị không phải `rootless`/`roothide` → **không thể build rootful**;
3. ép `ARCHS = arm64` (không arm64e);
4. export `THEOS_PACKAGE_SCHEME` để Theos nạp module scheme tương ứng.

## Vì sao roothide cần Theos riêng

`THEOS_PACKAGE_SCHEME=roothide` khiến Theos nạp `vendor/mod/<scheme>`.
Module này chỉ tồn tại trong **roothide/theos** (clone `--recursive`):

* `vendor/mod/roothide/package/deb.mk` → ép `THEOS_PACKAGE_ARCH := iphoneos-arm64e`;
* `vendor/mod/roothide/instance/{library,framework}.mk` → install-name
  `@loader_path/.jbroot<install_path>/...`;
* `vendor/include/roothide.h` + `vendor/lib/iphone/roothide/libroothide.tbd`.

Với Theos upstream, scheme `roothide` không tồn tại → make báo
`'roothide' package scheme does not exist`. Vì vậy CI dùng 2 repo khác nhau.

## Vì sao code vẫn là arm64 dù package ghi arm64e

`THEOS_PACKAGE_ARCH` chỉ là **trường `Architecture:` trong file control** — nó nói
với package manager biết gói thuộc hàng roothide. Kiến trúc Mach-O do `ARCHS` quyết định.
Ta đặt `ARCHS = arm64` nên `cpusubtype = 0` (CPU_SUBTYPE_ARM64_ALL) — **không phải
arm64e (0x80000002)**. CI verify bước này.

## Resolve đường dẫn lúc chạy (`Sources/SBPaths.m`)

```
dlopen("libroothide.dylib")  →  dlsym("jbroot")  →  jbroot("/")
        │ fail
        ├─ stat("/var/jb/usr/lib") == 0  → "/var/jb"
        └─ else                          → "/"
```

* Ưu tiên `jbroot()` vì roothide random hoá đường dẫn jbroot.
* Không link cứng `libroothide` → **một binary dùng được cho cả hai scheme**
  (roothide vẫn nạp bình thường vì dlsym chỉ chạy khi có thư viện).
* `SBPathCandidates()` trả về danh sách ứng viên cho một đường dẫn logic;
  `SBConfig` dùng nó để fallback khi cfprefsd không phục vụ domain
  (SiriViewService bị sandbox trên một số cấu hình).

## CI

Matrix 2 job (`rootless`, `roothide`). Job roothide clone `roothide/theos --recursive`
và build `./build.sh --linux SCHEME=roothide`; verify `Architecture` khớp matrix,
Mach-O là arm64, và **không có layout rootful** (`/usr/lib`, `/Library` ở gốc gói).
Release (tag `v*` hoặc chạy tay) chứa **cả hai** file `.deb` + `SHA256SUMS-*`.
