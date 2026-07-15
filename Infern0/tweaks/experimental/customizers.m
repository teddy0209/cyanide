#import "customizers.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../darksword_tweaks.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

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
static bool gHomeHasAppliedConfig = false;
static bool gHomeAppliedHideBadges = false, gHomeAppliedHideDots = false;
static bool gHomeAppliedHideFolderBackground = false, gHomeAppliedHideDockBackground = false;
static int gHomeAppliedIconAlpha = 100;

static int gFreeHorizontalStep = 8;
static int gFreeVerticalStep = 5;
static int gFreeStaggerPercent = 35;
static uint64_t gFreeIcons[512] = {0};
static CUSRect gFreeFrames[512] = {0};
static int gFreeIconCount = 0;

static int gAppLibraryScale = 92;
static int gAppLibraryHorizontalSpacing = 0;
static int gAppLibraryVerticalSpacing = 0;
static bool gAppLibraryHideLabels = false;
static bool gAppLibraryDisableTodayView = true;
static uint64_t gAppLibraryIcons[512] = {0};
static CUSRect gAppLibraryFrames[512] = {0};
static int gAppLibraryIconCount = 0;
static uint64_t gAppLibraryLabels[512] = {0};
static int gAppLibraryLabelCount = 0;
static bool gAppLibraryTodayRemoved = false;

static int gLockClockScale = 100;
static int gLockXOffset = 0;
static int gLockYOffset = 0;
static bool gLockHideQuickActions = false;
static bool gLockHideDots = false;
static int gLockContentAlpha = 100;
static int gLockMediaScale = 92;
static bool gLockHideMediaArtwork = false;
static bool gMetalLockLightEnabled = false;
static int gMetalLockLightIntensity = 72;
static int gMetalLockLightThickness = 5;
static int gMetalLockLightStyle = 0;
static uint64_t gMetalLockLightOverlay = 0;
static bool gLockConfigDirty = false;

static void cus_class_name(uint64_t obj, char *out, size_t outLen)
{
    (void)sb_read_class_name(obj, out, outLen);
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

static bool cus_is_inside_app_library(uint64_t view)
{
    for (int depth = 0; r_is_objc_ptr(view) && depth < 12; depth++) {
        char cls[160] = {0};
        cus_class_name(view, cls, sizeof(cls));
        if (cus_contains(cls, "SBHLibrary") || cus_contains(cls, "AppLibrary") ||
            cus_contains(cls, "LibraryPod") || cus_contains(cls, "LibraryCategory")) return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

static bool cus_is_inside_dock(uint64_t view)
{
    for (int depth = 0; r_is_objc_ptr(view) && depth < 12; depth++) {
        char cls[160] = {0};
        cus_class_name(view, cls, sizeof(cls));
        if (cus_contains(cls, "Dock") && !cus_contains(cls, "Document")) return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

static void homecustom_scan(uint64_t view, int depth, int *visited, int *changed)
{
    if (!r_is_objc_ptr(view) || depth > 12 || !visited || *visited >= 768 ||
        (changed && *changed >= 256)) return;
    (*visited)++;
    char cls[160] = {0};
    cus_class_name(view, cls, sizeof(cls));
    bool touched = false;

    if ((cus_contains(cls, "IconBadge") || cus_contains(cls, "SBIconBadge")) && !cus_contains(cls, "Label")) {
        if (gHomeHideBadges) { double alpha = 0.0; touched = sb_cc_override_bytes("homecustom", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)); }
    } else if ((cus_contains(cls, "PageControl") || cus_contains(cls, "PageIndicator") || cus_contains(cls, "PageDot")) &&
               (cus_contains(cls, "SBIcon") || cus_contains(cls, "HomeScreen") || cus_contains(cls, "RootFolder"))) {
        if (gHomeHideDots) { double alpha = 0.0; touched = sb_cc_override_bytes("homecustom", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)); }
    } else if (cus_contains(cls, "FolderIconBackground") || cus_contains(cls, "FolderBackground")) {
        if (gHomeHideFolderBackground) { double alpha = 0.0; touched = sb_cc_override_bytes("homecustom", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)); }
    } else if (cus_contains(cls, "DockBackground") || cus_contains(cls, "DockPlatter") ||
               cus_contains(cls, "DockMaterial") || cus_contains(cls, "DockEffect")) {
        if (gHomeHideDockBackground) { double alpha = 0.0; touched = sb_cc_override_bytes("homecustom", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)); }
    } else if (cus_contains(cls, "SBIconView")) {
        if (gHomeIconAlpha != 100) {
            double alpha = (double)gHomeIconAlpha / 100.0;
            touched = sb_cc_override_bytes("homecustom", view, "alpha", "setAlpha:", &alpha, sizeof(alpha));
            r_msg2_main(view, "setUserInteractionEnabled:", 1, 0, 0, 0);
        }
    }
    if (touched && changed) (*changed)++;

    uint64_t subs = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subs) ? r_msg2_main(subs, "count", 0, 0, 0, 0) : 0;
    if (count > 256) count = 256;
    for (uint64_t i = 0; i < count; i++)
        homecustom_scan(r_msg2_main(subs, "objectAtIndex:", i, 0, 0, 0), depth + 1, visited, changed);
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
    log_user("[HOMECUSTOM][CONFIG] hideBadges=%d hidePageDots=%d hideFolderBackground=%d hideDockBackground=%d iconAlpha=%d%%.\n",
             gHomeHideBadges, gHomeHideDots, gHomeHideFolderBackground,
             gHomeHideDockBackground, gHomeIconAlpha);
}

