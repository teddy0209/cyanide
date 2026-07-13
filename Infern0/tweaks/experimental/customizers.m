#import "customizers.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

typedef struct { double x, y, width, height; } CUSRect;
typedef struct { double a, b, c, d, tx, ty; } CUSAffine;

static bool gHomeHideBadges = false;
static bool gHomeHideDots = false;
static bool gHomeHideFolderBackground = false;
static bool gHomeHideDockBackground = false;
static int gHomeIconAlpha = 100;

static int gFreeHorizontalStep = 8;
static int gFreeVerticalStep = 5;
static int gFreeStaggerPercent = 35;
static uint64_t gFreeIcons[512] = {0};
static CUSRect gFreeFrames[512] = {0};
static int gFreeIconCount = 0;

static int gLockClockScale = 100;
static int gLockXOffset = 0;
static int gLockYOffset = 0;
static bool gLockHideQuickActions = false;
static bool gLockHideDots = false;
static int gLockContentAlpha = 100;

static void cus_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    uint64_t name = r_is_objc_ptr(cls)
        ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!name) return;
    uint64_t copy = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    if (!copy) return;
    remote_read(copy, out, outLen - 1);
    out[outLen - 1] = '\0';
    r_free(copy);
}

static void cus_set_alpha(uint64_t view, double alpha)
{
    if (r_is_objc_ptr(view) && r_responds_main(view, "setAlpha:"))
        r_msg2_main_raw(view, "setAlpha:", &alpha, sizeof(alpha), NULL, 0, NULL, 0, NULL, 0);
}

