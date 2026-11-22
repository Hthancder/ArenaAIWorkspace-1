#include "modules/wifi/wifi_observation_logic.h"
#include "modules/ble/ble_guard_logic.h"
#include <cassert>
#include <cstdio>
#include <random>
#include <vector>

int main() {
    WifiSsidElement ssid;
    std::vector<uint8_t> f(36, 0);
    f.insert(f.end(), {1, 1, 0x82, 0, 3, 'a', 'b', 'c', 3, 1, 11});
    assert(wifiFindSsid(f.data(), f.size(), 36, ssid));
    assert(ssid.length == 3 && !ssid.allZero && ssid.bytes[0] == 'a');
    auto empty = f;
    empty.resize(36); empty.insert(empty.end(), {0, 0});
    assert(wifiFindSsid(empty.data(), empty.size(), 36, ssid) && ssid.allZero && ssid.length == 0);
    auto hidden = f; hidden.resize(36); hidden.insert(hidden.end(), {0, 3, 0, 0, 0});
    assert(wifiFindSsid(hidden.data(), hidden.size(), 36, ssid) && ssid.allZero);
    auto partial = f; partial.resize(36); partial.insert(partial.end(), {0, 5, 'a', 'b', 0, 0, 0, 0});
    // The final four bytes are an FCS, never the last bytes of an SSID.
    assert(!wifiFindSsid(partial.data(), partial.size()-4, 36, ssid));
    auto duplicate = f; duplicate.insert(duplicate.end(), {0, 1, 'x'});
    assert(!wifiFindSsid(duplicate.data(), duplicate.size(), 36, ssid));
    auto oversized = f; oversized.resize(36); oversized.push_back(0); oversized.push_back(33); oversized.resize(71, 'x');
    assert(!wifiFindSsid(oversized.data(), oversized.size(), 36, ssid));
    auto malformed = f; malformed.push_back(7);
    assert(!wifiFindSsid(malformed.data(), malformed.size(), 36, ssid));
    assert(!wifiFindSsid(nullptr, 0, 0, ssid));
    assert(!wifiFindSsid(f.data(), f.size(), f.size()+1, ssid));

    WifiBssidSet set;
    // Find two distinct addresses that hash to the same initial bucket.
    int first[64]; for (int &v : first) v = -1;
    bool collisionFound = false;
    for (int i=0; i<256 && !collisionFound; ++i) {
        const uint8_t mac[6] = {0,0,0,0,static_cast<uint8_t>(i >> 4),static_cast<uint8_t>(i)};
        uint32_t h = 2166136261u;
        for (auto byte : mac) { h ^= byte; h *= 16777619u; }
        const int bucket = h % 64;
        if (first[bucket] >= 0) {
            int old = first[bucket];
            const uint8_t other[6] = {0,0,0,0,static_cast<uint8_t>(old >> 4),static_cast<uint8_t>(old)};
            set.add(other); set.add(mac); set.add(other);
            assert(set.count() == 2);
            collisionFound = true;
        } else first[bucket] = i;
    }
    assert(collisionFound); set.clear();
    for (unsigned i=0; i<64; ++i) {
        const uint8_t mac[6] = {0,0,0,0,0,static_cast<uint8_t>(i)};
        set.add(mac); set.add(mac);
    }
    assert(set.count() == 64 && !set.saturated());
    const uint8_t extra[6] = {0,0,0,0,0,64};
    set.add(extra); assert(set.count() == 64 && set.saturated());
    set.clear(); assert(set.count() == 0 && !set.saturated());
    set.add(extra); assert(set.count() == 1);
    assert(wifiObservedRate(10, 200) == 50);
    assert(wifiObservedRate(1, 0) == 0);
    assert(wifiObservedRate(UINT32_MAX, 1) == UINT32_MAX);
    assert(wifiEstimatedLoad(6000, 0, 100) == 8);
    assert(wifiEstimatedLoad(6000, 0, 200) == 4);
    assert(wifiEstimatedLoad(UINT32_MAX, UINT32_MAX, 1) == 100);
    assert(wifiEstimatedLoad(10, 1, 0) == 0);
    assert(wifiRetryPercent(20, 40) == 50);
    assert(wifiRetryPercent(UINT32_MAX, 1) == 100);
    assert(wifiRetryPercent(0, 0) == 0);
    uint8_t load[14] = {}; bool sampled[14] = {};
    assert(wifiPickBestPrimary(load, sampled) == 0);
    for (int i=1; i<=11; ++i) sampled[i] = true;
    load[1] = 100; load[6] = 40; load[11] = 0;
    assert(wifiPickBestPrimary(load, sampled) == 11);
    sampled[7] = false;
    assert(wifiPickBestPrimary(load, sampled) == 0);
    assert(wifiCleanScore(load, 0) == -1 && wifiCleanScore(load, 14) == -1);

    std::vector<uint8_t> apple = {0x4c,0,0x12,0x19};
    apple.resize(29, 0x33);
    assert(bleGuardManufacturer(apple.data(), apple.size()) == BleGuardManufacturer::FindMyLike);
    for (size_t i=0; i<apple.size(); ++i)
        assert(bleGuardManufacturer(apple.data(), i) == BleGuardManufacturer::None);
    auto nearby=apple; nearby[2]=0x07;
    assert(bleGuardManufacturer(nearby.data(),nearby.size()) == BleGuardManufacturer::None);
    auto mixed=apple; mixed.insert(mixed.end(), {0x01, 0x01, 0x42});
    assert(bleGuardManufacturer(mixed.data(),mixed.size()) == BleGuardManufacturer::FindMyLike);
    mixed.push_back(0x12); assert(bleGuardManufacturer(mixed.data(),mixed.size()) == BleGuardManufacturer::None);
    const uint8_t samsung[] = {0x75,0,0x42,4,1,2,3,4};
    assert(bleGuardManufacturer(samsung, sizeof(samsung)) == BleGuardManufacturer::SmartTagLike);
    assert(bleGuardManufacturer(samsung, sizeof(samsung)-1) == BleGuardManufacturer::None);
    assert(bleGuardManufacturer(nullptr, 100) == BleGuardManufacturer::None);
    assert(bleGuardIncrement(65535) == 65535 && bleGuardIncrement(2) == 3);
    assert(!bleGuardExpired(9, 0xfffffff0u, 30));
    assert(bleGuardExpired(14, 0xfffffff0u, 30));

    std::mt19937 rng(7);
    for (int i=0;i<30000;++i) {
        std::vector<uint8_t> b(rng()%256);
        for (auto &v : b) v = static_cast<uint8_t>(rng());
        wifiFindSsid(b.data(), b.size(), rng()%300, ssid);
        if (b.size() >= 2 && i % 3 == 0) { b[0]=0x4c; b[1]=0; }
        bleGuardManufacturer(b.data(), b.size());
    }
    std::puts("Radio observation regression tests passed");
}
