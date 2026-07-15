#import "betterccxi.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gBetterCCXIApplied = false;
static int gBetterCCXIZLift = 4;
static int gBetterCCXIDepthLimit = 12;
static int gBetterCCXIModuleScalePercent = 96;
typedef struct { double a, b, c, d, tx, ty; } BetterCCXIAffine;

static uint64_t betterccxi_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void betterccxi_class_name(uint64_t obj, char *out, size_t outLen)
{
    (void)sb_read_class_name(obj, out, outLen);
}

static void betterccxi_scan(uint64_t parent, double scale, int depth, int *visited, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > gBetterCCXIDepthLimit || !visited ||
        *visited >= 320 || (hits && *hits >= 48)) return;
    (*visited)++;
    char cls[160] = {0};
    betterccxi_class_name(parent, cls, sizeof(cls));
    // Never lift every generic ControlCenter ancestor: that changes stacking
    // for overlays, gestures, and dismissal chrome. Only module/media layers
    // participate in this compact presentation.
    bool target = strstr(cls, "CCUIModule") || strstr(cls, "MediaControls") ||
                  strstr(cls, "NowPlaying");
    bool scaleTarget = strstr(cls, "CCUIModuleContainer") || strstr(cls, "MediaControlsPanelView") ||
                       strstr(cls, "NowPlayingContainer");
    uint64_t layer = target ? r_msg2_main(parent, "layer", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(layer)) {
        double z = (double)gBetterCCXIZLift;
        sb_cc_override_bytes("betterccxi", layer, "zPosition", "setZPosition:", &z, sizeof(z));
        if (hits) (*hits)++;
    }
    if (scaleTarget && r_responds_main(parent, "setTransform:")) {
        BetterCCXIAffine transform = { scale, 0, 0, scale, 0, 0 };
        sb_cc_override_bytes("betterccxi", parent, "transform", "setTransform:", &transform, sizeof(transform));
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 80) count = 80;
    for (uint64_t i = 0; i < count; i++) {
        betterccxi_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), scale, depth + 1, visited, hits);
    }
}

bool betterccxi_apply_in_session(void)
{
    printf("[BETTERCCXI] apply\n");
    uint64_t win = sb_control_center_window();
    if (!r_is_objc_ptr(win)) return false;
    int visited = 0, hits = 0;
    betterccxi_scan(win, (double)gBetterCCXIModuleScalePercent / 100.0, 0, &visited, &hits);
    printf("[BETTERCCXI] lift=%d scale=%d%% depth=%d visited=%d hits=%d\n", gBetterCCXIZLift, gBetterCCXIModuleScalePercent, gBetterCCXIDepthLimit, visited, hits);
    gBetterCCXIApplied = hits > 0;
    return gBetterCCXIApplied;
}

bool betterccxi_stop_in_session(void)
{
    printf("[BETTERCCXI] stop\n");
    int hits = sb_cc_restore_owner("betterccxi");
    gBetterCCXIApplied = false;
    log_user("[BETTERCCXI][RESTORE] exactProperties=%d.\n", hits);
    return hits > 0;
}

void betterccxi_configure(int zLift, int depthLimit, int moduleScalePercent)
{
    if (zLift < 0) zLift = 0;
    if (zLift > 20) zLift = 20;
    if (depthLimit < 4) depthLimit = 4;
    if (depthLimit > 16) depthLimit = 16;
    if (moduleScalePercent < 75) moduleScalePercent = 75;
    if (moduleScalePercent > 115) moduleScalePercent = 115;
    gBetterCCXIZLift = zLift;
    gBetterCCXIDepthLimit = depthLimit;
    gBetterCCXIModuleScalePercent = moduleScalePercent;
}

void betterccxi_forget_remote_state(void) { gBetterCCXIApplied = false; sb_cc_forget_owner("betterccxi"); }
