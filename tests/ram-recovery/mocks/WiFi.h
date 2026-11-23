#pragma once
#define WIFI_MODE_NULL 0
struct MockWiFi { int mode = 0; int getMode() { return mode; } };
extern MockWiFi WiFi;
