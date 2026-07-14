#ifndef communityports_h
#define communityports_h

#include <stdbool.h>

typedef enum {
    CommunityPortScrollingDock = 0,
    CommunityPortNiuBiBar,
    CommunityPortVolSkip,
    CommunityPortFlow,
    CommunityPortAppProfiles,
    CommunityPortChargeFX,
    CommunityPortRotatePro,
    CommunityPortKeepEye,
    CommunityPortLastLook,
    CommunityPortCount
} CommunityPort;

void communityports_configure(int dockVisibleIcons, int barThickness,
                              int profileBrightnessPercent, int chargeThickness,
                              int hudYOffset, int lastLookAlphaPercent);
bool communityports_apply(CommunityPort port);
bool communityports_stop(CommunityPort port);
bool communityports_stop_all(void);
void communityports_forget_remote_state(void);

#endif
