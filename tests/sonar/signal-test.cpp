#include "modules/others/sonar_signal.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>
int main() {
    constexpr float pi = 3.14159265358979323846f;
    std::vector<int16_t> samples(1024);
    for (int i=0; i<512; ++i) {
        int16_t s = int16_t(10000 * std::sin(2*pi*18500*i/48000));
        samples[2*i] = samples[2*i+1] = s;
    }
    float carrier = sonarMagnitude(samples.data(), 512, 18500, 0, 48000);
    float leak = sonarMagnitude(samples.data(), 512, 18900, 0, 48000);
    assert(carrier > 30 && leak < carrier * .02f);
    for (int i=0; i<512; ++i) {
        samples[2*i] += int16_t(3000 * std::sin(2*pi*18900*i/48000));
    }
    assert(sonarMagnitude(samples.data(),512,18900,0,48000) > 10*leak);
    SonarGate g;
    assert(!g.update(100, 50, 28, true));
    assert(!g.update(499, 50, 28, true));
    assert(g.update(500, 50, 28, true));
    assert(!g.update(2000, 50, 28, true));
    assert(!g.update(3000, 0, 28, true));
    assert(!g.update(4100, 0, 28, false));
    assert(g.latched);
    assert(!g.update(4200, 0, 28, true));
    assert(!g.update(5400, 0, 28, true));
    assert(!g.latched);
    assert(!g.update(5500, 50, 28, true));
    assert(g.update(5900, 50, 28, true));
    g.reset(); assert(!g.latched);
    std::cout << "Sonar signal and gate tests passed\n";
}
