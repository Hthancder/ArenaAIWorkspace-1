#!/usr/bin/env bash
# build.sh — build SiriBridge
#
#  macOS + Theos (khuyến nghị, toolchain chính thức):
#     ./build.sh
#
#  Linux (đã test trong sandbox dự án): cần
#     - Theos đã `--recursive`
#     - SDK iPhoneOS15.6.sdk trong $THEOS/sdks (từ github.com/theos/sdks)
#     - zig 0.13.x  (pip install ziglang==0.13.0)
#     - rsync
#   rồi: ZIG_BIN=/path/to/zig THEOS=/path/to/theos ./build.sh --linux
#
set -euo pipefail
cd "$(dirname "$0")"

MODE="macos"
if [[ "${1:-}" == "--linux" ]]; then MODE="linux"; shift; fi

if [[ "$MODE" == "linux" ]]; then
  : "${THEOS:?cần export THEOS}"
  : "${ZIG_BIN:?cần export ZIG_BIN (đường dẫn tới binary zig 0.13.x)}"
  STUB="$(pwd)/tools/theos-toolchain-stub/bin"
  mkdir -p "$THEOS/toolchain/linux/iphone/bin"
  for t in clang clang++; do
    ln -sf "$STUB/$t" "$THEOS/toolchain/linux/iphone/bin/$t"
  done
  export ZIG_BIN
  # zig không tự tìm libSystem trong SDK → cần -L; wrapper đã xử lý
  make package TARGET_CODESIGN=true
else
  : "${THEOS:?cần cài Theos: https://theos.dev}"
  make clean >/dev/null 2>&1 || true
  make package FINALPACKAGE=1
fi

echo
echo "==> Sản phẩm:"
ls -la packages/*.deb 2>/dev/null || true
