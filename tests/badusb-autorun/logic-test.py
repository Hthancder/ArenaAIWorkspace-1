#!/usr/bin/env python3
"""Exercise the actual Auto-Run task loop with deterministic host-side stubs."""
import pathlib, subprocess, sys, tempfile
src=pathlib.Path(sys.argv[1]); code=(src/'src/modules/badusb_ble/badusb_autorun.cpp').read_text()
a=code.index('static void badUsbAutoRunTask(void *param) {'); b=code.index('\nbool badUsbAutoRunExecuteNow',a)
task=code[a:b]
pre=r'''
#include <cassert>
#include <iostream>
#include <stdexcept>
#include <string>
#include <cstdint>
#define USB_as_HID 1
#define pdMS_TO_TICKS(x) (x)
struct Config { struct Settings { bool enabled=true, confirmWindow=true, runOncePerPlug=true; int trigger=0, confirmMs=1000; std::string payloadFs="LittleFS", payloadPath="/test"; } badUsbAutoRun; } bruceConfig;
static bool s_armed=false,s_lastMounted=false,s_usbInitialized=true,mounted=true;
static unsigned long s_lastPlugMs=0;
static int runs=0, confirmations=0, waits=0, ticks=0, failAt=0, cancelAt=0, disconnectAt=0;
unsigned long millis(){return 42;}
bool tud_mounted(){return mounted;}
void ensureUsbHidReady() {s_usbInitialized=true;}
bool badUsbAutoRunIsArmed(){return bruceConfig.badUsbAutoRun.enabled && bruceConfig.badUsbAutoRun.trigger != 1;}
bool autoRunShouldStop(){return !bruceConfig.badUsbAutoRun.enabled || !mounted;}
bool waitAutoRunConnected(uint32_t){++waits; return !autoRunShouldStop();}
bool doConfirmCountdown(uint16_t){++confirmations;return confirmations!=cancelAt && !autoRunShouldStop();}
bool runPayloadFile(const std::string&,const std::string&){++runs;if(runs==disconnectAt) mounted=false;return runs!=failAt;}
void vTaskDelay(int ms){if((ms==300 || ms==1000) && ++ticks>=4)throw std::runtime_error("done");}
'''
post=r'''
void reset(bool once,int trigger=0){bruceConfig=Config{};bruceConfig.badUsbAutoRun.runOncePerPlug=once;bruceConfig.badUsbAutoRun.trigger=trigger;s_armed=false;s_lastMounted=false;mounted=true;runs=confirmations=waits=ticks=failAt=cancelAt=disconnectAt=0;}
void execute(){try{badUsbAutoRunTask(nullptr);assert(false);}catch(const std::runtime_error&) {}}
int main(){
 reset(true);execute();assert(runs==1 && confirmations==1);
 reset(false);disconnectAt=3;execute();assert(runs==3 && confirmations==3 && !mounted);
 reset(false);cancelAt=2;execute();assert(runs==1 && confirmations==2);
 reset(false);failAt=1;execute();assert(runs==1);
 reset(false,2);disconnectAt=2;execute();assert(runs==2 && waits>=2);
 reset(false,1);execute();assert(runs==0 && confirmations==0);
 std::cout<<"Auto-Run once/repeat/cancel/disconnect/unsupported-trigger checks passed\n";
}
'''
ducky=(src/'src/modules/badusb_ble/ducky_typer.cpp').read_text()
assert 'key_input(*fs, path, hid_usb, autoRunShouldStop)' in code
assert '__atomic_exchange_n(&s_running, true' in code
assert 'if (shouldStop && shouldStop()) { interrupted = true; goto EXIT; }' in ducky
assert 'if (!handlePauseResume()) { interrupted = true; goto EXIT; }' in ducky
assert 'vTaskDelete(s_task)' not in code
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d)/'autorun.cpp';p.write_text(pre+task+post);exe=pathlib.Path(d)/'test'
 subprocess.run(['g++','-std=c++17','-Wall','-Wextra','-Werror',str(p),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True,timeout=10)
