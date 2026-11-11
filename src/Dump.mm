// src/Dump.mm — metadata-driven offset resolver + status UI
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

typedef void*    (*t_domain_get)(void);
typedef void**   (*t_domain_assemblies)(void*, size_t*);
typedef void*    (*t_assembly_image)(void*);
typedef const char* (*t_image_name)(void*);
typedef void*    (*t_class_from_name)(void*, const char*, const char*);
typedef void*    (*t_class_get_fields)(void*, void**);
typedef const char* (*t_field_get_name)(void*);
typedef size_t   (*t_field_get_offset)(void*);
typedef uint32_t (*t_field_get_flags)(void*);
typedef void*    (*t_thread_attach)(void*);

static t_domain_get        p_domain_get;
static t_domain_assemblies p_domain_assemblies;
static t_assembly_image    p_assembly_image;
static t_image_name        p_image_name;
static t_class_from_name   p_class_from_name;
static t_class_get_fields  p_class_get_fields;
static t_field_get_name    p_field_get_name;
static t_field_get_offset  p_field_get_offset;
static t_field_get_flags   p_field_get_flags;
static t_thread_attach     p_thread_attach;

static uintptr_t gBase = 0;
static int       gResolved = 0;
static char      gHow[16] = "none";
static bool      gOnce = false;
static FILE*     gOut = nullptr;

static bool apiReady(void) {
    return p_domain_get && p_class_from_name && p_class_get_fields && p_field_get_offset && p_field_get_name && p_thread_attach;
}

static void* viaDlsym(const char* n) { return dlsym(RTLD_DEFAULT, n); }

static void scanSymtab(void) {
    const struct mach_header_64* h = (const struct mach_header_64*)gBase;
    if (!h) return;
    uintptr_t p = (uintptr_t)h + sizeof(*h);
    const struct symtab_command* st = nullptr;
    uint64_t textVm = 0;
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command* lc = (const struct load_command*)p;
        if (lc->cmd == LC_SYMTAB) st = (const struct symtab_command*)lc;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* sg = (const struct segment_command_64*)lc;
            if (strcmp(sg->segname, "__TEXT") == 0) textVm = sg->vmaddr;
        }
        p += lc->cmdsize;
    }
    if (!st || !textVm) return;
    const struct nlist_64* syms = (const struct nlist_64*)(gBase + (st->symoff - textVm));
    const char* strs = (const char*)(gBase + (st->stroff - textVm));
    struct Pair { const char* name; void** slot; };
    Pair table[] = {
        {"il2cpp_domain_get", (void**)&p_domain_get},
        {"il2cpp_domain_get_assemblies", (void**)&p_domain_assemblies},
        {"il2cpp_assembly_get_image", (void**)&p_assembly_image},
        {"il2cpp_image_get_name", (void**)&p_image_name},
        {"il2cpp_class_from_name", (void**)&p_class_from_name},
        {"il2cpp_class_get_fields", (void**)&p_class_get_fields},
        {"il2cpp_field_get_name", (void**)&p_field_get_name},
        {"il2cpp_field_get_offset", (void**)&p_field_get_offset},
        {"il2cpp_field_get_flags", (void**)&p_field_get_flags},
        {"il2cpp_thread_attach", (void**)&p_thread_attach},
    };
    for (uint32_t i = 0; i < st->nsyms; i++) {
        if (syms[i].n_un.n_strx == 0) continue;
        const char* nm = strs + syms[i].n_un.n_strx;
        if (strncmp(nm, "il2cpp_", 7) != 0) continue;
        for (auto& e : table) {
            if (*e.slot) continue;
            if (strcmp(nm, e.name) != 0) continue;
            *e.slot = (void*)(gBase + (syms[i].n_value - textVm));
        }
    }
    strcpy(gHow, "symtab");
}

