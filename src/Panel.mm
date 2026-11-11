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

Config gCfg = { .smooth = 0.22f, .fovDeg = 14.f, .status = S_BOOT };
char   gUuidActual[64] = {0};

static uintptr_t gBase = 0;
static bool      gUuidOk = true;
static uintptr_t gLastPlayer = 0;
static uintptr_t gLastTarget = 0;
static Quat      gAimState = {0,0,0,1};
static uintptr_t gMainWindow = 0;
static XenoMenu* gMenu = nil;
static NSTimer*  gAttach = nil;

// ---------------- module resolve ----------------

static const char* imageName(uint32_t i) { return _dyld_get_image_name(i); }

static bool isTargetModule(const char* path) {
    if (!path) return false;
    const char* slash = strrchr(path, '/');
    const char* leaf = slash ? slash + 1 : path;
    return strcmp(leaf, off::kModule) == 0;   // exact leaf, not substring
}

static void readUUID(const struct mach_header_64* h, char* out, size_t cap) {
    uintptr_t p = (uintptr_t)h + sizeof(*h);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command* lc = (const struct load_command*)p;
        if (lc->cmd == LC_UUID) {
            const struct uuid_command* uc = (const struct uuid_command*)lc;
            snprintf(out, cap, "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                uc->uuid[0], uc->uuid[1], uc->uuid[2], uc->uuid[3], uc->uuid[4], uc->uuid[5],
                uc->uuid[6], uc->uuid[7], uc->uuid[8], uc->uuid[9], uc->uuid[10], uc->uuid[11],
                uc->uuid[12], uc->uuid[13], uc->uuid[14], uc->uuid[15]);
            return;
        }
        p += lc->cmdsize;
    }
}

static uintptr_t resolveBase(void) {
    if (gBase) return gBase;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* n = imageName(i);
        if (!isTargetModule(n)) continue;
        gBase = strip((uintptr_t)_dyld_get_image_header(i));
        readUUID((const struct mach_header_64*)gBase, gUuidActual, sizeof gUuidActual);
        if (off::kExpectedUUID[0] && strcasecmp(gUuidActual, off::kExpectedUUID) != 0) {
            gUuidOk = false;
            NSLog(@"[XENO] UUID mismatch: got %s want %s", gUuidActual, off::kExpectedUUID);
        }
        NSLog(@"[XENO] module %s @ %p uuid %s", n, (void*)gBase, gUuidActual);
        return gBase;
    }
    return 0;
}

static uintptr_t matchPtr(void) {
    uintptr_t b = resolveBase();
    if (!b) return 0;
    uintptr_t cls = strip(read<uintptr_t>(b + off::InitBase));
    if (!isHeap(cls)) return 0;
    uintptr_t statics = strip(read<uintptr_t>(cls + off::StaticFields));
    if (!isHeap(statics)) return 0;
    return strip(read<uintptr_t>(statics + off::CurrentMatch));
}

static uintptr_t localPtr(void) {
    uintptr_t m = matchPtr();
    if (!m) return 0;
    return strip(read<uintptr_t>(m + off::LocalPlayer));
}

// ---------------- world transforms ----------------

static bool worldMatrix(uintptr_t tf, Mat4* out, int depth) {
    if (!isHeap(tf) || depth > 16) return false;
    Quat q = read<Quat>(tf + off::Tf_LocalRotation);
    Vec3 p = read<Vec3>(tf + off::Tf_LocalPosition);
    Vec3 s = read<Vec3>(tf + off::Tf_LocalScale);
    Mat4 local = trs(q, p, s);
    uintptr_t father = strip(read<uintptr_t>(tf + off::Tf_Father));
    if (isHeap(father) && father != tf) {
        Mat4 parent;
        if (!worldMatrix(father, &parent, depth + 1)) return false;
        *out = mmul(parent, local);
        return true;
    }
    *out = local;
    return true;
}

static bool worldPos(uintptr_t tf, Vec3* out) {
    Mat4 m;
    if (!worldMatrix(tf, &m, 0)) return false;
    *out = { m.m[12], m.m[13], m.m[14] };
    return true;
}

static bool worldRot(uintptr_t tf, Quat* out, int depth) {
    if (!isHeap(tf) || depth > 16) return false;
    Quat q = qnorm(read<Quat>(tf + off::Tf_LocalRotation));
    uintptr_t father = strip(read<uintptr_t>(tf + off::Tf_Father));
    if (isHeap(father) && father != tf) {
        Quat parent;
        if (!worldRot(father, &parent, depth + 1)) return false;
        *out = qmul(parent, q);
        return true;
    }
    *out = q;
    return true;
}

// ---------------- view matrix ----------------

static bool saneMatrix(const float* m) {
    if (!m) return false;
    for (int i = 0; i < 16; i++) if (!isfinite(m[i])) return false;
    if (fabsf(m[15] - 1.f) > 0.05f) return false;
    if (fabsf(m[3]) > 0.01f || fabsf(m[7]) > 0.01f || fabsf(m[11]) > 0.01f) return false;
    float t = fabsf(m[12]) + fabsf(m[13]) + fabsf(m[14]);
    return t > 0.001f && t < 1e7f;
}

