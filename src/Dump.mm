// src/Dump.mm — runtime offset resolver. Separate dylib, never ships with the panel.
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

// ---------------- Il2Cpp exports ----------------

typedef void*    (*t_domain_get)(void);
typedef void**   (*t_domain_assemblies)(void*, size_t*);
typedef void*    (*t_assembly_image)(void*);
typedef const char* (*t_image_name)(void*);
typedef size_t   (*t_image_class_count)(void*);
typedef void*    (*t_image_class)(void*, size_t);
typedef void*    (*t_class_from_name)(void*, const char*, const char*);
typedef void*    (*t_class_fields)(void*, void**);
typedef const char* (*t_field_name)(void*);
typedef size_t   (*t_field_offset)(void*);
typedef void*    (*t_field_type)(void*);
typedef void     (*t_field_static_get)(void*, void*);
typedef uint32_t (*t_field_flags)(void*);
typedef char*    (*t_type_name)(void*);
typedef void*    (*t_class_methods)(void*, void**);
typedef const char* (*t_method_name)(void*);
typedef void*    (*t_method_ptr)(void*);
typedef const char* (*t_class_namespace)(void*);
typedef void*    (*t_thread_attach)(void*);

static t_domain_get        p_domain_get;
static t_domain_assemblies p_domain_assemblies;
static t_assembly_image    p_assembly_image;
static t_image_name        p_image_name;
static t_image_class_count p_image_class_count;
static t_image_class       p_image_class;
static t_class_from_name   p_class_from_name;
static t_class_fields      p_class_fields;
static t_field_name        p_field_name;
static t_field_offset      p_field_offset;
static t_field_type        p_field_type;
static t_field_static_get  p_field_static_get;
static t_field_flags       p_field_flags;
static t_type_name         p_type_name;
static t_class_methods     p_class_methods;
static t_method_name       p_method_name;
static t_method_ptr        p_method_ptr;
static t_class_namespace   p_class_namespace;
static t_thread_attach     p_thread_attach;

static uintptr_t gBase = 0;
static int       gResolved = 0;      // 0 none, 1 partial, 2 api ok
static char      gHow[16] = "none";
static bool      gOnce = false;

#define NEED(sym) p_##sym
static bool apiReady(void) {
    return p_domain_get && p_domain_assemblies && p_assembly_image &&
           p_class_from_name && p_class_fields && p_field_offset &&
           p_field_type && p_field_name && p_type_name;
}

static void* viaDlsym(const char* n) { return dlsym(RTLD_DEFAULT, n); }

// ---------------- symtab fallback ----------------

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
        {"il2cpp_image_get_class_count", (void**)&p_image_class_count},
        {"il2cpp_image_get_class", (void**)&p_image_class},
        {"il2cpp_class_from_name", (void**)&p_class_from_name},
        {"il2cpp_class_get_fields", (void**)&p_class_fields},
        {"il2cpp_field_get_name", (void**)&p_field_name},
        {"il2cpp_field_get_offset", (void**)&p_field_offset},
        {"il2cpp_field_get_type", (void**)&p_field_type},
        {"il2cpp_field_static_get_value", (void**)&p_field_static_get},
        {"il2cpp_field_get_flags", (void**)&p_field_flags},
        {"il2cpp_type_get_name", (void**)&p_type_name},
        {"il2cpp_class_get_methods", (void**)&p_class_methods},
        {"il2cpp_method_get_name", (void**)&p_method_name},
        {"il2cpp_method_get_pointer", (void**)&p_method_ptr},
        {"il2cpp_class_get_namespace", (void**)&p_class_namespace},
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
    p_image_class_count = (t_image_class_count)viaDlsym("il2cpp_image_get_class_count");
    p_image_class       = (t_image_class)viaDlsym("il2cpp_image_get_class");
    p_class_from_name   = (t_class_from_name)viaDlsym("il2cpp_class_from_name");
    p_class_fields      = (t_class_fields)viaDlsym("il2cpp_class_get_fields");
    p_field_name        = (t_field_name)viaDlsym("il2cpp_field_get_name");
    p_field_offset      = (t_field_offset)viaDlsym("il2cpp_field_get_offset");
    p_field_type        = (t_field_type)viaDlsym("il2cpp_field_get_type");
    p_field_static_get  = (t_field_static_get)viaDlsym("il2cpp_field_static_get_value");
    p_field_flags       = (t_field_flags)viaDlsym("il2cpp_field_get_flags");
    p_type_name         = (t_type_name)viaDlsym("il2cpp_type_get_name");
    p_class_methods     = (t_class_methods)viaDlsym("il2cpp_class_get_methods");
    p_method_name       = (t_method_name)viaDlsym("il2cpp_method_get_name");
    p_method_ptr        = (t_method_ptr)viaDlsym("il2cpp_method_get_pointer");
    p_class_namespace   = (t_class_namespace)viaDlsym("il2cpp_class_get_namespace");
    p_thread_attach     = (t_thread_attach)viaDlsym("il2cpp_thread_attach");

    if (!apiReady()) scanSymtab();
    gResolved = apiReady() ? 2 : (p_domain_get ? 1 : 0);
}

