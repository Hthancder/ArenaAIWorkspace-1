#!/usr/bin/env python3
"""Regression locks for the UI/UX consistency sweep.

Every check pins a concrete defect that used to exist in the firmware, so a
future edit that reintroduces it fails here instead of on the device.
"""
import re, sys, pathlib

src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "firmware/Bruce")
fails = []

def read(rel):
    return (src / rel).read_text(encoding="utf-8", errors="ignore")

def check(name, ok, detail=""):
    if not ok:
        fails.append(f"{name}: {detail}")

NON_ASCII = re.compile(r"[^\x00-\x7F]")

# 1) The panel font is a bitmap ASCII font (LovyanGFX default; DisplayDrivers never
#    calls setFont), so a non-ASCII menu label or drawn status string is garbage.
ui_files = ["src/modules/ble/ble_spam.cpp", "src/core/menu_items/QuickMenu.cpp", "src/modules/others/tururururu.cpp"]
for rel in ui_files:
    txt = read(rel)
    for i, line in enumerate(txt.splitlines(), 1):
        s = line.strip()
        if not s.startswith(("options.push_back", "{ \"", '{"')) and "push_back(\"" not in s:
            continue
        for m in re.finditer(r'"((?:[^"\\]|\\.){2,80})"', s):
            if NON_ASCII.search(m.group(1)):
                fails.append(f"{rel}:{i}: non-ASCII menu label {m.group(1)!r} cannot render")

# 2) Button hints must come from one place, tuned to this 3-button board.
flags = read("include/precompiler_flags.h")
for macro in ["UI_HINT_SELECT", "UI_HINT_BACK", "UI_HINT_LIST", "UI_HINT_STOP"]:
    check(f"hint macro {macro}", f"#define {macro}" in flags, "missing from precompiler_flags.h")
check("BTN_ALIAS wired into hints", 'UI_HINT_SELECT BTN_ALIAS' in flags or 'BTN_ALIAS' in flags.split("UI_HINT_SELECT")[1][:80], "hints must use BTN_ALIAS")

# No source file may hardcode a keyboard-only hint: this board has three
# physical buttons (Prev/Next/Sel), so "Click", "ESC" and a bare "SEL " prefix
# in a footer are all wrong. Serial-console prompts are exempt -- they really
# are typed on a PC.
SERIAL = {"src/core/connect/serial_commands.cpp", "src/core/serial_commands/wifi_commands.cpp"}
HINT_CALL = re.compile(r"drawString|drawCentreString|drawAlignedString|padprintln")
for path in (src / "src").rglob("*.cpp"):
    rel = str(path.relative_to(src)).replace("\\", "/")
    txt = path.read_text(encoding="utf-8", errors="ignore")
    for i, line in enumerate(txt.splitlines(), 1):
        if not HINT_CALL.search(line):
            continue
        if rel in SERIAL:
            continue
        for banned in ("Click=", "ESC=", "SEL ", "[ESC]", "SEL:"):
            if banned in line:
                check(f"hardcoded PC hint {rel}:{i}", False, f"{banned!r} in {line.strip()[:60]}")
                break

# 3) A selectable row whose callback does nothing looks like a dead button.
for path in (src / "src").rglob("*.cpp"):
    txt = path.read_text(encoding="utf-8", errors="ignore")
    for m in re.finditer(r'\{\s*"(---[^"]*---)"\s*,\s*\[\s*\]\s*\(\s*\)\s*\{\s*\}\s*\}', txt):
        check(f"dead separator row {path.relative_to(src)}", False, m.group(1))

# 4) Menu labels are clamped to the row width before drawing.
disp = read("src/core/display.cpp")
check("fitMenuLabel exists", "String fitMenuLabel(" in disp, "helper removed")
check("neighbour rows clamped", disp.count("fitMenuLabel(options[idx].label, neighborMaxChars)") == 2,
      "both neighbours must use fitMenuLabel")
check("selected row clamped", "fitMenuLabel(selLbl," in disp, "selected row must use fitMenuLabel")
hdr = read("src/core/display.h")
check("fitMenuLabel declared", "String fitMenuLabel(const String &label, int maxChars);" in hdr, "missing prototype")

# 5) Every /ota/chunk answer is JSON: the upload page parses with .json(), so a
#    plain-text 401 surfaced as "Network error" instead of "log in again".
web = read("src/core/wifi/webInterface.cpp")
start = web.index('"/ota/chunk"')
chunk = web[start:]
chunk = chunk[:chunk.index('server->on("', 10) if 'server->on("' in chunk[10:] else len(chunk)]
st = chunk.index("if (!st->authOk)")
auth_reply = chunk[st:st + 400]
check("ota/chunk 401 is JSON", "application/json" in auth_reply, "browser cannot parse plain text")

# 6) WebUI ships one language: English, like the rest of the interface.
js = read("embedded_resources/web_interface/index.js")
CJK_VI = re.compile(r"[\u00e0-\u00e3\u00e8-\u00ea\u00ec-\u00ed\u00f2-\u00f5\u00f9-\u00fa\u0103\u0111\u0129\u0169\u01a1\u01b0\u1ea0-\u1ef9]", re.I)
allowed = {"const base="}  # captive-portal page content is deliberately Vietnamese
for i, line in enumerate(js.splitlines(), 1):
    if not CJK_VI.search(line):
        continue
    if any(a in line for a in allowed):
        continue
    fails.append(f"index.js:{i}: Vietnamese UI string in an English interface: {line.strip()[:70]}")

if fails:
    print("UI/UX consistency checks FAILED:")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("UI/UX consistency checks passed")
