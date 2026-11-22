#include "modules/wifi/lan_guard_logic.h"
#include <cassert>
#include <cstdio>
#include <random>
#include <vector>

static std::vector<uint8_t> packet() {
    std::vector<uint8_t> p(240, 0);
    p[0] = 2; p[16] = 192; p[17] = 168; p[18] = 7; p[19] = 42;
    p[236] = 0x63; p[237] = 0x82; p[238] = 0x53; p[239] = 0x63;
    p.insert(p.end(), {0, 53, 1, 2, 54, 4, 192, 168, 7, 1, 255});
    return p;
}
int main() {
    LanGuardDhcpReply result;
    auto p = packet();
    assert(lanGuardParseDhcp(p.data(), p.size(), result));
    assert(result.type == 2 && result.hasServer && result.server[3] == 1 && result.offered[3] == 42);
    for (size_t i = 0; i < p.size(); ++i) {
        LanGuardDhcpReply unused;
        assert(!lanGuardParseDhcp(p.data(), i, unused));
    }
    auto invalid = p; invalid[236] = 0; assert(!lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid[0] = 1; assert(!lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid[243] = 3; assert(!lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid[243] = 5; assert(lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid[243] = 6; assert(lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid[242] = 2; assert(!lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid[245] = 5; assert(!lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid.pop_back(); invalid.insert(invalid.end(), {53, 1, 2, 255});
    assert(!lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid.pop_back(); invalid.insert(invalid.end(), {54, 4, 1, 2, 3, 4, 255});
    assert(!lanGuardParseDhcp(invalid.data(), invalid.size(), result));
    invalid = p; invalid.erase(invalid.begin()+244, invalid.begin()+250);
    assert(lanGuardParseDhcp(invalid.data(), invalid.size(), result) && !result.hasServer);
    assert(!lanGuardParseDhcp(nullptr, 0, result));

    // Exercise arbitrary input lengths and malformed DHCP options under sanitizers.
    std::mt19937 rng(12345);
    for (int i=0; i<20000; ++i) {
        std::vector<uint8_t> data(rng() % 800);
        for (auto &v : data) v = static_cast<uint8_t>(rng());
        if (data.size() >= 240) {
            data[0]=2; data[236]=0x63; data[237]=0x82; data[238]=0x53; data[239]=0x63;
        }
        lanGuardParseDhcp(data.data(), data.size(), result);
    }

    LanGuardGatewayBaseline baseline;
    const uint8_t gw1[4]={192,168,1,1}, gw2[4]={192,168,2,1};
    const uint8_t ap1[6]={1,2,3,4,5,6}, ap2[6]={1,2,3,4,5,7};
    const uint8_t mac1[6]={0,1,2,3,4,5}, mac2[6]={0,1,2,3,4,6};
    uint8_t old[6] = {};
    assert(!baseline.observe(mac1,old));
    baseline.link(gw1,ap1);
    assert(!baseline.known() && !baseline.observe(mac1,old) && baseline.known());
    assert(!baseline.observe(mac1,old));
    assert(baseline.observe(mac2,old) && !std::memcmp(old,mac1,6));
    baseline.link(gw1,ap2);
    assert(!baseline.known() && !baseline.observe(mac1,old));
    baseline.link(gw2,ap2);
    assert(!baseline.known() && !baseline.observe(mac2,old));
    baseline.link(nullptr,nullptr);
    assert(!baseline.known());
    baseline.link(gw1,ap1);
    assert(!baseline.observe(mac1,old));
    uint32_t last = 0; bool initialized = false;
    assert(lanGuardAllowSample(0xfffffff0u, last, initialized, 5000));
    assert(!lanGuardAllowSample(10, last, initialized, 5000));
    assert(lanGuardAllowSample(4984, last, initialized, 5000));
    assert(!lanGuardAllowSample(4985, last, initialized, 5000));
    std::puts("LAN Guard logic regression tests passed");
}