bool homecustom_apply_in_session(void)
{
    bool configChanged = gHomeHasAppliedConfig &&
        (gHomeAppliedHideBadges != gHomeHideBadges || gHomeAppliedHideDots != gHomeHideDots ||
         gHomeAppliedHideFolderBackground != gHomeHideFolderBackground ||
         gHomeAppliedHideDockBackground != gHomeHideDockBackground ||
         gHomeAppliedIconAlpha != gHomeIconAlpha);
    if (configChanged) sb_cc_restore_owner("homecustom");
    uint64_t windows[64] = {0};
    int windowCount = sb_collect_windows(windows, 64), visited = 0, changed = 0;
    for (int i = 0; i < windowCount; i++) homecustom_scan(windows[i], 0, &visited, &changed);
    gHomeHasAppliedConfig = true;
    gHomeAppliedHideBadges = gHomeHideBadges;
    gHomeAppliedHideDots = gHomeHideDots;
    gHomeAppliedHideFolderBackground = gHomeHideFolderBackground;
    gHomeAppliedHideDockBackground = gHomeHideDockBackground;
    gHomeAppliedIconAlpha = gHomeIconAlpha;
    printf("[HOMECUSTOM] badges=%d dots=%d folders=%d dock=%d iconAlpha=%d visited=%d changed=%d windows=%d\n",
           gHomeHideBadges, gHomeHideDots, gHomeHideFolderBackground,
           gHomeHideDockBackground, gHomeIconAlpha, visited, changed, windowCount);
    log_user("[HOMECUSTOM][APPLY] windows=%d matchedViews=%d hideBadges=%d hideDots=%d hideFolders=%d hideDock=%d iconAlpha=%d%% result=%s.\n",
             windowCount, changed, gHomeHideBadges, gHomeHideDots,
             gHomeHideFolderBackground, gHomeHideDockBackground, gHomeIconAlpha,
             changed > 0 ? "active" : "no supported views found");
    return changed > 0;
}

bool homecustom_stop_in_session(void)
{
    int restored = sb_cc_restore_owner("homecustom");
    gHomeHasAppliedConfig = false;
    printf("[HOMECUSTOM] exactPropertiesRestored=%d\n", restored);
    log_user("[HOMECUSTOM][RESTORE] exactProperties=%d result=%s.\n",
             restored, restored > 0 ? "restored" : "nothing-owned");
    return restored > 0;
}

void homecustom_forget_remote_state(void) { gHomeHasAppliedConfig = false; sb_cc_forget_owner("homecustom"); }

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
    log_user("[FREEPLACEMENT][CONFIG] horizontalStep=%dpt verticalStep=%dpt alternateStagger=%d%%.\n",
             gFreeHorizontalStep, gFreeVerticalStep, gFreeStaggerPercent);
}

