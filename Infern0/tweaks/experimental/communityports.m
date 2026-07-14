#import "communityports.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <stdio.h>
#import <stdint.h>
#import <string.h>

typedef struct { double x, y, width, height; } CPRect;
typedef struct { double width, height; } CPSize;
typedef struct { double a, b, c, d, tx, ty; } CPTransform;

static uint64_t gCPViews[CommunityPortCount] = {0};
static uint64_t gDockIcons[64] = {0}, gDockParents[64] = {0};
static CPRect gDockFrames[64] = {{0}};
static int gDockIconCount = 0;
static uint64_t gFlowViews[128] = {0}, gLastLookViews[256] = {0};
static int gFlowCount = 0, gLastLookCount = 0;
static int gFlowLastReported = -1, gLastLookLastReported = -1;
static uint64_t gChargeLastState = UINT64_MAX;
static char gProfileLastBundle[192] = {0};
static int gDockVisibleIcons = 5, gBarThickness = 5, gProfileBrightness = 82;
static int gChargeThickness = 5, gHUDYOffset = 58, gLastLookAlpha = 92;

static uint64_t cp_color(double r, double g, double b, double a)
{
    uint64_t cls = r_class("UIColor");
    return r_is_objc_ptr(cls) ? r_msg2_main_raw(cls, "colorWithRed:green:blue:alpha:",
        &r, sizeof(r), &g, sizeof(g), &b, sizeof(b), &a, sizeof(a)) : 0;
}

