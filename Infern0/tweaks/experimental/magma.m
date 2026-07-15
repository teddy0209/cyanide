#import "magma.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <string.h>
#import <sys/time.h>

static uint64_t gMagmaTint = 0;
static int gMagmaRed = 255;
static int gMagmaGreen = 71;
static int gMagmaBlue = 20;
static int gMagmaAlpha = 100;
static bool gMagmaColorToggles = true;
static bool gMagmaColorSliders = true;
static bool gMagmaColorMedia = true;
static bool gMagmaColorBackground = false;
static bool gMagmaConfigDirty = false;
static uint64_t gMagmaCandidateWindow = 0;
static uint64_t gMagmaCandidateSinceUS = 0;
static uint64_t gMagmaAppliedWindow = 0;
static bool gMagmaLastApplySucceeded = false;

static uint64_t magma_now_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;
}

static uint64_t magma_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red), &green, sizeof(green),
                           &blue, sizeof(blue), &alpha, sizeof(alpha));
}

static bool magma_window_is_visible(uint64_t target)
{
    if (!r_is_objc_ptr(target)) return false;
    uint64_t windows[64] = {0};
    int count = sb_collect_windows(windows, 64);
    for (int i = 0; i < count; i++) {
        if (windows[i] != target) continue;
        if (r_responds_main(target, "isHidden") &&
            (r_msg2_main(target, "isHidden", 0, 0, 0, 0) & 0xff)) return false;
        double alpha = 1.0;
        if (r_responds_main(target, "alpha") &&
            !r_msg2_main_struct_ret(target, "alpha", &alpha, sizeof(alpha),
                                    NULL, 0, NULL, 0, NULL, 0, NULL, 0))
            return false;
        return alpha > 0.01;
    }
    return false;
}

static void magma_class_name(uint64_t obj, char *out, size_t outLen)
{
    (void)sb_read_class_name(obj, out, outLen);
}

static void magma_scan(uint64_t parent, uint64_t color, bool ccContext, int depth,
                       int *visited, int *hits)
{
    // One malformed or unusually deep module must not turn Apply into an
    // unbounded RemoteCall storm. The caps cover a normal CC presentation.
    if (!r_is_objc_ptr(parent) || depth > 10 || !visited || *visited >= 320 ||
        (hits && *hits >= 48)) return;
    (*visited)++;
    char cls[160] = {0};
    magma_class_name(parent, cls, sizeof(cls));
    ccContext = ccContext || strstr(cls, "CCUI") || strstr(cls, "ControlCenter");
    bool explicitlyCC = strstr(cls, "CCUI") || strstr(cls, "ControlCenter");
    bool isToggle = explicitlyCC && (strstr(cls, "Toggle") || strstr(cls, "Button") ||
                                      strstr(cls, "Glyph") || strstr(cls, "Connectivity"));
    bool isSlider = explicitlyCC && (strstr(cls, "Slider") || strstr(cls, "ContinuousSlider"));
    bool isMedia = explicitlyCC && (strstr(cls, "Media") || strstr(cls, "NowPlaying") || strstr(cls, "MRU"));
    // Generic Container/Background views often own the presentation mask and
    // dismissal transition. Restrict optional background coloring to platters
    // and material views that are actually rendered content.
    bool isBackground = explicitlyCC && (strstr(cls, "Platter") || strstr(cls, "Material"));
    bool target = ccContext && ((gMagmaColorToggles && isToggle) || (gMagmaColorSliders && isSlider) ||
                  (gMagmaColorMedia && isMedia));
    if (target && r_is_objc_ptr(color)) {
        bool changed = sb_cc_override_object("magma", parent, "tintColor", "setTintColor:", color);
        if (r_responds_main(parent, "setTextColor:"))
            changed = sb_cc_override_object("magma", parent, "textColor", "setTextColor:", color) || changed;
        if (changed && hits) (*hits)++;
    }
    if (ccContext && gMagmaColorBackground && isBackground && r_is_objc_ptr(color) && r_responds_main(parent, "setBackgroundColor:")) {
        if (sb_cc_override_object("magma", parent, "backgroundColor", "setBackgroundColor:", color) && hits)
            (*hits)++;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 80) count = 80;
    for (uint64_t i = 0; i < count; i++)
        magma_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), color,
                   ccContext, depth + 1, visited, hits);
}