bool freeplacement_apply_in_session(void)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(iconClass) || !r_is_objc_ptr(listClass)) return false;

    uint64_t lists[64] = {0};
    int listCount = sb_collect_views_in_windows(listClass, lists, 64);
    int discovered = 0, moved = 0, pageCount = 0, skipped = 0, clamped = 0;
    for (int page = 0; page < listCount; page++) {
        if (cus_is_inside_app_library(lists[page]) || cus_is_inside_dock(lists[page])) {
            skipped++;
            continue;
        }
        uint64_t icons[256] = {0};
        CUSRect pageBounds = {0};
        cus_get_rect(lists[page], "bounds", &pageBounds);
        int pageIconCount = sb_collect_icon_views_from_list(lists[page], icons, 256);
        int pageMoved = 0;
        discovered += pageIconCount;
        for (int ordinal = 0; ordinal < pageIconCount; ordinal++) {
            uint64_t icon = icons[ordinal];
            // The owning list was classified above. Re-walking every icon's
            // ancestor class chain caused hundreds of redundant remote reads.
            CUSRect frame;
            if (!cus_get_rect(icon, "frame", &frame) || frame.width <= 0 || frame.height <= 0) continue;
            int saved = free_saved_index(icon);
            if (saved < 0 && gFreeIconCount < 512) {
                saved = gFreeIconCount;
                gFreeIcons[gFreeIconCount] = icon;
                gFreeFrames[gFreeIconCount++] = frame;
                // Page icon views are lazy and can be torn down while the
                // user scrolls. Keep every cached frame target alive until
                // restore so a later refresh never messages a stale pointer.
                r_msg2_main(icon, "retain", 0, 0, 0, 0);
            }
            if (saved >= 0) frame = gFreeFrames[saved];
            int columnPhase = (ordinal % 5) - 2;
            int rowPhase = ((ordinal / 5) % 5) - 2;
            double stagger = (ordinal & 1) ? (double)gFreeStaggerPercent / 100.0 : 0.0;
            frame.x += (double)columnPhase * gFreeHorizontalStep + stagger * gFreeHorizontalStep;
            frame.y += (double)rowPhase * gFreeVerticalStep;
            if (pageBounds.width > 0 && pageBounds.height > 0) {
                double minX = pageBounds.x + 2.0, minY = pageBounds.y + 2.0;
                double maxX = pageBounds.x + pageBounds.width - frame.width - 2.0;
                double maxY = pageBounds.y + pageBounds.height - frame.height - 2.0;
                double oldX = frame.x, oldY = frame.y;
                if (maxX >= minX) frame.x = fmax(minX, fmin(maxX, frame.x));
                if (maxY >= minY) frame.y = fmax(minY, fmin(maxY, frame.y));
                if (frame.x != oldX || frame.y != oldY) clamped++;
            }
            cus_set_rect(icon, frame);
            r_msg2_main(icon, "setUserInteractionEnabled:", 1, 0, 0, 0);
            moved++;
            pageMoved++;
        }
        if (pageMoved > 0) {
            pageCount++;
            log_user("[FREEPLACEMENT][PAGE %d] list=0x%llx discoveredIcons=%d movedIcons=%d ordering=page-local tapsPreserved=1.\n",
                     pageCount, lists[page], pageIconCount, pageMoved);
        }
    }
    printf("[FREEPLACEMENT] horizontalStep=%d verticalStep=%d stagger=%d%% pages=%d moved=%d saved=%d taps=preserved\n",
           gFreeHorizontalStep, gFreeVerticalStep, gFreeStaggerPercent,
           pageCount, moved, gFreeIconCount);
    log_user("[FREEPLACEMENT][APPLY] discoveredLists=%d activePages=%d skippedDockLibraryLists=%d discoveredIcons=%d moved=%d clampedOnScreen=%d savedStockFrames=%d horizontalStep=%dpt verticalStep=%dpt stagger=%d%% ordering=page-local tapsPreserved=1 result=%s.\n",
             listCount, pageCount, skipped, discovered, moved, clamped,
             gFreeIconCount, gFreeHorizontalStep, gFreeVerticalStep, gFreeStaggerPercent,
             moved > 0 ? "active" : "no eligible home-page icons");
    return moved > 0;
}

bool freeplacement_stop_in_session(void)
{
    int restored = 0;
    for (int i = 0; i < gFreeIconCount; i++) {
        if (!r_is_objc_ptr(gFreeIcons[i])) continue;
        cus_set_rect(gFreeIcons[i], gFreeFrames[i]);
        r_msg2_main(gFreeIcons[i], "release", 0, 0, 0, 0);
        restored++;
    }
    memset(gFreeIcons, 0, sizeof(gFreeIcons));
    memset(gFreeFrames, 0, sizeof(gFreeFrames));
    gFreeIconCount = 0;
    printf("[FREEPLACEMENT] restored=%d\n", restored);
    log_user("[FREEPLACEMENT][RESTORE] restoredFrames=%d cacheCleared=1.\n", restored);
    return restored > 0;
}

void freeplacement_forget_remote_state(void)
{
    int forgotten = gFreeIconCount;
    memset(gFreeIcons, 0, sizeof(gFreeIcons));
    memset(gFreeFrames, 0, sizeof(gFreeFrames));
    gFreeIconCount = 0;
    log_user("[FREEPLACEMENT][FORGET] cleared %d cached icon reference(s).\n", forgotten);
}

static int applibrary_saved_icon_index(uint64_t icon)
{
    for (int i = 0; i < gAppLibraryIconCount; i++) if (gAppLibraryIcons[i] == icon) return i;
    return -1;
}

static bool applibrary_label_is_saved(uint64_t label)
{
    for (int i = 0; i < gAppLibraryLabelCount; i++) if (gAppLibraryLabels[i] == label) return true;
    return false;
}

