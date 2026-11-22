#pragma once
#include <string>
#include <map>
#include <cstdint>
inline std::map<std::string, int> fakePrefs;
struct Preferences {
    bool begin(const char*, bool) { return true; }
    bool getBool(const char* key, bool fallback) { return fakePrefs.count(key) ? fakePrefs[key] != 0 : fallback; }
    uint32_t getUInt(const char* key, uint32_t fallback) { return fakePrefs.count(key) ? fakePrefs[key] : fallback; }
    int getInt(const char* key, int fallback) { return fakePrefs.count(key) ? fakePrefs[key] : fallback; }
    uint8_t getUChar(const char* key, uint8_t fallback) { return fakePrefs.count(key) ? fakePrefs[key] : fallback; }
    void putUChar(const char* key, uint8_t v) { fakePrefs[key] = v; }
    void putBool(const char* key, bool v) { fakePrefs[key] = v; }
    void putUInt(const char* key, uint32_t v) { fakePrefs[key] = v; }
    void putInt(const char* key, int v) { fakePrefs[key] = v; }
    void end() {}
};
