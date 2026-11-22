#pragma once
#include <string>
#include <vector>
#include <map>
#include <cstring>
#include <algorithm>
#include <cstddef>
#include <cstdint>
inline std::map<std::string, std::vector<uint8_t>> fakeFiles;
class File {
    const std::vector<uint8_t>* data = nullptr;
    size_t pos = 0;
public:
    File() = default;
    explicit File(const std::vector<uint8_t>* p): data(p) {}
    explicit operator bool() const { return data != nullptr; }
    bool isDirectory() const { return false; }
    size_t size() const { return data ? data->size() : 0; }
    size_t read(uint8_t *out, size_t count) {
        if (!data) return 0;
        count = std::min(count, data->size() - pos);
        std::memcpy(out, data->data() + pos, count); pos += count; return count;
    }
    void close() {}
};
struct LittleFSStub {
    File open(const char* path, const char*) {
        auto it = fakeFiles.find(path); return it == fakeFiles.end() ? File() : File(&it->second);
    }
};
inline LittleFSStub LittleFS;
