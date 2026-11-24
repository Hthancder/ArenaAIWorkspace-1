#include <cassert>
#include <cstdint>
#include <cstddef>
#include <iostream>
#define DSOLUTION_183_2MIC 1
#define pdMS_TO_TICKS(x) (x)
#define ESP_OK 0
struct OtaUiSnapshot { bool active; bool done; uint8_t pct; size_t written; size_t total; };
static bool owner=false, active=false, s_otaUiNeedsRedraw=false, s_webUiScreenDirty=false;
static bool NextPress,PrevPress,UpPress,DownPress,SelPress,EscPress,AnyKeyPress,NextPagePress,PrevPagePress,LongPress,SerialCmdPress;
// The ux.inc slice references every input global; mark the unused ones as used.
static void touchAllKeys(){ (void)DownPress;(void)NextPagePress;(void)PrevPagePress;(void)LongPress;(void)SerialCmdPress;(void)AnyKeyPress; }
static int wakeCount, drawCount, delays, locks, watchdog;
static unsigned long fakeMillis = 0;
unsigned long millis(){ return fakeMillis; }
bool uxIsMenuTask(){return owner;}
bool isOtaInProgress(){return active;}
void wakeUpScreen(){++wakeCount;}
OtaUiSnapshot otaUiSnapshot(){return {active,false,(uint8_t)(delays*20),(size_t)delays*100,500};}
void drawWebUiOtaOverlay(){++drawCount;}
int esp_task_wdt_status(void*){return 0;} void esp_task_wdt_reset(){++watchdog;}
// 100 ms slice steps: three steps would finish the transfer, so a *bounded*
// checkpoint returns after at most kOtaUiSliceMs no matter what the transfer does.
void vTaskDelay(int ms){ assert(ms==100); fakeMillis += (unsigned long)ms; ++delays; }
void inputLock(){++locks;} void inputUnlock(){--locks;}
#include "ui.inc"
int main(){
  touchAllKeys();
  // Not the UI task: no drawing, no wake.
  active=true; otaUiCheckpoint();
  assert(!wakeCount && !drawCount && locks==0);

  // UI task, transfer stalls forever: the checkpoint must still return, and it
  // must not eat the key globals (wiping Esc is what looked like a dead device).
  owner=true; delays=0; fakeMillis=0;
  NextPress=SelPress=EscPress=AnyKeyPress=true;
  otaUiCheckpoint();
  assert(wakeCount==1);
  assert(drawCount>0);                       // drew at least once
  assert(delays*100 <= 300);                 // bounded slice, not the whole transfer
  assert(active);                            // transfer still running: caller keeps serving
  assert(EscPress && SelPress && NextPress && !UpPress && !PrevPress); // input survived
  assert(s_webUiScreenDirty);

  // A finished transfer is redrawn once and reported through the redraw flag.
  active=false;
  assert(otaUiConsumeRedraw()); assert(!otaUiConsumeRedraw());
  owner=false; assert(!otaUiConsumeRedraw());
  // A held key is what starts an on-device cancel; it must not be cleared here.
  UpPress=true; PrevPress=true;
  otaUiCheckpoint();                 // transfer is over: nothing to interrupt
  assert(UpPress && PrevPress);
  std::cout<<"OTA screen owner, bounded slice and input-preservation tests passed\n";
}