// ---------------- expectations ----------------

struct Expect {
    const char* cls;
    const char* ns;
    uintptr_t   offset;
    const char* type;     // expected il2cpp type name
    const char* label;
};

static const Expect kExpect[] = {
    {"Match",     "", 0x50,  "System.Boolean", "Player_IsDead"},
    {"Player",    "", 0x94,  "System.IntPtr",  "LocalPlayer"},
    {"Player",    "", 0x440, "UnityEngine.Quaternion", "AimRotation"},
    {"Player",    "", 0x434, "System.IntPtr",  "Weapon"},
    {"Player",    "", 0x49C, "System.IntPtr",  "Bones_Head"},
    {"Player",    "", 0x348, "System.IntPtr",  "CharacterController"},
    {"Player",    "", 0x500, "System.IntPtr",  "LocalPlayerAttributes"},
    {"Player",    "", 0x28C, "System.IntPtr",  "MainCameraTransform"},
    {"Transform", "UnityEngine", 0x10, "UnityEngine.Quaternion", "Tf_LocalRotation"},
    {"Transform", "UnityEngine", 0x20, "UnityEngine.Vector3",    "Tf_LocalPosition"},
    {"Transform", "UnityEngine", 0x30, "UnityEngine.Vector3",    "Tf_LocalScale"},
    {"Transform", "UnityEngine", 0x48, "System.IntPtr",          "Tf_Father"},
    {"Camera",    "UnityEngine", 0xE8, "System.IntPtr",          "Cam_ViewMatrixField"},
    {"GunFeelProfile", "", 0x1D0, "System.Boolean", "WGP_EnableRecoil"},
    {"GunFeelProfile", "", 0x1D6, "System.Boolean", "WGP_EnableSpread"},
    {"GunFeelProfile", "", 0x1A4, "System.Single",  "WGP_HipRecoilPitchScale"},
    {"GunFeelProfile", "", 0x0A0, "System.Single",  "WGP_HipRecoilYawScale"},
    {"GunFeelProfile", "", 0x128, "System.Single",  "WGP_HipSpreadLimit"},
    {"GunFeelProfile", "", 0x0FC, "System.Single",  "WGP_AdsSpreadLimit"},
    {"WeaponData", "", 0x158, "System.Single", "ReloadSpeed"},
};

static const char* kClassHints[] = {
    "Player", "Match", "GameRoom", "GameManager", "PlayerManager",
    "Weapon", "GunFeelProfile", "WeaponData", "CharacterController",
    "LocalPlayerAttributes",
};
static const char* kStaticHints[] = {
    "GameRoom", "Match", "GameManager", "Game", "PlayerManager", "GameCore",
};

// ---------------- report ----------------

static FILE* gOut = nullptr;
static int   gFails = 0;

static void js(const char* s) {
    if (!s) return;
    for (; *s; s++) {
        if (*s == '"' || *s == '\\') fputc('\\', gOut);
        if ((unsigned char)*s < 0x20) { fprintf(gOut, "\\u%04x", *s); continue; }
        fputc(*s, gOut);
    }
}

struct FieldInfo {
    const char* name;
    const char* type;
    size_t      offset;
    bool        isStatic;
};

