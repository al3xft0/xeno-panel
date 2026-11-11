#pragma once
#include <cstdint>
#include <cstdio>
#include <fcntl.h>
#include <unistd.h>
#include <sys/time.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

// Breadcrumb ring — survives a signal, dumps to Documents/xeno_crash.log.
// You have no debugger on-device; this is the only post-mortem you'll get.
namespace bc {
constexpr int kSlots = 32;
inline const char* gRing[kSlots] = {};
inline volatile int gHead = 0;
inline char gPath[512] = {};

inline void init() {
    const char* home = getenv("HOME");
    if (!home) return;
    snprintf(gPath, sizeof gPath, "%s/Documents/xeno_crash.log", home);
}
inline void mark(const char* s) {
    int h = gHead;
    gRing[h % kSlots] = s;
    gHead = h + 1;
}
inline void dump() {
    if (!gPath[0]) return;
    int fd = open(gPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    char line[160];
    struct timeval tv; gettimeofday(&tv, nullptr);
    int n = snprintf(line, sizeof line, "\n=== %ld.%06d ===\n", (long)tv.tv_sec, (int)tv.tv_usec);
    write(fd, line, n);
    int h = gHead;
    for (int i = (h > kSlots ? h - kSlots : 0); i < h; i++) {
        const char* s = gRing[i % kSlots];
        if (!s) continue;
        write(fd, s, strlen(s));
        write(fd, "\n", 1);
    }
    close(fd);
}
}

static inline uintptr_t strip(uintptr_t p) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)__builtin_ptrauth_strip((void*)p, ptrauth_key_asia);
#else
    return p;
#endif
}

static inline bool isHeap(uintptr_t p) {
    return p >= 0x100000000ULL && p < 0x8000000000ULL && (p & 7) == 0;
}

template <typename T> static inline T read(uintptr_t a) {
    if (!isHeap(a)) return T{};
    return *reinterpret_cast<T*>(a);
}

template <typename T> static inline void write(uintptr_t a, T v) {
    if (!isHeap(a)) return;
    *reinterpret_cast<T*>(a) = v;
}

// ---- restore list: every mutation snapshotted so toggling off actually reverts ----
struct SavedWrite {
    uintptr_t addr;
    uint8_t   bytes[16];
    uint32_t  size;
    int       group;
    bool      used;
};

constexpr int kSavedMax = 192;
static SavedWrite gSaved[kSavedMax];
static int gSavedCursor = 0;

template <typename T>
static void saveWrite(int group, uintptr_t addr, T v) {
    if (!isHeap(addr)) return;
    SavedWrite& s = gSaved[gSavedCursor % kSavedMax];
    gSavedCursor++;
    if (s.used) {   // evict: restore the one we're overwriting
        memcpy((void*)s.addr, s.bytes, s.size);
    }
    s.addr = addr; s.size = sizeof(T); s.group = group; s.used = true;
    memcpy(s.bytes, (void*)addr, sizeof(T));
    *reinterpret_cast<T*>(addr) = v;
}

static void restoreGroup(int group) {
    for (int i = 0; i < kSavedMax; i++) {
        SavedWrite& s = gSaved[i];
        if (!s.used || s.group != group) continue;
        if (isHeap(s.addr)) memcpy((void*)s.addr, s.bytes, s.size);
        s.used = false;
    }
}

static void dropStale() {
    for (int i = 0; i < kSavedMax; i++) gSaved[i].used = false;
    gSavedCursor = 0;
}
