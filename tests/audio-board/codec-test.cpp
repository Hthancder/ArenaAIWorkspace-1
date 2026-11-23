#include <cassert>
#include <cstdint>
#include <vector>
#include <utility>
#include <map>
#include <iostream>
#define ES7210_ADDR 0x40
#define ES8311_ADDR 0x18
#define PIN_PA_ENABLE 4
#define HIGH 1
#define LOW 0
static int pa;
void delay(int) {}
void digitalWrite(int pin,int value) { assert(pin == PIN_PA_ENABLE); pa = value; }
struct SerialStub { void println(const char*) {} template<typename... A> void printf(const char*,A...) {} } Serial;
struct TwoWire {
    int addr=0, index=0, failReg=-1, failAddr=0; uint8_t reg=0;
    std::map<int,int> regs; std::vector<std::pair<int,int>> writes;
    void beginTransmission(int a) { addr=a; index=0; }
    void write(uint8_t v) { if (index++ == 0) reg=v; else {regs[addr*256+reg]=v; writes.emplace_back(addr*256+reg,v);} }
    int endTransmission() { return addr == failAddr && reg == failReg ? 1 : 0; }
} wire;
TwoWire *getSysI2CBus() { return &wire; }
#include "codec.inc"
using i2s_chan_handle_t = void*;
using esp_err_t = int;
#define ESP_OK 0
#define ESP_FAIL 1
#define I2S_NUM_0 0
#define I2S_ROLE_MASTER 0
#define SPECTRUM_HEIGHT 124
#define MIC_SAMPLE_RATE 48000
#define GPIO_NUM_0 0
struct i2s_chan_config_t { int dma_desc_num; int dma_frame_num; };
#define I2S_CHANNEL_DEFAULT_CONFIG(port,role) i2s_chan_config_t{}
static i2s_chan_handle_t i2s_chan = nullptr;
static bool failCreate, failInit, failEnable; static int deletes, disables;
int i2s_new_channel(i2s_chan_config_t*,void*,i2s_chan_handle_t *ch) { if(failCreate) return 1; *ch=(void*)1; return 0; }
int micInitChannel(i2s_chan_handle_t,int) { return failInit ? 1 : 0; }
int i2s_channel_enable(i2s_chan_handle_t) { return failEnable ? 1 : 0; }
int i2s_channel_disable(i2s_chan_handle_t) { ++disables; return 0; }
int i2s_del_channel(i2s_chan_handle_t) { ++deletes; return 0; }
const char *esp_err_to_name(int) { return "mock error"; }
void gpio_reset_pin(int) {}
#include "mic.inc"
int main() {
    assert(InitI2SMicroPhone());
    assert(isBoardMicActive() && isBoardMicReady());
    assert(wire.regs[0x4001] == 0x34 && wire.regs[0x404b] == 0 && wire.regs[0x404c] == 255);
    assert(wire.regs[0x4006] == 0 && wire.regs[0x4011] == 0x60);
    auto n=wire.writes.size(); assert(!InitI2SMicroPhone()); assert(wire.writes.size() == n);
    deinitMicroPhone(); assert(!isBoardMicReady() && !isBoardMicActive());
    assert(wire.regs[0x404b] == 255 && wire.regs[0x404c] == 255 && wire.regs[0x4001] == 0x7f);
    n=wire.writes.size(); failCreate=true; assert(!InitI2SMicroPhone()); assert(wire.writes.size() == n); failCreate=false;
    failInit=true; assert(!InitI2SMicroPhone()); assert(wire.writes.size() == n && !i2s_chan); failInit=false;
    failEnable=true; assert(!InitI2SMicroPhone()); assert(wire.writes.size() == n && !i2s_chan); failEnable=false;
    wire.failAddr=0x40; wire.failReg=0x4b; assert(!InitI2SMicroPhone());
    assert(!isBoardMicReady() && !isBoardMicActive() && !i2s_chan);
    wire.failAddr=0x18; wire.failReg=0x12; _setup_codec_speaker(true);
    assert(!isBoardSpeakerReady() && pa==LOW); _setup_codec_speaker(false);
    wire.failAddr=0; _setup_codec_speaker(true); assert(isBoardSpeakerReady() && pa==HIGH);
    _setup_codec_speaker(false); assert(!isBoardSpeakerReady() && pa==LOW);
    assert(deletes >= 4 && disables >= 4);
    std::cout << "Codec register, error and ownership tests passed\n";
}
