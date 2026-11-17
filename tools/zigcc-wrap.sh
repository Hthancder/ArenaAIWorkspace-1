#!/usr/bin/env bash
# Wrapper: chuyển các cờ của Theos/clang sang dạng zig cc hiểu được.
# Theos gọi:  cc -target arm64-apple-ios15.0 -isysroot <SDK> ... -c file.m -o file.o
# zig  cc:    --target=aarch64-ios -mios-version-min=15.0 -isysroot <SDK> -isystem <SDK>/usr/include
set -e
ZIG="${ZIG_BIN:-zig}"
args=()
sdk=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -target)
      shift
      t="$1"
      # arm64-apple-ios15.0  /  arm64e-apple-ios15.0
      minver="${t##*-ios}"
      [[ "$minver" == "$t" ]] && minver=""
      args+=("--target=aarch64-ios")
      ;;
    -isysroot) shift; sdk="$1"; args+=("-isysroot" "$1") ;;
    -arch) shift ;;
    -miphoneos-version-min=*) : ;;
    *) args+=("$1") ;;
  esac
  shift
done
if [[ -n "$sdk" ]]; then
  [[ -d "$sdk/usr/include" ]] && args+=("-isystem" "$sdk/usr/include")
  [[ -d "$sdk/System/Library/Frameworks" ]] && args+=("-F$sdk/System/Library/Frameworks")
  [[ -d "$sdk/System/Library/PrivateFrameworks" ]] && args+=("-F$sdk/System/Library/PrivateFrameworks")
  [[ -d "$sdk/usr/lib" ]] && args+=("-L$sdk/usr/lib")
fi
args+=("-fno-modules")
# Chừa chỗ trong header để ta tự thêm LC_CODE_SIGNATURE (zig/ld64 không ký trên Linux)
args+=("-Wl,-headerpad,0x1000")
# Nếu SDK không có ldid, Theos vẫn gọi codesign tool; bỏ qua an toàn:
exec "$ZIG" cc "${args[@]}"
