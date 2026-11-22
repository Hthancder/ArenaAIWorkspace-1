#include <cassert>
#include <cstring>
#include <iostream>
#include <vector>
#include "globals.h"
#include "Wire.h"
#include "driver/i2s_std.h"
#include "core/dsolution_ux.h"
SerialStub Serial; WireStub Wire; Config bruceConfig;
static unsigned nowMs; static bool mic, speaker, playing, i2sBusy, writeError, codecOk = true;
static TaskHandle_t task = (void*)1;
static int starts, stops, deleted, blinks, addr, begins;
static bool restartFindDuringWrite = false;
static std::vector<int16_t> output;
uint32_t millis() { return nowMs; }
TaskHandle_t xTaskGetCurrentTaskHandle() { return task; }
void vTaskDelay(unsigned n) { nowMs += n; }
void blinkLed(int) { ++blinks; }
bool isBoardMicActive() { return mic; }
bool isSpeakerActive() { return speaker; }
bool isAudioPlaying() { return playing; }
void _setup_codec_speaker(bool on) { if (on) { ++starts; speaker = true; } else { ++stops; speaker = false; } }
void WireStub::beginTransmission(int a) { addr = a; }
int WireStub::endTransmission() { return codecOk ? 0 : 1; }
int i2s_new_channel(const i2s_chan_config_t *cfg, i2s_chan_handle_t *tx, void*) {
    assert(cfg->port == 0); if (i2sBusy) return 1; ++begins; *tx = (void*)2; return 0;
}
int i2s_channel_init_std_mode(i2s_chan_handle_t, const i2s_std_config_t *cfg) {
    assert(cfg->clk_cfg.sample_rate_hz == 48000 && cfg->slot_cfg.bit_shift);
    assert(cfg->gpio_cfg.mclk == 5 && cfg->gpio_cfg.bclk == 15 && cfg->gpio_cfg.ws == 16 && cfg->gpio_cfg.dout == 6);
    return 0;
}
int i2s_channel_enable(i2s_chan_handle_t) { return 0; }
int i2s_channel_write(i2s_chan_handle_t,const void *buf,size_t n,size_t *written,unsigned) {
    if (restartFindDuringWrite) {
        restartFindDuringWrite = false; uxFindStop(); nowMs += 10001;
        const char *err = nullptr; assert(uxFindStart(&err));
    }
    if (writeError) { *written = 0; return 1; }
    const int16_t *p = (const int16_t*)buf; output.insert(output.end(), p, p + n / 2); *written=n; return 0;
}
int i2s_channel_disable(i2s_chan_handle_t) { return 0; }
int i2s_del_channel(i2s_chan_handle_t) { ++deleted; return 0; }
int main() {
    uxInitMenuTask();
    task = (void*)3; assert(!uxSpeakerTest() && begins == 0); task = (void*)1;
    bruceConfig.soundEnabled = 0; assert(!uxSpeakerTest() && begins == 0);
    bruceConfig.soundEnabled = 1; mic = true; assert(!uxSpeakerTest() && begins == 0); mic = false;
    speaker = true; assert(!uxSpeakerTest() && begins == 0); speaker = false;
    playing = true; assert(!uxSpeakerTest() && begins == 0); playing = false;
    i2sBusy = true; assert(!uxSpeakerTest()); i2sBusy = false;
    codecOk = false; assert(!uxSpeakerTest() && starts == 0 && deleted == 1 && addr == 0x18); codecOk = true;
    assert(uxSpeakerTest() && starts == 1 && stops == 1 && !speaker);
    bool nonzero = false; for (size_t i=0; i<output.size(); i+=2) { assert(output[i] == output[i+1]); nonzero |= output[i] != 0; }
    assert(nonzero && output.back() == 0);
    writeError = true; assert(!uxSpeakerTest() && starts == 2 && stops == 2 && !speaker); writeError = false;
    uxSetUiFeedback(false); int before = starts; uxSound(UiSound::Select); assert(starts == before);
    uxSound(UiSound::Warning); assert(starts == before + 1); uxSound(UiSound::Warning); assert(starts == before + 1);
    uxSetUiFeedback(true);
    nowMs += 4000; before = starts;
    uxBatteryCheck(0, false); uxBatteryCheck(12, false); assert(starts == before);
    uxBatteryCheck(12, false); assert(starts == before + 1);
    nowMs += 4000; uxBatteryCheck(12, false); assert(starts == before + 1);
    uxBatteryCheck(25, false); uxBatteryCheck(10, false); uxBatteryCheck(10, false);
    assert(starts == before + 2);
    const char *err = nullptr; assert(uxFindStart(&err)); assert(uxFindStatus() == "queued");
    assert(!uxFindStart(&err)); uxService(); assert(uxFindStatus() == "playing" && blinks == 1);
    nowMs += 700; uxService(); nowMs += 700; uxService(); assert(uxFindStatus() == "finished" && blinks == 3);
    assert(!uxFindStart(&err)); nowMs += 10000; assert(uxFindStart(&err)); uxFindStop(); assert(uxFindStatus() == "cancelled");
    nowMs += 10000; assert(uxFindStart(&err)); nowMs += 15001; assert(uxFindStatus() == "expired");
    nowMs += 10000; assert(uxFindStart(&err)); bruceConfig.soundEnabled = 0; uxService(); assert(uxFindStatus() == "playing_silent");
    nowMs += 700; uxService(); nowMs += 700; uxService(); assert(uxFindStatus() == "silent_or_busy" && blinks == 6);
    bruceConfig.soundEnabled = 1; nowMs += 10000; assert(uxFindStart(&err));
    restartFindDuringWrite = true; uxService();
    assert(uxFindStatus() == "queued"); // old audio must not finish the replacement request
    uxService(); assert(uxFindStatus() == "playing");
    std::cout << "Device UX audio and find regression tests passed\n";
}