static bool cus_get_rect(uint64_t view, const char *sel, CUSRect *out)
{
    if (!r_is_objc_ptr(view) || !out || !r_responds_main(view, sel)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(view, sel, out, sizeof(*out), NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static void cus_set_rect(uint64_t view, CUSRect frame)
{
    if (r_is_objc_ptr(view) && r_responds_main(view, "setFrame:"))
        r_msg2_main_raw(view, "setFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
}

static void cus_set_transform(uint64_t view, CUSAffine transform)
{
    if (r_is_objc_ptr(view) && r_responds_main(view, "setTransform:"))
        r_msg2_main_raw(view, "setTransform:", &transform, sizeof(transform), NULL, 0, NULL, 0, NULL, 0);
}

static bool cus_contains(const char *name, const char *needle)
{
    return name && needle && strstr(name, needle) != NULL;
}

static void homecustom_scan(uint64_t view, int depth, int *changed)
{
    if (!r_is_objc_ptr(view) || depth > 16) return;
    char cls[160] = {0};
    cus_class_name(view, cls, sizeof(cls));
    bool touched = false;

    if ((cus_contains(cls, "IconBadge") || cus_contains(cls, "SBIconBadge")) && !cus_contains(cls, "Label")) {
        cus_set_alpha(view, gHomeHideBadges ? 0.0 : 1.0); touched = true;
    } else if ((cus_contains(cls, "PageControl") || cus_contains(cls, "PageIndicator") || cus_contains(cls, "PageDot")) &&
               (cus_contains(cls, "SBIcon") || cus_contains(cls, "HomeScreen") || cus_contains(cls, "RootFolder"))) {
        cus_set_alpha(view, gHomeHideDots ? 0.0 : 1.0); touched = true;
    } else if (cus_contains(cls, "FolderIconBackground") || cus_contains(cls, "FolderBackground")) {
        cus_set_alpha(view, gHomeHideFolderBackground ? 0.0 : 1.0); touched = true;
    } else if (cus_contains(cls, "DockBackground") || cus_contains(cls, "DockPlatter") ||
               cus_contains(cls, "DockMaterial") || cus_contains(cls, "DockEffect")) {
        cus_set_alpha(view, gHomeHideDockBackground ? 0.0 : 1.0); touched = true;
    } else if (cus_contains(cls, "SBIconView")) {
        cus_set_alpha(view, (double)gHomeIconAlpha / 100.0);
        r_msg2_main(view, "setUserInteractionEnabled:", 1, 0, 0, 0);
        touched = true;
    }
    if (touched && changed) (*changed)++;

    uint64_t subs = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subs) ? r_msg2_main(subs, "count", 0, 0, 0, 0) : 0;
    if (count > 256) count = 256;
    for (uint64_t i = 0; i < count; i++)
        homecustom_scan(r_msg2_main(subs, "objectAtIndex:", i, 0, 0, 0), depth + 1, changed);
}

void homecustom_configure(bool hideBadges, bool hidePageDots, bool hideFolderBackground,
                          bool hideDockBackground, int iconAlphaPercent)
{
    if (iconAlphaPercent < 20) iconAlphaPercent = 20;
    if (iconAlphaPercent > 100) iconAlphaPercent = 100;
    gHomeHideBadges = hideBadges;
    gHomeHideDots = hidePageDots;
    gHomeHideFolderBackground = hideFolderBackground;
    gHomeHideDockBackground = hideDockBackground;
    gHomeIconAlpha = iconAlphaPercent;
}

bool homecustom_apply_in_session(void)
{
    uint64_t windows[64] = {0};
    int windowCount = sb_collect_windows(windows, 64), changed = 0;
    for (int i = 0; i < windowCount; i++) homecustom_scan(windows[i], 0, &changed);
    printf("[HOMECUSTOM] badges=%d dots=%d folders=%d dock=%d iconAlpha=%d changed=%d windows=%d\n",
           gHomeHideBadges, gHomeHideDots, gHomeHideFolderBackground,
           gHomeHideDockBackground, gHomeIconAlpha, changed, windowCount);
    return changed > 0;
}

bool homecustom_stop_in_session(void)
{
    bool oldBadges = gHomeHideBadges, oldDots = gHomeHideDots;
    bool oldFolders = gHomeHideFolderBackground, oldDock = gHomeHideDockBackground;
    int oldAlpha = gHomeIconAlpha;
    homecustom_configure(false, false, false, false, 100);
    bool ok = homecustom_apply_in_session();
    homecustom_configure(oldBadges, oldDots, oldFolders, oldDock, oldAlpha);
    printf("[HOMECUSTOM] restored stock visibility\n");
    return ok;
}

void homecustom_forget_remote_state(void) {}

static int free_saved_index(uint64_t icon)
{
    for (int i = 0; i < gFreeIconCount; i++) if (gFreeIcons[i] == icon) return i;
    return -1;
}

void freeplacement_configure(int horizontalStep, int verticalStep, int staggerPercent)
{
    if (horizontalStep < -40) horizontalStep = -40;
    if (horizontalStep > 40) horizontalStep = 40;
    if (verticalStep < -40) verticalStep = -40;
    if (verticalStep > 40) verticalStep = 40;
    if (staggerPercent < 0) staggerPercent = 0;
    if (staggerPercent > 100) staggerPercent = 100;
    gFreeHorizontalStep = horizontalStep;
    gFreeVerticalStep = verticalStep;
    gFreeStaggerPercent = staggerPercent;
}

bool freeplacement_apply_in_session(void)
{
    uint64_t cls = r_class("SBIconView"), icons[512] = {0};
    int count = r_is_objc_ptr(cls) ? sb_collect_views_in_windows(cls, icons, 512) : 0;
    int moved = 0;
    for (int i = 0; i < count; i++) {
        uint64_t icon = icons[i];
        CUSRect frame;
        if (!cus_get_rect(icon, "frame", &frame) || frame.width <= 0 || frame.height <= 0) continue;
        int saved = free_saved_index(icon);
        if (saved < 0 && gFreeIconCount < 512) {
            saved = gFreeIconCount;
            gFreeIcons[gFreeIconCount] = icon;
            gFreeFrames[gFreeIconCount++] = frame;
        }
        if (saved >= 0) frame = gFreeFrames[saved];
        int columnPhase = (i % 5) - 2;
        int rowPhase = ((i / 5) % 5) - 2;
        double stagger = (i & 1) ? (double)gFreeStaggerPercent / 100.0 : 0.0;
        frame.x += (double)columnPhase * gFreeHorizontalStep + stagger * gFreeHorizontalStep;
        frame.y += (double)rowPhase * gFreeVerticalStep;
        cus_set_rect(icon, frame);
        r_msg2_main(icon, "setUserInteractionEnabled:", 1, 0, 0, 0);
        moved++;
    }
    printf("[FREEPLACEMENT] horizontalStep=%d verticalStep=%d stagger=%d%% moved=%d saved=%d taps=preserved\n",
           gFreeHorizontalStep, gFreeVerticalStep, gFreeStaggerPercent, moved, gFreeIconCount);
    return moved > 0;
}

bool freeplacement_stop_in_session(void)
{
    int restored = 0;
    for (int i = 0; i < gFreeIconCount; i++) {
        if (!r_is_objc_ptr(gFreeIcons[i])) continue;
        cus_set_rect(gFreeIcons[i], gFreeFrames[i]);
        restored++;
    }
    memset(gFreeIcons, 0, sizeof(gFreeIcons));
    memset(gFreeFrames, 0, sizeof(gFreeFrames));
    gFreeIconCount = 0;
    printf("[FREEPLACEMENT] restored=%d\n", restored);
    return true;
}

void freeplacement_forget_remote_state(void)
{
    memset(gFreeIcons, 0, sizeof(gFreeIcons));
    memset(gFreeFrames, 0, sizeof(gFreeFrames));
    gFreeIconCount = 0;
}

static void lockcustomizer_scan(uint64_t view, int depth, bool lockContext, bool restore, int *changed)
{
    if (!r_is_objc_ptr(view) || depth > 18) return;
    char cls[160] = {0};
    cus_class_name(view, cls, sizeof(cls));
    bool isLock = cus_contains(cls, "LockScreen") || cus_contains(cls, "CoverSheet") ||
                  cus_contains(cls, "CSPageControl") || cus_contains(cls, "CSCoverSheet") ||
                  cus_contains(cls, "CSMainPage") || cus_contains(cls, "SBDashBoard");
    lockContext = lockContext || isLock;
    bool isClock = cus_contains(cls, "DateView") || cus_contains(cls, "ClockView") || cus_contains(cls, "TimeView");
    bool isQuick = cus_contains(cls, "QuickAction") || cus_contains(cls, "CameraGrabber") || cus_contains(cls, "Flashlight");
    bool isDots = cus_contains(cls, "PageControl") || cus_contains(cls, "PageIndicator");
    if (isClock && lockContext) {
        double scale = restore ? 1.0 : (double)gLockClockScale / 100.0;
        CUSAffine t = {scale, 0, 0, scale, restore ? 0.0 : gLockXOffset, restore ? 0.0 : gLockYOffset};
        cus_set_transform(view, t);
        cus_set_alpha(view, restore ? 1.0 : (double)gLockContentAlpha / 100.0);
        if (changed) (*changed)++;
    } else if (isQuick && lockContext) {
        cus_set_alpha(view, (!restore && gLockHideQuickActions) ? 0.0 : 1.0);
        if (changed) (*changed)++;
    } else if (isDots && lockContext) {
        cus_set_alpha(view, (!restore && gLockHideDots) ? 0.0 : 1.0);
        if (changed) (*changed)++;
    }
    uint64_t subs = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subs) ? r_msg2_main(subs, "count", 0, 0, 0, 0) : 0;
    if (count > 256) count = 256;
    for (uint64_t i = 0; i < count; i++)
        lockcustomizer_scan(r_msg2_main(subs, "objectAtIndex:", i, 0, 0, 0), depth + 1, lockContext, restore, changed);
}

void lockcustomizer_configure(int clockScalePercent, int horizontalOffset, int verticalOffset,
                              bool hideQuickActions, bool hidePageDots, int contentAlphaPercent)
{
    if (clockScalePercent < 50) clockScalePercent = 50;
    if (clockScalePercent > 180) clockScalePercent = 180;
    if (horizontalOffset < -160) horizontalOffset = -160;
    if (horizontalOffset > 160) horizontalOffset = 160;
    if (verticalOffset < -300) verticalOffset = -300;
    if (verticalOffset > 300) verticalOffset = 300;
    if (contentAlphaPercent < 20) contentAlphaPercent = 20;
    if (contentAlphaPercent > 100) contentAlphaPercent = 100;
    gLockClockScale = clockScalePercent;
    gLockXOffset = horizontalOffset;
    gLockYOffset = verticalOffset;
    gLockHideQuickActions = hideQuickActions;
    gLockHideDots = hidePageDots;
    gLockContentAlpha = contentAlphaPercent;
}

static bool lockcustomizer_run(bool restore)
{
    uint64_t windows[64] = {0};
    int windowCount = sb_collect_windows(windows, 64), changed = 0;
    for (int i = 0; i < windowCount; i++) lockcustomizer_scan(windows[i], 0, false, restore, &changed);
    printf("[LOCKCUSTOM] restore=%d scale=%d%% x=%d y=%d quick=%d dots=%d alpha=%d%% changed=%d\n",
           restore, gLockClockScale, gLockXOffset, gLockYOffset,
           gLockHideQuickActions, gLockHideDots, gLockContentAlpha, changed);
    return changed > 0;
}

bool lockcustomizer_apply_in_session(void) { return lockcustomizer_run(false); }
bool lockcustomizer_stop_in_session(void) { lockcustomizer_run(true); return true; }
void lockcustomizer_forget_remote_state(void) {}
