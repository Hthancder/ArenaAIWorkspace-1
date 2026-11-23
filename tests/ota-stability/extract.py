import pathlib,sys
src=pathlib.Path(sys.argv[1]); tmp=pathlib.Path(sys.argv[2]);
s=(src/'src/core/wifi/webInterface.cpp').read_text()
a=s.index('    // Chunked Resumable WebOTA API'); b=s.index('    // Software USB ROM Bootloader trigger',a)
(tmp/'routes.inc').write_text(s[a:b])
a=s.index('static void otaAcquireLock(');b=s.index('static void delayedRestartTask(',a)
(tmp/'lifecycle.inc').write_text(s[a:b])
a=s.index('static bool otaSessionMatches(');b=s.index('bool checkUserWebAuth(',a)
(tmp/'match.inc').write_text(s[a:b])
a=s.index('#if defined(DSOLUTION_183_2MIC)\nbool otaUiConsumeRedraw()');b=s.index('void drawWebUiScreen(',a)
(tmp/'ui.inc').write_text(s[a:b])
h=(src/'include/globals.h').read_text();assert h.index('otaUiCheckpoint();',h.index('extern inline bool check(')) < h.index('if (!btn) return false;',h.index('extern inline bool check('))
d=(src/'src/core/display.cpp').read_text();assert 'if (otaUiConsumeRedraw())' in d
assert 'if (!isOtaInProgress()) uxService();' in s
print('OTA screen checkpoint wiring checks passed')

boot=s[s.index('    auto handleBootloaderReq'):s.index('    server->on("/bootloader", HTTP_POST')]
reboot=s[s.index('    // Reboot device (supports ?target='):s.index('    // List files',s.index('    // Reboot device (supports ?target='))]
assert 'if (isOtaInProgress() || s_otaRestartPending)' in boot and 'if (isOtaInProgress() || s_otaRestartPending)' in reboot
assert '!= pdPASS' in boot and '!= pdPASS' in reboot
