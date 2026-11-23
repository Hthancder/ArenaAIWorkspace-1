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
static int wakeCount, drawCount, delays, locks, watchdog;
bool uxIsMenuTask(){return owner;}
bool isOtaInProgress(){return active;}
void wakeUpScreen(){++wakeCount;}
OtaUiSnapshot otaUiSnapshot(){return {active,false,(uint8_t)(delays*20),(size_t)delays*100,500};}
void drawWebUiOtaOverlay(){++drawCount;}
int esp_task_wdt_status(void*){return 0;} void esp_task_wdt_reset(){++watchdog;}
void vTaskDelay(int ms){assert(ms==100); if(++delays==3)active=false;}
void inputLock(){++locks;} void inputUnlock(){--locks;}
#include "ui.inc"
int main(){
 active=true;otaUiCheckpoint();assert(!wakeCount&&!drawCount); owner=true;NextPress=SelPress=EscPress=AnyKeyPress=true;
 otaUiCheckpoint();assert(wakeCount==1 && drawCount==3 && watchdog==3 && !active && locks==0);
 assert(!NextPress&&!SelPress&&!EscPress&&!AnyKeyPress&&s_webUiScreenDirty);
 assert(otaUiConsumeRedraw());assert(!otaUiConsumeRedraw());owner=false;assert(!otaUiConsumeRedraw());
 std::cout<<"OTA screen owner, redraw and input cleanup tests passed\n";
}
