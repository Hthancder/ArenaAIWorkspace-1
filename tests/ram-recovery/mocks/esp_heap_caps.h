#pragma once
#include <cstddef>
#define MALLOC_CAP_DMA 1
extern size_t blockSize, totalFree;
inline size_t heap_caps_get_largest_free_block(int) { return blockSize; }
inline size_t heap_caps_get_free_size(int) { return totalFree; }
