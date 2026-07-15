#import "pullover.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <string.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} PullOverRect;

static uint64_t gPullOverView = 0;
static uint64_t gPullOverIcons[4] = {0};
static uint64_t gPullOverIconParents[4] = {0};
static uint64_t gPullOverIconIndices[4] = {0};
static PullOverRect gPullOverIconFrames[4] = {{0}};
static int gPullOverIconCount = 0;
static int gPullOverWidth = 76;
static int gPullOverYOffset = 130;
static int gPullOverMaxHeight = 420;
static int gPullOverCornerRadius = 20;
static int gPullOverBackgroundAlphaPercent = 88;

static uint64_t pullover_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red),
                           &green, sizeof(green),
                           &blue, sizeof(blue),
                           &alpha, sizeof(alpha));
}

static uint64_t pullover_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return 0;
    return r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
}

static PullOverRect pullover_bounds_for_view(uint64_t view)
{
    PullOverRect bounds = { 0, 0, 390, 844 };
    if (r_is_objc_ptr(view)) {
        r_msg2_main_struct_ret(view, "bounds", &bounds, sizeof(bounds),
                               NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    }
    if (bounds.width <= 0) bounds.width = 390;
    if (bounds.height <= 0) bounds.height = 844;
    return bounds;
}

static uint64_t pullover_alloc_view(double x, double y, double w, double h)
{
    uint64_t UIView = r_class("UIView");
    if (!r_is_objc_ptr(UIView)) return 0;
    uint64_t view = r_msg2_main(UIView, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(view)) return 0;
    PullOverRect frame = { x, y, w, h };
    view = r_msg2_main_raw(view, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    return r_is_objc_ptr(view) ? view : 0;
}

static uint64_t pullover_alloc_label(void)
{
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(UILabel)) return 0;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(label)) return 0;
    PullOverRect frame = { 8, 230, 60, 24 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return 0;
    uint64_t str = r_nsstr_retained("App");
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    uint64_t white = pullover_color(1, 1, 1, 0.92);
    if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double size = 13.0;
        uint64_t font = r_msg2_main_raw(UIFont, "boldSystemFontOfSize:", &size, sizeof(size), NULL, 0, NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    return label;
}

static void pullover_add_grabber(uint64_t tray, double trayWidth)
{
    uint64_t grabber = pullover_alloc_view((trayWidth - 5.0) / 2.0, 18.0, 5.0, 44.0);
    if (!r_is_objc_ptr(grabber)) return;
    uint64_t bg = pullover_color(1, 1, 1, 0.52);
    if (r_is_objc_ptr(bg)) r_msg2_main(grabber, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(grabber, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 2.5;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    r_msg2_main(tray, "addSubview:", grabber, 0, 0, 0);
    r_msg2_main(grabber, "release", 0, 0, 0, 0);
}

static void pullover_restore_icons(void)
{
    int restored = 0;
    for (int i = 0; i < gPullOverIconCount; i++) {
        if (!r_is_objc_ptr(gPullOverIcons[i]) || !r_is_objc_ptr(gPullOverIconParents[i])) continue;
        uint64_t siblings = r_msg2_main(gPullOverIconParents[i], "subviews", 0, 0, 0, 0);
        uint64_t count = r_is_objc_ptr(siblings) ? r_msg2_main(siblings, "count", 0, 0, 0, 0) : 0;
        uint64_t index = gPullOverIconIndices[i] == UINT64_MAX ? count : gPullOverIconIndices[i];
        if (index > count) index = count;
        if (r_responds_main(gPullOverIconParents[i], "insertSubview:atIndex:"))
            r_msg2_main(gPullOverIconParents[i], "insertSubview:atIndex:", gPullOverIcons[i], index, 0, 0);
        else
            r_msg2_main(gPullOverIconParents[i], "addSubview:", gPullOverIcons[i], 0, 0, 0);
        r_msg2_main_raw(gPullOverIcons[i], "setFrame:", &gPullOverIconFrames[i], sizeof(PullOverRect),
                        NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(gPullOverIconParents[i], "release", 0, 0, 0, 0);
        restored++;
    }
    int interactionRestored = sb_cc_restore_owner("pullover");
    memset(gPullOverIcons, 0, sizeof(gPullOverIcons));
    memset(gPullOverIconParents, 0, sizeof(gPullOverIconParents));
    memset(gPullOverIconFrames, 0, sizeof(gPullOverIconFrames));
    memset(gPullOverIconIndices, 0, sizeof(gPullOverIconIndices));
    gPullOverIconCount = 0;
    if (restored || interactionRestored)
        log_user("[PULLOVER][RESTORE] returned=%d exactInteractionStates=%d originalListsFramesAndSiblingOrder=1.\n",
                 restored, interactionRestored);
}

static void pullover_add_icon_slot(uint64_t tray, double x, double y, double side)
{
    uint64_t slot = pullover_alloc_view(x, y, side, side);
    if (!r_is_objc_ptr(slot)) return;
    uint64_t bg = pullover_color(1, 1, 1, 0.14);
    if (r_is_objc_ptr(bg)) r_msg2_main(slot, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(slot, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = side * 0.24;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    r_msg2_main(tray, "addSubview:", slot, 0, 0, 0);
    r_msg2_main(slot, "release", 0, 0, 0, 0);
}

static bool pullover_is_excluded_icon(uint64_t view)
{
    for (int depth = 0; r_is_objc_ptr(view) && depth < 12; depth++) {
        char buffer[160] = {0};
        (void)sb_read_class_name(view, buffer, sizeof(buffer));
        if (strstr(buffer, "Dock") || strstr(buffer, "Library") || strstr(buffer, "Folder")) return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

static int pullover_attach_live_icons(uint64_t tray, double trayWidth, double trayHeight)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t icons[512] = {0};
    int discovered = 0;
    uint64_t listClass = r_class("SBIconListView"), lists[64] = {0};
    int listCount = r_is_objc_ptr(listClass)
        ? sb_collect_views_in_windows(listClass, lists, 64) : 0;
    for (int l = 0; l < listCount && discovered < 512; l++) {
        uint64_t pageIcons[256] = {0};
        int pageCount = sb_collect_icon_views_from_list(lists[l], pageIcons, 256);
        for (int i = 0; i < pageCount && discovered < 512; i++) {
            bool duplicate = false;
            for (int k = 0; k < discovered; k++)
                if (icons[k] == pageIcons[i]) { duplicate = true; break; }
            if (!duplicate) icons[discovered++] = pageIcons[i];
        }
    }
    if (discovered == 0 && r_is_objc_ptr(iconClass))
        discovered = sb_collect_views_in_windows(iconClass, icons, 512);
    double side = trayWidth - 24.0;
    if (side < 36.0) side = 36.0;
    if (side > 64.0) side = 64.0;
    double y = 76.0;

    for (int i = 0; i < discovered && gPullOverIconCount < 4; i++) {
        uint64_t icon = icons[i];
        if (!sb_view_is_visible_in_window(icon) || pullover_is_excluded_icon(icon)) continue;
        uint64_t parent = r_is_objc_ptr(icon) ? r_msg2_main(icon, "superview", 0, 0, 0, 0) : 0;
        PullOverRect frame = {0};
        if (!r_is_objc_ptr(parent) ||
            !r_msg2_main_struct_ret(icon, "frame", &frame, sizeof(frame),
                                    NULL, 0, NULL, 0, NULL, 0, NULL, 0) ||
            frame.width <= 20.0 || frame.height <= 20.0) continue;
        if (y + side > trayHeight - 20.0) break;

        int slot = gPullOverIconCount++;
        gPullOverIcons[slot] = icon;
        gPullOverIconParents[slot] = parent;
        r_msg2_main(parent, "retain", 0, 0, 0, 0);
        gPullOverIconFrames[slot] = frame;
        uint64_t siblings = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
        gPullOverIconIndices[slot] = r_is_objc_ptr(siblings)
            ? r_msg2_main(siblings, "indexOfObject:", icon, 0, 0, 0) : UINT64_MAX;
        r_msg2_main(tray, "addSubview:", icon, 0, 0, 0);
        PullOverRect trayFrame = { (trayWidth - side) * 0.5, y, side, side };
        r_msg2_main_raw(icon, "setFrame:", &trayFrame, sizeof(trayFrame),
                        NULL, 0, NULL, 0, NULL, 0);
        sb_cc_override_bool("pullover", icon, "isUserInteractionEnabled",
                            "setUserInteractionEnabled:", true);
        y += side + 14.0;
    }
    log_user("[PULLOVER][ICONS] discoveredLists=%d discoveredIcons=%d visibleAttached=%d capacity=4 tapsPreserved=1.\n",
             listCount, discovered, gPullOverIconCount);
    return gPullOverIconCount;
}

bool pullover_apply_in_session(void)
{
    printf("[PULLOVER] apply\n");
    if (r_is_objc_ptr(gPullOverView)) {
        pullover_restore_icons();
        r_msg2_main(gPullOverView, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(gPullOverView, "release", 0, 0, 0, 0);
        gPullOverView = 0;
    }
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    PullOverRect bounds = pullover_bounds_for_view(win);
    double trayHeight = bounds.height - 260.0;
    if (trayHeight < 260.0) trayHeight = 260.0;
    if (trayHeight > (double)gPullOverMaxHeight) trayHeight = (double)gPullOverMaxHeight;
    uint64_t tray = pullover_alloc_view(bounds.width - (double)gPullOverWidth - 8.0,
                                        (double)gPullOverYOffset,
                                        (double)gPullOverWidth,
                                        trayHeight);
    if (!r_is_objc_ptr(tray)) return false;
    uint64_t bg = pullover_color(0.05, 0.06, 0.07, (double)gPullOverBackgroundAlphaPercent / 100.0);
    if (r_is_objc_ptr(bg)) r_msg2_main(tray, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(tray, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = (double)gPullOverCornerRadius;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    pullover_add_grabber(tray, (double)gPullOverWidth);
    double iconSide = (double)gPullOverWidth - 24.0;
    if (iconSide < 32.0) iconSide = 32.0;
    if (iconSide > 64.0) iconSide = 64.0;
    r_msg2_main(win, "addSubview:", tray, 0, 0, 0);
    int attached = pullover_attach_live_icons(tray, (double)gPullOverWidth, trayHeight);
    if (attached == 0) {
        pullover_add_icon_slot(tray, ((double)gPullOverWidth - iconSide) / 2.0, 88.0, iconSide);
        pullover_add_icon_slot(tray, ((double)gPullOverWidth - iconSide) / 2.0, 156.0, iconSide);
        uint64_t label = pullover_alloc_label();
        if (r_is_objc_ptr(label)) {
            r_msg2_main(tray, "addSubview:", label, 0, 0, 0);
            r_msg2_main(label, "release", 0, 0, 0, 0);
        }
    }
    gPullOverView = tray;
    log_user("[PULLOVER][APPLY] frameX=%.1f y=%d width=%d height=%.1f radius=%d alpha=%d%% liveIcons=%d result=%s.\n",
             bounds.width - (double)gPullOverWidth - 8.0, gPullOverYOffset,
             gPullOverWidth, trayHeight, gPullOverCornerRadius,
             gPullOverBackgroundAlphaPercent, attached,
             attached > 0 ? "interactive launcher ready" : "tray ready; no eligible icons yet");
    return true;
}

bool pullover_stop_in_session(void)
{
    printf("[PULLOVER] stop\n");
    pullover_restore_icons();
    if (r_is_objc_ptr(gPullOverView)) {
        r_msg2_main(gPullOverView, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(gPullOverView, "release", 0, 0, 0, 0);
    }
    gPullOverView = 0;
    log_user("[PULLOVER][STOP] tray removed and all borrowed live icons restored.\n");
    return true;
}

void pullover_configure(int width, int yOffset, int maxHeight, int cornerRadius, int backgroundAlphaPercent)
{
    if (width < 52) width = 52; if (width > 140) width = 140;
    if (yOffset < 40) yOffset = 40; if (yOffset > 300) yOffset = 300;
    if (maxHeight < 220) maxHeight = 220; if (maxHeight > 720) maxHeight = 720;
    if (cornerRadius < 0) cornerRadius = 0; if (cornerRadius > 40) cornerRadius = 40;
    if (backgroundAlphaPercent < 20) backgroundAlphaPercent = 20; if (backgroundAlphaPercent > 100) backgroundAlphaPercent = 100;
    gPullOverWidth = width;
    gPullOverYOffset = yOffset;
    gPullOverMaxHeight = maxHeight;
    gPullOverCornerRadius = cornerRadius;
    gPullOverBackgroundAlphaPercent = backgroundAlphaPercent;
}

void pullover_forget_remote_state(void)
{
    gPullOverView = 0;
    memset(gPullOverIcons, 0, sizeof(gPullOverIcons));
    memset(gPullOverIconParents, 0, sizeof(gPullOverIconParents));
    memset(gPullOverIconFrames, 0, sizeof(gPullOverIconFrames));
    memset(gPullOverIconIndices, 0, sizeof(gPullOverIconIndices));
    gPullOverIconCount = 0;
    sb_cc_forget_owner("pullover");
}
