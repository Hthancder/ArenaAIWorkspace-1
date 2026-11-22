#pragma once
#include <cstdint>
#include <string>
#include <algorithm>
using std::min; using std::max;
using String = std::string;
using TaskHandle_t = void*;
using portMUX_TYPE = int;
#define portMUX_INITIALIZER_UNLOCKED 0
#define portENTER_CRITICAL(x) ((void)(x))
#define portEXIT_CRITICAL(x) ((void)(x))
#define pdMS_TO_TICKS(x) (x)
// The real Arduino core also exposes tone(); keep it in this stub to catch name collisions.
void tone(uint8_t pin, unsigned int frequency, unsigned long duration = 0);
uint32_t millis();
TaskHandle_t xTaskGetCurrentTaskHandle();
void vTaskDelay(unsigned);
struct SerialStub { void println(const char*) {} };
extern SerialStub Serial;
