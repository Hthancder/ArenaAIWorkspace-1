#!/usr/bin/env bash
set -e
ZIG="${ZIG_BIN:-/tmp/z13/ziglang/zig}"
args=()
sdk=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -target) shift; t="$1"; minver="${t##*-ios}"; [[ "$minver" == "$t" ]] && minver=""
             args+=("--target=aarch64-ios") ;;
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
  [[ -d "$sdk/usr/lib" ]] && args+=("-L$sdk/usr/lib")
fi
args+=("-fno-modules")
exec "$ZIG" c++ "${args[@]}"