bool magma_apply_in_session(void)
{
    printf("[MAGMA] apply\n");
    if (gMagmaConfigDirty) {
        int restored = sb_cc_restore_owner("magma");
        log_user("[MAGMA][RECONFIGURE] removedPriorProperties=%d before applying the new target groups.\n",
                 restored);
        gMagmaConfigDirty = false;
        gMagmaAppliedWindow = 0;
        gMagmaLastApplySucceeded = false;
    }
    // Checking membership in UIApplication.windows is much cheaper and safer
    // than rediscovering the CC hierarchy on every refresh tick.
    if (gMagmaAppliedWindow && magma_window_is_visible(gMagmaAppliedWindow))
        return gMagmaLastApplySucceeded;
    if (gMagmaAppliedWindow) {
        log_user("[MAGMA][PRESENTATION-END] window=0x%llx result=awaiting-next-open.\n",
                 gMagmaAppliedWindow);
        gMagmaAppliedWindow = 0;
        gMagmaLastApplySucceeded = false;
        gMagmaCandidateWindow = 0;
        gMagmaCandidateSinceUS = 0;
    }

    uint64_t window = sb_control_center_window();
    uint64_t nowUS = magma_now_us();
    if (!r_is_objc_ptr(window)) {
        gMagmaCandidateWindow = 0;
        gMagmaCandidateSinceUS = 0;
        return false;
    }
    if (window != gMagmaCandidateWindow) {
        gMagmaCandidateWindow = window;
        gMagmaCandidateSinceUS = nowUS;
        log_user("[MAGMA][DEBOUNCE] visibleWindow=0x%llx result=waiting-for-stable-presentation.\n",
                 window);
        return false;
    }
    if (nowUS - gMagmaCandidateSinceUS < 350000ULL) return false;

    gMagmaTint = magma_color((double)gMagmaRed / 255.0,
                             (double)gMagmaGreen / 255.0,
                             (double)gMagmaBlue / 255.0,
                             (double)gMagmaAlpha / 100.0);
    int visited = 0, hits = 0;
    magma_scan(window, gMagmaTint, false, 0, &visited, &hits);
    printf("[MAGMA EVO] toggles=%d sliders=%d media=%d background=%d visited=%d hits=%d window=0x%llx stableMs=%llu\n",
           gMagmaColorToggles, gMagmaColorSliders, gMagmaColorMedia,
           gMagmaColorBackground, visited, hits, window,
           (unsigned long long)((nowUS - gMagmaCandidateSinceUS) / 1000ULL));
    gMagmaAppliedWindow = window;
    gMagmaLastApplySucceeded = hits > 0;
    if (!gMagmaLastApplySucceeded)
        log_user("[MAGMA][NO-SAFE-TARGETS] window=0x%llx visited=%d result=skipped-until-next-presentation.\n",
                 window, visited);
    return gMagmaLastApplySucceeded;
}

bool magma_stop_in_session(void)
{
    printf("[MAGMA] stop\n");
    int hits = sb_cc_restore_owner("magma");
    gMagmaTint = 0;
    gMagmaCandidateWindow = 0;
    gMagmaCandidateSinceUS = 0;
    gMagmaAppliedWindow = 0;
    gMagmaLastApplySucceeded = false;
    log_user("[MAGMA][RESTORE] exactProperties=%d result=%s.\n", hits, hits > 0 ? "restored" : "nothing-owned");
    return hits > 0;
}

void magma_configure(int red, int green, int blue, int alpha,
                     bool colorToggles, bool colorSliders, bool colorMedia, bool colorBackground)
{
    if (red < 0) red = 0; if (red > 255) red = 255;
    if (green < 0) green = 0; if (green > 255) green = 255;
    if (blue < 0) blue = 0; if (blue > 255) blue = 255;
    if (alpha < 5) alpha = 5; if (alpha > 100) alpha = 100;
    if (gMagmaRed != red || gMagmaGreen != green || gMagmaBlue != blue ||
        gMagmaAlpha != alpha || gMagmaColorToggles != colorToggles ||
        gMagmaColorSliders != colorSliders || gMagmaColorMedia != colorMedia ||
        gMagmaColorBackground != colorBackground) {
        gMagmaConfigDirty = true;
    }
    gMagmaRed = red;
    gMagmaGreen = green;
    gMagmaBlue = blue;
    gMagmaAlpha = alpha;
    gMagmaColorToggles = colorToggles;
    gMagmaColorSliders = colorSliders;
    gMagmaColorMedia = colorMedia;
    gMagmaColorBackground = colorBackground;
}

void magma_forget_remote_state(void) { gMagmaTint = 0; gMagmaConfigDirty = false; gMagmaCandidateWindow = 0; gMagmaCandidateSinceUS = 0; gMagmaAppliedWindow = 0; gMagmaLastApplySucceeded = false; sb_cc_forget_owner("magma"); }
