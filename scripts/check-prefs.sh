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
# Controller do Apple cung cấp. Chỉ những lớp có hành vi ổn định trong
# PreferenceLoader mới được phép — trước đây `PSListItemsController` làm trang
# cấu hình OpenAI văng ngay khi mở (nó cần `values`/`titles` dạng khác).
APPLE_DETAILS = set()  # mọi hàng "chọn một giá trị" đều dùng SXAPIChoiceController
FORBIDDEN_DETAILS = {
    "PSListItemsController": "dùng SXAPIChoiceController (tự dựng) — lớp này cần "
                             "values/titles không tới được cell trong trang nạp bằng plist",
}

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
        if isinstance(detail, str) and detail in FORBIDDEN_DETAILS:
            fail(f"{plist_path}: detail '{detail}' bị cấm — {FORBIDDEN_DETAILS[detail]}")
        if isinstance(detail, str) and detail and detail not in FORBIDDEN_DETAILS:
            if not detail.startswith("PS") and detail not in impls:
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

# --------------------------------------------- thuộc tính mutable dùng copy
# `copy` trên NSMutableArray/Dictionary/Set trả về bản BẤT BIẾN ⇒ thao tác
# thêm/xoá/sửa sau đó văng "unrecognized selector". Đây đúng là lỗi từng làm
# Settings văng khi lưu header.
for path in checked:
    text = read(path)
    for match in re.finditer(r"@property[^;]*?\bcopy\b[^;]*?\bNSMutable[A-Za-z]+", text):
        line = text[:match.start()].count("\n") + 1
        fail(f"{path}:{line}: thuộc tính NSMutable… khai báo copy sẽ thành bản bất biến — dùng strong")

# ----------------------------------- không reload bảng trong lúc đang gõ chữ
# Reload cell/section ngay trong sự kiện gõ sẽ gỡ ô nhập khỏi cửa sổ và UIKit
# hạ bàn phím sau mỗi ký tự (đúng lỗi "gõ 1 chữ là bàn phím tắt").
for path in sorted(glob.glob("Prefs/*.m")):
    text = read(path)
    handlers = set()
    for match in re.finditer(
            r"@selector\(([A-Za-z_][A-Za-z0-9_]*):?\)\s*forControlEvents:\s*UIControlEventEditingChanged",
            text):
        handlers.add(match.group(1))
    for name in sorted(handlers):
        body = re.search(r"^-\s*\([^)]*\)\s*" + re.escape(name) + r"\b.*?\n\}", text,
                         re.MULTILINE | re.DOTALL)
        if not body:
            continue
        for bad in ("reloadData", "reloadSections", "reloadSpecifier", "reloadSpecifiers"):
            if bad in body.group(0):
                fail(f"{path}: {name} vừa xử lý gõ chữ vừa gọi {bad} — bàn phím sẽ tắt sau mỗi ký tự")

# ----------------------------- khai báo lại thuộc tính của lớp cha (lỗi build)
# `table`/`view`/`specifiers`/`specifier`/`bundle` đã có trong PSListController.
# Khai báo lại trong @interface (kể cả extension) của lớp con PSListController
# làm clang báo -Wobjc-property-synthesis; CI build với -Werror nên đỏ ngay
# trong khi lint tĩnh vẫn xanh. Chỉ xét các lớp thật sự kế thừa PSListController
# để không báo nhầm lớp thường có thuộc tính cùng tên.
LIST_INHERITED = {"table", "view", "specifiers", "specifier", "bundle"}
list_classes = set()
for path in sorted(glob.glob("Prefs/*.h") + glob.glob("Prefs/*.m")):
    for match in re.finditer(r"@interface\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*PSListController\b",
                             read(path)):
        list_classes.add(match.group(1))
