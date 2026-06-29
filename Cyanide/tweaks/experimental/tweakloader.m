#import "tweakloader.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

#define TLDIR @"TweakLoader"

typedef void (*tweak_ctor_t)(void);
typedef void (*tweak_dtor_t)(void);

typedef struct {
    void *handle;
    tweak_ctor_t ctor;
    tweak_dtor_t dtor;
    char name[256];
} TLLoadedTweak;

static TLLoadedTweak gTlTweaks[64];
static unsigned int gTlCount = 0;
static bool gTlApplied = false;

void tweakloader_reload_list(void)
{
    for (unsigned int i = 0; i < gTlCount; i++) {
        if (gTlTweaks[i].handle) {
            if (gTlTweaks[i].dtor) gTlTweaks[i].dtor();
            dlclose(gTlTweaks[i].handle);
        }
    }
    gTlCount = 0;
    memset(gTlTweaks, 0, sizeof(gTlTweaks));

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count == 0) return;
    NSString *docDir = paths[0];
    NSString *tlDir = [docDir stringByAppendingPathComponent:@TLDIR];

    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:tlDir isDirectory:&isDir] || !isDir) {
        [[NSFileManager defaultManager] createDirectoryAtPath:tlDir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        return;
    }

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tlDir error:nil];
    for (NSString *file in files) {
        if (![file hasSuffix:@".dylib"]) continue;
        if (gTlCount >= 64) break;

        NSString *fullPath = [tlDir stringByAppendingPathComponent:file];
        void *handle = dlopen(fullPath.UTF8String, RTLD_LAZY);
        if (!handle) {
            printf("[TWEAKLOADER] dlopen failed for %s: %s\n", file.UTF8String, dlerror());
            continue;
        }

        TLLoadedTweak *t = &gTlTweaks[gTlCount];
        t->handle = handle;
        snprintf(t->name, sizeof(t->name), "%s", file.UTF8String);

        t->ctor = (tweak_ctor_t)dlsym(handle, "tweak_initialize");
        t->dtor = (tweak_dtor_t)dlsym(handle, "tweak_finalize");

        if (t->ctor) {
            t->ctor();
            printf("[TWEAKLOADER] loaded %s (ctor called)\n", t->name);
        } else {
            printf("[TWEAKLOADER] loaded %s (no tweak_initialize symbol)\n", t->name);
        }
        gTlCount++;
    }
    printf("[TWEAKLOADER] loaded %u dylibs from %s\n", gTlCount, TLDIR.UTF8String);
}

bool tweakloader_apply_in_session(void)
{
    printf("[TWEAKLOADER] apply\n");
    if (gTlCount == 0) {
        tweakloader_reload_list();
    }
    gTlApplied = true;
    return true;
}

bool tweakloader_stop_in_session(void)
{
    printf("[TWEAKLOADER] stop\n");
    for (unsigned int i = 0; i < gTlCount; i++) {
        if (gTlTweaks[i].handle && gTlTweaks[i].dtor) {
            gTlTweaks[i].dtor();
        }
        if (gTlTweaks[i].handle) {
            dlclose(gTlTweaks[i].handle);
        }
    }
    gTlCount = 0;
    gTlApplied = false;
    return true;
}

void tweakloader_forget_remote_state(void)
{
    gTlApplied = false;
}

unsigned int tweakloader_loaded_count(void)
{
    return gTlCount;
}
