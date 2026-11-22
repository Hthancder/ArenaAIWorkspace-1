#pragma once
#include "DisplayDrivers.h"
struct SerialStub { void write(const uint8_t *, size_t) {} };
extern SerialStub *serialDevice;

extern bool isWebUIActive;
