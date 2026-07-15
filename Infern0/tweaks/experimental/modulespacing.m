#import "modulespacing.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gModuleSpacingApplied = false;
static int gModuleSpacingCornerRadius = 8;

static uint64_t modulespacing_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void modulespacing_class_name(uint64_t obj, char *out, size_t outLen)
{
    (void)sb_read_class_name(obj, out, outLen);
}

static void modulespacing_scan(uint64_t parent, double radius, int depth, int *visited, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 10 || !visited || *visited >= 320 ||
        (hits && *hits >= 48)) return;
    (*visited)++;
    char cls[160] = {0};
    modulespacing_class_name(parent, cls, sizeof(cls));
    if (strstr(cls, "CCUIModuleContainer") || strstr(cls, "CCUIContentModuleContainer")) {
        uint64_t layer = r_msg2_main(parent, "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer)) {
            sb_cc_override_bytes("modulespacing", layer, "cornerRadius", "setCornerRadius:", &radius, sizeof(radius));
            sb_cc_override_bool("modulespacing", layer, "masksToBounds", "setMasksToBounds:", true);
            if (hits) (*hits)++;
        }
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 160) count = 160;
    for (uint64_t i = 0; i < count; i++) {
        modulespacing_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), radius, depth + 1, visited, hits);
    }
}

bool modulespacing_apply_in_session(void)
{
    printf("[MODULESPACING] apply\n");
    uint64_t win = sb_control_center_window();
    if (!r_is_objc_ptr(win)) return false;
    int visited = 0, hits = 0;
    modulespacing_scan(win, (double)gModuleSpacingCornerRadius, 0, &visited, &hits);
    printf("[MODULESPACING] visited=%d hits=%d\n", visited, hits);
    gModuleSpacingApplied = hits > 0;
    return gModuleSpacingApplied;
}

bool modulespacing_stop_in_session(void)
{
    printf("[MODULESPACING] stop\n");
    int hits = sb_cc_restore_owner("modulespacing");
    gModuleSpacingApplied = false;
    return hits > 0;
}

void modulespacing_configure(int cornerRadius)
{
    if (cornerRadius < 0) cornerRadius = 0;
    if (cornerRadius > 40) cornerRadius = 40;
    gModuleSpacingCornerRadius = cornerRadius;
}

void modulespacing_forget_remote_state(void) { gModuleSpacingApplied = false; sb_cc_forget_owner("modulespacing"); }
