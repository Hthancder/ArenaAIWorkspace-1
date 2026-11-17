# theos-toolchain-stub

Thư mục này cho phép **build tweak này trên Linux** mà không cần Xcode.

* `bin/clang`, `bin/clang++` → wrapper gọi `zig cc` / `zig c++` (zig 0.13.x)
  với target `aarch64-ios`, tự thêm `-isystem <SDK>/usr/include`,
  `-F<SDK>/System/Library/Frameworks` và `-L<SDK>/usr/lib`.
* `build.sh --linux` sẽ symlink hai file này vào
  `$THEOS/toolchain/linux/iphone/bin/` để Theos gọi tới.

Đây **chỉ là công cụ build**; sản phẩm vẫn là Mach-O arm64 iOS 15.0+
được ký ad-hoc bởi Theos (`ldid` khi có, hoặc không ký nếu thiếu —
trên máy rootless, ElleKit/libhooker nạp dylib không cần chữ ký).
