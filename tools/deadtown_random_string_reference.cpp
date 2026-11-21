// Test-only reference using gmrunner's pinned runtime/Random.h. This is NOT
// native Android RNG or proof of GameMaker/iOS equivalence. Compiled separately
// from the GML diagnostic so call order and next RNG draw can be compared.
#include "runtime/Random.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

int main() {
    for (int seed : {1, 42, 12345, -1}) {
        gm::GMRandom rng(seed);
        auto range = [&](int low, int high) {
            return low + static_cast<int>(std::trunc(rng.next() * (high - low + 1)));
        };
        std::string result;
        for (int i = 0; i < 20; ++i) {
            int letters[] = {range(65, 90), range(97, 122), range(48, 57)};
            int choice = std::min(static_cast<int>(std::floor(rng.next() * 3)), 2);
            result += static_cast<char>(letters[choice]);
        }
        int next = range(0, 255);
        std::printf("RANDOM_STRING_VM:%d:%s:%d\n", seed, result.c_str(), next);
    }
}