for path in sorted(glob.glob("Prefs/*.h") + glob.glob("Prefs/*.m")):
    code = read(path)
    # `[^@]*?` không dùng được: chính `@property` chứa '@' nên khối không bao giờ khớp.
    for match in re.finditer(r"@interface\s+([A-Za-z_][A-Za-z0-9_]*)[^\n]*\n(.*?)@end",
                             code, re.DOTALL):
        if match.group(1) not in list_classes:
            continue
        body = match.group(0)
        for prop in re.finditer(
                r"@property\s*\([^)]*\)\s*[A-Za-z_][A-Za-z0-9_<>, ]*?\*?\s*([A-Za-z_][A-Za-z0-9_]*)\s*;",
                body):
            if prop.group(1) in LIST_INHERITED:
                line = code[:match.start() + prop.start()].count("\n") + 1
                fail(f"{path}:{line}: lớp {match.group(1)} (PSListController) khai báo lại "
                     f"thuộc tính '{prop.group(1)}' — clang báo -Wobjc-property-synthesis "
                     "và build -Werror sẽ đỏ")

# ------------------------------------------- setProperty trên biểu thức `id`
# `items.firstObject` có kiểu `id`, nên `-setProperty:forKey:` nhập nhằng với
# `NSStream` và clang báo "multiple methods named 'setProperty:forKey:' found
# with mismatched result" — lỗi chỉ lộ khi build thật (CI), không lộ khi lint.
for path in checked:
    text = read(path)
    for match in re.finditer(r"\[\s*[A-Za-z_][A-Za-z0-9_\.]*\.(?:firstObject|lastObject)\s+setProperty:", text):
        line = text[:match.start()].count("\n") + 1
        fail(f"{path}:{line}: gọi setProperty: trên biểu thức `id` (firstObject/lastObject) — "
             "gán qua biến PSSpecifier* trước, nếu không clang báo lỗi nhập nhằng")

# --------------------------------------------- key màn hình đọc phải có trong code
# Một hàng PSLinkListCell trỏ tới SXChoiceController với `key` mà lớp đó không
# biết sẽ mở ra màn hình trống (đúng kiểu lỗi "bấm vào không có gì xảy ra").
CHOICE_KEYS = set()
root_text = read("Prefs/SXRootListController.m")
for match in re.finditer(r'SXChoiceDefinitionFor\(@"([A-Za-z0-9_]+)"\)', root_text):
    CHOICE_KEYS.add(match.group(1))
for match in re.finditer(r'@"([A-Za-z0-9_]+)"\s*:\s*\[SXChoiceController class\]', root_text):
    CHOICE_KEYS.add(match.group(1))

for plist_path in sorted(glob.glob("Prefs/Resources/*.plist")):
    try:
        data = plistlib.load(open(plist_path, "rb"))
    except Exception:
        continue
    for spec in walk_specifiers(data):
        if spec.get("detail") != "SXChoiceController":
            continue
        key = spec.get("key")
        if isinstance(key, str) and key and key not in CHOICE_KEYS:
            fail(f"{plist_path}: hàng '{spec.get('label')}' dùng SXChoiceController "
                 f"nhưng key '{key}' không có định nghĩa")

# ------------------------------------- luật mạng: mọi redirect phải được xét lại
# Lỗi thật: `web_fetch` ghi chú "không đi theo redirect" nhưng URLSession vẫn
# đi theo, nên một trang công khai có thể chuyển hướng vào 127.0.0.1. Từ nay
# tầng HTTP hỏi lại từng đích; ai gọi GET mà không truyền `rejectRedirect`
# trong khi đọc URL do AI/người dùng nhập là lỗi.
NET_FILES = ["Sources/SXToolCatalog.m"]
for path in NET_FILES:
    text = read(path)
    for match in re.finditer(r"\[SXHTTP getURL:", text):
        tail = text[match.start():match.start() + 1200]
        if "rejectRedirect:" not in tail:
            line = text[:match.start()].count("\n") + 1
            fail(f"{path}:{line}: gọi SXHTTP getURL: mà không truyền rejectRedirect: — "
                 "redirect có thể nhảy vào mạng nội bộ")
    if "SXNetHostIsPrivate" not in text and "SXHostIsPrivate" not in text:
        fail(f"{path}: phải kiểm tra host bằng SXNetPolicy trước khi tải URL do model chọn")

