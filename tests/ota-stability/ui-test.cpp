#include <cassert>
#include <cstdint>
#include <cstddef>
#include <iostream>
#define DSOLUTION_183_2MIC 1
#define pdMS_TO_TICKS(x) (x)
#define ESP_OK 0
struct OtaUiSnapshot { bool active; bool done; uint8_t pct; size_t written; size_t total; bool preparing; };
static bool owner=false, active=false, s_otaUiNeedsRedraw=false, s_webUiScreenDirty=false;
static bool NextPress,PrevPress,UpPress,DownPress,SelPress,EscPress,AnyKeyPress,NextPagePress,PrevPagePress,LongPress,SerialCmdPress;
static void touchAllKeys(){ (void)NextPress;(void)DownPress;(void)NextPagePress;(void)PrevPagePress;(void)LongPress;(void)SerialCmdPress;(void)AnyKeyPress; }
static int wakeCount, drawCount, delays;
static unsigned long fakeMillis = 0;
static uint8_t snapPct=0; static size_t snapWritten=0; static bool snapDone=false, snapPreparing=false;
unsigned long millis(){ return fakeMillis; }
bool uxIsMenuTask(){return owner;}
bool isOtaInProgress(){return active;}
void wakeUpScreen(){++wakeCount;}
OtaUiSnapshot otaUiSnapshot(){return {active,snapDone,snapPct,snapWritten,500,snapPreparing};}
void drawWebUiOtaOverlay(){++drawCount;}
int esp_task_wdt_status(void*){return 0;} void esp_task_wdt_reset(){}
// Every delay is a bug now: the checkpoint is reached from check(), which a menu
// calls 6-9 times per loop iteration.
void vTaskDelay(int){ ++delays; fakeMillis += 100; }
void inputLock(){} void inputUnlock(){}
#include "ui.inc"
static void reset(){ wakeCount=drawCount=delays=0; s_otaUiNeedsRedraw=false; s_webUiScreenDirty=false;
                     snapPct=0; snapWritten=0; snapDone=false; snapPreparing=false; }
int main(){
  touchAllKeys();

  // Not the UI task: no drawing, no wake, no delay.
  active=true; otaUiCheckpoint();
  assert(!wakeCount && !drawCount && !delays);

  // THE REGRESSION THAT MATTERS: check() calls this 6-9 times per menu loop.
  // It must never sleep, and an unchanged picture must not be redrawn.
  owner=true; reset(); active=true; snapWritten=100; snapPct=20;
  for (int i=0;i<9;i++) otaUiCheckpoint();
  assert(delays==0);                      // never blocks
  assert(drawCount==1);                   // drawn once, not nine times
  assert(wakeCount==1);

  // Progress updates are drawn; the same value is not drawn again.
  snapWritten=200; snapPct=40; otaUiCheckpoint(); assert(drawCount==2 && delays==0);
  otaUiCheckpoint(); otaUiCheckpoint();   assert(drawCount==2 && delays==0);

  // A finished transfer redraws once, and must not queue a repaint on every call.
  snapDone=true; otaUiCheckpoint();       assert(drawCount==3);
  otaUiCheckpoint();                      assert(drawCount==3);

  // While transferring, no full-screen repaint is requested at all.
  assert(!s_webUiScreenDirty);

  // Ending the transfer asks for exactly one repaint, then goes quiet.
  active=false; reset();
  otaUiCheckpoint();                      assert(s_otaUiNeedsRedraw);
  s_otaUiNeedsRedraw=false;
  for (int i=0;i<9;i++) otaUiCheckpoint();
  assert(!s_otaUiNeedsRedraw && !drawCount && !delays);

  // A held key (on-device cancel) is never swallowed here.
  UpPress=PrevPress=SelPress=EscPress=true;
  otaUiCheckpoint();
  assert(UpPress && PrevPress && SelPress && EscPress);

  // A second transfer works after the idle gap.
  active=true; snapPct=5; otaUiCheckpoint(); assert(drawCount==1 && delays==0);

  // Idle board, no transfer: nothing happens and nothing is delayed.
  active=false; reset(); for (int i=0;i<9;i++) otaUiCheckpoint();
  assert(!drawCount && !delays);

  std::cout<<"OTA screen owner, non-blocking checkpoint and repaint-throttle tests passed\n";
}
