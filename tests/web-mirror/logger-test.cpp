#include <cassert>
#include <cstdio>
#include <vector>
#include <string>
#include "globals.h"
#include "tftLogger.h"
#include "core/tftLogger/legacy_text_packet.h"
bool isWebUIActive = false;
SerialStub serial;
SerialStub *serialDevice = &serial;
struct Packet { int fn; std::vector<uint8_t> bytes; };
std::vector<Packet> snapshot(tft_logger &t) {
    std::vector<uint8_t> buf(MAX_BIN_LOG_SIZE);
    size_t size = 0; t.getBinLog(buf.data(), size);
    assert(size <= buf.size());
    std::vector<Packet> packets;
    for (size_t i=0; i<size;) {
        assert(buf[i] == 0xaa && i+3 <= size && buf[i+1]>=3 && i+buf[i+1]<=size);
        packets.push_back({buf[i+2], {buf.begin()+i, buf.begin()+i+buf[i+1]}});
        i += buf[i+1];
    }
    return packets;
}
int main() {
    tft_logger t;
    t.setLogging(true);
    {
        std::vector<uint8_t> buf(MAX_BIN_LOG_SIZE);
        size_t size = 0; bool active = false, truncated = true, base = true;
        t.getBinLog(buf.data(), size, &active, &truncated, &base);
        assert(active && !truncated && !base && size == 8);
    }
    t.fillScreen(0x1234);
    t.drawPixel(1, 2, 0xabcd);
    t.fillRect(0, 0, 4, 4, 0);
    t.drawPixel(1, 2, 0xabcd);
    t.setLogging(true); // repeated start must not erase the current frame
    auto p = snapshot(t);
    assert(p.size() == 5 && p[1].fn == FILLSCREEN && p[2].fn == DRAWPIXEL && p[4].fn == DRAWPIXEL);
    assert(t.hasLogBase() && !t.isLogTruncated());
    for (int i=0; i<MAX_LOG_ENTRIES+5; ++i) t.drawPixel(i, 0, i);
    p=snapshot(t); assert(p.size()==MAX_LOG_ENTRIES+1 && t.isLogTruncated());
    assert(p[1].fn == DRAWPIXEL && p[1].bytes[3] == 0 && p[1].bytes[4] == 5);
    t.fillScreen(0); assert(!t.isLogTruncated() && t.hasLogBase());
    uint16_t pixel = 0xffff;
    t.pushImage(0, 0, 1, 1, &pixel);
    {
        std::vector<uint8_t> buf(MAX_BIN_LOG_SIZE);
        size_t size = 0; bool unmapped = false;
        t.getBinLog(buf.data(), size, nullptr, nullptr, nullptr, &unmapped);
        assert(unmapped);
        t.fillScreen(0);
        t.getBinLog(buf.data(), size, nullptr, nullptr, nullptr, &unmapped);
        assert(!unmapped);
    }
    t.setSleepMode(true); t.drawString("one", 0, 0); t.drawString("two", 0, 10);
    p=snapshot(t); assert(p.size()==4 && p[2].fn == DRAWSTRING_DATUM && p[3].fn == DRAWSTRING_DATUM);
    t.setSleepMode(false); t.fillScreen(0);
    t.setTextDatum(4); t.drawString("center", 30, 40);
    p = snapshot(t);
    assert(p.back().fn == DRAWSTRING_DATUM && p.back().bytes[13] == 4);
    uint8_t legacy[MAX_LOG_SIZE] = {};
    size_t legacySize = legacyTextPacket(p.back().bytes.data(), p.back().bytes.size(), legacy);
    assert(legacySize == p.back().bytes.size() - 1 && legacy[1] == legacySize && legacy[2] == DRAWSTRING);
    assert(std::string(reinterpret_cast<char *>(legacy + 13), legacySize - 13) == "center");
    assert(!legacyTextPacket(p.back().bytes.data(), 13, legacy));
    t.markUnmappedPixels();
    {
        std::vector<uint8_t> buf(MAX_BIN_LOG_SIZE);
        size_t size = 0; bool unmapped = false;
        t.getBinLog(buf.data(), size, nullptr, nullptr, nullptr, &unmapped);
        assert(unmapped);
        t.fillScreen(0);
        t.getBinLog(buf.data(), size, nullptr, nullptr, nullptr, &unmapped);
        assert(!unmapped);
    }
    for (int i=0; i<MAX_LOG_IMAGES; ++i) t.imageToBin(2, String(std::string("/image") + std::to_string(i) + ".png"), 0, 0, false, 0);
    p=snapshot(t); assert(p.size()==MAX_LOG_IMAGES+2 && p[2].fn == DRAWIMAGE);
    assert(std::string(p[2].bytes.begin()+12,p[2].bytes.end())=="/image0.png");
    t.imageToBin(2, "/overflow.png", 0, 0, false, 0); assert(t.isLogTruncated());
    t.setLogging(false); assert(!t.getLogging());
    {
        std::vector<uint8_t> buf(MAX_BIN_LOG_SIZE);
        size_t size = 0; bool active = true, truncated = true, base = true;
        t.getBinLog(buf.data(), size, &active, &truncated, &base);
        assert(!active && !truncated && !base && size == 8);
    }
    std::puts("logger regression tests passed");
}
