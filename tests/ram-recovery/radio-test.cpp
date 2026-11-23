#include <cassert>
#include "core/radio_mem.h"
MockSerial Serial;
MockESP ESP;
MockWiFi WiFi;
size_t blockSize, totalFree;
bool hasPsram = true, webUi = false;
int freedWifi = 0, freedBle = 0, released = 0;
bool isWebUiActiveOrStarting() { return webUi; }
bool radioFreeBleForWifi() { ++freedBle; return true; }
bool radioFreeWiFiForBle() { ++freedWifi; return true; }
void sdrBankHeapInit() {}
void sdrBankReleaseForRadio() { ++released; }
int main() {
    webUi = true; WiFi.mode = 1; blockSize = 60*1024; totalFree = blockSize;
    assert(radioHasMemForBle()); assert(released == 0 && freedWifi == 0);
    blockSize = 10*1024; totalFree = 20*1024;
    assert(!radioHasMemForBle()); assert(!radioHasMemForWifi());
    assert(freedWifi == 0 && freedBle == 0);
    blockSize = 30*1024; totalFree = 50*1024;
    assert(!radioHasMemForBle()); // PSRAM relaxation requires Wi-Fi off
    WiFi.mode = 0; assert(radioHasMemForBle());
    totalFree = 47*1024; assert(!radioHasMemForBle());
    blockSize = 15*1024; assert(radioHasMemForWifi());
}
