#include <cassert>
#include <iostream>
#include <vector>
#include "Preferences.h"
#include "MenuItemInterface.h"
#include "core/menu_items/QuickMenu.h"
SerialStub Serial; Config bruceConfig; TftStub tft; bool returnToMenu = false;
static int calls, step; static std::vector<std::vector<String>> seen;
bool wifiConnectMenu() { return true; }
void channel_analyzer_setup() {}
void ble_scan() { ++calls; }
void ble_guard_setup() {}
void startWebUi(bool) {}
int loopOptions(std::vector<Option>& opts, int, const char *title) {
    std::vector<String> labels; for (auto &o: opts) labels.push_back(o.label); seen.push_back(labels);
    String want;
    if (step == 0) want = "* BLE Scan";
    else if (step == 1) want = "Edit favorites";
    else if (step == 2) { assert(String(title) == "Pin shortcuts"); want = "[x] WiFi Connect"; }
    else want = "Back";
    ++step;
    for (size_t i=0; i<opts.size(); ++i) if (opts[i].label == want) { opts[i].operation(); return (int)i; }
    assert(false); return -1;
}
int main() {
    QuickMenu q; q.optionsMenu();
    assert(calls == 1);
    assert(fakePrefs["recent"] == 2);
    assert(fakePrefs["favorites"] == 30);
    assert(seen.at(1).at(0) == "Recent: BLE Scan");
    bool found=false; for (const auto &x : seen.at(4)) if (x == "* WiFi Connect") found=true;
    assert(!found);
    std::cout << "Device UX favorites regression tests passed\n";
}
