#!/usr/bin/env python3
"""Bảo đảm các hàng "chọn một giá trị" luôn hiện được TRẠNG THÁI.

Lỗi đã xảy ra (1.2.1): chọn xong một tuỳ chọn mà không thấy dấu ✓ hay giá trị
nào. Nguyên nhân: `readPreferenceValue:` trả nhãn đã dịch ("Thông minh",
"Google Gemini", "Bubble “chưa kịp”") trong khi cell của Preferences tra giá trị
đó trong `validValues` ("smart", "gemini", "bubble") — không khớp nên ô phải
rỗng và không có ✓.

Luật kiểm tra:
  1. Mọi hàng `PSLinkListCell` trong plist phải có `validValues`.
  2. Với mỗi hàng như vậy, nhánh `readPreferenceValue:` tương ứng trong
     `SXRootListController.m` chỉ được trả về chuỗi nằm trong `validValues`
     (hoặc biến thể hiện tại của cùng khoá).
  3. Trang gốc phải gắn cell tự vẽ cho mọi hàng `PSLinkListCell`
     (gán `PSCellClassKey`) — nếu không, trạng thái phụ thuộc hành vi của Apple.
  4. `SXAPIChoiceController` phải có ô ✓ (dùng SXChoiceRow) và ghi + phát notify
     khi chọn, thay vì chỉ đặt chữ "✓" vào ô value.

Chạy: python3 scripts/check-choice-state.py
"""
import glob
import os
import plistlib
import re
import sys

ERRORS = []


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


root_source = read("Prefs/SXRootListController.m")
choice_source = read("Prefs/SXAPIChoiceController.m")

# ---------------------------------------------------------------- 1 + 2
for plist_path in sorted(glob.glob("Prefs/Resources/*.plist")):
    with open(plist_path, "rb") as handle:
        try:
            data = plistlib.load(handle)
        except Exception as exc:  # noqa: BLE001
            ERRORS.append(f"{plist_path}: plist hỏng — {exc}")
            continue
    for spec in walk(data):
        if spec.get("cell") != "PSLinkListCell":
            continue
        key = spec.get("key")
        values = spec.get("validValues")
        # Hàng số (Nhiệt độ, Thời gian chờ…) lấy lựa chọn từ `SXChoiceController`
        # chứ không từ plist: kiểm riêng nhánh đó bên dưới.
        if spec.get("detail") == "SXChoiceController":
            if "SXChoiceActiveKey" not in root_source:
                ERRORS.append(
                    f"{plist_path}: hàng số '{spec.get('label')}' mở SXChoiceController "
                    "nhưng bảng chọn không đánh dấu mức đang dùng (SXChoiceActiveKey)")
            continue
        if not isinstance(values, list) or not values:
            ERRORS.append(f"{plist_path}: hàng '{spec.get('label')}' (key={key}) "
                          "không có validValues — không thể hiện trạng thái")
            continue
        if not key:
            continue
        # Nhánh xử lý trong readPreferenceValue: của trang gốc (nếu có).
        block = re.search(
            r'if \(\[key isEqualToString:@"' + re.escape(key) + r'"\]\)\s*\{(.*?)\n\t\t\}',
            root_source, re.DOTALL)
        if not block:
            continue
        body = block.group(1)
        # Bỏ so sánh (`isEqualToString:`) — chỉ xét chuỗi ĐƯỢC TRẢ VỀ.
        returned = []
        for match in re.finditer(r'return\s+([^;]+);', body):
            expression = match.group(1)
            expression = re.sub(r'\[[^\]]*isEqualToString:@"[^"]*"\]', "", expression)
            returned += re.findall(r'@"([^"]*)"', expression)
            if re.search(r'\breturn\s+action\b', match.group(0)):
                returned += ["keep", "retry", "bubble"]
        for value in returned:
            if value not in [str(v) for v in values]:
                ERRORS.append(
                    f"Prefs/SXRootListController.m: readPreferenceValue cho '{key}' trả "
                    f"nhãn '{value}' nhưng validValues là {values} — cell sẽ để trống ô "
                    "giá trị và không có dấu ✓ (trả giá trị thật, nhãn đưa vào trailing)")

# ------------------------------------------------------------------ 3
if "PSCellClassKey" not in root_source:
    ERRORS.append("Prefs/SXRootListController.m: không gắn cellClass cho hàng "
                  "PSLinkListCell — trạng thái sẽ phụ thuộc hành vi của Preferences")
if "SXChoiceTrailingKey" not in root_source:
    ERRORS.append("Prefs/SXRootListController.m: không đặt giá trị hiển thị ở mép phải "
                  "(SXChoiceTrailingKey) — người dùng không thấy đang chọn gì")

# ------------------------------------------------------------------ 4
if "SXChoiceRow" not in choice_source:
    ERRORS.append("Prefs/SXAPIChoiceController.m: không dùng SXChoiceRow — không có ✓")
if "SXChoiceActiveKey" not in choice_source:
    ERRORS.append("Prefs/SXAPIChoiceController.m: không đánh dấu hàng đang chọn")
if "notify_post" not in choice_source:
    ERRORS.append("Prefs/SXAPIChoiceController.m: chọn xong không phát notify — trang gốc "
                  "sẽ không cập nhật giá trị mới")
if re.search(r'forKey:PSValueKey\][^;]*@\\?"✓', choice_source):
    ERRORS.append("Prefs/SXAPIChoiceController.m: vẫn đặt '✓' vào ô value thay vì vẽ trạng thái")

for message in ERRORS:
    print(f"✗ {message}")
if ERRORS:
    print(f"\n✗ {len(ERRORS)} lỗi trạng thái hàng chọn.")
    sys.exit(1)
print("✓ trạng thái hàng chọn: getter trả giá trị thật, cell tự vẽ ✓/giá trị.")
