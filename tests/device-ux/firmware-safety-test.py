#!/usr/bin/env python3
"""Guard critical UI/firmware wiring on the patched Bruce source."""
import pathlib, re, sys
src = pathlib.Path(sys.argv[1])
serial = (src / 'src/core/serialcmds.cpp').read_text()
web = (src / 'src/core/wifi/webInterface.cpp').read_text()
studio = (src / 'src/core/menu_items/StudioMenu.cpp').read_text()
files = (src / 'src/core/menu_items/FileMenu.cpp').read_text()
assert 's_capTarget' not in serial
assert 'String capture;' in serial and 'TeeSerialDevice tee(saved, &capture)' in serial
assert 's_capGeneration == packet.captureId' in serial
assert 's_capActive = false;' in serial
assert 'serveWebUIFile(request, "qr_local.js"' in web
assert 'parseBounded("delayMs", 0, 10000, v)' in web
assert 'parseBounded("confirmMs", 1000, 10000, ms)' in web
assert 'parseBounded("trigger", 0, 2, tr)' in web
assert 'xTaskCreate(badUsbAutoRunTestTask, "badUsbAutoTest", 6144, nullptr, 1, nullptr) != pdPASS' in web
assert 'Payload set to " + jsonEscape(fs+":"+path) + "\\\"}' in web
assert studio.count('sonar_guard_setup}') == 1
assert '{"Back",           []() {}}' in studio
assert 'std::vector<Option> micOptions' in studio
assert '!defined(DSOLUTION_183_2MIC)\n    options.push_back({"Connect"' in files
print('Firmware UI safety wiring checks passed')