static void resolveApi(void) {
    if (gResolved == 2) return;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* n = _dyld_get_image_name(i);
        if (!n) continue;
        const char* leaf = strrchr(n, '/');
        leaf = leaf ? leaf + 1 : n;
        if (strcmp(leaf, off::kModule) != 0) continue;
        gBase = strip((uintptr_t)_dyld_get_image_header(i));
        break;
    }
    if (!gBase) return;
    strcpy(gHow, "dlsym");
    p_domain_get        = (t_domain_get)viaDlsym("il2cpp_domain_get");
    p_domain_assemblies = (t_domain_assemblies)viaDlsym("il2cpp_domain_get_assemblies");
    p_assembly_image    = (t_assembly_image)viaDlsym("il2cpp_assembly_get_image");
    p_image_name        = (t_image_name)viaDlsym("il2cpp_image_get_name");
    p_class_from_name   = (t_class_from_name)viaDlsym("il2cpp_class_from_name");
    p_class_get_fields  = (t_class_get_fields)viaDlsym("il2cpp_class_get_fields");
    p_field_get_name    = (t_field_get_name)viaDlsym("il2cpp_field_get_name");
    p_field_get_offset  = (t_field_get_offset)viaDlsym("il2cpp_field_get_offset");
    p_field_get_flags   = (t_field_get_flags)viaDlsym("il2cpp_field_get_flags");
    p_thread_attach     = (t_thread_attach)viaDlsym("il2cpp_thread_attach");
    if (!apiReady()) scanSymtab();
    gResolved = apiReady() ? 2 : 0;
}

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
    gDumpWin = [[UIWindow alloc] initWithFrame:CGRectMake(16, 90, 300, 240)];
    gDumpWin.windowLevel = UIWindowLevelAlert + 1;
    gDumpWin.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.96];
    gDumpWin.layer.cornerRadius = 14;
    gDumpWin.layer.borderWidth = 0.6;
    gDumpWin.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    gDumpWin.hidden = NO;

    gStatus = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, 276, 22)];
    gStatus.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold];
    gStatus.textColor = UIColor.whiteColor;
    gStatus.text = @"dump: idle";
    [gDumpWin addSubview:gStatus];

    gConsole = [[UITextView alloc] initWithFrame:CGRectMake(8, 36, 284, 140)];
    gConsole.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    gConsole.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    gConsole.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    gConsole.editable = NO;
    gConsole.text = @"";
    [gDumpWin addSubview:gConsole];

    gDumpBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    gDumpBtn.frame = CGRectMake(12, 186, 276, 40);
    [gDumpBtn setTitle:@"Dump Now" forState:UIControlStateNormal];
    [gDumpBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    gDumpBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    gDumpBtn.layer.cornerRadius = 8;
    [gDumpBtn addTarget:nil action:@selector(manualDump) forControlEvents:UIControlEventTouchUpInside];
    [gDumpWin addSubview:gDumpBtn];
    [gDumpWin makeKeyAndVisible];
}

static void emit(const char* fmt, ...) {
    if (!gOut) return;
    va_list ap; va_start(ap, fmt);
    vfprintf(gOut, fmt, ap);
    va_end(ap);
}

static void dumpClassFields(void* image, const char* ns, const char* name) {
    void* k = p_class_from_name(image, ns, name);
    if (!k) { emit("MISS %s.%s\n", ns, name); return; }
    emit("=== %s.%s ===\n", ns, name);
    void* it = nullptr; void* f;
    while ((f = p_class_get_fields(k, &it))) {
        size_t o = p_field_get_offset(f);
        const char* fn = p_field_get_name(f);
        uint32_t flags = p_field_get_flags ? p_field_get_flags(f) : 0;
        bool st = (flags & 0x0010) != 0;
        emit("  %s = 0x%zX%s\n", fn ? fn : "?", o, st ? "  [static]" : "");
    }
}

static void manualDump(void) {
    logLine(@"manual dump");
    setStatus(@"dump: running");
    if (gOnce) { logLine(@"already done"); return; }
    resolveApi();
    if (gResolved != 2) {
        logLine(@"il2cpp api missing");
        setStatus(@"dump: no api");
        return;
    }
    gOnce = true;
    const char* home = getenv("HOME");
    if (!home) { logLine(@"no HOME"); return; }
    char path[512];
    snprintf(path, sizeof path, "%s/Documents/xeno_dump.txt", home);
    gOut = fopen(path, "w");
    if (!gOut) { logLine(@"fopen failed"); return; }

    void* domain = p_domain_get();
    if (p_thread_attach) p_thread_attach(domain);

    size_t asmCount = 0;
    void** asms = p_domain_assemblies(domain, &asmCount);
    void* game = nullptr;
    for (size_t i = 0; i < asmCount && i < 512; i++) {
        void* img = p_assembly_image(asms[i]);
        const char* nm = img && p_image_name ? p_image_name(img) : nullptr;
        if (nm && strstr(nm, "Assembly-CSharp")) { game = img; break; }
    }
    if (!game) { emit("no Assembly-CSharp\n"); fclose(gOut); return; }

    emit("// xeno dump via Il2Cpp API (%s)\n", gHow);
    dumpClassFields(game, "", "Player");
    dumpClassFields(game, "", "Match");
    dumpClassFields(game, "", "GameMatch");
    dumpClassFields(game, "", "Weapon");
    dumpClassFields(game, "", "GunFeelProfile");
    dumpClassFields(game, "", "WeaponData");

    fclose(gOut);
    gOut = nullptr;
    setStatus(@"dump: complete");
    logLine(@"wrote Documents/xeno_dump.txt");
    NSLog(@"[XENO-DUMP] wrote %s", path);
}

__attribute__((constructor))
static void dumpInit(void) {
    bc::init();
    dispatch_async(dispatch_get_main_queue(), ^{
        makeDumpUI();
        logLine(@"dump ui ready — tap Dump Now in match");
    });
}
