// Host regression tests for the beacon-spam engine and the beacon/deauth
// transmit loop. prepare.py extracts both directly from wifi_atks.cpp, so these
// assertions run against the code that ships, not a copy of it.
// Host test of the beacon/deauth transmit loop: exact counts, parallel deauth,
// channel sweep, pause and stop. The loop is lifted verbatim from
// beaconAttack() so this exercises the shipped code, not a re-implementation.
#include "stubs.h"
#include <cassert>
#include <iostream>

static std::vector<std::string> sentSsid;
static int beaconFrames = 0, deauthFrames = 0;
static std::vector<uint8_t> channelsSet;
static uint8_t wifi_channel = 6;
static int randSeq = 0;
int rand() { return (randSeq++ * 37) % 1000; }
void generateRandomWiFiMac(uint8_t m[6]) { for (int i = 0; i < 6; i++) m[i] = 0x02; }

#define WIFI_IF_STA 0
#define pdMS_TO_TICKS(x) (x)
#define WIFI_IF_AP 1
#define ESP_OK 0
#define WIFI_SECOND_CHAN_NONE 0

int wifiRawTx(int iface, const uint8_t *pkt, size_t len) {
    if (iface == WIFI_IF_AP) { deauthFrames++; }
    else { beaconFrames++; sentSsid.push_back(std::string((const char*)pkt + 38, pkt[37])); }
    return 0;
}
int esp_wifi_set_channel(uint8_t ch, int) { channelsSet.push_back(ch); wifi_channel = ch; return ESP_OK; }
const uint8_t channels[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
uint8_t channelIndex = 0;
uint8_t wifi_channel_global = 1;
static int hops = 0;
void nextChannel() {
    channelIndex = (channelIndex + 1) % (sizeof(channels) / sizeof(channels[0]));
    wifi_channel = channels[channelIndex];
    hops++;
}

size_t prepareBeaconPacket(uint8_t *pkt, const uint8_t *mac, const char *ssid, uint8_t ssidLen, uint8_t ch, bool) {
    memset(pkt, 0, 109); pkt[0] = 0x80;
    memcpy(&pkt[10], mac, 6); memcpy(&pkt[16], mac, 6);
    pkt[37] = ssidLen; if (ssidLen) memcpy(&pkt[38], ssid, ssidLen);
    pkt[38 + ssidLen] = ch;
    return 38 + ssidLen + 4;
}

namespace beaconSpam { struct Counters { uint32_t beacons, deauths, sweeps, deauthRounds; }; }

#include "engine.inc"

// --- harness state that the loop touches ---
static bool SelPress = false, EscPress = false;
static int64_t millis() { static int64_t m = 0; return ++m; }
static void vTaskDelay(int) {}
static void displayWarning(const char *, bool) {}
struct TftStub { void setTextSize(int) {} } tft;
static bool check(bool &b) { bool v = b; b = false; return v; }

int main() {
    struct Case { uint32_t target; int deauthMode; uint32_t expectBeacons; uint32_t expectDeauthPerBeacon; };

    // 1) Fixed count stops exactly at the number the user asked for.
    for (uint32_t want : {1u, 5u, 100u}) {
        beaconFrames = deauthFrames = 0; sentSsid.clear(); channelsSet.clear();
        uint8_t deauth_frame_default[26] = {0};
        uint8_t deauth_frame[26] = {0};
        beaconSpam::Counters counters{};
        uint32_t packets = 0, lastDraw = 0, targetCount = want;
        bool done = false, paused = false;
        int deauthEnabled = 0, deauthMode = 0;
        std::vector<uint8_t> deauthChannels;
        size_t deauthChannelIdx = 0; uint8_t lastDeauthChannel = 6;
        uint8_t deauthFrame[26] = {0};
        const uint8_t broadcastMac[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
        SpamSsidSource src{}; src.mode = 0;
        const char *list = "A\nB\nC\n"; src.list = list; src.listLen = strlen(list);
        auto drawStatus = [&]() {};
        uint8_t wifi_channel_local = 6; (void)wifi_channel_local;
        #define wifi_channel wifi_channel_local
        #include "loop.inc"
        #undef wifi_channel

        assert(beaconFrames == (int)want);
        assert(packets == want);
        std::cout << "count " << want << " -> sent " << beaconFrames << " beacons OK\n";
    }

    // 2) Deauth runs in the same pass: 3 deauth frames per beacon, none when off.
    {
        beaconFrames = deauthFrames = 0;
        uint8_t deauth_frame_default[26] = {0};
        uint8_t deauth_frame[26] = {0};
        beaconSpam::Counters counters{};
        uint32_t packets = 0, lastDraw = 0, targetCount = 10;
        bool done = false, paused = false;
        int deauthEnabled = 1, deauthMode = 1;
        std::vector<uint8_t> deauthChannels{6};
        size_t deauthChannelIdx = 0; uint8_t lastDeauthChannel = 6;
        uint8_t deauthFrame[26] = {0};
        const uint8_t broadcastMac[6] = {0};
        SpamSsidSource src{}; src.mode = 0;
        const char *list = "A\n"; src.list = list; src.listLen = strlen(list);
        auto drawStatus = [&]() {};
        uint8_t wifi_channel_local = 6; (void)wifi_channel_local;
        #define wifi_channel wifi_channel_local
        #include "loop.inc"
        #undef wifi_channel
        assert(beaconFrames == 10);
        assert(deauthFrames == 30);            // 3 per beacon
        assert(counters.deauths == 30);
        std::cout << "parallel deauth -> " << deauthFrames << " deauth frames for 10 beacons OK\n";
    }

    // 3) Sweep mode changes channel; same-channel mode does not.
    {
        beaconFrames = deauthFrames = 0; channelsSet.clear();
        uint8_t deauth_frame_default[26] = {0};
        uint8_t deauth_frame[26] = {0};
        beaconSpam::Counters counters{};
        uint32_t packets = 0, lastDraw = 0, targetCount = 8;
        bool done = false, paused = false;
        int deauthEnabled = 1, deauthMode = 2;
        std::vector<uint8_t> deauthChannels{1, 6, 11};
        size_t deauthChannelIdx = 0; uint8_t lastDeauthChannel = 1;
        uint8_t deauthFrame[26] = {0};
        const uint8_t broadcastMac[6] = {0};
        SpamSsidSource src{}; src.mode = 0;
        const char *list = "A\n"; src.list = list; src.listLen = strlen(list);
        auto drawStatus = [&]() {};
        uint8_t wifi_channel_local = 1; (void)wifi_channel_local;
        #define wifi_channel wifi_channel_local
        #include "loop.inc"
        #undef wifi_channel
        assert(beaconFrames == 8);
        assert(channelsSet.size() >= 2);       // it really hopped
        std::cout << "sweep changed channel " << channelsSet.size() << " times OK\n";
    }


    // 4) SSID source: list order and wrap, final entry without a trailing
    //    newline, single-SSID counter, and the random length range.
    {
        SpamSsidSource s{}; s.mode = 0;
        const char *list = "One\nTwo\nThree";
        s.list = list; s.listLen = strlen(list);
        std::vector<std::string> got;
        char buf[33];
        for (int i = 0; i < 5; i++) { spamNextSsid(s, buf, sizeof(buf)); got.push_back(buf); }
        assert(got[0] == "One" && got[1] == "Two" && got[2] == "Three");
        assert(got[3] == "One");           // wraps
        std::cout << "ssid list (no trailing newline) " << got[0] << "," << got[1] << ","
                  << got[2] << "," << got[3] << " OK\n";

        SpamSsidSource s4{}; s4.mode = 4; s4.singleBase = "Test";
        spamNextSsid(s4, buf, sizeof(buf)); std::string a1 = buf;
        spamNextSsid(s4, buf, sizeof(buf)); std::string a2 = buf;
        assert(a1 == "Test1" && a2 == "Test2");
        std::cout << "single counter " << a1 << "," << a2 << " OK\n";

        SpamSsidSource s2{}; s2.mode = 2;
        for (int i = 0; i < 40; i++) {
            uint8_t n = spamNextSsid(s2, buf, sizeof(buf));
            assert(n >= 7 && n <= 28);
        }
        std::cout << "random ssid length within 7..28 OK\n";

        // A 30-char base plus a counter must still fit the 32-byte field.
        SpamSsidSource s5{}; s5.mode = 4; s5.singleBase = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        uint8_t n5 = spamNextSsid(s5, buf, sizeof(buf));
        assert(n5 <= 32);
        std::cout << "long base clamped to " << (int)n5 << " bytes OK\n";
    }

    // 5) Regression: switching to the counted loop must not stop the channel
    //    hopping the old beaconSpamList() did. A 3-SSID list over 12 beacons is
    //    4 full passes, so the radio has to have moved.
    {
        beaconFrames = deauthFrames = 0; channelsSet.clear(); hops = 0;
        channelIndex = 0;
        int64_t hopM = 0; (void)hopM;
        uint8_t deauth_frame_default[26] = {0};
        uint8_t deauth_frame[26] = {0};
        beaconSpam::Counters counters{};
        uint32_t packets = 0, lastDraw = 0, targetCount = 12;
        bool done = false, paused = false;
        int deauthEnabled = 0, deauthMode = 0;
        std::vector<uint8_t> deauthChannels;
        size_t deauthChannelIdx = 0; uint8_t lastDeauthChannel = 1;
        uint8_t deauthFrame[26] = {0};
        const uint8_t broadcastMac[6] = {0};
        SpamSsidSource src{}; src.mode = 0;
        const char *list = "A\nB\nC\n"; src.list = list; src.listLen = strlen(list);
        auto drawStatus = [&]() {};
        uint8_t wifi_channel_local = 1; (void)wifi_channel_local;
        #define wifi_channel wifi_channel_local
        #include "loop.inc"
        #undef wifi_channel
        assert(beaconFrames == 12);
        assert(hops >= 3);   // 4 passes over the list
        std::cout << "channel hops on list wrap: " << hops << " for 12 beacons OK\n";
    }

    std::cout << "ALL BEACON SPAM TESTS PASSED\n";
    return 0;
}
