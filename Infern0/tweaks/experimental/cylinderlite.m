#import "cylinderlite.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

static bool gCyApplied = false;
static uint64_t gCyLastIconListView = 0;
static int gCyDepth = -10;
static int gCyPerspectiveDistance = 650;
static int gCyMaxIcons = 512;
static uint64_t gCyLists[64] = {0};
static int gCyListCount = 0;
static uint64_t gCyIcons[512] = {0};
static uint64_t gCyIconLists[512] = {0};
static int gCyIconCount = 0;

typedef struct {
    double m11, m12, m13, m14;
    double m21, m22, m23, m24;
    double m31, m32, m33, m34;
    double m41, m42, m43, m44;
} CYRemoteCATransform3D;

typedef struct { double x, y, width, height; } CYRect;

static CYRemoteCATransform3D cy_identity_transform(void)
{
    CYRemoteCATransform3D t;
    memset(&t, 0, sizeof(t));
    t.m11 = 1.0;
    t.m22 = 1.0;
    t.m33 = 1.0;
    t.m44 = 1.0;
    return t;
}

static bool cy_get_rect(uint64_t obj, const char *selector, CYRect *out)
{
    if (!r_is_objc_ptr(obj) || !out || !r_responds_main(obj, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(obj, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cy_list_is_excluded(uint64_t list)
{
    uint64_t view = list;
    for (int depth = 0; r_is_objc_ptr(view) && depth < 10; depth++) {
        char cls[160] = {0};
        (void)sb_read_class_name(view, cls, sizeof(cls));
        if (strstr(cls, "Dock") || strstr(cls, "Library")) return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

static double cy_page_progress(uint64_t list)
{
    CYRect bounds = {0}, windowRect = {0};
    uint64_t nilView = 0;
    if (!cy_get_rect(list, "bounds", &bounds) || bounds.width <= 1.0) return 0.0;
    if (!r_msg2_main_struct_ret(list, "convertRect:toView:", &windowRect, sizeof(windowRect),
                                &bounds, sizeof(bounds), &nilView, sizeof(nilView),
                                NULL, 0, NULL, 0)) return 0.0;
    uint64_t window = r_msg2_main(list, "window", 0, 0, 0, 0);
    CYRect windowBounds = {0};
    if (!cy_get_rect(window, "bounds", &windowBounds) || windowBounds.width <= 1.0) return 0.0;
    double progress = ((windowRect.x + windowRect.width * 0.5) -
                       (windowBounds.x + windowBounds.width * 0.5)) / windowBounds.width;
    if (progress < -1.25) progress = -1.25;
    if (progress > 1.25) progress = 1.25;
    return progress;
}

static CYRemoteCATransform3D cy_icon_transform(uint64_t icon, uint64_t list, int ordinal, double pageProgress)
{
    CYRemoteCATransform3D t = cy_identity_transform();
    CYRect iconFrame = {0}, listBounds = {0};
    double normalized = ((double)(ordinal % 4) - 1.5) / 1.5;
    if (cy_get_rect(icon, "frame", &iconFrame) &&
        cy_get_rect(list, "bounds", &listBounds) && listBounds.width > 1.0) {
        double center = iconFrame.x + iconFrame.width * 0.5;
        normalized = ((center - listBounds.x) / listBounds.width - 0.5) * 2.0;
    }
    if (normalized < -1.0) normalized = -1.0;
    if (normalized > 1.0) normalized = 1.0;
    // Centered pages settle at identity. During a horizontal swipe, the page
    // rotates as a cylinder and icons fan slightly according to their column.
    double angle = pageProgress * (1.35 + normalized * 0.18);
    double cosine = cos(angle), sine = sin(angle);
    int distance = gCyPerspectiveDistance < 250 ? 250 : gCyPerspectiveDistance;
    t.m11 = cosine;
    t.m13 = -sine;
    t.m31 = sine;
    t.m33 = cosine;
    t.m34 = -1.0 / (double)distance;
    t.m43 = (double)gCyDepth * fabs(pageProgress) * (1.0 + fabs(normalized) * 0.15);
    return t;
}

static void cy_apply_perspective_to_layer(uint64_t layer, bool enabled)
{
    if (!r_is_objc_ptr(layer)) return;
    CYRemoteCATransform3D t = cy_identity_transform();
    int distance = gCyPerspectiveDistance;
    if (distance < 250) distance = 250;
    if (enabled) t.m34 = -1.0 / (double)distance;
    sb_cc_override_bytes("cylinderlite", layer, "sublayerTransform", "setSublayerTransform:",
                         &t, sizeof(t));
}

static void cy_discover_pages(void)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(iconClass) || !r_is_objc_ptr(listClass)) return;
    uint64_t lists[64] = {0};
    int listCount = sb_collect_views_in_windows(listClass, lists, 64);
    for (int i = 0; i < listCount && gCyListCount < 64; i++) {
        if (cy_list_is_excluded(lists[i])) continue;
        bool known = false;
        for (int k = 0; k < gCyListCount; k++) if (gCyLists[k] == lists[i]) { known = true; break; }
        if (!known) {
            gCyLists[gCyListCount++] = lists[i];
            r_msg2_main(lists[i], "retain", 0, 0, 0, 0);
            uint64_t layer = r_msg2_main(lists[i], "layer", 0, 0, 0, 0);
            cy_apply_perspective_to_layer(layer, true);
        }
        uint64_t pageIcons[256] = {0};
        int count = sb_collect_icon_views_from_list(lists[i], pageIcons, 256);
        for (int j = 0; j < count && gCyIconCount < gCyMaxIcons; j++) {
            bool iconKnown = false;
            for (int k = 0; k < gCyIconCount; k++) if (gCyIcons[k] == pageIcons[j]) { iconKnown = true; break; }
            if (!iconKnown) {
                gCyIcons[gCyIconCount] = pageIcons[j];
                gCyIconLists[gCyIconCount] = lists[i];
                gCyIconCount++;
                r_msg2_main(pageIcons[j], "retain", 0, 0, 0, 0);
            }
        }
    }
}

bool cylinderlite_refresh_in_session(bool discoverPages)
{
    if (discoverPages || gCyListCount == 0 || gCyIconCount == 0) cy_discover_pages();
    int transformed = 0;
    double pageProgress[64] = {0};
    for (int i = 0; i < gCyListCount; i++)
        pageProgress[i] = cy_page_progress(gCyLists[i]);
    for (int i = 0; i < gCyIconCount; i++) {
        uint64_t icon = gCyIcons[i], list = gCyIconLists[i];
        if (!r_is_objc_ptr(icon) || !r_is_objc_ptr(list)) continue;
        double progress = 0.0;
        for (int page = 0; page < gCyListCount; page++)
            if (gCyLists[page] == list) { progress = pageProgress[page]; break; }
        uint64_t layer = r_msg2_main(icon, "layer", 0, 0, 0, 0);
        if (!r_is_objc_ptr(layer)) continue;
        CYRemoteCATransform3D transform = cy_icon_transform(icon, list, i, progress);
        if (sb_cc_override_bytes("cylinderlite", layer, "transform", "setTransform:",
                                 &transform, sizeof(transform))) transformed++;
        r_msg2_main(icon, "setUserInteractionEnabled:", 1, 0, 0, 0);
    }
    gCyApplied = transformed > 0;
    return gCyApplied;
}

bool cylinderlite_apply_in_session(void)
{
    printf("[CYLINDER] apply\n");

    cy_discover_pages();
    for (int i = 0; i < gCyListCount; i++) {
        uint64_t layer = r_msg2_main(gCyLists[i], "layer", 0, 0, 0, 0);
        cy_apply_perspective_to_layer(layer, true);
    }
    bool active = cylinderlite_refresh_in_session(false);
    int iconCount = gCyIconCount, pageCount = gCyListCount, listCount = gCyListCount, excludedLists = 0;
    gCyLastIconListView = gCyListCount > 0 ? gCyLists[0] : 0;
    printf("[CYLINDER] transformed icons=%d pages=%d lists=%d excluded=%d scanLimit=%d taps=preserved\n",
           iconCount, pageCount, listCount, excludedLists, gCyMaxIcons);
    log_user("[CYLINDER][APPLY] discoveredLists=%d activePages=%d excludedDockLibraryLists=%d transformedIcons=%d depth=%d perspective=%d scanLimit=%d tapsPreserved=1 result=%s.\n",
             listCount, pageCount, excludedLists, iconCount, gCyDepth,
             gCyPerspectiveDistance, gCyMaxIcons, iconCount > 0 ? "active" : "no-home-pages");

    return active;
}

bool cylinderlite_stop_in_session(void)
{
    printf("[CYLINDER] stop\n");
    int iconCount = gCyIconCount, listCount = gCyListCount;
    int restored = sb_cc_restore_owner("cylinderlite");
    for (int i = 0; i < gCyIconCount; i++)
        if (r_is_objc_ptr(gCyIcons[i])) r_msg2_main(gCyIcons[i], "release", 0, 0, 0, 0);
    for (int i = 0; i < gCyListCount; i++)
        if (r_is_objc_ptr(gCyLists[i])) r_msg2_main(gCyLists[i], "release", 0, 0, 0, 0);
    memset(gCyLists, 0, sizeof(gCyLists));
    memset(gCyIcons, 0, sizeof(gCyIcons));
    memset(gCyIconLists, 0, sizeof(gCyIconLists));
    gCyListCount = gCyIconCount = 0;
    gCyLastIconListView = 0;
    gCyApplied = false;
    log_user("[CYLINDER][RESTORE] icons=%d lists=%d identityTransforms=1 perspectiveCleared=1.\n",
             iconCount, listCount);
    return restored > 0;
}

void cylinderlite_configure(int depth, int perspectiveDistance, int maxIcons)
{
    if (depth > 0) depth = 0;
    if (depth < -80) depth = -80;
    if (perspectiveDistance < 250) perspectiveDistance = 250;
    if (perspectiveDistance > 1600) perspectiveDistance = 1600;
    if (maxIcons < 32) maxIcons = 32;
    if (maxIcons > 512) maxIcons = 512;
    gCyDepth = depth;
    gCyPerspectiveDistance = perspectiveDistance;
    gCyMaxIcons = maxIcons;
}

void cylinderlite_forget_remote_state(void)
{
    gCyApplied = false;
    gCyLastIconListView = 0;
    memset(gCyLists, 0, sizeof(gCyLists));
    memset(gCyIcons, 0, sizeof(gCyIcons));
    memset(gCyIconLists, 0, sizeof(gCyIconLists));
    gCyListCount = gCyIconCount = 0;
    sb_cc_forget_owner("cylinderlite");
}
