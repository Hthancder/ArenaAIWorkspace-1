#!/usr/bin/env bash
# build.sh — build SiriBridge
#
#   ./build.sh                        # rootless, ký bằng ldid thật (macOS)
#   ./build.sh SCHEME=roothide        # roothide
#   ./build.sh THEOS=/opt/theos SCHEME=roothide
#
# Cần (macOS): Theos (https://theos.dev), ldid (`brew install ldid`),
# dpkg (`brew install dpkg`), Xcode Command Line Tools.
#
# Ghi chú quan trọng: dùng FINALPACKAGE=1. `make package` thường KHÔNG ký
# binary; thiếu chữ ký ad-hoc là process chết ngay khi dyld load.
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "--linux" ]]; then
  cat >&2 <<'EOF'
LỖI: chế độ build bằng zig trên Linux đã bị bỏ.

Lý do: linker của zig sinh LC_LOAD_DYLINKER trong một MH_DYLIB — Mach-O
không hợp lệ với dyld của iOS, và zig không ký ad-hoc được. Đây chính là
nguyên nhân gây sập/safe mode. Xem docs/09-ly-do-chuyen-sang-macos.md.

Build trên macOS:
    brew install ldid dpkg
    git clone --recursive https://github.com/theos/theos.git ~/theos
    git clone --depth 1 https://github.com/theos/sdks.git && \
      cp -R sdks/iPhoneOS15.6.sdk ~/theos/sdks/
    export THEOS=~/theos
    ./build.sh
EOF
  exit 1
fi

: "${THEOS:?cần export THEOS (https://theos.dev)}"

command -v ldid >/dev/null 2>&1 || {
  echo "LỖI: không có ldid. Chạy: brew install ldid" >&2
  exit 1
}

ARGS=("$@")

make clean >/dev/null 2>&1 || true
rm -rf Prefs/.theos packages

# FINALPACKAGE=1  → Theos chạy `ldid -S` trên dylib và bundle (BẮT BUỘC)
make package FINALPACKAGE=1 "${ARGS[@]}"

echo
echo "==> Sản phẩm:"
ls -la packages/*.deb 2>/dev/null || true

echo
echo "==> Kiểm tra:"
DEB="$(ls packages/*.deb | head -n1)"
case "$DEB" in
  *arm64e*) ARCH=iphoneos-arm64e ;;
  *)        ARCH=iphoneos-arm64 ;;
esac
python3 tools/verify_deb.py "$DEB" "$ARCH" --strict
