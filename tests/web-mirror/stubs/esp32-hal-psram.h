#pragma once
#include <cstdlib>
inline bool psramFound() { return true; }
inline void *ps_malloc(size_t n) { return malloc(n); }
