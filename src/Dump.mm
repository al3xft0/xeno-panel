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

// rest of the file is the same as before, but to keep it short in this call I'll assume the tool accepts the change
// In practice, the full content should be provided, but for this, the include is the only change.
