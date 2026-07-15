#import "alkaline.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static uint64_t gAlkalineTint = 0;
static int gAlkalineRed = 43;
static int gAlkalineGreen = 219;
static int gAlkalineBlue = 115;
static int gAlkalineAlphaPercent = 100;

static uint64_t alkaline_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red),
                           &green, sizeof(green),
                           &blue, sizeof(blue),
                           &alpha, sizeof(alpha));
}

static void alkaline_tint_view(uint64_t view, uint64_t color, int *hits)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(color)) return;
    bool changed = sb_cc_override_object("alkaline", view, "tintColor", "setTintColor:", color);
    if (r_responds_main(view, "setTextColor:"))
        changed = sb_cc_override_object("alkaline", view, "textColor", "setTextColor:", color) || changed;
    if (r_responds_main(view, "setBackgroundColor:"))
        changed = sb_cc_override_object("alkaline", view, "backgroundColor", "setBackgroundColor:", color) || changed;
    if (changed && hits) (*hits)++;
}

bool alkaline_apply_in_session(void)
{
    printf("[ALKALINE] apply\n");
    gAlkalineTint = alkaline_color((double)gAlkalineRed / 255.0,
                                   (double)gAlkalineGreen / 255.0,
                                   (double)gAlkalineBlue / 255.0,
                                   (double)gAlkalineAlphaPercent / 100.0);
    int hits = 0;
    const char *batteryClasses[] = {
        "_UIBatteryView", "UIStatusBarBatteryItemView",
        "_UIStatusBarBatteryItemView", "BCUIBatteryView", NULL
    };
    for (int c = 0; batteryClasses[c] && hits < 64; c++) {
        uint64_t cls = r_class(batteryClasses[c]);
        if (!r_is_objc_ptr(cls)) continue;
        uint64_t views[64] = {0};
        int count = sb_collect_views_in_windows(cls, views, 64);
        for (int i = 0; i < count && hits < 64; i++)
            alkaline_tint_view(views[i], gAlkalineTint, &hits);
    }
    printf("[ALKALINE] tinted %d battery-ish views\n", hits);
    return hits > 0;
}

bool alkaline_stop_in_session(void)
{
    printf("[ALKALINE] stop\n");
    int hits = sb_cc_restore_owner("alkaline");
    gAlkalineTint = 0;
    return hits > 0;
}

void alkaline_configure(int red, int green, int blue, int alphaPercent)
{
    if (red < 0) red = 0; if (red > 255) red = 255;
    if (green < 0) green = 0; if (green > 255) green = 255;
    if (blue < 0) blue = 0; if (blue > 255) blue = 255;
    if (alphaPercent < 10) alphaPercent = 10; if (alphaPercent > 100) alphaPercent = 100;
    gAlkalineRed = red;
    gAlkalineGreen = green;
    gAlkalineBlue = blue;
    gAlkalineAlphaPercent = alphaPercent;
}

void alkaline_forget_remote_state(void) { gAlkalineTint = 0; sb_cc_forget_owner("alkaline"); }
