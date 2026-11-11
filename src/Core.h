#pragma once
#include <cstdint>

enum Group {
    G_RECOIL = 1, G_SPREAD, G_RELOAD, G_AMMO, G_FLY, G_NOCLIP
};

enum Toggle {
    T_AIMBOT, T_SOFT, T_RECOIL, T_SPREAD, T_RELOAD, T_AMMO, T_FLY, T_NOCLIP, T_RING, T_COUNT
};

enum Status {
    S_BOOT, S_NO_MODULE, S_UUID_BAD, S_NO_MATCH, S_LIVE
};

struct Config {
    bool  on[T_COUNT];
    float smooth;      // 0.02 .. 1.0
    float fovDeg;      // 1 .. 90
    float screenW, screenH;
    float insetTop;
    int   status;
};

extern Config gCfg;
extern char gUuidActual[64];

void  xenoStart(void);
void  xenoSetToggle(int idx);
void  xenoStep(int idx, int dir);
void  xenoApply(void);
float xenoFovRadius(void);
void  xenoReattach(void);
