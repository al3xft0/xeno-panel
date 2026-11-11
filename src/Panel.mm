#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <cstring>
#include <cstdlib>
#include <sys/mman.h>
#include "Core.h"
#include "VecMath.h"
#include "Mem.h"
#include "Menu.h"
#include "Offsets.h"

Config gCfg = { .smooth = 0.22f, .fovDeg = 14.f, .status = S_BOOT, .tab = TAB_AIM, .menuOpen = true };
char   gUuidActual[64] = {0};

static uintptr_t gBase = 0;
static bool      gUuidOk = true;
static uintptr_t gLastPlayer = 0;
static uintptr_t gLastTarget = 0;
static Quat      gAimState = {0,0,0,1};
static XenoMenu* gMenu = nil;
static NSTimer*  gAttach = nil;

// ... existing helpers unchanged (imageName through applyMovement) ...

static bool aobMatch(const uint8_t* data, const uint8_t* pat, size_t len) {
    for (size_t i = 0; i < len; i++) if (pat[i] != 0xFF && data[i] != pat[i]) return false;
    return true;
}

static uintptr_t aobScan(uintptr_t base, size_t span, const uint8_t* pat, size_t plen) {
    if (!base || span < plen) return 0;
    const uint8_t* p = (const uint8_t*)base;
    for (size_t i = 0; i + plen <= span; i++) {
        if (aobMatch(p + i, pat, plen)) return base + i;
    }
    return 0;
}

void xenoRestGuest(void) {
    uintptr_t base = resolveBase();
    if (!base) { NSLog(@"[mirage] rest guest: no module"); return; }
    // conservative span; refine from maps if needed
    size_t span = 0x2000000;

    // AOB 1 (ARM32 style — will not hit on arm64, placeholder)
    const uint8_t s1[] = {0x10,0x40,0x2d,0xe9,0xd0,0x40,0x9f,0xe5,0x04,0x40,0x8f,0xe0,0x00,0x00,0xd4,0xe5,0x00,0x00,0x50,0xe3,0x04,0x00,0x00,0x1a,0xc0,0x00,0x9f,0xe5,0x00,0x00,0x9f,0xe7,0xFF,0xFF,0x9e,0xeb,0x01,0x00,0xa0,0xe3,0x00,0x00,0xc4,0xe5,0x0d,0x05,0x03,0xe3};
    const uint8_t r1[] = {0x01,0x00,0xa0,0xe3,0x1e,0xff,0x2f,0xe1,0x04,0x40,0x8f,0xe0,0x00,0x00,0xd4,0xe5,0x00,0x00,0x50,0xe3,0x04,0x00,0x00,0x1a,0xc0,0x00,0x9f,0xe5,0x00,0x00,0x9f,0xe7,0xf1,0x65,0x9e,0xeb,0x01,0x00,0xa0,0xe3,0x00,0x00,0xc4,0xe5,0x0d,0x05,0x03,0xe3};

    uintptr_t hit = aobScan(base, span, s1, sizeof s1);
    if (hit) {
        long ps = sysconf(_SC_PAGESIZE);
        uintptr_t page = hit & ~(ps - 1);
        mprotect((void*)page, ps, PROT_READ | PROT_WRITE | PROT_EXEC);
        memcpy((void*)hit, r1, sizeof r1);
        mprotect((void*)page, ps, PROT_READ | PROT_EXEC);
        NSLog(@"[mirage] rest guest AOB1 patched @ %p", (void*)hit);
    } else {
        NSLog(@"[mirage] rest guest AOB1 not found (expected on arm64)");
    }
    // AOB 2 similar — add when you have the matching arm64 pattern
}

void xenoSetToggle(int idx) {
    if (idx < 0 || idx >= T_COUNT) return;
    bool was = gCfg.on[idx];
    gCfg.on[idx] = !was;
    if (!was) {
        if (idx == T_REST_GUEST) xenoRestGuest();
        return;
    }

    switch (idx) {
        case T_RECOIL: restoreGroup(G_RECOIL); break;
        case T_SPREAD: restoreGroup(G_SPREAD); break;
        case T_RELOAD: restoreGroup(G_RELOAD); break;
        case T_AMMO:   restoreGroup(G_AMMO);   break;
        case T_FLY:    restoreGroup(G_FLY);    break;
        case T_NOCLIP: restoreGroup(G_NOCLIP); break;
        case T_AIMBOT: gAimState = {0,0,0,1}; break;
        default: break;
    }
}

// ... rest of file (xenoStep through xenoInit) unchanged ...
