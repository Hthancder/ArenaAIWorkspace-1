#!/usr/bin/env bash
# Kiểm tra cục bộ SiriX — không cần Xcode/macOS:
#   1) Logos preprocess Tweak.x  →  2) zig compile toàn bộ .m/.ii (aarch64-ios)  →  3) validate plist
# Yêu cầu: perl, python3, ziglang (pip install ziglang), SDK iOS (theos/sdks), theos (clone).
set -euo pipefail
cd "$(dirname "$0")/.."

THEOS="${THEOS:-/tmp/theos-check}"
SDK="${SDK:-/tmp/sdks/iPhoneOS15.6.sdk}"
if command -v zig >/dev/null 2>&1; then
	ZIG=zig
elif [ -x /usr/local/lib/python3.11/dist-packages/ziglang/zig ]; then
	ZIG=/usr/local/lib/python3.11/dist-packages/ziglang/zig
else
	echo "✗ Không tìm thấy zig. Chạy: pip install --break-system-packages ziglang" >&2
	exit 1
fi
[ -x "$THEOS/bin/logos.pl" ] || { echo "✗ THEOS=$THEOS không có bin/logos.pl" >&2; exit 1; }
[ -d "$SDK" ] || { echo "✗ SDK=$SDK không tồn tại (clone https://github.com/theos/sdks)" >&2; exit 1; }

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
FAIL=0

echo "── [0/3] Settings lint"
./scripts/check-prefs.sh

echo "── [0/3] Selector khai báo phải có thân hàm"
# 1.1.10–1.1.12 văng vì `headersSummaryForProvider:` được KHAI BÁO trong header
# và GỌI từ Settings nhưng chưa từng được viết. Trình biên dịch không bắt được
# (Objective-C chỉ cảnh báo), nên kiểm ở đây.
python3 scripts/check-declared-methods.py || FAIL=1
python3 scripts/check-specifier-types.py || FAIL=1

echo "── [0/3] Lưới an toàn cho mọi trang Settings"
# Trang con mở ra trống là lỗi người dùng thấy rõ nhất mà trình biên dịch không
# bắt được: mỗi lớp SX*Controller phải gọi SXShowContentFallbackIfNeeded.
./scripts/test-prefs-fallback.sh || FAIL=1

echo "── [1/3] Logos preprocess"
perl "$THEOS/bin/logos.pl" Sources/Tweak.x > "$OUT/Tweak.ii"
echo "   ✓ Sources/Tweak.x → Tweak.ii ($(grep -c '' "$OUT/Tweak.ii") dòng)"

echo "── [2/3] Compile (zig cc, aarch64-ios, -fobjc-arc)"
ZIG_FLAGS=(
	-target aarch64-ios.15.0
	-iframework "$SDK/System/Library/Frameworks"
	-I "$SDK/usr/include"
	-I "$THEOS/vendor/include"
	-I Sources
	-I Prefs
	-I include
	-x objective-c
	-fobjc-arc
	-Wall
	-Werror
	-Wno-unused-parameter
	-Wno-deprecated-declarations
	-DSX_SCHEME=\"rootless\"
)
compile() {
	local src="$1" name
	name=$(basename "$src" | tr '.' '_')
	if "$ZIG" cc "${ZIG_FLAGS[@]}" -c "$src" -o "$OUT/$name.o" 2> "$OUT/$name.log"; then
		echo "   ✓ $src"
	else
		echo "   ✗ $src"
		cat "$OUT/$name.log"
		FAIL=1
	fi
}
for f in Sources/*.m "$OUT/Tweak.ii" Prefs/*.m; do
	compile "$f"
done

echo "── [3/3] Plist validate"
python3 - <<'PY' || FAIL=1
import plistlib, sys, pathlib
files = [
    "SiriX.plist", "Prefs/Resources/Root.plist",
    "Prefs/Resources/Info.plist",
    "layout/Library/PreferenceLoader/Preferences/SiriX.plist",
]
ok = True
for f in files:
    try:
        with open(f, "rb") as fh:
            data = plistlib.load(fh)
        print(f"   ✓ {f}")
    except Exception as e:
        print(f"   ✗ {f}: {e}")
        ok = False
root = plistlib.load(open("Prefs/Resources/Root.plist", "rb"))
n = len(root.get("items", []))
print(f"   ✓ Root.plist: {n} specifier")
if n < 20:
    print("   ✗ Root.plist quá ít specifier"); ok = False
sys.exit(0 if ok else 1)
PY

if [ "$FAIL" -ne 0 ]; then
	echo "✗ CÓ LỖI — xem ở trên."
	exit 1
fi
echo "✓ TOÀN BỘ OK — sẵn sàng push để CI build deb."
