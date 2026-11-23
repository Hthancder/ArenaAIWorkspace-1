import pathlib, sys
root = pathlib.Path(sys.argv[1]) / 'src'
menu = (root / 'core/main_menu.cpp').read_text()
assert 'std::vector<Option>().swap(options);' in menu[menu.index('void MainMenu::begin'):menu.index('bool gridStyle')]
ble = (root / 'modules/ble/ble_common.cpp').read_text()
setup = ble[ble.index('bool ble_scan_setup()'):ble.index('void ble_scan()')]
assert '!NimBLEDevice::isInitialized() && !radioHasMemForBle()' in setup
scan = ble[ble.index('void ble_scan()'):ble.index('bool initBLEServer()')]
assert scan.index('pBLEScan->stop();') < scan.rindex('pBLEScan->clearResults();') < scan.index('if (!bleWasActiveBefore)')
suite = (root / 'modules/ble/BLE_Suite.cpp').read_text()
assert '!NimBLEDevice::isInitialized() && !radioHasMemForBle()' in suite
for name in ['ble_security_audit.cpp', 'ble_gatt_cloner.cpp']:
    src = (root / 'modules/ble' / name).read_text()
    assert '#if !defined(DSOLUTION_183_2MIC)\n    if (!radioHasMemForBle()) radioFreeWiFiForBle();\n#endif' in src
print('RAM recovery wiring checks passed')