static void applibrarystudio_scan(uint64_t view, int depth, bool libraryContext,
                                  int *visited, int *ordinal, int *iconsChanged, int *labelsChanged)
{
    if (!r_is_objc_ptr(view) || depth > 12 || !visited || *visited >= 1024 ||
        (ordinal && *ordinal >= 512)) return;
    (*visited)++;
    char cls[160] = {0};
    cus_class_name(view, cls, sizeof(cls));
    bool libraryClass = cus_contains(cls, "SBHLibrary") || cus_contains(cls, "AppLibrary") ||
                        cus_contains(cls, "LibraryPod") || cus_contains(cls, "LibraryCategory");
    libraryContext = libraryContext || libraryClass;

    bool iconClass = cus_contains(cls, "SBIconView") ||
                     (libraryClass && cus_contains(cls, "IconView") && !cus_contains(cls, "Label"));
    if (libraryContext && iconClass) {
        CUSRect current;
        if (cus_get_rect(view, "frame", &current) && current.width > 0 && current.height > 0) {
            int saved = applibrary_saved_icon_index(view);
            if (saved < 0 && gAppLibraryIconCount < 512) {
                saved = gAppLibraryIconCount;
                gAppLibraryIcons[gAppLibraryIconCount] = view;
                gAppLibraryFrames[gAppLibraryIconCount++] = current;
                r_msg2_main(view, "retain", 0, 0, 0, 0);
            }
            if (saved >= 0) {
                CUSRect frame = gAppLibraryFrames[saved];
                double scale = (double)gAppLibraryScale / 100.0;
                double originalWidth = frame.width, originalHeight = frame.height;
                frame.width *= scale;
                frame.height *= scale;
                frame.x += (originalWidth - frame.width) * 0.5;
                frame.y += (originalHeight - frame.height) * 0.5;
                int position = ordinal ? (*ordinal)++ : saved;
                int columnPhase = (position % 4) - 1;
                int rowPhase = ((position / 4) % 4) - 1;
                frame.x += (double)columnPhase * gAppLibraryHorizontalSpacing;
                frame.y += (double)rowPhase * gAppLibraryVerticalSpacing;
                cus_set_rect(view, frame);
                r_msg2_main(view, "setUserInteractionEnabled:", 1, 0, 0, 0);
                if (iconsChanged) (*iconsChanged)++;
            }
        }
    } else if (libraryContext && (cus_contains(cls, "IconLabel") || cus_contains(cls, "TitleLabel"))) {
        if (!applibrary_label_is_saved(view) && gAppLibraryLabelCount < 512)
            gAppLibraryLabels[gAppLibraryLabelCount++] = view;
        if (gAppLibraryHideLabels) {
            double alpha = 0.0;
            if (sb_cc_override_bytes("applibrarystudio", view, "alpha", "setAlpha:",
                                     &alpha, sizeof(alpha)) && labelsChanged)
                (*labelsChanged)++;
        }
    }

    uint64_t subs = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subs) ? r_msg2_main(subs, "count", 0, 0, 0, 0) : 0;
    if (count > 256) count = 256;
    for (uint64_t i = 0; i < count; i++)
        applibrarystudio_scan(r_msg2_main(subs, "objectAtIndex:", i, 0, 0, 0), depth + 1,
                              libraryContext, visited, ordinal, iconsChanged, labelsChanged);
}

void applibrarystudio_configure(int iconScalePercent, int horizontalSpacing,
                                int verticalSpacing, bool hideLabels, bool disableTodayView)
{
    if (iconScalePercent < 65) iconScalePercent = 65;
    if (iconScalePercent > 120) iconScalePercent = 120;
    if (horizontalSpacing < -30) horizontalSpacing = -30;
    if (horizontalSpacing > 30) horizontalSpacing = 30;
    if (verticalSpacing < -30) verticalSpacing = -30;
    if (verticalSpacing > 30) verticalSpacing = 30;
    gAppLibraryScale = iconScalePercent;
    gAppLibraryHorizontalSpacing = horizontalSpacing;
    gAppLibraryVerticalSpacing = verticalSpacing;
    gAppLibraryHideLabels = hideLabels;
    gAppLibraryDisableTodayView = disableTodayView;
    log_user("[APPLIBRARY][CONFIG] iconScale=%d%% horizontalSpacing=%dpt verticalSpacing=%dpt hideLabels=%d disableTodayView=%d.\n",
             gAppLibraryScale, gAppLibraryHorizontalSpacing,
             gAppLibraryVerticalSpacing, gAppLibraryHideLabels,
             gAppLibraryDisableTodayView);
}

