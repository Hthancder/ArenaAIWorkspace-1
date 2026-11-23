from pathlib import Path
import sys
root = Path(sys.argv[1])
web = (root / 'src/core/wifi/webInterface.cpp').read_text()
menu = (root / 'src/core/menu_items/ConfigMenu.cpp').read_text()
settings = (root / 'src/core/settings.cpp').read_text()
quick = (root / 'src/core/menu_items/QuickMenu.cpp').read_text()
wifi = (root / 'src/core/menu_items/WifiMenu.cpp').read_text()
assert 's_webUiCancelRequested && isWebUIActive) stopWebUi()' in web
assert 'xTaskCreate(webUiAutoStartTask' in web and 's_webUiQueued = false;' in web[web.index('void startWebUiBackgroundTask'):]
assert 'bruceConfig.webUiAutoStart || bruceConfig.startupApp == "WebUI"' in menu
assert 'if (bruceConfig.startupApp == "WebUI") bruceConfig.setStartupApp("")' in web
assert 'toggleWebUiAutoStartFromMenu()' in menu
assert 'if (appName == "WebUI") continue;' in settings
assert 'case 4: loopOptionsWebUi();' in quick
assert 'stopWebUiFromMenu(true)' in wifi
portal = (root / 'src/modules/wifi/evil_portal.cpp').read_text()
assert 'printFootnote("Deauth not configured")' in portal
assert 'printFootnote("Deauth paused")' in portal
print('WebUI startup and entry-point wiring regression checks passed')
