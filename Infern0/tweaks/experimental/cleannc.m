#import "cleannc.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

static bool gCleanncApplied = false;
static int gCleanncChanged = 0;

bool cleannc_apply_in_session(void)
{
    printf("[CLEANNC] apply\n");
    gCleanncChanged = 0;

    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (!r_is_objc_ptr(windows)) return false;
    uint64_t winCount = r_msg2_main(windows, "count", 0, 0, 0, 0);
    if (winCount > 64) winCount = 64;

    for (uint64_t i = 0; i < winCount; i++) {
        uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(win)) continue;
        uint64_t root = r_msg2_main(win, "rootViewController", 0, 0, 0, 0);
        if (!r_is_objc_ptr(root)) continue;

        char cls[128] = {0};
        if (!sb_read_class_name(root, cls, sizeof(cls))) continue;

        if (strstr(cls, "CoverSheet") || strstr(cls, "NCNotification")) {
            uint64_t listView = r_ivar_value(root, "_listView");
            if (!r_is_objc_ptr(listView)) listView = r_msg2_main(root, "listView", 0, 0, 0, 0);
            if (!r_is_objc_ptr(listView)) continue;

            uint64_t subviews = r_msg2_main(listView, "subviews", 0, 0, 0, 0);
            if (!r_is_objc_ptr(subviews)) continue;
            uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
            if (count > 128) count = 128;

            for (uint64_t j = 0; j < count; j++) {
                uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", j, 0, 0, 0);
                if (!r_is_objc_ptr(sv)) continue;

                char svCls[128] = {0};
                (void)sb_read_class_name(sv, svCls, sizeof(svCls));

                if (strstr(svCls, "Search") || strstr(svCls, "search")) {
                    if (sb_cc_override_bool("cleannc", sv, "isHidden", "setHidden:", true)) gCleanncChanged++;
                }
                if (strstr(svCls, "NoNotifications") || strstr(svCls, "no_notifications")) {
                    if (sb_cc_override_bool("cleannc", sv, "isHidden", "setHidden:", true)) gCleanncChanged++;
                }
            }

            uint64_t bgView = r_ivar_value(root, "_backgroundView");
            if (r_is_objc_ptr(bgView)) {
                if (sb_cc_override_bool("cleannc", bgView, "isHidden", "setHidden:", true)) gCleanncChanged++;
            }
        }
    }

    gCleanncApplied = gCleanncChanged > 0;
    log_user("[CLEANNC][APPLY] exactOverrides=%d result=%s.\n",
             gCleanncChanged, gCleanncApplied ? "active" : "no-supported-views");
    return gCleanncApplied;
}

bool cleannc_stop_in_session(void)
{
    printf("[CLEANNC] stop\n");
    int restored = sb_cc_restore_owner("cleannc");
    gCleanncApplied = false;
    log_user("[CLEANNC][RESTORE] exactProperties=%d.\n", restored);
    return restored > 0;
}

void cleannc_forget_remote_state(void)
{
    gCleanncApplied = false;
    gCleanncChanged = 0;
    sb_cc_forget_owner("cleannc");
}