bool applibrarystudio_apply_in_session(void)
{
    if (!gAppLibraryHideLabels) sb_cc_restore_owner("applibrarystudio");
    uint64_t windows[64] = {0};
    int windowCount = sb_collect_windows(windows, 64);
    int visited = 0, ordinal = 0, iconsChanged = 0, labelsChanged = 0;
    for (int i = 0; i < windowCount; i++)
        applibrarystudio_scan(windows[i], 0, false, &visited, &ordinal, &iconsChanged, &labelsChanged);
    bool todayOK = true;
    if (gAppLibraryDisableTodayView && !gAppLibraryTodayRemoved) {
        todayOK = darksword_tweak_disable_today_view_in_session();
        if (todayOK) gAppLibraryTodayRemoved = true;
    }
    bool layoutRequested = gAppLibraryScale != 100 || gAppLibraryHorizontalSpacing != 0 ||
                           gAppLibraryVerticalSpacing != 0 || gAppLibraryHideLabels;
    bool layoutOK = !layoutRequested || iconsChanged > 0 || labelsChanged > 0;
    bool todayRequested = gAppLibraryDisableTodayView;
    bool todayApplied = !todayRequested || gAppLibraryTodayRemoved;
    bool applied = todayOK && todayApplied && layoutOK;
    printf("[APPLIBRARY] scale=%d%% spacing=%d/%d labelsHidden=%d disableToday=%d todayResult=%d todayRemoved=%d visited=%d icons=%d labels=%d saved=%d windows=%d taps=preserved\n",
           gAppLibraryScale, gAppLibraryHorizontalSpacing, gAppLibraryVerticalSpacing,
           gAppLibraryHideLabels, gAppLibraryDisableTodayView, todayOK,
           gAppLibraryTodayRemoved, visited, iconsChanged, labelsChanged, gAppLibraryIconCount, windowCount);
    log_user("[APPLIBRARY][APPLY] windows=%d iconsChanged=%d labelsChanged=%d savedFrames=%d scale=%d%% spacing=%d/%dpt hideLabels=%d disableToday=%d todayResult=%d todayRemoved=%d tapsPreserved=1 result=%s.\n",
             windowCount, iconsChanged, labelsChanged, gAppLibraryIconCount,
             gAppLibraryScale, gAppLibraryHorizontalSpacing, gAppLibraryVerticalSpacing,
             gAppLibraryHideLabels, gAppLibraryDisableTodayView, todayOK,
             gAppLibraryTodayRemoved,
             applied ? "active" : "incomplete");
    return applied;
}

bool applibrarystudio_stop_in_session(void)
{
    int restored = 0;
    for (int i = 0; i < gAppLibraryIconCount; i++) {
        if (!r_is_objc_ptr(gAppLibraryIcons[i])) continue;
        cus_set_rect(gAppLibraryIcons[i], gAppLibraryFrames[i]);
        r_msg2_main(gAppLibraryIcons[i], "release", 0, 0, 0, 0);
        restored++;
    }
    int labelProperties = sb_cc_restore_owner("applibrarystudio");
    int labels = gAppLibraryLabelCount;
    bool todayNeedsRespring = gAppLibraryTodayRemoved;
    applibrarystudio_forget_remote_state();
    printf("[APPLIBRARY] restoredIcons=%d restoredLabels=%d todayViewRestore=%s\n",
           restored, labels, todayNeedsRespring ? "respring-required" : "not-needed");
    log_user("[APPLIBRARY][RESTORE] restoredIcons=%d restoredLabels=%d todayViewRestore=%s cacheCleared=1.\n",
             restored, labels, todayNeedsRespring ? "respring-required" : "not-needed");
    return !todayNeedsRespring && (restored > 0 || labelProperties > 0 || labels == 0);
}

void applibrarystudio_forget_remote_state(void)
{
    memset(gAppLibraryIcons, 0, sizeof(gAppLibraryIcons));
    memset(gAppLibraryFrames, 0, sizeof(gAppLibraryFrames));
    memset(gAppLibraryLabels, 0, sizeof(gAppLibraryLabels));
    gAppLibraryIconCount = 0;
    gAppLibraryLabelCount = 0;
    gAppLibraryTodayRemoved = false;
    sb_cc_forget_owner("applibrarystudio");
}

static bool lockcustomizer_window_visible(uint64_t window)
{
    if (!r_is_objc_ptr(window)) return false;
    if (r_responds_main(window, "isHidden") &&
        (r_msg2_main(window, "isHidden", 0, 0, 0, 0) & 0xff)) return false;
    double alpha = 1.0;
    if (r_responds_main(window, "alpha") &&
        !r_msg2_main_struct_ret(window, "alpha", &alpha, sizeof(alpha),
                                NULL, 0, NULL, 0, NULL, 0, NULL, 0))
        return false;
    return alpha > 0.01;
}

static bool lockcustomizer_matches_window(uint64_t window)
{
    if (!r_is_objc_ptr(window)) return false;
    char cls[160] = {0};
    cus_class_name(window, cls, sizeof(cls));
    if (cus_contains(cls, "CoverSheet") || cus_contains(cls, "LockScreen") ||
        cus_contains(cls, "DashBoard")) return true;
    uint64_t controller = r_responds_main(window, "rootViewController")
        ? r_msg2_main(window, "rootViewController", 0, 0, 0, 0) : 0;
    cus_class_name(controller, cls, sizeof(cls));
    return cus_contains(cls, "CoverSheet") || cus_contains(cls, "LockScreen") ||
           cus_contains(cls, "DashBoard") || cus_contains(cls, "CSCombined");
}

static uint64_t lockcustomizer_window(bool *visible)
{
    if (visible) *visible = false;
    uint64_t windows[64] = {0};
    int count = sb_collect_windows(windows, 64);
    for (int i = count - 1; i >= 0; i--) {
        if (lockcustomizer_matches_window(windows[i]) &&
            lockcustomizer_window_visible(windows[i])) {
            if (visible) *visible = true;
            return windows[i];
        }
    }
    // SpringBoard normally builds and retains the Cover Sheet window before
    // it becomes visible. Pre-arming only this class-verified hierarchy makes
    // lock-screen settings survive the Settings app being suspended on lock.
    for (int i = count - 1; i >= 0; i--)
        if (lockcustomizer_matches_window(windows[i])) return windows[i];
    return 0;
}