static bool cp_rect(uint64_t view, const char *selector, CPRect *out)
{
    if (!r_is_objc_ptr(view) || !out || !r_responds_main(view, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(view, selector, out, sizeof(*out), NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static void cp_set_rect(uint64_t view, CPRect frame)
{
    if (r_is_objc_ptr(view)) r_msg2_main_raw(view, "setFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
}

static uint64_t cp_alloc_view(const char *className, CPRect frame)
{
    uint64_t cls = r_class(className ?: "UIView");
    uint64_t obj = r_is_objc_ptr(cls) ? r_msg2_main(cls, "alloc", 0, 0, 0, 0) : 0;
    return r_is_objc_ptr(obj)
        ? r_msg2_main_raw(obj, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0) : 0;
}

static uint64_t cp_window(void)
{
    uint64_t win = sb_frontmost_window();
    if (r_is_objc_ptr(win)) return win;
    uint64_t appClass = r_class("UIApplication");
    uint64_t app = r_is_objc_ptr(appClass) ? r_msg2_main(appClass, "sharedApplication", 0, 0, 0, 0) : 0;
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void cp_round(uint64_t view, double radius, double borderWidth, uint64_t color)
{
    uint64_t layer = r_is_objc_ptr(view) ? r_msg2_main(view, "layer", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(layer)) return;
    r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main_raw(layer, "setBorderWidth:", &borderWidth, sizeof(borderWidth), NULL, 0, NULL, 0, NULL, 0);
    uint64_t cg = r_is_objc_ptr(color) ? r_msg2_main(color, "CGColor", 0, 0, 0, 0) : 0;
    if (cg) r_msg2_main(layer, "setBorderColor:", cg, 0, 0, 0);
    r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
}

static bool cp_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!r_is_objc_ptr(obj) || !out || outLen < 2) return false;
    out[0] = '\0';
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    uint64_t name = r_is_objc_ptr(cls) ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    uint64_t len = name ? r_dlsym_call(R_TIMEOUT, "strlen", name, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!len) return false;
    if (len >= outLen) len = outLen - 1;
    uint64_t copy = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    bool ok = copy && remote_read(copy, out, len);
    if (copy) r_free(copy);
    out[len] = '\0';
    return ok;
}

static bool cp_has_ancestor(uint64_t view, const char *needle)
{
    for (int depth = 0; r_is_objc_ptr(view) && depth < 12; depth++) {
        char name[160] = {0};
        if (cp_class_name(view, name, sizeof(name)) && strstr(name, needle)) return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

static uint64_t cp_invocation0(uint64_t target, const char *selectorName)
{
    uint64_t sel = r_sel(selectorName);
    if (!r_is_objc_ptr(target) || !sel || !r_responds_main(target, selectorName)) return 0;
    uint64_t sig = r_msg2_main(target, "methodSignatureForSelector:", sel, 0, 0, 0);
    uint64_t cls = r_class("NSInvocation");
    uint64_t inv = r_is_objc_ptr(cls) && r_is_objc_ptr(sig)
        ? r_msg2_main(cls, "invocationWithMethodSignature:", sig, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(inv)) return 0;
    r_msg2_main(inv, "setTarget:", target, 0, 0, 0);
    r_msg2_main(inv, "setSelector:", sel, 0, 0, 0);
    r_msg2_main(inv, "retainArguments", 0, 0, 0, 0);
    return inv;
}

static uint64_t cp_invocation_int(uint64_t target, const char *selectorName, int64_t value)
{
    uint64_t inv = cp_invocation0(target, selectorName);
    if (!r_is_objc_ptr(inv)) return 0;
    uint64_t buf = r_dlsym_call(R_TIMEOUT, "malloc", sizeof(value), 0, 0, 0, 0, 0, 0, 0);
    if (!buf || !remote_write(buf, &value, sizeof(value))) { if (buf) r_free(buf); return 0; }
    r_msg2_main(inv, "setArgument:atIndex:", buf, 2, 0, 0);
    r_free(buf);
    r_msg2_main(inv, "retainArguments", 0, 0, 0, 0);
    return inv;
}

static uint64_t cp_button(uint64_t parent, const char *title, CPRect frame, uint64_t invocation)
{
    uint64_t button = cp_alloc_view("UIButton", frame);
    if (!r_is_objc_ptr(button)) {
        uint64_t cls = r_class("UIButton");
        button = r_is_objc_ptr(cls) ? r_msg2_main(cls, "buttonWithType:", 0, 0, 0, 0) : 0;
        cp_set_rect(button, frame);
    }
    uint64_t text = r_nsstr_retained(title ?: "");
    if (r_is_objc_ptr(text)) { r_msg2_main(button, "setTitle:forState:", text, 0, 0, 0); r_msg2_main(text, "release", 0, 0, 0, 0); }
    r_msg2_main(button, "setBackgroundColor:", cp_color(1, 1, 1, 0.12), 0, 0, 0);
    cp_round(button, 11.0, 0.5, cp_color(1, 1, 1, 0.25));
    if (r_is_objc_ptr(invocation)) {
        r_msg2_main(button, "addTarget:action:forControlEvents:", invocation, r_sel("invoke"), 1ULL << 6, 0);
        uint64_t key = r_sel("infern0CommunityPortInvocation");
        if (key) r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", button, key, invocation, 1, 0, 0, 0, 0);
    }
    r_msg2_main(parent, "addSubview:", button, 0, 0, 0);
    return button;
}

static uint64_t cp_label(uint64_t parent, const char *text, CPRect frame, double size)
{
    uint64_t label = cp_alloc_view("UILabel", frame);
    uint64_t string = r_nsstr_retained(text ?: "");
    if (r_is_objc_ptr(string)) { r_msg2_main(label, "setText:", string, 0, 0, 0); r_msg2_main(string, "release", 0, 0, 0, 0); }
    uint64_t fontClass = r_class("UIFont");
    uint64_t font = r_is_objc_ptr(fontClass) ? r_msg2_main_raw(fontClass, "monospacedSystemFontOfSize:weight:", &size, sizeof(size), &(double){0.35}, sizeof(double), NULL, 0, NULL, 0) : 0;
    if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    r_msg2_main(label, "setTextColor:", cp_color(1, 1, 1, 0.96), 0, 0, 0);
    r_msg2_main(parent, "addSubview:", label, 0, 0, 0);
    return label;
}

static bool cp_apply_scrolling_dock(void)
{
    if (gDockIconCount) communityports_stop(CommunityPortScrollingDock);
    uint64_t iconClass = r_class("SBIconView"), icons[512] = {0};
    int count = r_is_objc_ptr(iconClass) ? sb_collect_views_in_windows(iconClass, icons, 512) : 0;
    uint64_t commonParent = 0;
    CPRect parentBounds = {0};
    for (int i = 0; i < count && gDockIconCount < 64; i++) {
        if (!cp_has_ancestor(icons[i], "Dock")) continue;
        uint64_t parent = r_msg2_main(icons[i], "superview", 0, 0, 0, 0);
        CPRect frame = {0};
        if (!r_is_objc_ptr(parent) || !cp_rect(icons[i], "frame", &frame)) continue;
        if (!commonParent) { commonParent = parent; cp_rect(parent, "bounds", &parentBounds); }
        if (parent != commonParent) continue;
        int n = gDockIconCount++;
        gDockIcons[n] = icons[i]; gDockParents[n] = parent; gDockFrames[n] = frame;
    }
    if (!gDockIconCount || !r_is_objc_ptr(commonParent)) return false;
    uint64_t scroll = cp_alloc_view("UIScrollView", parentBounds);
    if (!r_is_objc_ptr(scroll)) return false;
    r_msg2_main(scroll, "setShowsHorizontalScrollIndicator:", 0, 0, 0, 0);
    r_msg2_main(scroll, "setAlwaysBounceHorizontal:", 1, 0, 0, 0);
    r_msg2_main(scroll, "setClipsToBounds:", 0, 0, 0, 0);
    double step = parentBounds.width / (double)gDockVisibleIcons;
    double side = fmin(step * 0.82, gDockFrames[0].width);
    for (int i = 0; i < gDockIconCount; i++) {
        r_msg2_main(scroll, "addSubview:", gDockIcons[i], 0, 0, 0);
        CPRect f = { step * i + (step - side) * 0.5, (parentBounds.height - side) * 0.5, side, side };
        cp_set_rect(gDockIcons[i], f);
        r_msg2_main(gDockIcons[i], "setUserInteractionEnabled:", 1, 0, 0, 0);
    }
    CPSize content = { step * gDockIconCount, parentBounds.height };
    r_msg2_main_raw(scroll, "setContentSize:", &content, sizeof(content), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main(commonParent, "addSubview:", scroll, 0, 0, 0);
    gCPViews[CommunityPortScrollingDock] = scroll;
    log_user("[SCROLLINGDOCK][APPLY] discovered=%d dockIcons=%d visibleSlots=%d contentWidth=%.1f liveTaps=1 horizontalBounce=1.\n", count, gDockIconCount, gDockVisibleIcons, content.width);
    return true;
}

static bool cp_apply_niubibar(void)
{
    uint64_t win = cp_window(); CPRect bounds = {0};
    if (!cp_rect(win, "bounds", &bounds)) return false;
    uint64_t bar = cp_alloc_view("UIView", (CPRect){bounds.width * 0.16, bounds.height - 38.0, bounds.width * 0.68, 30.0});
    r_msg2_main(bar, "setBackgroundColor:", cp_color(0.05, 0.05, 0.07, 0.78), 0, 0, 0);
    cp_round(bar, 15.0, (double)gBarThickness / 5.0, cp_color(0.2, 0.7, 1.0, 0.8));
    uint64_t springBoardClass = r_class("SpringBoard");
    uint64_t springBoard = r_is_objc_ptr(springBoardClass) ? r_msg2_main(springBoardClass, "sharedApplication", 0, 0, 0, 0) : 0;
    uint64_t lockAction = cp_invocation0(springBoard, "_simulateLockButtonPress");
    cp_button(bar, "Lock", (CPRect){4, 3, 70, 24}, lockAction);
    uint64_t iconClass = r_class("SBIconController");
    uint64_t iconController = r_is_objc_ptr(iconClass) ? r_msg2_main(iconClass, "sharedInstance", 0, 0, 0, 0) : 0;
    uint64_t search = cp_invocation0(iconController, "presentSpotlight");
    if (!search) search = cp_invocation0(iconController, "_presentSpotlight");
    cp_button(bar, "Search", (CPRect){bounds.width * 0.68 - 74, 3, 70, 24}, search);
    r_msg2_main(win, "addSubview:", bar, 0, 0, 0);
    gCPViews[CommunityPortNiuBiBar] = bar;
    log_user("[NIUBIBAR][APPLY] width=68%% thickness=%d lockAction=%d spotlightAction=%d pressable=1.\n", gBarThickness, r_is_objc_ptr(lockAction), r_is_objc_ptr(search));
    return true;
}

static bool cp_apply_volskip(void)
{
    uint64_t path = r_alloc_str("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer");
    if (path) { r_dlsym_call(R_TIMEOUT, "dlopen", path, 2, 0, 0, 0, 0, 0, 0); r_free(path); }
    uint64_t playerClass = r_class("MPMusicPlayerController");
    uint64_t player = r_is_objc_ptr(playerClass) ? r_msg2_main(playerClass, "systemMusicPlayer", 0, 0, 0, 0) : 0;
    uint64_t win = cp_window(); if (!r_is_objc_ptr(player) || !r_is_objc_ptr(win)) return false;
    uint64_t panel = cp_alloc_view("UIView", (CPRect){8, 180, 52, 158});
    r_msg2_main(panel, "setBackgroundColor:", cp_color(0.04, 0.04, 0.06, 0.82), 0, 0, 0);
    cp_round(panel, 18, 1, cp_color(1, 1, 1, 0.2));
    cp_button(panel, "Prev", (CPRect){5, 6, 42, 44}, cp_invocation0(player, "skipToPreviousItem"));
    cp_button(panel, "Play", (CPRect){5, 56, 42, 44}, cp_invocation0(player, "play"));
    cp_button(panel, "Next", (CPRect){5, 106, 42, 44}, cp_invocation0(player, "skipToNextItem"));
    r_msg2_main(win, "addSubview:", panel, 0, 0, 0); gCPViews[CommunityPortVolSkip] = panel;
    log_user("[VOLSKIP][APPLY] mediaController=0x%llx controls=previous/play/next scope=systemMusicPlayer hardwareInterception=0.\n", player);
    return true;
}

static bool cp_apply_flow(void)
{
    uint64_t viewClass = r_class("UIView"), views[1024] = {0};
    int count = r_is_objc_ptr(viewClass) ? sb_collect_views_in_windows(viewClass, views, 1024) : 0;
    CPTransform scale = {1.05,0,0,1.05,0,0}; gFlowCount = 0;
    for (int i = 0; i < count && gFlowCount < 128; i++) {
        char name[160] = {0}; if (!cp_class_name(views[i], name, sizeof(name))) continue;
        if (!strstr(name, "MediaControls") && !strstr(name, "NowPlaying") && !strstr(name, "Artwork")) continue;
        gFlowViews[gFlowCount++] = views[i];
        if (r_responds_main(views[i], "setTransform:")) r_msg2_main_raw(views[i], "setTransform:", &scale, sizeof(scale), NULL, 0, NULL, 0, NULL, 0);
        cp_round(views[i], 18.0, 0.0, 0);
    }
    if (gFlowLastReported != gFlowCount) {
        log_user("[FLOWLITE][APPLY] scanned=%d styledNowPlayingViews=%d scale=105%% radius=18 artworkAndControls=1.\n", count, gFlowCount);
        gFlowLastReported = gFlowCount;
    }
    return gFlowCount > 0;
}

static bool cp_apply_app_profiles(void)
{
    uint64_t appClass = r_class("SBApplicationController");
    uint64_t controller = r_is_objc_ptr(appClass) ? r_msg2_main(appClass, "sharedInstance", 0, 0, 0, 0) : 0;
    uint64_t app = r_is_objc_ptr(controller) && r_responds_main(controller, "frontmostApplication") ? r_msg2_main(controller, "frontmostApplication", 0, 0, 0, 0) : 0;
    uint64_t bid = r_is_objc_ptr(app) && r_responds_main(app, "bundleIdentifier") ? r_msg2_main(app, "bundleIdentifier", 0, 0, 0, 0) : 0;
    char bundle[192] = "SpringBoard";
    if (r_is_objc_ptr(bid)) { uint64_t c = r_msg2_main(bid, "UTF8String", 0, 0, 0, 0); uint64_t len = c ? r_dlsym_call(R_TIMEOUT, "strlen", c,0,0,0,0,0,0,0) : 0; if (len) { if (len > 191) len=191; uint64_t copy=r_dlsym_call(R_TIMEOUT,"strdup",c,0,0,0,0,0,0,0); if(copy){remote_read(copy,bundle,len);r_free(copy);bundle[len]='\0';}} }
    int pct = gProfileBrightness;
    if (strstr(bundle, "camera")) pct = 100; else if (strstr(bundle, "Maps") || strstr(bundle, "maps")) pct = 92;
    if (strcmp(bundle, gProfileLastBundle) == 0) return true;
    uint64_t screenClass = r_class("UIScreen"), screen = r_is_objc_ptr(screenClass) ? r_msg2_main(screenClass, "mainScreen",0,0,0,0) : 0;
    double brightness = (double)pct / 100.0;
    if (r_is_objc_ptr(screen)) r_msg2_main_raw(screen, "setBrightness:", &brightness, sizeof(brightness), NULL,0,NULL,0,NULL,0);
    log_user("[APPPROFILES][APPLY] foreground=%s profileBrightness=%d%% rule=%s.\n", bundle, pct, pct==100?"camera":(pct==92?"maps":"default"));
    strncpy(gProfileLastBundle, bundle, sizeof(gProfileLastBundle)-1);
    return r_is_objc_ptr(screen);
}

static bool cp_apply_chargefx(void)
{
    uint64_t deviceClass=r_class("UIDevice"), device=r_is_objc_ptr(deviceClass)?r_msg2_main(deviceClass,"currentDevice",0,0,0,0):0;
    if (!r_is_objc_ptr(device)) return false;
    r_msg2_main(device,"setBatteryMonitoringEnabled:",1,0,0,0);
    uint64_t state=r_msg2_main(device,"batteryState",0,0,0,0);
    if (state == gChargeLastState && r_is_objc_ptr(gCPViews[CommunityPortChargeFX])) return true;
    if (r_is_objc_ptr(gCPViews[CommunityPortChargeFX])) r_msg2_main(gCPViews[CommunityPortChargeFX],"removeFromSuperview",0,0,0,0);
    uint64_t win=cp_window(); CPRect b={0}; if(!cp_rect(win,"bounds",&b)) return false;
    uint64_t edge=cp_alloc_view("UIView",b); r_msg2_main(edge,"setUserInteractionEnabled:",0,0,0,0);
    double alpha=(state==2||state==3)?0.95:0.0; uint64_t color=cp_color(0.15,1.0,0.42,alpha);
    cp_round(edge,28.0,(double)gChargeThickness,color); r_msg2_main(win,"addSubview:",edge,0,0,0); gCPViews[CommunityPortChargeFX]=edge;
    log_user("[CHARGEFX][APPLY] batteryState=%llu charging=%d thickness=%d visibleAlpha=%.2f passthrough=1.\n",state,(state==2||state==3),gChargeThickness,alpha);
    gChargeLastState = state;
    return true;
}

static bool cp_apply_rotatepro(void)
{
    uint64_t deviceClass=r_class("UIDevice"), device=r_is_objc_ptr(deviceClass)?r_msg2_main(deviceClass,"currentDevice",0,0,0,0):0;
    uint64_t inv=cp_invocation_int(device,"setOrientation:",3);
    uint64_t win=cp_window(); if(!r_is_objc_ptr(win)||!r_is_objc_ptr(inv)) return false;
    uint64_t button=cp_button(win,"Rotate",(CPRect){330,110,54,44},inv); gCPViews[CommunityPortRotatePro]=button;
    log_user("[ROTATEPRO][APPLY] floatingButton=1 requestedOrientation=landscapeRight selectorAvailable=1.\n"); return true;
}

static bool cp_apply_keepeye(void)
{
    uint64_t win=cp_window(); CPRect b={0}; if(!cp_rect(win,"bounds",&b)) return false;
    uint64_t deviceClass=r_class("UIDevice"), device=r_is_objc_ptr(deviceClass)?r_msg2_main(deviceClass,"currentDevice",0,0,0,0):0;
    r_msg2_main(device,"setBatteryMonitoringEnabled:",1,0,0,0);
    uint64_t batteryState=r_msg2_main(device,"batteryState",0,0,0,0);
    uint64_t processClass=r_class("NSProcessInfo"), process=r_is_objc_ptr(processClass)?r_msg2_main(processClass,"processInfo",0,0,0,0):0;
    uint64_t cores=r_is_objc_ptr(process)?r_msg2_main(process,"activeProcessorCount",0,0,0,0):0;
    const char *batteryText=(batteryState==2)?"charging":((batteryState==3)?"full":((batteryState==1)?"battery":"unknown"));
    char text[160]; snprintf(text,sizeof(text),"CPU %llu cores   BAT %s   RC live",cores,batteryText);
    uint64_t hud=cp_alloc_view("UIView",(CPRect){18,(double)gHUDYOffset,b.width-36,34}); r_msg2_main(hud,"setBackgroundColor:",cp_color(0.03,0.04,0.06,0.82),0,0,0); cp_round(hud,12,0.5,cp_color(0.2,0.7,1,0.5));
    cp_label(hud,text,(CPRect){10,5,b.width-56,24},12); r_msg2_main(hud,"setUserInteractionEnabled:",0,0,0,0); r_msg2_main(win,"addSubview:",hud,0,0,0); gCPViews[CommunityPortKeepEye]=hud;
    log_user("[KEEPEYE][APPLY] activeCores=%llu batteryState=%llu(%s) y=%d refresh=visual-loop.\n",cores,batteryState,batteryText,gHUDYOffset); return true;
}

static bool cp_apply_lastlook(void)
{
    uint64_t viewClass=r_class("UIView"), views[1024]={0}; int count=r_is_objc_ptr(viewClass)?sb_collect_views_in_windows(viewClass,views,1024):0;
    gLastLookCount=0; double alpha=(double)gLastLookAlpha/100.0; CPTransform t={0.96,0,0,0.96,0,0};
    for(int i=0;i<count&&gLastLookCount<256;i++){char name[160]={0};if(!cp_class_name(views[i],name,sizeof(name)))continue;if(!strstr(name,"Notification")&&!strstr(name,"ShortLook")&&!strstr(name,"Platter"))continue;gLastLookViews[gLastLookCount++]=views[i];r_msg2_main_raw(views[i],"setAlpha:",&alpha,sizeof(alpha),NULL,0,NULL,0,NULL,0);if(r_responds_main(views[i],"setTransform:"))r_msg2_main_raw(views[i],"setTransform:",&t,sizeof(t),NULL,0,NULL,0,NULL,0);cp_round(views[i],18,1,cp_color(1,1,1,0.16));}
    if(gLastLookLastReported!=gLastLookCount){log_user("[LASTLOOK][APPLY] scanned=%d notificationViews=%d opacity=%d%% compactScale=96%% oledStyle=1.\n",count,gLastLookCount,gLastLookAlpha);gLastLookLastReported=gLastLookCount;}return gLastLookCount>0;
}

void communityports_configure(int dockVisibleIcons, int barThickness, int profileBrightnessPercent, int chargeThickness, int hudYOffset, int lastLookAlphaPercent)
{
    gDockVisibleIcons=fmax(3,fmin(8,dockVisibleIcons)); gBarThickness=fmax(1,fmin(10,barThickness));
    gProfileBrightness=fmax(20,fmin(100,profileBrightnessPercent)); gChargeThickness=fmax(1,fmin(14,chargeThickness));
    gHUDYOffset=fmax(28,fmin(220,hudYOffset)); gLastLookAlpha=fmax(20,fmin(100,lastLookAlphaPercent));
    log_user("[COMMUNITYPORTS][CONFIG] dockVisible=%d barThickness=%d defaultBrightness=%d%% chargeThickness=%d hudY=%d lastLookAlpha=%d%%.\n",gDockVisibleIcons,gBarThickness,gProfileBrightness,gChargeThickness,gHUDYOffset,gLastLookAlpha);
}

bool communityports_apply(CommunityPort port)
{
    if (port<0||port>=CommunityPortCount) return false;
    if (port!=CommunityPortScrollingDock && port!=CommunityPortFlow && port!=CommunityPortAppProfiles && port!=CommunityPortChargeFX && port!=CommunityPortLastLook && r_is_objc_ptr(gCPViews[port])) communityports_stop(port);
    switch(port){case CommunityPortScrollingDock:return cp_apply_scrolling_dock();case CommunityPortNiuBiBar:return cp_apply_niubibar();case CommunityPortVolSkip:return cp_apply_volskip();case CommunityPortFlow:return cp_apply_flow();case CommunityPortAppProfiles:return cp_apply_app_profiles();case CommunityPortChargeFX:return cp_apply_chargefx();case CommunityPortRotatePro:return cp_apply_rotatepro();case CommunityPortKeepEye:return cp_apply_keepeye();case CommunityPortLastLook:return cp_apply_lastlook();default:return false;}
}

bool communityports_stop(CommunityPort port)
{
    if(port<0||port>=CommunityPortCount)return false;
    if(port==CommunityPortScrollingDock){for(int i=0;i<gDockIconCount;i++){if(r_is_objc_ptr(gDockIcons[i])&&r_is_objc_ptr(gDockParents[i])){r_msg2_main(gDockParents[i],"addSubview:",gDockIcons[i],0,0,0);cp_set_rect(gDockIcons[i],gDockFrames[i]);}}memset(gDockIcons,0,sizeof(gDockIcons));memset(gDockParents,0,sizeof(gDockParents));memset(gDockFrames,0,sizeof(gDockFrames));gDockIconCount=0;}
    if(port==CommunityPortFlow){CPTransform id={1,0,0,1,0,0};for(int i=0;i<gFlowCount;i++){if(r_is_objc_ptr(gFlowViews[i])){r_msg2_main_raw(gFlowViews[i],"setTransform:",&id,sizeof(id),NULL,0,NULL,0,NULL,0);cp_round(gFlowViews[i],0,0,0);}}memset(gFlowViews,0,sizeof(gFlowViews));gFlowCount=0;}
    if(port==CommunityPortLastLook){CPTransform id={1,0,0,1,0,0};double a=1;for(int i=0;i<gLastLookCount;i++){if(r_is_objc_ptr(gLastLookViews[i])){r_msg2_main_raw(gLastLookViews[i],"setAlpha:",&a,sizeof(a),NULL,0,NULL,0,NULL,0);r_msg2_main_raw(gLastLookViews[i],"setTransform:",&id,sizeof(id),NULL,0,NULL,0,NULL,0);cp_round(gLastLookViews[i],0,0,0);}}memset(gLastLookViews,0,sizeof(gLastLookViews));gLastLookCount=0;}
    if(r_is_objc_ptr(gCPViews[port]))r_msg2_main(gCPViews[port],"removeFromSuperview",0,0,0,0);gCPViews[port]=0;
    log_user("[COMMUNITYPORTS][STOP] port=%d restored=1 overlayRemoved=1.\n",port);return true;
}

bool communityports_stop_all(void){for(int i=0;i<CommunityPortCount;i++)communityports_stop((CommunityPort)i);return true;}
void communityports_forget_remote_state(void){memset(gCPViews,0,sizeof(gCPViews));memset(gDockIcons,0,sizeof(gDockIcons));memset(gDockParents,0,sizeof(gDockParents));memset(gDockFrames,0,sizeof(gDockFrames));memset(gFlowViews,0,sizeof(gFlowViews));memset(gLastLookViews,0,sizeof(gLastLookViews));memset(gProfileLastBundle,0,sizeof(gProfileLastBundle));gDockIconCount=gFlowCount=gLastLookCount=0;gFlowLastReported=gLastLookLastReported=-1;gChargeLastState=UINT64_MAX;}
