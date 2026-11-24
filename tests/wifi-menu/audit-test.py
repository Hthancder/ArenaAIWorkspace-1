#!/usr/bin/env python3
"""Static audit of the reorganized WiFi menu.

Checks that every feature has exactly one canonical entry and that nested
submenus use the non-recursive Back option.
"""
import re
import sys
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else "firmware/Bruce")
code = (src / "src/core/menu_items/WifiMenu.cpp").read_text()
header = (src / "src/core/menu_items/WifiMenu.h").read_text()


def body(name):
    start = code.index(f"void WifiMenu::{name}(")
    depth = 0
    for i in range(code.index("{", start), len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return code[start:i + 1]
    raise AssertionError(f"unbalanced body for {name}")


functions = ["optionsMenu", "connectionMenu", "scanMenu", "defenseMenu", "lanMenu",
             "remoteMenu", "toolsMenu", "evilPortalMenu"]
bodies = {name: body(name) for name in functions}

# One canonical entry per capability, no matter how many menus used to duplicate it.
canonical = {
    "EvilPortal(": "evilPortalMenu",
    "portal_napt_setup": "evilPortalMenu",
    "addEvilWifiMenu": "evilPortalMenu",
    "removeEvilWifiMenu": "evilPortalMenu",
    "setEvilGatewayIp": "evilPortalMenu",
    "setEvilPasswordMode": "evilPortalMenu",
    "setEvilEndpointCreds": "evilPortalMenu",
    "setEvilAllowGetCreds": "evilPortalMenu",
    "setEvilEndpointSsid": "evilPortalMenu",
    "setEvilAllowSetSsid": "evilPortalMenu",
    "setEvilAllowEndpointDisplay": "evilPortalMenu",
    "wifi_atk_menu": "toolsMenu",
    "netcutMenu": "toolsMenu",
    "wifite_menu": "toolsMenu",
    "wifi_recover_menu": "toolsMenu",
    "brucegotchi_start": "toolsMenu",
    "sdr_menu": "toolsMenu",
    "probe_radar_setup": "scanMenu",
    "channel_analyzer_setup": "scanMenu",
    "dual_band_analyzer_setup": "scanMenu",
    "sniffer_setup": "scanMenu",
    "ftm_ranging_setup": "scanMenu",
    "csi_radar_setup": "scanMenu",
    "wids_guard_setup": "defenseMenu",
    "jam_detect_setup": "defenseMenu",
    "lan_guard_setup": "defenseMenu",
    "napt_router_setup": "lanMenu",
    "napt_http_inspector_setup": "lanMenu",
    "responder_plus_setup": "lanMenu",
    "lan_auditor_setup": "lanMenu",
    "wifiMACMenu": "connectionMenu",
    "wg_setup": "remoteMenu",
    "listenTcpPort": "remoteMenu",
    "clientTCP": "remoteMenu",
    "telnet_setup": "remoteMenu",
    "ssh_setup": "remoteMenu",
}
for token, owner in canonical.items():
    occurrences = [name for name, text in bodies.items() if token in text]
    assert occurrences == [owner], f"{token} should live only in {owner}, found {occurrences}"

# Network info has one entry and handles STA and AP-only modes.
assert code.count("displayAPInfo") == 1, "displayAPInfo must be referenced once, from showWifiInfo"
assert "showWifiInfo" in bodies["connectionMenu"] and "softAPIP" in code
assert "Network info" in bodies["connectionMenu"]

# Renamed entries keep their on-device feature guide (exact or prefix match).
guide = (src / "src/core/feature_guide.cpp").read_text()
for label in ["Packet Sniffer", "2.4 GHz Analyzer", "WIDS / Deauth Guard", "ARP Scan Hosts"]:
    assert f'"{label}"' in guide, f"feature guide lost {label}"
    assert label in code, f"{label} is not in the WiFi menu"

# menu lambdas that used to reopen the parent menu nested a loop per visit
assert '"Back", [this]' not in code, "Back must be a no-op lambda; loopOptions already returns"

# Every submenu ends on a Back option and a single loopOptions call.
for name in functions[1:]:
    text = bodies[name]
    own_level = re.findall(r"\n {4,8}loopOptions\(", text)
    assert len(own_level) == 1, f"{name} must render exactly one menu level, found {len(own_level)}"
    assert "backOption()" in text, f"{name} is missing Back"

# The top level stays short: connection, WebUI, tools, plus the full-build groups and Main Menu.
top = bodies["optionsMenu"]
labels = re.findall(r'\{?"([^"]+)",', top)
expected = ["WiFi Tools", "Survey & Analyze", "Defense", "LAN & HTTP", "Remote Access"]
# Turning the radio off must be one tap from the top level, not a nested entry.
assert "Turn Off WiFi" in top, "WiFi off should be reachable from the top level"
assert top.count('"Turn Off WiFi"') == 1
for label in expected:
    assert label in top, f"missing top-level group {label}"
assert "addOptionToMainMenu()" in top
assert top.index('"WiFi Tools"') < top.index('"Survey & Analyze"'), "WiFi Tools should come before the long tail"
print("WiFi menu dedupe, Back and group audit passed")