static void lockcustomizer_scan(uint64_t view, int depth, bool lockContext,
                                int *visited, int *changed)
{
    if (!r_is_objc_ptr(view) || depth > 12 || !visited || *visited >= 384 ||
        (changed && *changed >= 64)) return;
    (*visited)++;
    char cls[160] = {0};
    cus_class_name(view, cls, sizeof(cls));
    bool isLock = cus_contains(cls, "LockScreen") || cus_contains(cls, "CoverSheet") ||
                  cus_contains(cls, "CSPageControl") || cus_contains(cls, "CSCoverSheet") ||
                  cus_contains(cls, "CSMainPage") || cus_contains(cls, "SBDashBoard") ||
                  cus_contains(cls, "CSCombined");
    lockContext = lockContext || isLock;
    bool isClock = cus_contains(cls, "LockScreenDateView") || cus_contains(cls, "CSDateView") ||
                   cus_contains(cls, "CoverSheetDateView") || cus_contains(cls, "ClockView");
    bool isQuick = cus_contains(cls, "QuickAction") || cus_contains(cls, "CameraGrabber") || cus_contains(cls, "Flashlight");
    bool isDots = cus_contains(cls, "PageControl") || cus_contains(cls, "PageIndicator");
    bool isMedia = cus_contains(cls, "MediaControlsPanelView") || cus_contains(cls, "NowPlayingContainer");
    bool isArtwork = cus_contains(cls, "Artwork") || cus_contains(cls, "CoverArt");
    if (isClock && lockContext) {
        double scale = (double)gLockClockScale / 100.0;
        CUSAffine t = {scale, 0, 0, scale, gLockXOffset, gLockYOffset};
        bool didChange = sb_cc_override_bytes("lockcustomizer", view, "transform", "setTransform:", &t, sizeof(t));
        double alpha = (double)gLockContentAlpha / 100.0;
        didChange = sb_cc_override_bytes("lockcustomizer", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)) || didChange;
        if (didChange && changed) (*changed)++;
    } else if (isQuick && lockContext && gLockHideQuickActions) {
        double alpha = 0.0;
        if (sb_cc_override_bytes("lockcustomizer", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)) && changed) (*changed)++;
    } else if (isDots && lockContext && gLockHideDots) {
        double alpha = 0.0;
        if (sb_cc_override_bytes("lockcustomizer", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)) && changed) (*changed)++;
    } else if (isArtwork && lockContext && gLockHideMediaArtwork) {
        double alpha = 0.0;
        if (sb_cc_override_bytes("lockcustomizer", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)) && changed) (*changed)++;
    } else if (isMedia && lockContext) {
        double scale = (double)gLockMediaScale / 100.0;
        CUSAffine t = { scale, 0, 0, scale, 0, 0 };
        if (sb_cc_override_bytes("lockcustomizer", view, "transform", "setTransform:", &t, sizeof(t)) && changed) (*changed)++;
    }
    uint64_t subs = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subs) ? r_msg2_main(subs, "count", 0, 0, 0, 0) : 0;
    if (count > 96) count = 96;
    for (uint64_t i = 0; i < count; i++)
        lockcustomizer_scan(r_msg2_main(subs, "objectAtIndex:", i, 0, 0, 0),
                            depth + 1, lockContext, visited, changed);
}