static int collectFields(void* klass, FieldInfo* out, int cap) {
    int n = 0;
    void* it = nullptr;
    void* f;
    while ((f = p_class_fields(klass, &it)) && n < cap) {
        uint32_t flags = p_field_flags ? p_field_flags(f) : 0;
        out[n].name = p_field_name(f);
        out[n].type = p_type_name(p_field_type(f));
        out[n].offset = p_field_offset(f);
        out[n].isStatic = (flags & 0x0010) != 0;
        n++;
    }
    return n;
}

static void dumpClass(void* image, const char* ns, const char* name) {
    void* klass = p_class_from_name(image, ns, name);
    fprintf(gOut, "  {\"class\": \"%s\", \"ns\": \"%s\", ", name, ns);
    if (!klass) { fprintf(gOut, "\"found\": false},\n"); return; }
    fprintf(gOut, "\"found\": true, \"fields\": [");

    FieldInfo fi[512];
    int n = collectFields(klass, fi, 512);
    size_t maxOff = 0;
    for (int i = 0; i < n; i++) {
        if (i) fputc(',', gOut);
        fprintf(gOut, "{\"name\": \"");
        js(fi[i].name);
        fprintf(gOut, "\", \"type\": \"");
        js(fi[i].type);
        fprintf(gOut, "\", \"offset\": %zu, \"static\": %s}",
                fi[i].offset, fi[i].isStatic ? "true" : "false");
        if (!fi[i].isStatic && fi[i].offset > maxOff) maxOff = fi[i].offset;
    }
    fprintf(gOut, "], \"max_instance_offset\": %zu, \"methods\": [", maxOff);

    if (p_class_methods && p_method_name && p_method_ptr) {
        void* it = nullptr;
        void* m;
        int c = 0;
        while ((m = p_class_methods(klass, &it)) && c < 64) {
            void* fn = p_method_ptr(m);
            if (!fn) continue;
            if (c) fputc(',', gOut);
            fprintf(gOut, "{\"name\": \"");
            js(p_method_name(m));
            fprintf(gOut, "\", \"rva\": \"0x%llX\"}",
                    (unsigned long long)(strip((uintptr_t)fn) - gBase));
            c++;
        }
    }
    fprintf(gOut, "]},\n");
}

static void verdictFor(void* image, const Expect& e) {
    fprintf(gOut, "  {\"label\": \"%s\", \"class\": \"%s\", \"expected_offset\": \"0x%zX\", ", e.label, e.cls, e.offset);
    void* klass = p_class_from_name(image, e.ns, e.cls);
    if (!klass) { fprintf(gOut, "\"verdict\": \"CLASS_MISSING\"},\n"); gFails++; return; }

    FieldInfo fi[512];
    int n = collectFields(klass, fi, 512);
    size_t maxOff = 0;
    for (int i = 0; i < n; i++) if (!fi[i].isStatic && fi[i].offset > maxOff) maxOff = fi[i].offset;

    if (maxOff < e.offset) {
        fprintf(gOut, "\"verdict\": \"PAST_END\", \"max_instance_offset\": \"0x%zX\"},\n", maxOff);
        gFails++; return;
    }

    for (int i = 0; i < n; i++) {
        if (fi[i].isStatic || fi[i].offset != e.offset) continue;
        bool ok = fi[i].type && strcmp(fi[i].type, e.type) == 0;
        fprintf(gOut, "\"verdict\": \"%s\", \"found_name\": \"", ok ? "OK" : "TYPE_MISMATCH");
        js(fi[i].name);
        fprintf(gOut, "\", \"found_type\": \"");
        js(fi[i].type);
        fprintf(gOut, "\"},\n");
        if (!ok) gFails++;
        return;
    }
    fprintf(gOut, "\"verdict\": \"NO_FIELD_AT_OFFSET\"},\n");
    gFails++;
}

