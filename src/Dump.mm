// src/Dump.mm — runtime offset resolver + status UI
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#include <dlfcn.h>
#include <cstring>
#include <cstdio>
#include "Mem.h"
#include "VecMath.h"
#include "Offsets.h"

// (all the existing Il2Cpp typedefs, statics, resolveApi, scanSymtab, Expect, helpers, runDump, tick stay exactly as before)

// ---------------- status UI ----------------

static UIWindow* gDumpWin = nil;
static UILabel*  gStatus = nil;
static UITextView* gConsole = nil;
static UIButton* gDumpBtn = nil;

static void logLine(NSString* s) {
    if (!gConsole) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        gConsole.text = [gConsole.text stringByAppendingFormat:@"%@\n", s];
        [gConsole scrollRangeToVisible:NSMakeRange(gConsole.text.length, 0)];
    });
}

static void setStatus(NSString* s) {
    if (!gStatus) return;
    dispatch_async(dispatch_get_main_queue(), ^{ gStatus.text = s; });
}

static void makeDumpUI(void) {
    if (gDumpWin) return;
    UIWindow* w = nil;
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow* ww in ((UIWindowScene*)s).windows) if (ww.isKeyWindow) { w = ww; break; }
    }
    if (!w) return;

    gDumpWin = [[UIWindow alloc] initWithFrame:CGRectMake(16, 80, 280, 220)];
    gDumpWin.windowLevel = UIWindowLevelAlert + 1;
    gDumpWin.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.96];
    gDumpWin.layer.cornerRadius = 14;
    gDumpWin.layer.borderWidth = 0.6;
    gDumpWin.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    gDumpWin.hidden = NO;

    gStatus = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, 256, 22)];
    gStatus.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold];
    gStatus.textColor = UIColor.whiteColor;
    gStatus.text = @"dump: waiting";
    [gDumpWin addSubview:gStatus];

    gConsole = [[UITextView alloc] initWithFrame:CGRectMake(8, 36, 264, 120)];
    gConsole.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    gConsole.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    gConsole.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    gConsole.editable = NO;
    gConsole.text = @"";
    [gDumpWin addSubview:gConsole];

    gDumpBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    gDumpBtn.frame = CGRectMake(12, 166, 256, 40);
    [gDumpBtn setTitle:@"Dump Now" forState:UIControlStateNormal];
    [gDumpBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    gDumpBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    gDumpBtn.layer.cornerRadius = 8;
    [gDumpBtn addTarget:nil action:@selector(manualDump) forControlEvents:UIControlEventTouchUpInside];
    [gDumpWin addSubview:gDumpBtn];

    [gDumpWin makeKeyAndVisible];
}

static void manualDump(void) {
    logLine(@"manual dump requested");
    setStatus(@"dump: running...");
    runDump();
}

// patch the existing tick / runDump to call the UI

static void runDump(void) {
    if (gOnce) { logLine(@"already dumped"); return; }
    resolveApi();
    if (gResolved != 2) {
        logLine(@"il2cpp api unavailable");
        setStatus(@"dump: no api");
        bc::mark("dump: il2cpp api unavailable");
        return;
    }
    gOnce = true;
    setStatus(@"dump: writing...");
    logLine(@"api ok, writing report");

    const char* home = getenv("HOME");
    if (!home) { logLine(@"no HOME"); return; }
    char path[512];
    snprintf(path, sizeof path, "%s/Documents/offsets_report.json", home);
    gOut = fopen(path, "w");
    if (!gOut) { logLine(@"fopen failed"); return; }

    // (existing write logic stays identical — omitted here for length, keep the original body)
    // ... original fprintf / dumpClass / verdictFor calls ...

    fclose(gOut);
    gOut = nullptr;
    NSString* msg = [NSString stringWithFormat:@"wrote %s (%d fails)", path, gFails];
    logLine(msg);
    setStatus(@"dump: complete");
    NSLog(@"[XENO-DUMP] wrote %s (%d failures)", path, gFails);
    bc::mark("dump: complete");
}

__attribute__((constructor))
static void dumpInit(void) {
    bc::init();
    dispatch_async(dispatch_get_main_queue(), ^{
        makeDumpUI();
        [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer* t) { tick(); }];
    });
}
