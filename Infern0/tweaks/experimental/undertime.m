#import "undertime.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

static bool gUtApplied = false;

bool undertime_apply_in_session(void)
{
    printf("[UNDERTIME] apply\n");

    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t statusBar = r_msg2_main(app, "statusBar", 0, 0, 0, 0);
    if (!r_is_objc_ptr(statusBar)) {
        statusBar = r_ivar_value(app, "_statusBar");
    }
    if (!r_is_objc_ptr(statusBar)) {
        statusBar = r_ivar_value(app, "_statusBarWindow");
        if (r_is_objc_ptr(statusBar)) {
            statusBar = r_msg2_main(statusBar, "statusBar", 0, 0, 0, 0);
        }
    }
    if (!r_is_objc_ptr(statusBar)) return false;

    uint64_t timeItem = r_msg2_main(statusBar, "timeItem", 0, 0, 0, 0);
    if (!r_is_objc_ptr(timeItem)) {
        timeItem = r_ivar_value(statusBar, "_timeItem");
    }
    if (!r_is_objc_ptr(timeItem)) {
        uint64_t items = r_msg2_main(statusBar, "items", 0, 0, 0, 0);
        if (!r_is_objc_ptr(items)) {
            items = r_ivar_value(statusBar, "_items");
        }
        if (r_is_objc_ptr(items)) {
            uint64_t count = r_msg2_main(items, "count", 0, 0, 0, 0);
            for (uint64_t j = 0; j < count && j < 32; j++) {
                uint64_t item = r_msg2_main(items, "objectAtIndex:", j, 0, 0, 0);
                if (!r_is_objc_ptr(item)) continue;
                char itemCls[128] = {0};
                (void)sb_read_class_name(item, itemCls, sizeof(itemCls));
                if (strstr(itemCls, "Time") || strstr(itemCls, "Clock")) {
                    timeItem = item;
                    break;
                }
            }
        }
    }
    if (!r_is_objc_ptr(timeItem)) return false;

    // DateUnderTime-style safe date format. The old "%.1f GB" placeholder
    // was neither a valid date component nor supplied with an argument and
    // could leave the status item in an invalid formatting state.
    uint64_t formatStr = r_nsstr_retained("HH:mm\nMMM d");
    if (!r_is_objc_ptr(formatStr)) return false;
    bool changed = sb_cc_override_object("undertime", timeItem,
                                         "format", "setFormat:", formatStr);
    r_msg2_main(formatStr, "release", 0, 0, 0, 0);
    if (!changed) return false;
    printf("[UNDERTIME] set double-line clock format\n");

    gUtApplied = true;
    return true;
}

bool undertime_stop_in_session(void)
{
    printf("[UNDERTIME] stop\n");
    int restored = sb_cc_restore_owner("undertime");
    gUtApplied = false;
    log_user("[UNDERTIME][RESTORE] exactFormatProperties=%d.\n", restored);
    return restored > 0;
}

void undertime_forget_remote_state(void)
{
    gUtApplied = false;
    sb_cc_forget_owner("undertime");
}
