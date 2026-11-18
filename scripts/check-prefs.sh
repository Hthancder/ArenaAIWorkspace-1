#!/usr/bin/env bash
# Kiểm tra tĩnh cho tầng Settings (không cần Xcode/theos):
#   - plist hợp lệ + controller/action được tham chiếu có thật trong mã
#   - cân bằng ngoặc / @interface-@implementation-@end trong từng file .m/.h
#   - mọi @selector("sx_…") phải có khai báo tương ứng
#   - #import "SX*.h" phải trỏ tới file tồn tại
# Chạy: ./scripts/check-prefs.sh
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import glob
import os
import plistlib
import re
import sys

ROOT = os.getcwd()
ERRORS = []
WARNINGS = []

def fail(message):
    ERRORS.append(message)

def warn(message):
    WARNINGS.append(message)

def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()

# ---------------------------------------------------------------- plist
PLIST_CONTROLLER = {
    "Prefs/Resources/Root.plist": "SXRootListController",
    "Prefs/Resources/ProviderOpenAI.plist": "SXProviderConfigController",
    "Prefs/Resources/ProviderGemini.plist": "SXProviderConfigController",
}

def walk_specifiers(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk_specifiers(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk_specifiers(item)

impls = set()
sources = sorted(glob.glob("Prefs/*.m") + glob.glob("Sources/*.m"))
for path in sources:
    for match in re.finditer(r"@implementation\s+([A-Za-z_][A-Za-z0-9_]*)", read(path)):
        impls.add(match.group(1))

methods = {}
for path in sources + sorted(glob.glob("Prefs/*.h") + glob.glob("Sources/*.h")):
    text = read(path)
    for match in re.finditer(r"^[+-]\s*\([^)]*\)\s*([A-Za-z_][A-Za-z0-9_]*)", text, re.MULTILINE):
        methods.setdefault(match.group(1), set()).add(path)

for plist_path in sorted(glob.glob("Prefs/Resources/*.plist")):
    try:
        data = plistlib.load(open(plist_path, "rb"))
    except Exception as exc:
        fail(f"{plist_path}: plist không hợp lệ — {exc}")
        continue
    controller = PLIST_CONTROLLER.get(plist_path)
    controller_source = f"Prefs/{controller}.m" if controller else None
    controller_text = read(controller_source) if controller_source and os.path.exists(controller_source) else ""

    for spec in walk_specifiers(data):
        detail = spec.get("detail")
        if isinstance(detail, str) and detail and not detail.startswith("PS"):
            if detail not in impls:
                fail(f"{plist_path}: detail '{detail}' không có @implementation")
        action = spec.get("action")
        if isinstance(action, str) and action:
            selector = action.rstrip(":")
            pattern = re.compile(r"^[+-]\s*\([^)]*\)\s*" + re.escape(selector) + r"\b", re.MULTILINE)
            if controller_text and not pattern.search(controller_text) and controller not in methods.get(selector, set()):
                fail(f"{plist_path}: action '{action}' không có trong {controller_source}")

# ------------------------------------------------------- cấu trúc C/ObjC
def strip_literals(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if ch == '"':
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            out.append('""')
            continue
        if ch == "'":
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == "'":
                    i += 1
                    break
                i += 1
            out.append("''")
            continue
        out.append(ch)
        i += 1
    return "".join(out)

checked = sorted(glob.glob("Prefs/*.m") + glob.glob("Prefs/*.h")
                 + glob.glob("Sources/*.m") + glob.glob("Sources/*.h"))
for path in checked:
    code = strip_literals(read(path))
    for opening, closing, label in (("{", "}", "{}"), ("(", ")", "()"), ("[", "]", "[]")):
        delta = code.count(opening) - code.count(closing)
        if delta != 0:
            fail(f"{path}: lệch {label} ({delta:+d})")
    if path.endswith(".m") or path.endswith(".h"):
        interfaces = len(re.findall(r"^\s*@interface\b", code, re.MULTILINE))
        implementations = len(re.findall(r"^\s*@implementation\b", code, re.MULTILINE))
        ends = len(re.findall(r"^\s*@end\b", code, re.MULTILINE))
        if ends != interfaces + implementations:
            fail(f"{path}: @end={ends} nhưng @interface={interfaces} + @implementation={implementations}")

# ------------------------------------------------------------- selector
for path in sorted(glob.glob("Prefs/*.m") + glob.glob("Sources/*.m")):
    for match in re.finditer(r"@selector\(([A-Za-z_][A-Za-z0-9_]*)\)", read(path)):
        name = match.group(1)
        if name.startswith("sx_") and name not in methods:
            fail(f"{path}: @selector({name}) không có khai báo nào")

# ---------------------------------------------------------------- import
for path in checked:
    for match in re.finditer(r'#import\s+"(SX[A-Za-z0-9_]*\.h)"', read(path)):
        header = match.group(1)
        if not any(os.path.exists(os.path.join(base, header)) for base in ("Prefs", "Sources", "include")):
            fail(f"{path}: #import \"{header}\" không tìm thấy file")

# ---------------------------------------------------------------- report
for message in WARNINGS:
    print(f"⚠️  {message}")
for message in ERRORS:
    print(f"✗ {message}")
if ERRORS:
    print(f"\n✗ {len(ERRORS)} lỗi — sửa trước khi push.")
    sys.exit(1)
print(f"✓ Settings lint OK ({len(checked)} file, {len(impls)} class).")
PY
