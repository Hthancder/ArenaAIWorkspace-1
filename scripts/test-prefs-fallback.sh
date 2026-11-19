#!/usr/bin/env bash
# Bảo đảm MỌI màn hình cài đặt đều có lưới an toàn: nếu một trang con mở ra
# trống, người dùng phải thấy lời giải thích + nút quay lại + nút sao chép log,
# chứ không phải màn hình trắng im lặng.
#
# Luật:
#   1. Mỗi lớp `...Controller` trong Prefs/ khai báo ở header phải gọi
#      SXShowContentFallbackIfNeeded trong mã của nó.
#   2. Lời gọi phải nằm trong `viewDidAppear:` (sau khi bảng đã có dữ liệu) —
#      gọi ở viewDidLoad sẽ chèn khối dự phòng lên trang chưa kịp tải.
#   3. Tên trang truyền vào phải là chuỗi không rỗng (không dùng nil).
#
# Chạy: ./scripts/test-prefs-fallback.sh
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import glob
import os
import re
import sys

ERRORS = []
CALL = "SXShowContentFallbackIfNeeded"

# Lớp nào là "màn hình cài đặt" (mở ra từ Settings) — lấy từ header công khai.
screens = []
for path in sorted(glob.glob("Prefs/*.h")):
    text = open(path, encoding="utf-8").read()
    for match in re.finditer(r"@interface\s+(SX\w*Controller)\s*:", text):
        screens.append((match.group(1), path))

# Lớp phụ trợ đặt cùng file .m (chi tiết/sửa) — cũng là trang người dùng mở.
for path in sorted(glob.glob("Prefs/*.m")):
    text = open(path, encoding="utf-8").read()
    for match in re.finditer(r"@interface\s+(SX\w*Controller)\s*:\s*(?:PS|UI)", text):
        screens.append((match.group(1), path))

seen = set()
for name, header in screens:
    if name in seen:
        continue
    seen.add(name)
    # Tìm file .m chứa @implementation của lớp.
    source = None
    for candidate in sorted(glob.glob("Prefs/*.m")):
        body = open(candidate, encoding="utf-8").read()
        if re.search(r"@implementation\s+" + re.escape(name) + r"\b", body):
            source = candidate
            impl = body
            break
    if source is None:
        ERRORS.append(f"{header}: lớp {name} không có @implementation")
        continue

    # Cắt riêng phần thân lớp: từ @implementation tới @implementation kế tiếp.
    start = re.search(r"@implementation\s+" + re.escape(name) + r"\b", impl).start()
    following = re.search(r"\n@implementation\s", impl[start + 1:])
    block = impl[start:start + 1 + following.start()] if following else impl[start:]

    if CALL not in block:
        ERRORS.append(f"{source}: {name} chưa gọi {CALL} — trang có thể trống im lặng")
        continue

    appear = re.search(r"^-\s*\(void\)\s*viewDidAppear:", block, re.MULTILINE)
    if not appear:
        ERRORS.append(f"{source}: {name} gọi {CALL} nhưng không có viewDidAppear:")
        continue
    # Lời gọi phải nằm trong viewDidAppear (tới trước hàm kế tiếp).
    after = block[appear.end():]
    end = re.search(r"\n-\s*\(", after)
    body = after[:end.start()] if end else after
    if CALL not in body:
        ERRORS.append(f"{source}: {name} gọi {CALL} ngoài viewDidAppear: — "
                      "cần gọi sau khi bảng đã có dữ liệu")
        continue

    call = re.search(CALL + r"\(\s*[^,]+,\s*(.+?)[,)]", body, re.DOTALL)
    if not call or not call.group(1).strip() or call.group(1).strip() == "nil":
        ERRORS.append(f"{source}: {name} truyền tiêu đề rỗng cho {CALL}")

for message in ERRORS:
    print(f"✗ {message}")
if ERRORS:
    print(f"\n✗ {len(ERRORS)} trang thiếu lưới an toàn.")
    sys.exit(1)
print(f"✓ lưới an toàn: {len(seen)} màn hình cài đặt đều có nội dung dự phòng.")
PY
