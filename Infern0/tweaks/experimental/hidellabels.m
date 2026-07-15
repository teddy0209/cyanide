#import "hidellabels.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gHllApplied = false;
static int gHllChanged = 0;

static void hll_scan_icon_views(uint64_t parent, int depth, int *visited)
{
    if (!r_is_objc_ptr(parent) || depth > 10 || !visited || *visited >= 768) return;
    (*visited)++;

    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 64) count = 64;

    for (uint64_t i = 0; i < count; i++) {
        uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(sv)) continue;

        char cls[128] = {0};
        (void)sb_read_class_name(sv, cls, sizeof(cls));

        if (strstr(cls, "SBIconView") && !strstr(cls, "Label")) {
            hll_scan_icon_views(sv, depth + 1, visited);
            continue;
        }

        if (strstr(cls, "Label") || strstr(cls, "label")) {
            uint64_t UILabel = r_class("UILabel");
            if (r_is_objc_ptr(UILabel)) {
                uint64_t isLabel = r_msg2_main(sv, "isKindOfClass:", UILabel, 0, 0, 0);
                if (isLabel & 0xff) {
                    double zero = 0.0;
                    if (sb_cc_override_bytes("hidellabels", sv, "alpha", "setAlpha:",
                                             &zero, sizeof(zero))) gHllChanged++;
                }
            }
        }

        hll_scan_icon_views(sv, depth + 1, visited);
    }
}

bool hidellabels_apply_in_session(void)
{
    printf("[HLL] apply\n");
    gHllChanged = 0;

    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(listClass)) return false;
    uint64_t lists[64] = {0};
    int listCount = sb_collect_views_in_windows(listClass, lists, 64);
    int visited = 0;
    for (int i = 0; i < listCount && visited < 768; i++) {
        uint64_t icons[256] = {0};
        int iconCount = sb_collect_icon_views_from_list(lists[i], icons, 256);
        for (int j = 0; j < iconCount && visited < 768; j++)
            hll_scan_icon_views(icons[j], 0, &visited);
    }

    gHllApplied = gHllChanged > 0;
    log_user("[HIDELABELS][APPLY] lists=%d visited=%d hiddenLabels=%d result=%s.\n",
             listCount, visited, gHllChanged, gHllApplied ? "active" : "no-labels-found");
    return gHllApplied;
}

bool hidellabels_stop_in_session(void)
{
    printf("[HLL] stop\n");
    int restored = sb_cc_restore_owner("hidellabels");
    gHllApplied = false;
    log_user("[HIDELABELS][RESTORE] exactProperties=%d.\n", restored);
    return restored > 0;
}

void hidellabels_forget_remote_state(void)
{
    gHllApplied = false;
    gHllChanged = 0;
    sb_cc_forget_owner("hidellabels");
}