static void dumpStatics(void* image) {
    for (const char* hint : kStaticHints) {
        void* k = p_class_from_name(image, "", hint);
        if (!k) continue;
        FieldInfo fi[128];
        int n = collectFields(k, fi, 128);
        for (int i = 0; i < n; i++) {
            if (!fi[i].isStatic || !fi[i].type) continue;
            if (strstr(fi[i].type, "IntPtr") == nullptr) continue;
            uintptr_t v = 0;
            if (p_field_static_get) p_field_static_get((void*)(uintptr_t)&fi[i], &v);
            fprintf(gOut, "  {\"static_hint\": \"%s\", \"field\": \"", hint);
            js(fi[i].name);
            fprintf(gOut, "\", \"value\": \"0x%llX\", \"heap\": %s},\n",
                    (unsigned long long)v, isHeap(v) ? "true" : "false");
        }
    }
}

// ---------------- entry ----------------

static void runDump(void) {
    if (gOnce) return;
    resolveApi();
    if (gResolved != 2) {
        bc::mark("dump: il2cpp api unavailable");
        return;
    }
    gOnce = true;

    const char* home = getenv("HOME");
    if (!home) return;
    char path[512];
    snprintf(path, sizeof path, "%s/Documents/offsets_report.json", home);
    gOut = fopen(path, "w");
    if (!gOut) return;

    void* domain = p_domain_get();
    if (!domain) { fclose(gOut); gOut = nullptr; return; }
    if (p_thread_attach) p_thread_attach(domain);

    fprintf(gOut, "{\"module\": \"%s\", \"dump_date\": \"%s\", \"api\": \"%s\", \"images\": [", off::kModule, off::kDumpDate, gHow);

    size_t asmCount = 0;
    void** asms = p_domain_assemblies(domain, &asmCount);
    void* game = nullptr;
    for (size_t i = 0; i < asmCount && i < 512; i++) {
        void* img = p_assembly_image(asms[i]);
        const char* nm = img && p_image_name ? p_image_name(img) : "?";
        if (i) fputc(',', gOut);
        fprintf(gOut, "\"");
        js(nm);
        fprintf(gOut, "\"");
        if (nm && (strcmp(nm, "Assembly-CSharp.dll") == 0 || strcmp(nm, "Assembly-CSharp") == 0)) game = img;
    }
    fprintf(gOut, "],\n");

    if (!game) {
        fprintf(gOut, "\"error\": \"Assembly-CSharp not found\", \"fails\": 1}\n");
        fclose(gOut);
        bc::mark("dump: no Assembly-CSharp");
        return;
    }

    void* core = nullptr;
    for (size_t i = 0; i < asmCount && i < 512; i++) {
        void* img = p_assembly_image(asms[i]);
        const char* nm = img && p_image_name ? p_image_name(img) : nullptr;
        if (nm && strstr(nm, "UnityEngine.CoreModule")) { core = img; break; }
    }

    fprintf(gOut, "\"classes\": [\n");
    for (const char* hint : kClassHints) dumpClass(game, "", hint);
    if (core) { dumpClass(core, "UnityEngine", "Transform"); dumpClass(core, "UnityEngine", "Camera"); }
    fprintf(gOut, "],\n\"statics\": [\n");
    dumpStatics(game);
    fprintf(gOut, "],\n\"verdicts\": [\n");

    for (const Expect& e : kExpect) {
        if (!strcmp(e.ns, "UnityEngine")) { if (core) verdictFor(core, e); }
        else verdictFor(game, e);
    }

    fprintf(gOut, "],\n\"fails\": %d}\n", gFails);
    fclose(gOut);
    gOut = nullptr;
    NSLog(@"[XENO-DUMP] wrote %s (%d failures)", path, gFails);
    bc::mark("dump: complete");
}

static void tick(void) {
    if (gOnce) return;
    resolveApi();
    if (gResolved != 2) return;
    // statics are only live once a match exists
    uintptr_t m = 0;
    void* domain = p_domain_get();
    if (domain) {
        size_t c = 0;
        void** a = p_domain_assemblies(domain, &c);
        for (size_t i = 0; i < c && i < 512 && !m; i++) {
            void* img = p_assembly_image(a[i]);
            const char* nm = img && p_image_name ? p_image_name(img) : nullptr;
            if (!nm || !strstr(nm, "Assembly-CSharp")) continue;
            void* k = p_class_from_name(img, "", "GameRoom");
            if (k) { (void)k; m = 1; }
        }
    }
    if (m) runDump();
}

__attribute__((constructor))
static void dumpInit(void) {
    bc::init();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer* t) { tick(); }];
    });
}
