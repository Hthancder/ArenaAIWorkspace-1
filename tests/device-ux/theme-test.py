#!/usr/bin/env python3
import re, sys
from pathlib import Path
src = Path(sys.argv[1])
html = (src / 'embedded_resources/web_interface/index.html').read_text()
colors = (src / 'src/core/settingsColor.h').read_text()
js = (src / 'embedded_resources/web_interface/index.js').read_text()
server = (src / 'src/core/wifi/webInterface.cpp').read_text()
def rgb565(hexstr):
    x = int(hexstr.lstrip('#'),16)
    return ((x >> 19) << 11) | (((x >> 10) & 63) << 5) | ((x >> 3) & 31)
chips = re.findall(r'data-pri="(#[0-9A-F]+)" data-sec="(#[0-9A-F]+)" data-bg="(#[0-9A-F]+)">([^<]+)',html)
assert len(chips) >= 6
for pri,sec,bg,name in chips:
    match = re.search(r'\{"' + re.escape(name) + r'",\s*(0x[0-9A-F]+),\s*(0x[0-9A-F]+),\s*(0x[0-9A-F]+)\}',colors)
    assert match and [int(x,16) for x in match.groups()] == list(map(rgb565,(pri,sec,bg))), name
assert '"menuStyle"' in server and 'MENU_STYLE' in server
assert 'applyThemeCss(info.PRI_COLOR, info.SEC_COLOR, info.BG_COLOR, info.MENU_STYLE)' in js
assert 'menuStyle: $("#pers-style").value' in js
print('Shared palette and menu-style wiring tests passed')