static const float* viewMatrix(uintptr_t cam) {
    if (!isHeap(cam)) return nullptr;
    uintptr_t f = strip(read<uintptr_t>(cam + off::Cam_ViewMatrixField));
    if (isHeap(f) && saneMatrix((const float*)f)) return (const float*)f;   // field held a pointer
    uintptr_t native = strip(read<uintptr_t>(cam + off::Obj_CachedPtr));
    if (isHeap(native) && saneMatrix((const float*)(native + off::Cam_ViewMatrixField)))
        return (const float*)(native + off::Cam_ViewMatrixField);
    if (saneMatrix((const float*)(cam + off::Cam_ViewMatrixField)))
        return (const float*)(cam + off::Cam_ViewMatrixField);              // inline matrix
    return nullptr;
}

// ---------------- apply ----------------

static void applyRecoil(uintptr_t lp) {
    uintptr_t w = strip(read<uintptr_t>(lp + off::Weapon));
    if (!isHeap(w)) return;
    uintptr_t feel = strip(read<uintptr_t>(w + off::Weapon_GunFeelProfile));
    if (!isHeap(feel)) return;
    saveWrite<bool>(G_RECOIL, feel + off::WGP_EnableRecoil, false);
    saveWrite<bool>(G_RECOIL, feel + off::WGP_EnableGunFeel, false);
    saveWrite<float>(G_RECOIL, feel + off::WGP_HipRecoilPitchScale, 0.f);
    saveWrite<float>(G_RECOIL, feel + off::WGP_HipRecoilYawScale, 0.f);
}

static void applySpread(uintptr_t lp) {
    uintptr_t w = strip(read<uintptr_t>(lp + off::Weapon));
    if (!isHeap(w)) return;
    uintptr_t feel = strip(read<uintptr_t>(w + off::Weapon_GunFeelProfile));
    if (!isHeap(feel)) return;
    saveWrite<bool>(G_SPREAD, feel + off::WGP_EnableSpread, false);
    saveWrite<float>(G_SPREAD, feel + off::WGP_HipSpreadLimit, 0.f);
    saveWrite<float>(G_SPREAD, feel + off::WGP_AdsSpreadLimit, 0.f);
}

static void applyReload(uintptr_t lp) {
    uintptr_t w = strip(read<uintptr_t>(lp + off::Weapon));
    if (!isHeap(w)) return;
    uintptr_t data = strip(read<uintptr_t>(w + off::WeaponData));
    if (isHeap(data)) saveWrite<float>(G_RELOAD, data + off::ReloadSpeed, 8.5f);
}

static void applyAmmo(uintptr_t lp) {
    uintptr_t attr = strip(read<uintptr_t>(lp + off::LocalPlayerAttributes));
    if (isHeap(attr)) saveWrite<bool>(G_AMMO, attr + off::Attr_UnlimitedAmmo, true);
}

static void applyMovement(uintptr_t lp) {
    uintptr_t cc = strip(read<uintptr_t>(lp + off::CharController));
    if (!isHeap(cc)) return;
    if (gCfg.on[T_FLY])   saveWrite<bool>(G_FLY,   cc + off::CCT_UseGravity, false);
    if (gCfg.on[T_NOCLIP]) saveWrite<bool>(G_NOCLIP, cc + off::CCT_SolveCollisions, false);
}

static void applyAim(uintptr_t lp, uintptr_t match) {
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
        if (read<int>(e + off::Entry_Hash) < 0) continue;          // free slot
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

    // desired camera orientation, then de-rotate into player-root space so the
    // third-person camera offset doesn't bias the shot
    Quat desiredCam = lookAt(camW, bestHead);
    Quat target = qmul(qmul(desiredCam, qinv(camWr)), rootWr);

    if (bestPlayer != gLastTarget) { gLastTarget = bestPlayer; gAimState = target; }
    else gAimState = qslerp(gAimState, target, gCfg.smooth);

    Quat out = gCfg.on[T_AIMBOT] ? target : gAimState;
    write<Quat>(lp + off::AimRotation, qnorm(out));
}

// ---------------- tick ----------------

float xenoFovRadius(void) {
    // degrees -> pixels, relative to a nominal 60 deg vertical FOV
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
    if (gCfg.on[T_RECOIL]) applyRecoil(lp);
    if (gCfg.on[T_SPREAD]) applySpread(lp);
    if (gCfg.on[T_RELOAD]) applyReload(lp);
    if (gCfg.on[T_AMMO])   applyAmmo(lp);
    if (gCfg.on[T_FLY] || gCfg.on[T_NOCLIP]) applyMovement(lp);
    applyAim(lp, match);
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

// ---------------- attach ----------------

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

// apply loop object — CADisplayLink needs an ObjC target
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
    // keep re-verifying the UUID gate until the module shows up
    [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer* t) {
        if (resolveBase()) [t invalidate];
    }];
}

__attribute__((constructor))
static void xenoInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ xenoStart(); });
}