void lockcustomizer_configure(int clockScalePercent, int horizontalOffset, int verticalOffset,
                              bool hideQuickActions, bool hidePageDots, int contentAlphaPercent,
                              int mediaScalePercent, bool hideMediaArtwork,
                              bool metalLightEnabled, int metalLightIntensityPercent,
                              int metalLightThickness, int metalLightStyle)
{
    if (clockScalePercent < 50) clockScalePercent = 50;
    if (clockScalePercent > 180) clockScalePercent = 180;
    if (horizontalOffset < -160) horizontalOffset = -160;
    if (horizontalOffset > 160) horizontalOffset = 160;
    if (verticalOffset < -300) verticalOffset = -300;
    if (verticalOffset > 300) verticalOffset = 300;
    if (contentAlphaPercent < 20) contentAlphaPercent = 20;
    if (contentAlphaPercent > 100) contentAlphaPercent = 100;
    if (mediaScalePercent < 65) mediaScalePercent = 65;
    if (mediaScalePercent > 115) mediaScalePercent = 115;
    if (metalLightIntensityPercent < 10) metalLightIntensityPercent = 10;
    if (metalLightIntensityPercent > 100) metalLightIntensityPercent = 100;
    if (metalLightThickness < 1) metalLightThickness = 1;
    if (metalLightThickness > 18) metalLightThickness = 18;
    if (metalLightStyle < 0) metalLightStyle = 0;
    if (metalLightStyle > 2) metalLightStyle = 2;
    if (gLockClockScale != clockScalePercent || gLockXOffset != horizontalOffset ||
        gLockYOffset != verticalOffset || gLockHideQuickActions != hideQuickActions ||
        gLockHideDots != hidePageDots || gLockContentAlpha != contentAlphaPercent ||
        gLockMediaScale != mediaScalePercent || gLockHideMediaArtwork != hideMediaArtwork ||
        gMetalLockLightEnabled != metalLightEnabled ||
        gMetalLockLightIntensity != metalLightIntensityPercent ||
        gMetalLockLightThickness != metalLightThickness ||
        gMetalLockLightStyle != metalLightStyle) {
        gLockConfigDirty = true;
    }
    gLockClockScale = clockScalePercent;
    gLockXOffset = horizontalOffset;
    gLockYOffset = verticalOffset;
    gLockHideQuickActions = hideQuickActions;
    gLockHideDots = hidePageDots;
    gLockContentAlpha = contentAlphaPercent;
    gLockMediaScale = mediaScalePercent;
    gLockHideMediaArtwork = hideMediaArtwork;
    gMetalLockLightEnabled = metalLightEnabled;
    gMetalLockLightIntensity = metalLightIntensityPercent;
    gMetalLockLightThickness = metalLightThickness;
    gMetalLockLightStyle = metalLightStyle;
    log_user("[LOCKCUSTOM][CONFIG] clockScale=%d%% offset=%d/%dpt hideQuickActions=%d hidePageDots=%d clockAlpha=%d%% mediaScale=%d%% hideArtwork=%d metalLight=%d metalIntensity=%d%% metalThickness=%dpt metalStyle=%d.\n",
             gLockClockScale, gLockXOffset, gLockYOffset, gLockHideQuickActions,
             gLockHideDots, gLockContentAlpha, gLockMediaScale,
             gLockHideMediaArtwork, gMetalLockLightEnabled,
             gMetalLockLightIntensity, gMetalLockLightThickness, gMetalLockLightStyle);
}

static uint64_t metal_lock_light_color(void)
{
    double red = 0.30, green = 0.72, blue = 1.0, alpha = 1.0;
    if (gMetalLockLightStyle == 1) { red = 0.72; green = 0.38; blue = 1.0; }
    if (gMetalLockLightStyle == 2) { red = 1.0; green = 0.67; blue = 0.24; }
    uint64_t cls = r_class("UIColor");
    return r_is_objc_ptr(cls)
        ? r_msg2_main_raw(cls, "colorWithRed:green:blue:alpha:",
                          &red, sizeof(red), &green, sizeof(green),
                          &blue, sizeof(blue), &alpha, sizeof(alpha)) : 0;
}

