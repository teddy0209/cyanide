#import "ccstatus.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>

typedef struct { double x; double y; double width; double height; } CCStatusRect;

static uint64_t gCCStatusLabel = 0;
static bool gCCStatusShowWifi = true;
static bool gCCStatusShowIP = true;
static int gCCStatusYOffset = 70;

static uint64_t ccstatus_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red), &green, sizeof(green),
                           &blue, sizeof(blue), &alpha, sizeof(alpha));
}

static uint64_t ccstatus_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

bool ccstatus_apply_in_session(void)
{
    printf("[CCSTATUS] apply\n");
    uint64_t win = sb_control_center_window();
    if (!r_is_objc_ptr(win)) return false;
    uint64_t currentParent = r_is_objc_ptr(gCCStatusLabel)
        ? r_msg2_main(gCCStatusLabel, "superview", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(gCCStatusLabel) && currentParent != win) {
        r_msg2_main(gCCStatusLabel, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(gCCStatusLabel, "release", 0, 0, 0, 0);
        gCCStatusLabel = 0;
    }
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(UILabel)) return false;
    bool created = !r_is_objc_ptr(gCCStatusLabel);
    uint64_t label = created ? r_msg2_main(UILabel, "alloc", 0, 0, 0, 0) : gCCStatusLabel;
    CCStatusRect frame = { 18, (double)gCCStatusYOffset, 330, 30 };
    if (created)
        label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    else
        r_msg2_main_raw(label, "setFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return false;
    const char *text = "CCStatus";
    if (gCCStatusShowWifi && gCCStatusShowIP) text = "Wi-Fi  |  IP";
    else if (gCCStatusShowWifi) text = "Wi-Fi";
    else if (gCCStatusShowIP) text = "IP";
    uint64_t str = r_nsstr_retained(text);
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    uint64_t white = ccstatus_color(1, 1, 1, 0.94);
    if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
    uint64_t bg = ccstatus_color(0, 0, 0, 0.22);
    if (r_is_objc_ptr(bg)) r_msg2_main(label, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double size = 12.0;
        double weight = 0.45;
        uint64_t font = r_msg2_main_raw(UIFont, "systemFontOfSize:weight:",
                                        &size, sizeof(size), &weight, sizeof(weight),
                                        NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    uint64_t layer = r_msg2_main(label, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 15.0;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    if (created) r_msg2_main(win, "addSubview:", label, 0, 0, 0);
    else r_msg2_main(win, "bringSubviewToFront:", label, 0, 0, 0);
    gCCStatusLabel = label;
    log_user("[CCSTATUS][APPLY] wifiLabel=%d ipLabel=%d y=%d overlay=%s liveNetworkLookup=0.\n",
             gCCStatusShowWifi, gCCStatusShowIP, gCCStatusYOffset,
             created ? "created" : "reused");
    return true;
}

bool ccstatus_stop_in_session(void)
{
    printf("[CCSTATUS] stop\n");
    bool removed = r_is_objc_ptr(gCCStatusLabel);
    if (removed) {
        r_msg2_main(gCCStatusLabel, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(gCCStatusLabel, "release", 0, 0, 0, 0);
    }
    gCCStatusLabel = 0;
    log_user("[CCSTATUS][STOP] overlayRemoved=%d.\n", removed);
    return true;
}

void ccstatus_configure(bool showWifi, bool showIP, int yOffset)
{
    if (yOffset < 20) yOffset = 20;
    if (yOffset > 180) yOffset = 180;
    gCCStatusShowWifi = showWifi;
    gCCStatusShowIP = showIP;
    gCCStatusYOffset = yOffset;
}

void ccstatus_forget_remote_state(void) { gCCStatusLabel = 0; }
