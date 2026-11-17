#!/bin/sh
# sb-doctor.sh — chẩn đoán vì sao SiriBridge không hiện trong Cài đặt.
#
#   sh /var/jb/usr/share/siribridge/sb-doctor.sh
#
# Script tự dò cả rootless (/var/jb) và roothide (cài ở gốc) nên chạy ở đâu cũng được.

RED=""; GRN=""; YLW=""; RST=""
if [ -t 1 ]; then RED="\033[31m"; GRN="\033[32m"; YLW="\033[33m"; RST="\033[0m"; fi
ok()   { echo "  ${GRN}OK${RST}   $*"; }
bad()  { echo "  ${RED}LỖI${RST}  $*"; }
warn() { echo "  ${YLW}HỎI${RST}  $*"; }

echo "=== SiriBridge doctor (v0.1.2) ==="
echo

# ---- 0. Ta đang ở đâu? ----
echo "--- 0. Môi trường ---"
JB=""
[ -d /var/jb/Library ] && JB="/var/jb"
if [ -n "$JB" ]; then ok "rootless: $JB"
else ok "roothide/khác: cài ở gốc /"; fi

# Bản cài sai chỗ là nguyên nhân số 1 của "không thấy Settings".
if [ -n "$JB" ] && [ -d "/Library/PreferenceBundles/SiriBridgePrefs.bundle" ]; then
  bad "Phát hiện bundle ở /Library (gốc) trong khi máy là ROOTLESS."
  echo "       → Bạn đã cài NHẦM bản roothide (*_iphoneos-arm64e.deb)."
  echo "         Gỡ:  dpkg -r com.hthancder.siribridge"
  echo "         Cài:  bản *_iphoneos-arm64.deb"
fi
if [ -z "$JB" ] && [ -d "/var/jb/Library/PreferenceBundles/SiriBridgePrefs.bundle" ]; then
  bad "Phát hiện bundle ở /var/jb trong khi máy KHÔNG phải rootless."
  echo "       → Bạn đã cài NHẦM bản rootless (*_iphoneos-arm64.deb)."
  echo "         Cài bản *_iphoneos-arm64e.deb."
fi

BUNDLE="${JB}/Library/PreferenceBundles/SiriBridgePrefs.bundle"
ENTRY="${JB}/Library/PreferenceLoader/Preferences/SiriBridge.plist"
DYLIB="${JB}/Library/MobileSubstrate/DynamicLibraries/SiriBridge.dylib"

# ---- 1. File ----
echo
echo "--- 1. File có mặt? ---"
for f in "$BUNDLE" "$BUNDLE/Info.plist" "$BUNDLE/SiriBridgePrefs" "$ENTRY" "$DYLIB"; do
  [ -e "$f" ] && ok "$f" || bad "THIẾU $f"
done

# ---- 2. Quyền ----
echo
echo "--- 2. Quyền (755 thư mục, 755 binary, 644 plist) ---"
for f in "$BUNDLE" "$BUNDLE/Info.plist" "$BUNDLE/SiriBridgePrefs" "$ENTRY"; do
  [ -e "$f" ] && echo "       $(stat -c '%a %U:%G' "$f" 2>/dev/null)  $f"
done

# ---- 3. PreferenceLoader ----
echo
echo "--- 3. PreferenceLoader (thứ quyết định Settings có mục hay không) ---"
PL=""
for p in "$JB/Library/PreferenceLoader" "$JB/Library/MobileSubstrate/DynamicLibraries/PreferenceLoader.dylib" "$JB/usr/lib/libprefs.dylib"; do
  [ -e "$p" ] && PL="$p"
done
if [ -n "$PL" ]; then
  ok "thấy $PL"
else
  bad "KHÔNG có PreferenceLoader."
  echo "       Không có nó thì Settings KHÔNG hiện bất kỳ tweak nào."
  echo "       Cài 'PreferenceLoader' từ repo:"
  echo "         rootless → repo Procursus/ElleKit"
  echo "         roothide → Bootstrap repo"
fi

# ---- 4. Safe mode? ----
echo
echo "--- 4. Có đang ở SAFE MODE không? ---"
echo "       (trong safe mode MỌI tweak bị tắt, kể cả PreferenceLoader"
echo "        → Cài đặt sẽ KHÔNG có mục nào. Thử xem tweak khác còn mục không.)"
SM=0
[ -f /var/mobile/Library/Preferences/com.hthancder.siribridge.safemode ] && {
  bad "file safe mode của SiriBridge ĐANG BẬT"
  echo "       tắt: rm /var/mobile/Library/Preferences/com.hthancder.siribridge.safemode && killall -9 SpringBoard"
  SM=1
}
if [ -f /var/mobile/Library/Logs/CrashReporter/SpringBoard-*.ips ]; then :; fi
ls /var/mobile/Library/Logs/CrashReporter/SpringBoard* 2>/dev/null | tail -3 | while read -r f; do
  echo "       crash gần đây: $f"
done
[ "$SM" = 0 ] && ok "không thấy cờ safe mode của SiriBridge"

# ---- 5. Entry plist hợp lệ? ----
echo
echo "--- 5. Entry plist ---"
if [ -f "$ENTRY" ]; then
  echo "       $(head -c 60 "$ENTRY" | tr -d '\n') ..."
  if grep -q "SiriBridgePrefs" "$ENTRY"; then ok "trỏ tới bundle SiriBridgePrefs"
  else bad "không thấy 'SiriBridgePrefs' trong plist"; fi
  if grep -q "SBRootListController" "$ENTRY"; then ok "detail = SBRootListController"
  else bad "không thấy class SBRootListController"; fi
else
  bad "không có entry plist → chắc chắn không hiện trong Settings"
fi

# ---- 6. Log ----
echo
echo "--- 6. Log tweak ---"
LOG="/var/mobile/Library/Logs/SiriBridge.log"
if [ -f "$LOG" ]; then tail -12 "$LOG"; else warn "chưa có $LOG (tweak chưa load lần nào)"; fi

# ---- 7. Package ----
echo
echo "--- 7. dpkg ---"
if command -v dpkg >/dev/null 2>&1; then
  dpkg -l 2>/dev/null | grep -iE "siribridge|preferenceloader" || warn "dpkg không thấy gói nào"
else
  warn "không có dpkg"
fi

echo
echo "=== hết. Gửi toàn bộ output này nếu cần trợ giúp. ==="