# ------------------------------------------- log: category phải nằm trong danh mục
# §8 của DESIGN-SYSTEM: `boot · pref · hook · capture · llm · resp · stt · tts · err`
# (cộng `tool`, `http`, `update` đã dùng thật và có trong màn Nhật ký). Một
# category lạ không bị lọc đúng trong màn Nhật ký và làm log rối khi gỡ lỗi.
KNOWN_LOG_CATEGORIES = {"boot", "pref", "hook", "capture", "llm", "resp",
                        "stt", "tts", "err", "tool", "http", "update"}
for path in sorted(glob.glob("Prefs/*.m") + glob.glob("Sources/*.m")):
    for match in re.finditer(r'SXLog(?:Dbg|Inf|Wrn|Err)\(@"([^"]*)"', read(path)):
        category = match.group(1)
        if category not in KNOWN_LOG_CATEGORIES:
            line = read(path)[:match.start()].count("\n") + 1
            fail(f"{path}:{line}: log category “{category}” không có trong danh mục "
                 f"cố định ({', '.join(sorted(KNOWN_LOG_CATEGORIES))})")

# -------------------------------- test: `assert(a, b)` không biên dịch được
# `assert` là macro một đối số: một dấu phẩy ở mức ngoặc ngoài (thường gặp khi
# viết `assert([x isEqualToString:[NSString stringWithFormat:..., arg]])`) làm
# clang báo "too many arguments" chỉ trên macOS — Linux local-check không thấy.
# Chỉ kiểm tests/*.m vì đó là nơi dùng assert() thật.
def mask_code(text):
    """Thay ký tự trong chuỗi ký tự và chú thích bằng khoảng trắng, giữ nguyên
    độ dài — để bộ đếm ngoặc không bị lừa bởi `@"]("` hay `// (`."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                out[i] = ' '; i += 1
        elif ch == '/' and i + 1 < n and text[i + 1] == '*':
            while i < n and not (text[i] == '*' and i + 1 < n and text[i + 1] == '/'):
                if text[i] != '\n': out[i] = ' '
                i += 1
            for _ in range(2):
                if i < n: out[i] = ' '; i += 1
        elif ch in ('"', "'"):
            quote = ch
            out[i] = ' '; i += 1
            while i < n and text[i] != quote:
                if text[i] == '\\' and i + 1 < n:
                    out[i] = ' '; i += 1
                if text[i] != '\n': out[i] = ' '
                i += 1
            if i < n: out[i] = ' '; i += 1
        else:
            i += 1
    return ''.join(out)

for path in sorted(glob.glob("tests/*.m")):
    text = read(path)
    masked = mask_code(text)
    for match in re.finditer(r"\bassert\(", masked):
        depth, i = 1, match.end()
        while i < len(masked) and depth > 0:
            ch = masked[i]
            # Bộ tiền xử lý CHỈ đếm ngoặc tròn (và ngoặc nhọn); ngoặc vuông
            # của Objective-C không che được dấu phẩy.
            if ch in "({":
                depth += 1
            elif ch in ")}":
                depth -= 1
            elif ch == "," and depth == 1:
                line = text[:i].count("\n") + 1
                fail(f"{path}:{line}: dấu phẩy ở mức ngoặc ngoài trong assert(...) — "
                     "tách biểu thức ra biến trước, assert chỉ nhận một đối số")
                break
            i += 1

# ------------------------- công cụ chạy trên luồng chính phải có trần ngắn
# `requiresMainThread` = handler chạy trên luồng UI của SpringBoard/Preferences.
# Mỗi giây handler giữ luồng đó là một giây giao diện đứng hình, nên trần phải
# ngắn. (Đã sửa một lỗi thật: nhánh "đã ở luồng chính" từng chạy handler KHÔNG
# có trần nào cả.) `liveData`/`sideEffect` không liên quan ở đây — chúng chỉ nói
# "đừng lấy từ bộ nhớ đệm trong lượt", đúng cho công cụ ghi/đọc trạng thái mới.
CATALOG = "Sources/SXToolCatalog.m"
if os.path.exists(CATALOG):
    text = read(CATALOG)
    for match in re.finditer(r"(\w+)\.requiresMainThread\s*=\s*YES", text):
        var = match.group(1)
        timeout_match = re.search(r"\b" + re.escape(var) + r"\.timeout\s*=\s*([0-9.]+)",
                                  text[max(0, match.start() - 400):match.end() + 400])
        if not timeout_match:
            continue   # dùng trần mặc định 8 s — cũng vượt ngưỡng dưới, báo lỗi luôn
        value = float(timeout_match.group(1))
        if value > 5.0:
            line = text[:match.start()].count("\n") + 1
            fail(f"{CATALOG}:{line}: công cụ “{var}” chạy trên luồng chính với trần "
                 f"{value:g}s (>5s) — giao diện sẽ đứng hình")

# ---------------------- plist: mọi hàng phải trỏ tới thứ THẬT SỰ tồn tại
# Ba lớp lỗi từng làm Settings văng ngay khi chạm một hàng:
#   1. `validValues` và `validTitles` lệch số phần tử ⇒ trang chọn truy cập
#      ngoài phạm vi khi vẽ bảng.
#   2. `detail` trỏ tới lớp không được biên dịch vào bundle ⇒ `NSClassFromString`
#      trả nil, Preferences đẩy một controller nil.
#   3. `configPlist` trỏ tới plist không có trong Resources ⇒ trang trắng.
# Kiểm ở đây (trước khi build) rẻ hơn nhiều so với một vòng cài trên máy.
PREFS_DIR = "Prefs"
objc_text = "\n".join(read(f) for f in sorted(
    glob.glob("Prefs/*.m") + glob.glob("Prefs/*.h")))
implemented = set(re.findall(r"@implementation\s+(\w+)", objc_text))
exported = set(re.findall(r"\b(\w+)\s*\(", objc_text)) | implemented
resources = {os.path.splitext(os.path.basename(f))[0]
             for f in glob.glob("Prefs/Resources/*.plist")}
for plist_path in sorted(glob.glob("Prefs/Resources/*.plist")):
    try:
        data = plistlib.load(open(plist_path, "rb"))
    except Exception:
        continue   # đã báo ở bước validate plist
    items = data.get("items") if isinstance(data, dict) else None
    if not isinstance(items, list):
        continue
    for index, row in enumerate(items):
        if not isinstance(row, dict):
            fail(f"{plist_path}: mục {index} không phải dictionary"); continue
        label = row.get("label", f"#{index}")
        values = row.get("validValues")
        titles = row.get("validTitles")
        if isinstance(values, list) or isinstance(titles, list):
            values = values if isinstance(values, list) else []
            titles = titles if isinstance(titles, list) else []
            if len(values) != len(titles):
                fail(f"{plist_path}: hàng “{label}” có {len(values)} validValues "
                     f"nhưng {len(titles)} validTitles — trang chọn sẽ truy cập ngoài phạm vi")
            for entry in values:
                if not isinstance(entry, str):
                    fail(f"{plist_path}: hàng “{label}” có validValue không phải chuỗi: {entry!r}")
        detail = row.get("detail")
        if isinstance(detail, str) and detail and detail not in exported:
            fail(f"{plist_path}: hàng “{label}” trỏ tới detail “{detail}” "
                 "nhưng không có lớp/hàm nào như vậy được biên dịch vào bundle")
        config = row.get("configPlist")
        if isinstance(config, str) and config and config not in resources:
            fail(f"{plist_path}: hàng “{label}” trỏ tới configPlist “{config}” "
                 "nhưng không có tệp đó trong Prefs/Resources")
        cell_class = row.get("cellClass")
        if isinstance(cell_class, str) and cell_class and cell_class not in exported:
            fail(f"{plist_path}: hàng “{label}” dùng cellClass “{cell_class}” không tồn tại")

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
