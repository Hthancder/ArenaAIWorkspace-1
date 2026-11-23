#pragma once
#include <cstddef>
struct MockSerial { template<typename... Args> void printf(const char*, Args...) {} void println(const char*) {} };
extern MockSerial Serial;
struct MockESP { size_t getFreePsram() { return 100000; } };
extern MockESP ESP;
