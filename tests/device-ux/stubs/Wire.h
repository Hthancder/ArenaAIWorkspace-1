#pragma once
struct WireStub { void beginTransmission(int); int endTransmission(); };
extern WireStub Wire;
