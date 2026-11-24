#!/usr/bin/env python3
"""Static audit of the deduplicated on-device menus (board: dsolution-183-2mic).

The complaint this guards against: the same feature reachable from two or three
parent menus, so the user sees the same row again and again and never knows
which copy is the right one. Each check names the single owner of a feature.
"""
import re
import sys
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else "firmware/Bruce")
items = src / "src/core/menu_items"


def read(name):
    return (items / f"{name}.cpp").read_text()


def body(code, name, cls=None):
    needle = f"void {cls}::{name}(" if cls else f"void {name}("
    start = code.index(needle)
    depth = 0
    for i in range(code.index("{", start), len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return code[start : i + 1]
    raise AssertionError(f"unbalanced body for {name}")


studio = read("StudioMenu")
others = read("OthersMenu")
config = read("ConfigMenu")
files = read("FileMenu")
ble = read("BleMenu")
wifi = read("WifiMenu")
main_menu = (src / "src/core/main_menu.cpp").read_text()
groups = (items / "MenuGroups.h").read_text()
suite = (src / "src/modules/ble/BLE_Suite.cpp").read_text()

# --- BadUSB: exactly one tree -------------------------------------------------
badusb_rows = ["USB Descriptor Info", "USB Keyboard", "Smart BadUSB Suite", "Virtual USB Drive", "USB U2F"]
for row in badusb_rows:
    holders = [name for name, code in (("BadUsbMenu", read("BadUsbMenu")), ("OthersMenu", others)) if f'"{row}"' in code]
    assert holders == ["BadUsbMenu"], f"{row} must only be listed in BadUsbMenu, found {holders}"
# Forwards need the real MainMenu definition, and every include must be the
# src-relative path (a bare "main_menu.h" only resolves inside src/core).
assert '#include "core/main_menu.h"' in others
assert '#include "main_menu.h"' not in others, "include path must be src-relative"
assert "mainMenu.badUsbMenu.optionsMenu()" in others, "Others must forward to the single BadUSB menu"
assert "ducky_setup" not in others.replace("mainMenu.badUsbMenu", ""), "Others kept a second BadUSB list"

# --- Microphone: one list -----------------------------------------------------
assert studio.count('"Spectrum"') == 1 and '"Spectrum"' not in others
assert studio.count('"Record"') == 1 and '"Record"' not in others
assert "mainMenu.studioMenu.micMenu()" in others, "Others must forward to Studio's microphone list"
assert "Sonar Motion Guard" not in studio, "sonar guard is a top-level tool, not a mic row"
assert studio.count('"Sonar Guard"') == 1, "Sonar Guard should be listed once, in Studio"

# --- Dual boot: one place -----------------------------------------------------
for name, code in (("StudioMenu", studio), ("OthersMenu", others), ("ConfigMenu", config)):
    assert "rebootToBootMenu" not in code, f"{name} must not repeat the dual-boot switches"
    assert "rebootToXiaoZhi" not in code, f"{name} must not repeat the XiaoZhi switch"
assert main_menu.count("rebootToBootMenu") == 1
assert main_menu.count("rebootToXiaoZhi") == 1

# --- Pet: preview is an app, the active one is a WiFi tool --------------------
assert "Pet preview" not in config, "the display-only pet is not a Display & UI setting"
assert studio.count("petPreview") == 1
assert wifi.count("brucegotchi_start") == 1

# --- BLE sniffer: one entry, one implementation per build ---------------------
assert ble.count('"BLE Sniffer"') == 1, "exactly one sniffer row on the Bluetooth menu"
assert "\"BLE Sniffer\"" not in suite, "the BLE Suite must not repeat the sniffer row"
sniffer_h = (src / "src/modules/ble/ble_sniffer.h").read_text()
assert "BLE_SnifferMenu" in sniffer_h
assert "BLE_Sniffer();\n#endif" not in sniffer_h, "the sniffer declaration must exist in every build"

# --- WebUI: one entry point ---------------------------------------------------
assert '"WebUI", loopOptionsWebUi' not in files, "Files must not offer a second WebUI entry"
assert "loopOptionsWebUi" in wifi
assert files.count("loopOptionsWebUi") <= 1

# --- Two different things must not share a label ------------------------------
assert '"Set Clock"' in config, "the time-setting row must not be labelled like the Clock app"
assert studio.count('"Clock"') == 1

# --- Shared helpers replace hand-rolled Back / Main Menu rows ----------------
for helper in ("backOption", "mainMenuOption"):
    assert helper in groups
assert '"Main Menu", []() {}' not in config, "Config must use the shared Main Menu helper"
assert "menu_groups::mainMenuOption()" in studio and "menu_groups::mainMenuOption()" in config
print("Menu dedupe audit passed")
