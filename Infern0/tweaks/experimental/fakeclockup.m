#import "fakeclockup.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gFcuApplied = false;
static double gFcuMultiplier = 1.0;

bool fakeclockup_apply_in_session(double speedMultiplier)
{
    printf("[FAKECLOCKUP] apply multiplier=%.2f\n", speedMultiplier);

    if (speedMultiplier <= 0.0) speedMultiplier = 1.0;

    uint64_t windows[64] = {0};
    int windowCount = sb_collect_windows(windows, 64), changed = 0;
    float speed = (float)speedMultiplier;
    for (int i = 0; i < windowCount; i++) {
        uint64_t layer = r_msg2_main(windows[i], "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer) &&
            sb_cc_override_bytes("fakeclockup", layer, "speed", "setSpeed:", &speed, sizeof(speed)))
            changed++;
    }
    if (changed == 0) return false;

    gFcuMultiplier = speedMultiplier;
    gFcuApplied = true;
    log_user("[FAKECLOCKUP][APPLY] windowLayers=%d speedMultiplier=%.2f exactRestoreCaptured=1.\n",
             changed, speedMultiplier);
    return true;
}

bool fakeclockup_stop_in_session(void)
{
    printf("[FAKECLOCKUP] stop\n");

    int restored = sb_cc_restore_owner("fakeclockup");
    gFcuApplied = false;
    gFcuMultiplier = 1.0;
    log_user("[FAKECLOCKUP][RESTORE] exactLayerSpeeds=%d.\n", restored);
    return restored > 0;
}

void fakeclockup_forget_remote_state(void)
{
    gFcuApplied = false;
    gFcuMultiplier = 1.0;
    sb_cc_forget_owner("fakeclockup");
}
