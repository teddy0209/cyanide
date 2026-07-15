#import "ccnoplatterdim.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gCCNoPlatterDimApplied = false;
static int gCCNoPlatterDimVisibleAlphaPercent = 96;

static uint64_t ccnoplatterdim_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void ccnoplatterdim_class_name(uint64_t obj, char *out, size_t outLen)
{
    (void)sb_read_class_name(obj, out, outLen);
}

static void ccnoplatterdim_scan(uint64_t parent, double alpha, int depth, int *visited, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 10 || !visited || *visited >= 320 ||
        (hits && *hits >= 32)) return;
    (*visited)++;
    char cls[160] = {0};
    ccnoplatterdim_class_name(parent, cls, sizeof(cls));
    bool dimTarget = strstr(cls, "Dimming") || strstr(cls, "PlatterOverlay") ||
                     strstr(cls, "ExpandedPlatterTransition");
    if (dimTarget) {
        sb_cc_override_bytes("ccnoplatterdim", parent, "alpha", "setAlpha:", &alpha, sizeof(alpha));
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 80) count = 80;
    for (uint64_t i = 0; i < count; i++) ccnoplatterdim_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), alpha, depth + 1, visited, hits);
}

bool ccnoplatterdim_apply_in_session(void)
{
    printf("[CCNOPLATTERDIM] apply\n");
    uint64_t win = sb_control_center_window();
    if (!r_is_objc_ptr(win)) return false;
    int visited = 0, hits = 0;
    // The target is the dimming overlay, so "expanded brightness" is the
    // inverse of its alpha. The previous direct mapping made 96% brightness
    // produce a 96%-opaque dim layer—the exact opposite of the setting.
    double dimAlpha = 1.0 - (double)gCCNoPlatterDimVisibleAlphaPercent / 100.0;
    ccnoplatterdim_scan(win, dimAlpha, 0, &visited, &hits);
    printf("[CCNOPLATTERDIM] visited=%d hits=%d\n", visited, hits);
    gCCNoPlatterDimApplied = hits > 0;
    return gCCNoPlatterDimApplied;
}

bool ccnoplatterdim_stop_in_session(void)
{
    printf("[CCNOPLATTERDIM] stop\n");
    int hits = sb_cc_restore_owner("ccnoplatterdim");
    gCCNoPlatterDimApplied = false;
    return hits > 0;
}

void ccnoplatterdim_configure(int visibleAlphaPercent)
{
    if (visibleAlphaPercent < 40) visibleAlphaPercent = 40;
    if (visibleAlphaPercent > 100) visibleAlphaPercent = 100;
    gCCNoPlatterDimVisibleAlphaPercent = visibleAlphaPercent;
}

void ccnoplatterdim_forget_remote_state(void) { gCCNoPlatterDimApplied = false; sb_cc_forget_owner("ccnoplatterdim"); }
