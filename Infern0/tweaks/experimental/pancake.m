#import "pancake.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gPcApplied = false;
static uint64_t gPcGesture = 0;
static uint64_t gPcWindow = 0;
static int gPcMinimumTouches = 1;
static int gPcMaximumTouches = 1;
static bool gPcCancelsTouches = false;

static uint64_t pc_navigation_target_for_controller(uint64_t controller, int depth)
{
    if (!r_is_objc_ptr(controller) || depth > 4) return 0;
    if (r_responds_main(controller, "popViewControllerAnimated:"))
        return controller;

    if (r_responds_main(controller, "navigationController")) {
        uint64_t nav = r_msg2_main(controller, "navigationController", 0, 0, 0, 0);
        if (r_is_objc_ptr(nav) && r_responds_main(nav, "popViewControllerAnimated:"))
            return nav;
    }

    if (r_responds_main(controller, "presentedViewController")) {
        uint64_t presented = r_msg2_main(controller, "presentedViewController", 0, 0, 0, 0);
        uint64_t target = pc_navigation_target_for_controller(presented, depth + 1);
        if (target) return target;
    }

    if (!r_responds_main(controller, "childViewControllers")) return 0;
    uint64_t children = r_msg2_main(controller, "childViewControllers", 0, 0, 0, 0);
    if (!r_is_objc_ptr(children)) return 0;
    uint64_t count = r_msg2_main(children, "count", 0, 0, 0, 0);
    if (count > 8) count = 8;
    uint64_t target = 0;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t child = r_msg2_main(children, "objectAtIndex:", i, 0, 0, 0);
        target = pc_navigation_target_for_controller(child, depth + 1);
        if (target) return target;
    }
    return 0;
}

bool pancake_apply_in_session(void)
{
    printf("[PANCAKE] apply\n");
    if (gPcApplied) pancake_stop_in_session();

    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (!r_is_objc_ptr(windows)) return false;
    uint64_t winCount = r_msg2_main(windows, "count", 0, 0, 0, 0);
    if (winCount > 32) winCount = 32;

    uint64_t keyWindow = 0;
    for (uint64_t i = 0; i < winCount; i++) {
        uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(win)) continue;
        uint64_t isKey = r_msg2_main(win, "isKeyWindow", 0, 0, 0, 0);
        if (isKey & 0xff) {
            keyWindow = win;
            break;
        }
    }
    if (!r_is_objc_ptr(keyWindow)) {
        keyWindow = r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(keyWindow)) return false;

    uint64_t root = r_msg2_main(keyWindow, "rootViewController", 0, 0, 0, 0);
    uint64_t target = pc_navigation_target_for_controller(root, 0);
    if (!r_is_objc_ptr(target)) {
        printf("[PANCAKE] no navigation target found for keyWindow 0x%llx\n", keyWindow);
        return false;
    }

    uint64_t gesture = r_responds_main(target, "interactivePopGestureRecognizer")
        ? r_msg2_main(target, "interactivePopGestureRecognizer", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(gesture)) {
        log_user("[PANCAKE][APPLY] failed: navigation target 0x%llx exposes no native interactive-pop recognizer.\n",
                 target);
        return false;
    }

    int changed = 0;
    changed += sb_cc_override_bool("pancake", gesture, "isEnabled", "setEnabled:", true) ? 1 : 0;
    changed += sb_cc_override_bool("pancake", gesture, "cancelsTouchesInView",
                                   "setCancelsTouchesInView:", gPcCancelsTouches) ? 1 : 0;
    uint64_t minimum = (uint64_t)gPcMinimumTouches;
    uint64_t maximum = (uint64_t)gPcMaximumTouches;
    if (r_responds_main(gesture, "minimumNumberOfTouches") &&
        r_responds_main(gesture, "setMinimumNumberOfTouches:"))
        changed += sb_cc_override_bytes("pancake", gesture, "minimumNumberOfTouches",
                                        "setMinimumNumberOfTouches:", &minimum, sizeof(minimum)) ? 1 : 0;
    if (r_responds_main(gesture, "maximumNumberOfTouches") &&
        r_responds_main(gesture, "setMaximumNumberOfTouches:"))
        changed += sb_cc_override_bytes("pancake", gesture, "maximumNumberOfTouches",
                                        "setMaximumNumberOfTouches:", &maximum, sizeof(maximum)) ? 1 : 0;

    gPcGesture = gesture;
    gPcWindow = keyWindow;
    gPcApplied = changed > 0;
    log_user("[PANCAKE][APPLY] nativeInteractivePop=1 gesture=0x%llx minimumTouches=%d maximumTouches=%d cancelsTouches=%d exactProperties=%d.\n",
             gesture, gPcMinimumTouches, gPcMaximumTouches, gPcCancelsTouches, changed);
    return gPcApplied;
}

bool pancake_stop_in_session(void)
{
    printf("[PANCAKE] stop\n");
    int restored = sb_cc_restore_owner("pancake");
    gPcGesture = 0;
    gPcWindow = 0;
    gPcApplied = false;
    log_user("[PANCAKE][STOP] nativeGestureKept=1 exactPropertiesRestored=%d.\n", restored);
    return true;
}

void pancake_configure(int minimumTouches, int maximumTouches, bool cancelsTouches)
{
    if (minimumTouches < 1) minimumTouches = 1;
    if (minimumTouches > 2) minimumTouches = 2;
    if (maximumTouches < minimumTouches) maximumTouches = minimumTouches;
    if (maximumTouches > 3) maximumTouches = 3;
    gPcMinimumTouches = minimumTouches;
    gPcMaximumTouches = maximumTouches;
    gPcCancelsTouches = cancelsTouches;
}

void pancake_forget_remote_state(void)
{
    gPcGesture = 0;
    gPcWindow = 0;
    gPcApplied = false;
    sb_cc_forget_owner("pancake");
}
