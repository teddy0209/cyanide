#import "cleanhomescreen.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gChsApplied = false;
static bool gChsBadgeHidden = false;
static bool gChsDotHidden = false;
static bool gChsLabelHidden = false;
static int gChsChanged = 0;

static bool chs_set_alpha(uint64_t view, double alpha)
{
    return r_is_objc_ptr(view) &&
        sb_cc_override_bytes("cleanhomescreen", view, "alpha", "setAlpha:", &alpha, sizeof(alpha));
}

static void chs_scan_views(uint64_t parent, int depth, bool insideIcon, int *visited)
{
    if (!r_is_objc_ptr(parent) || depth > 10 || !visited || *visited >= 768) return;
    (*visited)++;

    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 128) count = 128;

    for (uint64_t i = 0; i < count; i++) {
        uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(sv)) continue;

        char cls[128] = {0};
        (void)sb_read_class_name(sv, cls, sizeof(cls));
        bool childInsideIcon = insideIcon || strstr(cls, "SBIconView") != NULL;

        if (childInsideIcon && strstr(cls, "Badge") && !strstr(cls, "Label")) {
            if (gChsBadgeHidden && chs_set_alpha(sv, 0.0)) gChsChanged++;
        }

        if (strstr(cls, "SBIconListPageControl") ||
            strstr(cls, "SBRootFolderPageControl") ||
            strstr(cls, "SBHPageControl")) {
            if (gChsDotHidden && sb_cc_override_bool("cleanhomescreen", sv, "isHidden", "setHidden:", true)) gChsChanged++;
        }

        if (childInsideIcon && (strstr(cls, "Label") || strstr(cls, "label"))) {
            if (gChsLabelHidden && chs_set_alpha(sv, 0.0)) gChsChanged++;
        }

        chs_scan_views(sv, depth + 1, childInsideIcon, visited);
    }
}

bool cleanhomescreen_apply_in_session(bool hideBadges, bool hidePageDots, bool hideLabels)
{
    printf("[CHS] apply badges=%d dots=%d labels=%d\n", hideBadges, hidePageDots, hideLabels);

    bool configChanged = gChsApplied &&
        (gChsBadgeHidden != hideBadges || gChsDotHidden != hidePageDots ||
         gChsLabelHidden != hideLabels);
    if (configChanged) sb_cc_restore_owner("cleanhomescreen");
    gChsBadgeHidden = hideBadges;
    gChsDotHidden = hidePageDots;
    gChsLabelHidden = hideLabels;
    gChsChanged = 0;

    int visited = 0;
    uint64_t listClass = r_class("SBIconListView");
    uint64_t lists[64] = {0};
    int listCount = r_is_objc_ptr(listClass)
        ? sb_collect_views_in_windows(listClass, lists, 64) : 0;
    for (int i = 0; i < listCount && visited < 768; i++) {
        uint64_t icons[256] = {0};
        int iconCount = sb_collect_icon_views_from_list(lists[i], icons, 256);
        for (int j = 0; j < iconCount && visited < 768; j++)
            chs_scan_views(icons[j], 0, true, &visited);
    }
    if (gChsDotHidden) {
        const char *dotClasses[] = {
            "SBIconListPageControl", "SBRootFolderPageControl", "SBHPageControl", NULL
        };
        for (int c = 0; dotClasses[c]; c++) {
            uint64_t cls = r_class(dotClasses[c]);
            if (!r_is_objc_ptr(cls)) continue;
            uint64_t dots[16] = {0};
            int dotCount = sb_collect_views_in_windows(cls, dots, 16);
            for (int i = 0; i < dotCount; i++)
                if (sb_cc_override_bool("cleanhomescreen", dots[i], "isHidden", "setHidden:", true))
                    gChsChanged++;
        }
    }

    gChsApplied = gChsChanged > 0;
    log_user("[CLEANHOMESCREEN][APPLY] lists=%d visitedIconSubviews=%d exactOverrides=%d hideBadges=%d hideDots=%d hideLabels=%d result=%s.\n",
             listCount, visited, gChsChanged, hideBadges, hidePageDots, hideLabels,
             gChsApplied ? "active" : "nothing-requested-or-found");
    return gChsApplied;
}

bool cleanhomescreen_stop_in_session(void)
{
    printf("[CHS] stop\n");
    int restored = sb_cc_restore_owner("cleanhomescreen");
    gChsApplied = false;
    gChsBadgeHidden = false;
    gChsDotHidden = false;
    gChsLabelHidden = false;
    log_user("[CLEANHOMESCREEN][RESTORE] exactProperties=%d.\n", restored);
    return restored > 0;
}

void cleanhomescreen_forget_remote_state(void)
{
    gChsApplied = false;
    gChsChanged = 0;
    gChsBadgeHidden = false;
    gChsDotHidden = false;
    gChsLabelHidden = false;
    sb_cc_forget_owner("cleanhomescreen");
}
