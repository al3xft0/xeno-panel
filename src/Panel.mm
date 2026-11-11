#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <cstring>
#include <cstdlib>
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

// ... (keep all the existing helper functions exactly as they were: imageName, isTargetModule, readUUID, resolveBase, matchPtr, localPtr, worldMatrix, worldPos, worldRot, saneMatrix, viewMatrix, applyRecoil, applySpread, applyReload, applyAmmo, applyMovement)

static void applyAim(uintptr_t lp, uintptr_t match) {
    if (!gCfg.on[T_AIM_MASTER]) return;
    if (!gCfg.on[T_AIMBOT] && !gCfg.on[T_SOFT]) return;

    uintptr_t cam = strip(read<uintptr_t>(lp + off::MainCameraTransform));
    const float* view = viewMatrix(cam);
    if (!view) { bc::mark("aim: no view matrix"); return; }

    Vec3 camW;
    Quat camWr, rootWr;
    if (!worldPos(cam, &camW) || !worldRot(cam, &camWr, 0)) { bc::mark("aim: cam world fail"); return; }
    if (!worldRot(lp + off::Tf_LocalRotation - off::Tf_LocalRotation, &rootWr, 0)) { /* lp is not a transform */ }

    uintptr_t dict = strip(read<uintptr_t>(match + off::DictEntities));
    if (!isHeap(dict)) return;
    uintptr_t entries = strip(read<uintptr_t>(dict + off::Dict_Entries));
    int count = read<int>(dict + off::Dict_Count);
    if (!isHeap(entries) || count <= 0 || count > 256) return;

    float radius = xenoFovRadius();
    float cx = gCfg.screenW * 0.5f, cy = gCfg.screenH * 0.5f;
    float best = radius;
    Vec3 bestHead{};
    uintptr_t bestPlayer = 0;

    for (int i = 0; i < count; i++) {
        uintptr_t e = entries + (uintptr_t)i * off::Entry_Stride;
        if (read<int>(e + off::Entry_Hash) < 0) continue;
        uintptr_t p = strip(read<uintptr_t>(e + off::Entry_Value));
        if (!isHeap(p) || p == lp) continue;
        if (read<bool>(p + off::Player_IsDead)) continue;
        uintptr_t bone = strip(read<uintptr_t>(p + off::Bones_Head));
        Vec3 head;
        if (!worldPos(bone, &head)) continue;
        float sx, sy;
        if (!worldToScreen(head, view, &sx, &sy, gCfg.screenW, gCfg.screenH)) continue;
        float d = sqrtf((sx - cx) * (sx - cx) + (sy - cy) * (sy - cy));
        if (d < best) { best = d; bestHead = head; bestPlayer = p; }
    }
    if (!bestPlayer) { bc::mark("aim: no target"); return; }

    Quat desiredCam = lookAt(camW, bestHead);
    Quat target = qmul(qmul(desiredCam, qinv(camWr)), rootWr);

    if (bestPlayer != gLastTarget) { gLastTarget = bestPlayer; gAimState = target; }
    else gAimState = qslerp(gAimState, target, gCfg.smooth);

    Quat out = gCfg.on[T_AIMBOT] ? target : gAimState;
    write<Quat>(lp + off::AimRotation, qnorm(out));
}

float xenoFovRadius(void) {
    const float halfV = 30.f * (float)M_PI / 180.f;
    return tanf(gCfg.fovDeg * 0.5f * (float)M_PI / 180.f) / tanf(halfV) * (gCfg.screenH * 0.5f);
}

void xenoApply(void) {
    if (!gUuidOk) { gCfg.status = S_UUID_BAD; return; }
    uintptr_t lp = localPtr();
    if (!lp) { gCfg.status = resolveBase() ? S_NO_MATCH : S_NO_MODULE; return; }
    gCfg.status = S_LIVE;

    if (lp != gLastPlayer) {
        gLastPlayer = lp;
        dropStale();
        gLastTarget = 0;
        gAimState = {0,0,0,1};
        bc::mark("player swapped");
    }
    if (read<bool>(lp + off::Player_IsDead)) return;

    uintptr_t match = matchPtr();
    if (gCfg.on[T_AIM_MASTER]) {
        if (gCfg.on[T_RECOIL]) applyRecoil(lp);
        if (gCfg.on[T_SPREAD]) applySpread(lp);
        if (gCfg.on[T_RELOAD]) applyReload(lp);
        if (gCfg.on[T_AMMO])   applyAmmo(lp);
        applyAim(lp, match);
    }
    if (gCfg.on[T_FLY] || gCfg.on[T_NOCLIP]) applyMovement(lp);
    // ESP boxes: collect in next pass and let menu draw them
}

void xenoSetToggle(int idx) {
    if (idx < 0 || idx >= T_COUNT) return;
    bool was = gCfg.on[idx];
    gCfg.on[idx] = !was;
    if (!was) return;

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

void xenoStep(int idx, int dir) {
    if (idx == T_COUNT - 2) {
        gCfg.smooth = fminf(1.f, fmaxf(0.02f, gCfg.smooth + dir * 0.04f));
    } else if (idx == T_COUNT - 1) {
        gCfg.fovDeg = fminf(90.f, fmaxf(1.f, gCfg.fovDeg + dir * 2.f));
    }
}

static UIWindow* keyWindow(void) {
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow* w in ((UIWindowScene*)s).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

static void attach(void) {
    UIWindow* w = keyWindow();
    if (!w) return;

    if (gMenu && gMenu.superview == w) return;

    if (!gMenu) {
        gMenu = [[XenoMenu alloc] initWithFrame:w.bounds];
        gMenu.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    } else {
        [gMenu removeFromSuperview];
        gMenu.frame = w.bounds;
    }
    [w addSubview:gMenu];

    gCfg.screenW = w.bounds.size.width;
    gCfg.screenH = w.bounds.size.height;
    gCfg.insetTop = w.safeAreaInsets.top;

    if (!gMenu.link) {
        CADisplayLink* l = [CADisplayLink displayLinkWithTarget:gMenu selector:@selector(setNeedsDisplay)];
        [l addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        gMenu.link = l;
    }
}

@interface XenoTick : NSObject
@end
@implementation XenoTick
- (void)step { xenoApply(); }
@end

static XenoTick* gTick = nil;
static CADisplayLink* gTickLink = nil;

static void ensureTick(void) {
    if (gTickLink) return;
    gTick = [XenoTick new];
    gTickLink = [CADisplayLink displayLinkWithTarget:gTick selector:@selector(step)];
    [gTickLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

static void onCrash(int sig) {
    bc::dump();
    signal(sig, SIG_DFL);
    raise(sig);
}

void xenoStart(void) {
    bc::init();
    signal(SIGSEGV, onCrash);
    signal(SIGBUS, onCrash);
    signal(SIGABRT, onCrash);
    gAttach = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer* t) {
        attach();
        if (gMenu && gMenu.superview) { ensureTick(); [t invalidate]; }
    }];
    [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer* t) {
        if (resolveBase()) [t invalidate];
    }];
}

__attribute__((constructor))
static void xenoInit(void) {
    // delayed attach so the game loads clean first
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        xenoStart();
    });
}
