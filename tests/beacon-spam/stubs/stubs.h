// Minimal host stubs so the beacon-spam SSID engine can be compiled and run.
#pragma once
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include <functional>

#define PROGMEM
inline uint8_t pgm_read_byte(const void *p) { return *(const uint8_t *)p; }

struct String {
    std::string s;
    String() {}
    String(const char *c) : s(c ? c : "") {}
    String(const std::string &v) : s(v) {}
    String(uint32_t v) : s(std::to_string(v)) {}
    String(int v) : s(std::to_string(v)) {}
    String operator+(const String &o) const { return String(s + o.s); }
    String operator+(const char *o) const { return String(s + o); }
    size_t length() const { return s.size(); }
    const char *c_str() const { return s.c_str(); }
    String substring(size_t a, size_t b) const { return String(s.substr(a, b - a)); }
    void replace(const char *a, const char *b) { size_t p; while ((p = s.find(a)) != std::string::npos) s.replace(p, strlen(a), b); }
};

static const uint8_t BEACON_PKT_LEN = 109;
