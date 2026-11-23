#include <cassert>
#include <functional>
#include <iostream>
#include <string>
#include <vector>
using std::string;
struct Option { string label; std::function<void()> action; };
using wifi_mode_t = int;
constexpr int WIFI_MODE_AP = 1, WIFI_MODE_APSTA = 2, WIFI_MODE_STA = 3, MENU_TYPE_SUBMENU = 1;
struct Wifi { int mode = WIFI_MODE_STA; int getMode() { return mode; } } WiFi;
bool isWebUIActive = false, starting = false, ota = false, s_wifiSwitchBusy = false, returnToMenu = false;
bool cancellationCompletes = true, otaDuringCancellation = false, orphan = false;
struct Config {
    bool webUiAutoStart = false; string startupApp;
    void setStartupApp(const string &s) { startupApp = s; }
    void setWebUiAutoStart(bool b) { webUiAutoStart = b; }
} bruceConfig;
bool isWebUiActiveOrStarting() { return isWebUIActive || starting || orphan; }
int stopCount = 0, disconnectCount = 0, cancelCount = 0, warningCount = 0, startCount = 0;
std::vector<string> wanted, titles;
bool isOtaInProgress() { return ota; }
bool isWebUiStarting() { return starting; }
void displayWarning(const char *, bool) { ++warningCount; }
void cancelWebUiAutoStart() { ++cancelCount; if (cancellationCompletes) starting = false; if (otaDuringCancellation) ota = true; }
void stopWebUi() { ++stopCount; isWebUIActive = false; orphan = false; }
void wifiDisconnect() { ++disconnectCount; WiFi.mode = 0; }
#define pdMS_TO_TICKS(x) (x)
void vTaskDelay(int) {}
void startWebUi(bool ap) { ++startCount; isWebUIActive = true; WiFi.mode = ap ? WIFI_MODE_AP : WIFI_MODE_STA; }
int loopOptions(std::vector<Option> &items, int, const char *title) {
    titles.emplace_back(title);
    assert(!wanted.empty());
    string selected = wanted.front(); wanted.erase(wanted.begin());
    for (size_t i=0;i<items.size();++i) if (items[i].label == selected) { items[i].action(); return i; }
    assert(false); return -1;
}
#include "webui-extracted.inc"
int main() {
    wanted = {"Start on LAN WiFi", "Stop WebUI (keep WiFi)", "Back"};
    loopOptionsWebUi();
    assert(startCount == 1 && stopCount == 1 && disconnectCount == 0 && !isWebUIActive);
    assert((titles == std::vector<string>{"WebUI OFF", "WebUI ON", "WebUI OFF"}));
    isWebUIActive = true; ota = true;
    assert(!stopWebUiFromMenu(true) && stopCount == 1 && disconnectCount == 0);
    ota = false; s_wifiSwitchBusy = true;
    assert(!stopWebUiFromMenu(true) && stopCount == 1);
    s_wifiSwitchBusy = false; starting = true; cancellationCompletes = false;
    assert(!stopWebUiFromMenu(true) && stopCount == 1 && disconnectCount == 0);
    starting = false; cancellationCompletes = true; otaDuringCancellation = true;
    assert(!stopWebUiFromMenu(true) && stopCount == 1 && disconnectCount == 0);
    ota = false; otaDuringCancellation = false;
    assert(stopWebUiFromMenu(true) && stopCount == 2 && disconnectCount == 1);
    assert(warningCount == 4);
    bruceConfig.startupApp = "WebUI"; isWebUIActive = true;
    toggleWebUiAutoStartFromMenu();
    assert(bruceConfig.startupApp.empty() && !bruceConfig.webUiAutoStart && !isWebUIActive);
    assert(stopCount == 3 && disconnectCount == 1);
    toggleWebUiAutoStartFromMenu(); assert(bruceConfig.webUiAutoStart && stopCount == 3);
    isWebUIActive = true; ota = true; toggleWebUiAutoStartFromMenu();
    assert(!bruceConfig.webUiAutoStart && isWebUIActive && stopCount == 3);
    assert(warningCount == 5);
    ota = false; isWebUIActive = false; orphan = true;
    wanted = {"Clean up WebUI", "Back"}; titles.clear();
    loopOptionsWebUi();
    assert(!orphan && titles.front() == "WebUI cleanup");
    bruceConfig.startupApp = "Clock";
    toggleWebUiAutoStartFromMenu(); assert(bruceConfig.webUiAutoStart && bruceConfig.startupApp == "Clock");
    toggleWebUiAutoStartFromMenu(); assert(!bruceConfig.webUiAutoStart && bruceConfig.startupApp == "Clock");
    std::cout << "WebUI start/stop, cancellation, OTA and menu regression tests passed\n";
}
