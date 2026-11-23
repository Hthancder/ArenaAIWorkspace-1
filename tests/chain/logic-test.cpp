#include "modules/wifi/chain_logic.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

int main() {
    // Chain identity / steps
    assert(chainIdFromString("napt-lan") == CHAIN_NAPT_LAN);
    assert(chainIdFromString("NAPT-LAN") == CHAIN_NAPT_LAN);
    assert(chainIdFromString("bogus") == CHAIN_NONE);
    assert(strcmp(chainIdName(CHAIN_GUARD_AUDIT), "guard-audit") == 0);
    assert(strcmp(chainIdTitle(CHAIN_RECON_CAPTURE), "Recon -> Capture") == 0);
    assert(strstr(chainBlockReason(CHAIN_NEED_WIFI_MEM), "Low DMA RAM") != nullptr);
    ChainStep steps[8];
    assert(chainSteps(CHAIN_NAPT_LAN, steps, 8) == 4);
    assert(strcmp(steps[0].tool, "NAPT") == 0);
    assert(chainSteps(CHAIN_NONE, steps, 8) == 0);
    // total count is returned even when out is null (query mode)
    assert(chainSteps(CHAIN_NAPT_LAN, nullptr, 0) == 4);

    // Scoring: decloaked bonus, sig strength mapping
    ChainTarget a{}, b{};
    strcpy(a.ssid, "A"); a.channel = 6; a.rssi = -50; a.cleanScore = 80; a.decloaked = true;
    strcpy(b.ssid, "B"); b.channel = 1; b.rssi = -40; b.cleanScore = 10; b.decloaked = false;
    int sa = chainScoreTarget(a.rssi, a.cleanScore, a.decloaked);
    int sb = chainScoreTarget(b.rssi, b.cleanScore, b.decloaked);
    assert(sa > sb); // a gets +50 decloaked bonus
    assert(sa == (128 - 50) + 80 + 50);
    // empty / out-of-range
    assert(chainPickBestTarget(nullptr, 0) == -1);
    ChainTarget one[1]; one[0]=a;
    assert(chainPickBestTarget(one, 1) == 0);

    // pick best among several
    ChainTarget list[3]; list[0]=a; list[1]=b; list[2]=a;
    list[2].rssi = -90; list[2].cleanScore = 0; list[2].decloaked = false;
    assert(chainPickBestTarget(list, 3) == 0);

    // JSON int reader / guard count
    assert(chainJsonInt("{\"arpChanges\":2,\"dhcpMismatch\":1}", "\"arpChanges\"", -1) == 2);
    assert(chainJsonInt("{\"arpChanges\":2}", "\"dhcpMismatch\"", 9) == 9);
    assert(chainGuardAlertCount("{\"arpChanges\":2,\"dhcpMismatch\":1}") == 3);
    assert(chainGuardAlertCount("{\"arpChanges\":1,\"rogueDhcp\":2}") == 3);
    assert(chainGuardAlertCount("{}") == 0);
    assert(chainGuardAlertCount(nullptr) == 0);

    // /wifi_airtime.json parsing
    const char *air = "{\"bestCh\":6,\"bestScore\":88,\"hidden\":[{\"bssid\":\"AA:BB:CC:DD:EE:FF\",\"ch\":6,\"rssi\":-55,\"decloaked\":true,\"ssid\":\"Home\"},{\"bssid\":\"11:22:33:44:55:66\",\"ch\":1,\"rssi\":-70,\"decloaked\":false,\"ssid\":\"Cafe\"}]}";
    assert(chainParseAirtimeBestCh(air) == 6);
    assert(chainParseAirtimeBestScore(air) == 88);
    assert(chainParseAirtimeBestCh("{\"bestCh\":99}") == 0);
    assert(chainParseAirtimeBestCh(nullptr) == 0);
    ChainTarget hidden[4];
    size_t n = chainParseHiddenTargets(air, hidden, 4);
    assert(n == 2);
    assert(strcmp(hidden[0].ssid, "Home") == 0 && hidden[0].channel == 6 && hidden[0].decloaked);
    assert(hidden[1].channel == 1 && !hidden[1].decloaked);
    assert(chainPickBestTarget(hidden, n) == 0);
    // malformed / truncated inputs must not crash and yield 0
    const char *bads[] = {"", "{", "{\"hidden\":[", "{\"hidden\":[{\"bssid\":\"XX\"}]}", "{\"bestCh\":999}", nullptr};
    for (int i = 0; bads[i]; i++) {
        ChainTarget h[2]; chainParseHiddenTargets(bads[i], h, 2);
        chainParseAirtimeBestCh(bads[i]);
        chainGuardAlertCount(bads[i]);
    }
    // missing fields inside hidden entry => skipped
    const char *noCh = "{\"hidden\":[{\"bssid\":\"AA:BB:CC:DD:EE:FF\",\"ssid\":\"NoCh\"}]}";
    assert(chainParseHiddenTargets(noCh, hidden, 4) == 0);

    // BLE guard log parsing
    const char *ble = "# header\nTile-like | AA:BB:CC:DD:EE:FF | addrType=1 | RSSI=-60 dBm | sweeps=5 | age=10s\nSmartTag-like | 11:22:33:44:55:66 | addrType=0 | RSSI=-50 dBm | sweeps=9 | age=3s\nbad line\n";
    BleChainCandidate bc[4];
    size_t bn = chainParseBleGuardCandidates(ble, strlen(ble), bc, 4);
    assert(bn == 2);
    // sorted by hits desc
    assert(strcmp(bc[0].mac, "11:22:33:44:55:66") == 0 && bc[0].hits == 9);
    assert(bc[1].hits == 5);
    assert(chainParseBleGuardCandidates("", 0, bc, 4) == 0);
    assert(chainParseBleGuardCandidates(nullptr, 10, bc, 4) == 0);
    // long line truncation must not crash
    char longline[700]; memset(longline, 'A', sizeof(longline)-1); longline[sizeof(longline)-1]=0;
    assert(chainParseBleGuardCandidates(longline, strlen(longline), bc, 4) == 0);

    // Preconditions
    ChainPreconditions p{}; p.wifiMemOk = true; p.bleMemOk = true; p.usbHidOk = true; p.micOk = true;
    assert(chainCheckPreconditions(CHAIN_NAPT_LAN, p) == CHAIN_OK);
    p.wifiMemOk = false;
    assert(chainCheckPreconditions(CHAIN_NAPT_LAN, p) == CHAIN_NEED_WIFI_MEM);
    assert(chainCheckPreconditions(CHAIN_NONE, p) == CHAIN_UNKNOWN);
    p.wifiMemOk = true; p.bleMemOk = false;
    assert(chainCheckPreconditions(CHAIN_BLE_PIPELINE, p) == CHAIN_NEED_BLE_MEM);
    p.bleMemOk = true; p.usbHidOk = false;
    assert(chainCheckPreconditions(CHAIN_USB_VERIFY, p) == CHAIN_NEED_USB_HID);
    // watcher (NAPT/Portal/Guard must be running) reuses same preconditions
    ChainPreconditions w{}; w.naptRunning = true;
    assert(chainCheckWatcher(CHAIN_NAPT_LAN, w) == CHAIN_OK);
    w.naptRunning = false;
    assert(chainCheckWatcher(CHAIN_NAPT_LAN, w) == CHAIN_NEED_NAPT);

    // Guard audit summary
    char summary[160];
    size_t out = chainGuardAuditSummary("{\"arpChanges\":2,\"dhcpMismatch\":1}", "{\"devices\":5,\"findings\":1}", summary, sizeof(summary));
    assert(out > 0);
    assert(strstr(summary, "guard alerts=3") && strstr(summary, "lan devices=5"));
    assert(chainGuardAuditSummary(nullptr, nullptr, nullptr, 0) == 0);
    assert(chainGuardAuditSummary(nullptr, nullptr, summary, 0) == 0);

    // Fuzz-ish: random bytes through bounded parsers under ASan
    std::mt19937 rng(123);
    for (int i = 0; i < 8000; i++) {
        std::string s(rng() % 900, '\0');
        for (auto &c : s) c = char(rng() % 256);
        chainGuardAlertCount(s.c_str());
        chainParseAirtimeBestCh(s.c_str());
        chainParseHiddenTargets(s.c_str(), hidden, 4);
        chainParseBleGuardCandidates(s.c_str(), s.size(), bc, 4);
        chainGuardAuditSummary(s.c_str(), s.c_str(), summary, sizeof(summary));
        ChainPreconditions rp{}; rp.wifiMemOk = rng() % 2; rp.bleMemOk = rng() % 2; rp.usbHidOk = rng() % 2; rp.micOk = rng() % 2;
        for (int cid = 0; cid < (int)CHAIN_COUNT; cid++) chainCheckPreconditions((ChainId)cid, rp);
    }

    std::puts("Chain logic regression tests passed");
}
