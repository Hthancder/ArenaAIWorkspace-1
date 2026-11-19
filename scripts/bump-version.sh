#!/usr/bin/env bash
# Đổi số phiên bản ở mọi nơi cùng lúc — tránh cảnh "control 1.1.9 nhưng Settings
# vẫn 1.1.8" vì mỗi chỗ lưu một chuỗi riêng.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ne 1 ] || ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Dùng: $0 <major.minor.patch>   (ví dụ: $0 1.2.0)" >&2
	exit 1
fi
version="$1"
current=$(sed -n 's/^Version: //p' control)
if [ "$version" = "$current" ] && grep -q "SX_VERSION @\"$version\"" Sources/SXLog.h; then
	echo "Đã là $version — không đổi gì."
	exit 0
fi

# control
sed -i.bak -E "s/^Version: .*/Version: ${version}/" control && rm -f control.bak
# SXLog.h (SX_VERSION)
sed -i.bak -E "s/(#define SX_VERSION @\")[0-9]+\.[0-9]+\.[0-9]+(\")/\1${version}\2/" Sources/SXLog.h && rm -f Sources/SXLog.h.bak
# Prefs Info.plist: short version + build tăng một
build=$(( $(sed -n '/CFBundleVersion/{n;s/.*<string>\([0-9]*\)<\/string>.*/\1/p;}' Prefs/Resources/Info.plist) + 1 ))
python3 - "$version" "$build" <<'PY'
import plistlib, sys
path = 'Prefs/Resources/Info.plist'
with open(path, 'rb') as handle:
    info = plistlib.load(handle)
info['CFBundleShortVersionString'] = sys.argv[1]
info['CFBundleVersion'] = sys.argv[2]
with open(path, 'wb') as handle:
    plistlib.dump(info, handle)
PY

echo "✓ ${current} → ${version} (control, SX_VERSION, Info.plist build ${build})"
