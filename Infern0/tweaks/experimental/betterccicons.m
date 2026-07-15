#import "betterccicons.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gBetterCCIconsApplied = false;
static int gBetterCCIconsCornerRadius = 22;

static uint64_t betterccicons_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void betterccicons_class_name(uint64_t obj, char *out, size_t outLen)
{
    (void)sb_read_class_name(obj, out, outLen);
}

static void betterccicons_scan(uint64_t parent, double radius, int depth, int *visited, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 10 || !visited || *visited >= 320 ||
        (hits && *hits >= 48)) return;
    (*visited)++;
    char cls[160] = {0};
    betterccicons_class_name(parent, cls, sizeof(cls));
    // Restrict clipping to actual button/toggle backgrounds. Applying
    // masksToBounds to glyph-package or generic ButtonView layers clipped
    // symbols and produced the torn-looking Control Center overlay.
    bool target = strstr(cls, "CCUIRoundButton") ||
                  strstr(cls, "CCUIButtonModuleView") ||
                  strstr(cls, "ControlCenterButton") ||
                  strstr(cls, "ToggleView");
    uint64_t layer = target ? r_msg2_main(parent, "layer", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(layer)) {
        sb_cc_override_bytes("betterccicons", layer, "cornerRadius", "setCornerRadius:", &radius, sizeof(radius));
        sb_cc_override_bool("betterccicons", layer, "masksToBounds", "setMasksToBounds:", true);
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 120) count = 120;
    for (uint64_t i = 0; i < count; i++) betterccicons_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), radius, depth + 1, visited, hits);
}

bool betterccicons_apply_in_session(void)
{
    printf("[BETTERCCICONS] apply\n");
    uint64_t win = sb_control_center_window();
    if (!r_is_objc_ptr(win)) return false;
    int visited = 0, hits = 0;
    betterccicons_scan(win, (double)gBetterCCIconsCornerRadius, 0, &visited, &hits);
    printf("[BETTERCCICONS] visited=%d hits=%d budget=320\n", visited, hits);
    gBetterCCIconsApplied = hits > 0;
    return gBetterCCIconsApplied;
}

bool betterccicons_stop_in_session(void)
{
    printf("[BETTERCCICONS] stop\n");
    int hits = sb_cc_restore_owner("betterccicons");
    gBetterCCIconsApplied = false;
    return hits > 0;
}

void betterccicons_configure(int cornerRadius)
{
    if (cornerRadius < 0) cornerRadius = 0;
    if (cornerRadius > 44) cornerRadius = 44;
    gBetterCCIconsCornerRadius = cornerRadius;
}

void betterccicons_forget_remote_state(void) { gBetterCCIconsApplied = false; sb_cc_forget_owner("betterccicons"); }