static bool metal_lock_light_apply(uint64_t lockWindow)
{
    if (!gMetalLockLightEnabled) {
        bool removed = r_is_objc_ptr(gMetalLockLightOverlay);
        if (removed)
            r_msg2_main(gMetalLockLightOverlay, "removeFromSuperview", 0, 0, 0, 0);
        if (removed)
            r_msg2_main(gMetalLockLightOverlay, "release", 0, 0, 0, 0);
        gMetalLockLightOverlay = 0;
        log_user("[METALLOCK][DISABLED] overlayRemoved=%d result=stock-edge-light.\n", removed);
        return false;
    }
    if (!r_is_objc_ptr(lockWindow)) {
        printf("[METALLOCK] lock window not visible yet\n");
        log_user("[METALLOCK][WAIT] no visible CoverSheet window; apply will retry while the lock screen is presented.\n");
        return false;
    }
    CUSRect bounds;
    if (!cus_get_rect(lockWindow, "bounds", &bounds)) return false;
    if (!r_is_objc_ptr(gMetalLockLightOverlay)) {
        uint64_t alloc = r_msg2_main(r_class("UIView"), "alloc", 0, 0, 0, 0);
        gMetalLockLightOverlay = r_is_objc_ptr(alloc)
            ? r_msg2_main_raw(alloc, "initWithFrame:", &bounds, sizeof(bounds), NULL, 0, NULL, 0, NULL, 0) : 0;
        if (!r_is_objc_ptr(gMetalLockLightOverlay)) return false;
        r_msg2_main(gMetalLockLightOverlay, "setUserInteractionEnabled:", 0, 0, 0, 0);
        r_msg2_main(lockWindow, "addSubview:", gMetalLockLightOverlay, 0, 0, 0);
    } else {
        uint64_t parent = r_msg2_main(gMetalLockLightOverlay, "superview", 0, 0, 0, 0);
        if (parent != lockWindow)
            r_msg2_main(lockWindow, "addSubview:", gMetalLockLightOverlay, 0, 0, 0);
    }
    cus_set_rect(gMetalLockLightOverlay, bounds);
    cus_set_alpha(gMetalLockLightOverlay, (double)gMetalLockLightIntensity / 100.0);
    uint64_t layer = r_msg2_main(gMetalLockLightOverlay, "layer", 0, 0, 0, 0);
    uint64_t color = metal_lock_light_color();
    uint64_t cgColor = r_is_objc_ptr(color) ? r_msg2_main(color, "CGColor", 0, 0, 0, 0) : 0;
    double width = (double)gMetalLockLightThickness, radius = 26.0, shadowRadius = width * 2.2;
    float shadowOpacity = 0.92f;
    r_msg2_main_raw(layer, "setBorderWidth:", &width, sizeof(width), NULL, 0, NULL, 0, NULL, 0);
    if (cgColor) {
        r_msg2_main(layer, "setBorderColor:", cgColor, 0, 0, 0);
        r_msg2_main(layer, "setShadowColor:", cgColor, 0, 0, 0);
    }
    r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main_raw(layer, "setShadowOpacity:", &shadowOpacity, sizeof(shadowOpacity), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main_raw(layer, "setShadowRadius:", &shadowRadius, sizeof(shadowRadius), NULL, 0, NULL, 0, NULL, 0);
    printf("[METALLOCK] style=%d intensity=%d%% thickness=%d overlay=0x%llx window=0x%llx touches=passthrough\n",
           gMetalLockLightStyle, gMetalLockLightIntensity, gMetalLockLightThickness,
           gMetalLockLightOverlay, lockWindow);
    log_user("[METALLOCK] applied style=%d intensity=%d%% thickness=%dpt; overlay is noninteractive and cleanup is registered.\n",
             gMetalLockLightStyle, gMetalLockLightIntensity, gMetalLockLightThickness);
    return true;
}

static bool lockcustomizer_run(bool restore)
{
    if (restore) {
        int restored = sb_cc_restore_owner("lockcustomizer");
        bool overlayRemoved = r_is_objc_ptr(gMetalLockLightOverlay);
        if (overlayRemoved) {
            r_msg2_main(gMetalLockLightOverlay, "removeFromSuperview", 0, 0, 0, 0);
            r_msg2_main(gMetalLockLightOverlay, "release", 0, 0, 0, 0);
        }
        gMetalLockLightOverlay = 0;
        log_user("[LOCKCUSTOM][RESTORE] exactProperties=%d metalOverlayRemoved=%d result=%s.\n",
                 restored, overlayRemoved, (restored > 0 || overlayRemoved) ? "success" : "nothing-owned");
        return restored > 0 || overlayRemoved;
    }
    if (gLockConfigDirty) {
        int restored = sb_cc_restore_owner("lockcustomizer");
        log_user("[LOCKCUSTOM][RECONFIGURE] restoredPriorProperties=%d before applying the new selection.\n",
                 restored);
        gLockConfigDirty = false;
    }
    bool windowVisible = false;
    uint64_t lockWindow = lockcustomizer_window(&windowVisible);
    if (!r_is_objc_ptr(lockWindow)) {
        log_user("[LOCKCUSTOM][WAIT] no class-verified Cover Sheet window exists yet; no hierarchy was touched.\n");
        return false;
    }
    int visited = 0, changed = 0;
    lockcustomizer_scan(lockWindow, 0, true, &visited, &changed);
    bool metalOK = metal_lock_light_apply(lockWindow);
    printf("[LOCKCUSTOM] restore=%d scale=%d%% x=%d y=%d quick=%d dots=%d alpha=%d%% mediaScale=%d%% hideArtwork=%d metal=%d metalOK=%d visited=%d changed=%d\n",
           restore, gLockClockScale, gLockXOffset, gLockYOffset,
           gLockHideQuickActions, gLockHideDots, gLockContentAlpha,
           gLockMediaScale, gLockHideMediaArtwork, gMetalLockLightEnabled, metalOK, visited, changed);
    log_user("[LOCKCUSTOM][%s] window=0x%llx presentation=%s visited=%d matchedViews=%d clockScale=%d%% offset=%d/%dpt hideQuick=%d hideDots=%d alpha=%d%% mediaScale=%d%% hideArtwork=%d metalEnabled=%d metalResult=%d result=%s.\n",
             restore ? "RESTORE" : "APPLY", lockWindow,
             windowVisible ? "visible" : "prearmed-hidden", visited, changed,
             gLockClockScale, gLockXOffset, gLockYOffset,
             gLockHideQuickActions, gLockHideDots, gLockContentAlpha,
             gLockMediaScale, gLockHideMediaArtwork, gMetalLockLightEnabled,
             metalOK, (changed > 0 || metalOK) ? "success" : "no supported views");
    return changed > 0 || metalOK;
}

bool lockcustomizer_apply_in_session(void) { return lockcustomizer_run(false); }
bool lockcustomizer_stop_in_session(void) { return lockcustomizer_run(true); }
void lockcustomizer_forget_remote_state(void)
{
    bool hadOverlay = r_is_objc_ptr(gMetalLockLightOverlay);
    gMetalLockLightOverlay = 0;
    gLockConfigDirty = false;
    sb_cc_forget_owner("lockcustomizer");
    log_user("[LOCKCUSTOM][FORGET] cleared remote state; hadMetalOverlay=%d.\n", hadOverlay);
}
