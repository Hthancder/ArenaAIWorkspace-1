import pathlib,sys
src=pathlib.Path(sys.argv[1]); dest=pathlib.Path(sys.argv[2])
board=(src/'boards/dsolution-183-2mic/interface.cpp').read_text()
start=board.index('static bool codecWrite(')
end=board.index('// =====================================================================================\n//  Setup',start)
(dest/'codec.inc').write_text(board[start:end])
mic=(src/'src/modules/others/mic.cpp').read_text()
start=mic.index('bool deinitMicroPhone()')
end=mic.index('// Applies the wiring',start)
start2=mic.index('bool InitI2SMicroPhone()')
end2=mic.index('void mic_test_one_task()',start2)
(dest/'mic.inc').write_text(mic[start:end]+mic[start2:end2])
web=(src/'src/core/wifi/webInterface.cpp').read_text()
loop=web[web.index('void startWebUi(bool mode_ap)'):web.index('bool startWebUiHeadless(')]
assert 'if (!isOtaInProgress()) uxService();' in loop
assert loop.index('while (!check(EscPress))') < loop.index('if (!isOtaInProgress()) uxService();')
assert 'bool codecStarted = false;' in mic and 'if (codecStarted) _setup_codec_mic(false);' in mic
assert 'if (micOwned) deinitMicroPhone();' in mic
assert 'while (filled < total)' in mic
print('WebUI and microphone wiring checks passed')
