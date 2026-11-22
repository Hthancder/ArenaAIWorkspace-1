#pragma once
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <cstdlib>
#include <cstdarg>
#include <cstdio>
#include <string>
#define TFT_WIDTH 284
#define TFT_HEIGHT 240
#define LW 6
#define LH 8
#define DEC 10
using portMUX_TYPE = int;
#define portMUX_INITIALIZER_UNLOCKED 0
#define portENTER_CRITICAL(p) ((void)(p))
#define portEXIT_CRITICAL(p) ((void)(p))
using TaskHandle_t = void*;
using QueueHandle_t = void*;
#define pdMS_TO_TICKS(x) (x)
#define pdPASS 1
inline int uxQueueMessagesWaiting(void*) { return 0; }
inline int xQueueReceive(void*, void*, int) { return 0; }
inline int xQueueSend(void*, const void*, int) { return 1; }
inline void* xQueueCreate(int, int) { return nullptr; }
inline void vQueueDelete(void*) {}
inline void vTaskDelete(void*) {}
inline int xTaskCreate(void (*)(void*), const char*, int, void*, int, void**) { return pdPASS; }
#define log_e(...) ((void)0)
class String : public std::string {
public:
 using std::string::string;
 String(const std::string& s):std::string(s) {}
 String(char c):std::string(1,c) {}
 template<class T> String(T v, int):std::string(std::to_string(v)) {}
 bool isEmpty() const { return empty(); }
 String substring(int a, int b) const { return substr(a, b-a); }
};
class tft_display {
 uint8_t datum = 0;
public:
 tft_display(int16_t, int16_t) {}
 int width() { return TFT_WIDTH; } int height() { return TFT_HEIGHT; } int getRotation(){return 0;}
 void setTextDatum(uint8_t d) {datum=d;} uint8_t getTextDatum() const {return datum;}
 int getTextSize() const {return 1;} int getTextColor() const {return 65535;} int getTextBgColor() const {return 0;}
 int getCursorX() {return 0;} int getCursorY() {return 0;}
 template<class... T> void fillScreen(T...) {} template<class... T> void drawPixel(T...) {}
 template<class... T> void pushImage(T...) {}
 template<class... T> void drawLine(T...) {} template<class... T> void drawRect(T...) {}
 template<class... T> void fillRect(T...) {} template<class... T> void drawRoundRect(T...) {}
 template<class... T> void fillRoundRect(T...) {} template<class... T> void drawCircle(T...) {}
 template<class... T> void fillCircle(T...) {} template<class... T> void drawEllipse(T...) {}
 template<class... T> void fillEllipse(T...) {} template<class... T> void drawTriangle(T...) {}
 template<class... T> void fillTriangle(T...) {} template<class... T> void drawArc(T...) {}
 template<class... T> void drawWideLine(T...) {} template<class... T> void drawFastVLine(T...) {}
 template<class... T> void drawFastHLine(T...) {}
 int16_t drawString(const String&,int32_t,int32_t,uint8_t){return 1;}
 int16_t drawCentreString(const String&,int32_t,int32_t,uint8_t){return 1;}
 int16_t drawRightString(const String&,int32_t,int32_t,uint8_t){return 1;}
 size_t print(const String &s){return s.size();}
};
