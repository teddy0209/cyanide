//
//  sb_walk.m
//  Lifted verbatim from darksword_layout.m's rc_collect_list_views /
//  rc_collect_from_windows so themer.m and any future tweak can share them
//  without duplicating the BFS.
//

#import "sb_walk.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../VPhoneDebug.h"
#import "../LogTextView.h"

#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

#define SB_CC_PROPERTY_CAP 2048
#define SB_CC_OWNER_CAP 8
#define SB_CC_VALUE_CAP 128

typedef enum { SBCCValueBytes = 1, SBCCValueObject = 2, SBCCValueBool = 3 } SBCCValueType;
typedef struct {
    bool active;
    char owner[40];
    uint64_t sequence;
    uint64_t objectValue;
    uint8_t bytes[SB_CC_VALUE_CAP];
} SBCCOwnerValue;
typedef struct {
    bool active;
    uint64_t object;
    char getter[64];
    char setter[64];
    SBCCValueType type;
    size_t valueSize;
    uint64_t originalObject;
    uint8_t originalBytes[SB_CC_VALUE_CAP];
    SBCCOwnerValue owners[SB_CC_OWNER_CAP];
} SBCCProperty;

static SBCCProperty gSBCCProperties[SB_CC_PROPERTY_CAP];
static uint64_t gSBCCSequence = 1;
static int gSBCCFailureLogs = 0;

static void sb_cc_apply_property(SBCCProperty *property)
{
    if (!property || !property->active || !r_is_objc_ptr(property->object)) return;
    SBCCOwnerValue *winner = NULL;
    for (int i = 0; i < SB_CC_OWNER_CAP; i++)
        if (property->owners[i].active && (!winner || property->owners[i].sequence > winner->sequence))
            winner = &property->owners[i];
    if (property->type == SBCCValueObject) {
        uint64_t value = winner ? winner->objectValue : property->originalObject;
        r_msg2_main(property->object, property->setter, value, 0, 0, 0);
    } else if (property->type == SBCCValueBool) {
        uint64_t value = winner ? winner->objectValue : property->originalObject;
        r_msg2_main(property->object, property->setter, value ? 1 : 0, 0, 0, 0);
    } else {
        const void *value = winner ? winner->bytes : property->originalBytes;
        r_msg2_main_raw(property->object, property->setter,
                        value, property->valueSize, NULL, 0, NULL, 0, NULL, 0);
    }
}

static SBCCProperty *sb_cc_property(const char *owner, uint64_t object,
                                    const char *getter, const char *setter,
                                    SBCCValueType type, size_t valueSize)
{
    if (!owner || !owner[0] || !r_is_objc_ptr(object) || !getter || !setter ||
        valueSize > SB_CC_VALUE_CAP) return NULL;
    SBCCProperty *freeSlot = NULL;
    for (int i = 0; i < SB_CC_PROPERTY_CAP; i++) {
        SBCCProperty *p = &gSBCCProperties[i];
        if (!p->active) { if (!freeSlot) freeSlot = p; continue; }
        if (p->object == object && p->type == type && strcmp(p->setter, setter) == 0) {
            if (p->valueSize == valueSize && strcmp(p->getter, getter) == 0) return p;
            if (gSBCCFailureLogs++ < 12)
                log_user("[PROPERTY-COORDINATOR][SIGNATURE-MISMATCH] owner=%s object=0x%llx setter=%s existingGetter=%s requestedGetter=%s existingBytes=%lu requestedBytes=%lu result=rejected.\n",
                         owner, object, setter, p->getter, getter,
                         (unsigned long)p->valueSize, (unsigned long)valueSize);
            return NULL;
        }
    }
    if (!freeSlot) {
        if (gSBCCFailureLogs++ < 12)
            log_user("[PROPERTY-COORDINATOR][CAPACITY] owner=%s object=0x%llx setter=%s cap=%d result=rejected.\n",
                     owner, object, setter, SB_CC_PROPERTY_CAP);
        return NULL;
    }
    memset(freeSlot, 0, sizeof(*freeSlot));
    freeSlot->active = true;
    freeSlot->object = object;
    // Keep the mutation target alive while any tweak owns an override. UIKit
    // can otherwise tear down a page/window and leave a cached remote pointer
    // that still looks address-like but is no longer safe to message.
    r_msg2_main(object, "retain", 0, 0, 0, 0);
    freeSlot->type = type;
    freeSlot->valueSize = valueSize;
    strlcpy(freeSlot->getter, getter, sizeof(freeSlot->getter));
    strlcpy(freeSlot->setter, setter, sizeof(freeSlot->setter));
    if (type == SBCCValueObject) {
        freeSlot->originalObject = r_msg2_main(object, getter, 0, 0, 0, 0);
        if (r_is_objc_ptr(freeSlot->originalObject))
            r_msg2_main(freeSlot->originalObject, "retain", 0, 0, 0, 0);
    } else if (type == SBCCValueBool) {
        freeSlot->originalObject = r_msg2_main(object, getter, 0, 0, 0, 0) ? 1 : 0;
    } else if (!r_msg2_main_struct_ret(object, getter, freeSlot->originalBytes, valueSize,
                                       NULL, 0, NULL, 0, NULL, 0, NULL, 0)) {
        r_msg2_main(object, "release", 0, 0, 0, 0);
        memset(freeSlot, 0, sizeof(*freeSlot));
        if (gSBCCFailureLogs++ < 12)
            log_user("[PROPERTY-COORDINATOR][CAPTURE-FAIL] owner=%s object=0x%llx getter=%s setter=%s bytes=%lu.\n",
                     owner, object, getter, setter, (unsigned long)valueSize);
        return NULL;
    }
    return freeSlot;
}

static SBCCOwnerValue *sb_cc_owner_slot(SBCCProperty *property, const char *owner)
{
    SBCCOwnerValue *freeSlot = NULL;
    for (int i = 0; i < SB_CC_OWNER_CAP; i++) {
        SBCCOwnerValue *slot = &property->owners[i];
        if (slot->active && strcmp(slot->owner, owner) == 0) return slot;
        if (!slot->active && !freeSlot) freeSlot = slot;
    }
    if (!freeSlot) {
        if (gSBCCFailureLogs++ < 12)
            log_user("[PROPERTY-COORDINATOR][OWNER-CAPACITY] owner=%s object=0x%llx setter=%s ownerCap=%d.\n",
                     owner, property->object, property->setter, SB_CC_OWNER_CAP);
        return NULL;
    }
    memset(freeSlot, 0, sizeof(*freeSlot));
    freeSlot->active = true;
    strlcpy(freeSlot->owner, owner, sizeof(freeSlot->owner));
    return freeSlot;
}

bool sb_cc_override_object(const char *owner, uint64_t object,
                           const char *getter, const char *setter, uint64_t value)
{
    SBCCProperty *p = sb_cc_property(owner, object, getter, setter, SBCCValueObject, sizeof(uint64_t));
    SBCCOwnerValue *slot = p ? sb_cc_owner_slot(p, owner) : NULL;
    if (!slot) return false;
    if (slot->objectValue != value) {
        if (r_is_objc_ptr(value)) r_msg2_main(value, "retain", 0, 0, 0, 0);
        if (r_is_objc_ptr(slot->objectValue)) r_msg2_main(slot->objectValue, "release", 0, 0, 0, 0);
    }
    slot->objectValue = value;
    slot->sequence = gSBCCSequence++;
    sb_cc_apply_property(p);
    return true;
}

bool sb_cc_override_bytes(const char *owner, uint64_t object,
                          const char *getter, const char *setter,
                          const void *value, size_t valueSize)
{
    if (!value || valueSize == 0) return false;
    SBCCProperty *p = sb_cc_property(owner, object, getter, setter, SBCCValueBytes, valueSize);
    SBCCOwnerValue *slot = p ? sb_cc_owner_slot(p, owner) : NULL;
    if (!slot) return false;
    memcpy(slot->bytes, value, valueSize);
    slot->sequence = gSBCCSequence++;
    sb_cc_apply_property(p);
    return true;
}

bool sb_cc_override_bool(const char *owner, uint64_t object,
                         const char *getter, const char *setter, bool value)
{
    SBCCProperty *p = sb_cc_property(owner, object, getter, setter, SBCCValueBool, sizeof(uint64_t));
    SBCCOwnerValue *slot = p ? sb_cc_owner_slot(p, owner) : NULL;
    if (!slot) return false;
    slot->objectValue = value ? 1 : 0;
    slot->sequence = gSBCCSequence++;
    sb_cc_apply_property(p);
    return true;
}

int sb_cc_restore_owner(const char *owner)
{
    if (!owner || !owner[0]) return 0;
    int restored = 0;
    for (int i = 0; i < SB_CC_PROPERTY_CAP; i++) {
        SBCCProperty *p = &gSBCCProperties[i];
        if (!p->active) continue;
        bool removed = false, hasOwners = false;
        uint64_t removedObject = 0;
        for (int j = 0; j < SB_CC_OWNER_CAP; j++) {
            SBCCOwnerValue *slot = &p->owners[j];
            if (slot->active && strcmp(slot->owner, owner) == 0) {
                removedObject = slot->objectValue;
                memset(slot, 0, sizeof(*slot));
                removed = true;
            }
            if (slot->active) hasOwners = true;
        }
        if (!removed) continue;
        sb_cc_apply_property(p);
        if (p->type == SBCCValueObject && r_is_objc_ptr(removedObject))
            r_msg2_main(removedObject, "release", 0, 0, 0, 0);
        restored++;
        if (!hasOwners) {
            if (p->type == SBCCValueObject && r_is_objc_ptr(p->originalObject))
                r_msg2_main(p->originalObject, "release", 0, 0, 0, 0);
            r_msg2_main(p->object, "release", 0, 0, 0, 0);
            memset(p, 0, sizeof(*p));
        }
    }
    if (restored > 0)
        log_user("[PROPERTY-COORDINATOR][RESTORE] owner=%s exactProperties=%d remainingOwnersPreserved=1.\n",
                 owner, restored);
    return restored;
}

void sb_cc_forget_owner(const char *owner)
{
    if (!owner || !owner[0]) return;
    int forgotten = 0;
    for (int i = 0; i < SB_CC_PROPERTY_CAP; i++) {
        SBCCProperty *p = &gSBCCProperties[i];
        if (!p->active) continue;
        bool hadOwner = false, hasOwners = false;
        for (int j = 0; j < SB_CC_OWNER_CAP; j++) {
            SBCCOwnerValue *slot = &p->owners[j];
            if (slot->active && strcmp(slot->owner, owner) == 0) {
                memset(slot, 0, sizeof(*slot));
                hadOwner = true;
                forgotten++;
            }
            if (slot->active) hasOwners = true;
        }
        // Forget is used when the remote session may already be invalid. Do
        // not message or release stale remote objects here.
        if (hadOwner && !hasOwners) memset(p, 0, sizeof(*p));
    }
    if (forgotten > 0)
        log_user("[PROPERTY-COORDINATOR][FORGET] owner=%s staleProperties=%d remoteCalls=0.\n",
                 owner, forgotten);
}

void sb_cc_forget_all_overrides(void)
{
    // Used after a RemoteCall session disappears. Do not message or release
    // objects in the old process; all of those pointers are stale by design.
    memset(gSBCCProperties, 0, sizeof(gSBCCProperties));
    gSBCCSequence = 1;
    gSBCCFailureLogs = 0;
}

static uint64_t sw_safe_msg(uint64_t obj, const char *selname,
                            uint64_t a, uint64_t b, uint64_t c, uint64_t d)
{
    if (!obj) return 0;
    uint64_t sel = r_sel(selname);
    uint64_t rs  = r_sel("respondsToSelector:");
    if (!sel || !rs) return 0;
    if (!r_msg(obj, rs, sel, 0, 0, 0)) return 0;
    return r_msg(obj, sel, a, b, c, d);
}

#define CY_VPHONE_BRIDGE_MAGIC 0x43595342u
#define CY_VPHONE_BRIDGE_SOCK "/private/var/mobile/Library/Caches/com.zeroxjf.cyanide.vphone-springboard.sock"

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t op;
    uint64_t addr;
    uint64_t size;
    uint64_t args[8];
    char name[128];
} SBWBridgeReq;

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t status;
    uint64_t result;
    uint64_t extra;
} SBWBridgeResp;

static const char *sbw_class_name_from_ptr(uint64_t klass);

static bool sbw_read_full(int fd, void *buf, size_t len) {
    uint8_t *p = buf;
    while (len) { ssize_t n = read(fd, p, len); if (n <= 0) { if (n < 0 && errno == EINTR) continue; return false; } p += n; len -= n; }
    return true;
}
static bool sbw_write_full(int fd, const void *buf, size_t len) {
    const uint8_t *p = buf;
    while (len) { ssize_t n = write(fd, p, len); if (n <= 0) { if (n < 0 && errno == EINTR) continue; return false; } p += n; len -= n; }
    return true;
}

static int sb_collect_views_via_bridge_root(uint64_t root, const char *className, uint64_t *out, int cap)
{
    if (!root || !className || !className[0]) return 0;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un sun = {0};
    sun.sun_family = AF_UNIX;
    strlcpy(sun.sun_path, CY_VPHONE_BRIDGE_SOCK, sizeof(sun.sun_path));
    if (connect(fd, (struct sockaddr *)&sun, sizeof(sun)) != 0) { close(fd); return -1; }

    SBWBridgeReq req = {0};
    req.magic = CY_VPHONE_BRIDGE_MAGIC;
    req.op = 7;
    req.addr = root;
    req.args[0] = (uint64_t)cap;
    strlcpy(req.name, className, sizeof(req.name));

    if (!sbw_write_full(fd, &req, sizeof(req))) { close(fd); return -1; }

    SBWBridgeResp resp = {0};
    if (!sbw_read_full(fd, &resp, sizeof(resp)) || resp.magic != CY_VPHONE_BRIDGE_MAGIC || resp.status != 0) {
        close(fd); return -1;
    }
    int found = (int)resp.result;
    if (found > cap) found = cap;
    if (found > 0 && resp.extra > 0) {
        size_t readSz = (size_t)(found * sizeof(uint64_t));
        if (readSz > resp.extra) readSz = (size_t)resp.extra;
        if (!sbw_read_full(fd, out, readSz)) { close(fd); return -1; }
    }
    close(fd);
    return found;
}

int sb_collect_views(uint64_t root, uint64_t klass, uint64_t *out, int cap)
{
    if (!root || !klass || cap <= 0) return 0;

    if (remote_call_uses_vphone_bridge()) {
        const char *name = sbw_class_name_from_ptr(klass);
        if (name) {
            int n = sb_collect_views_via_bridge_root(root, name, out, cap);
            if (n >= 0) return n;
        }
    }
    uint64_t selSub  = r_sel("subviews");
    uint64_t selCnt  = r_sel("count");
    uint64_t selObj  = r_sel("objectAtIndex:");
    uint64_t selKind = r_sel("isKindOfClass:");

    enum { QMAX = 4096 };
    static uint64_t q[QMAX];
    int head = 0, tail = 0, found = 0, visited = 0;
    q[tail++] = root;
    while (head < tail && visited < QMAX) {
        uint64_t v = q[head++];
        visited++;
        if (!v) continue;
        if (r_msg(v, selKind, klass, 0, 0, 0)) {
            if (found < cap) out[found++] = v;
            continue;
        }
        uint64_t subs = r_msg(v, selSub, 0, 0, 0, 0);
        if (!subs) continue;
        uint64_t cn = r_msg(subs, selCnt, 0, 0, 0, 0);
        if (cn > 256) cn = 256;
        for (uint64_t i = 0; i < cn && tail < QMAX; i++) {
            uint64_t c = r_msg(subs, selObj, i, 0, 0, 0);
            if (c) q[tail++] = c;
        }
    }
    return found;
}

static int sb_collect_views_via_bridge(const char *className, uint64_t *out, int cap)
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un sun = {0};
    sun.sun_family = AF_UNIX;
    strlcpy(sun.sun_path, CY_VPHONE_BRIDGE_SOCK, sizeof(sun.sun_path));
    if (connect(fd, (struct sockaddr *)&sun, sizeof(sun)) != 0) { close(fd); return -1; }

    SBWBridgeReq req = {0};
    req.magic = CY_VPHONE_BRIDGE_MAGIC;
    req.op = 6;
    req.args[0] = (uint64_t)cap;
    strlcpy(req.name, className, sizeof(req.name));

    if (!sbw_write_full(fd, &req, sizeof(req))) { close(fd); return -1; }

    SBWBridgeResp resp = {0};
    if (!sbw_read_full(fd, &resp, sizeof(resp)) || resp.magic != CY_VPHONE_BRIDGE_MAGIC || resp.status != 0) {
        close(fd);
        return -1;
    }

    int found = (int)resp.result;
    if (found > cap) found = cap;
    if (found > 0 && resp.extra > 0) {
        size_t readSz = (size_t)(found * sizeof(uint64_t));
        if (readSz > resp.extra) readSz = (size_t)resp.extra;
        if (!sbw_read_full(fd, out, readSz)) { close(fd); return -1; }
    }
    close(fd);
    return found;
}

int sb_collect_views_in_windows_by_name(const char *className, uint64_t *out, int cap)
{
    if (!className || !className[0]) return 0;
    int n = sb_collect_views_via_bridge(className, out, cap);
    if (n < 0) {
        printf("[SB_WALK] vphone bridge sb_collect_views failed for %s\n", className);
    }
    if (n >= 0)
        printf("[SB_WALK] vphone bridge sb_collect_views class=%s found=%d\n", className, n);
    return n;
}

static uint64_t sbw_cached_SBIconListView = 0;
static uint64_t sbw_cached_SBIconView = 0;

static const char *sbw_class_name_from_ptr(uint64_t klass)
{
    if (klass == sbw_cached_SBIconListView && klass) return "SBIconListView";
    if (klass == sbw_cached_SBIconView && klass) return "SBIconView";

    uint64_t p = r_class("SBIconListView");
    if (p) sbw_cached_SBIconListView = p;
    if (p == klass) return "SBIconListView";

    p = r_class("SBIconView");
    if (p) sbw_cached_SBIconView = p;
    if (p == klass) return "SBIconView";

    return NULL;
}

int sb_collect_views_in_windows(uint64_t klass, uint64_t *out, int cap)
{
    if (remote_call_uses_vphone_bridge()) {
        const char *name = sbw_class_name_from_ptr(klass);
        if (name) {
            int bridged = sb_collect_views_in_windows_by_name(name, out, cap);
            if (bridged >= 0) return bridged;
            printf("[SB_WALK] falling back to generic RemoteCall view walk for %s\n", name);
        }
    }

    uint64_t clsApp = r_class("UIApplication");
    if (!clsApp) return 0;
    uint64_t app = sw_safe_msg(clsApp, "sharedApplication", 0, 0, 0, 0);
    if (!app) return 0;

    int n = 0;
    uint64_t wins = sw_safe_msg(app, "windows", 0, 0, 0, 0);
    if (wins) {
        uint64_t wc = r_msg(wins, r_sel("count"), 0, 0, 0, 0);
        if (wc > 32) wc = 32;
        for (uint64_t i = 0; i < wc && n < cap; i++) {
            uint64_t w = r_msg(wins, r_sel("objectAtIndex:"), i, 0, 0, 0);
            if (w) n += sb_collect_views(w, klass, out + n, cap - n);
        }
    }
    if (n == 0) {
        uint64_t kw = sw_safe_msg(app, "keyWindow", 0, 0, 0, 0);
        if (kw) n += sb_collect_views(kw, klass, out + n, cap - n);
    }
    return n;
}

int sb_collect_windows(uint64_t *out, int cap)
{
    if (!out || cap <= 0) return 0;
    uint64_t clsApp = r_class("UIApplication");
    if (!clsApp) return 0;
    uint64_t app = sw_safe_msg(clsApp, "sharedApplication", 0, 0, 0, 0);
    if (!app) return 0;

    int n = 0;
    uint64_t wins = sw_safe_msg(app, "windows", 0, 0, 0, 0);
    if (wins) {
        uint64_t count = r_msg(wins, r_sel("count"), 0, 0, 0, 0);
        if (count > (uint64_t)cap) count = (uint64_t)cap;
        for (uint64_t i = 0; i < count; i++) {
            uint64_t win = r_msg(wins, r_sel("objectAtIndex:"), i, 0, 0, 0);
            if (r_is_objc_ptr(win)) out[n++] = win;
        }
    }
    if (n == 0) {
        uint64_t key = sw_safe_msg(app, "keyWindow", 0, 0, 0, 0);
        if (r_is_objc_ptr(key)) out[n++] = key;
    }
    return n;
}

uint64_t sb_frontmost_window(void)
{
    uint64_t windows[64] = {0};
    int count = sb_collect_windows(windows, 64);
    for (int i = count - 1; i >= 0; i--) {
        uint64_t hidden = sw_safe_msg(windows[i], "isHidden", 0, 0, 0, 0);
        if (!(hidden & 0xff)) return windows[i];
    }
    for (int i = 0; i < count; i++) {
        uint64_t isKey = sw_safe_msg(windows[i], "isKeyWindow", 0, 0, 0, 0);
        if (isKey & 0xff) return windows[i];
    }
    return count > 0 ? windows[count - 1] : 0;
}

static bool sbw_object_name_contains_cc(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return false;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    uint64_t name = r_is_objc_ptr(cls)
        ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!name) return false;
    char buffer[192] = {0};
    remote_read(name, buffer, sizeof(buffer) - 1);
    return strstr(buffer, "ControlCenter") != NULL || strstr(buffer, "CCUI") != NULL;
}

static bool sbw_window_hosts_control_center(uint64_t window)
{
    if (!r_is_objc_ptr(window)) return false;
    if (sbw_object_name_contains_cc(window)) return true;

    uint64_t controller = sw_safe_msg(window, "rootViewController", 0, 0, 0, 0);
    if (sbw_object_name_contains_cc(controller)) return true;
    uint64_t rootView = sw_safe_msg(controller, "view", 0, 0, 0, 0);
    if (sbw_object_name_contains_cc(rootView)) return true;

    const char *rootClasses[] = {
        "CCUIModularControlCenterOverlayView",
        "CCUIModularControlCenterView",
        "CCUIControlCenterView",
        "CCUIModuleContainerView",
        "CCUIContentModuleContainerView",
        NULL,
    };
    uint64_t sample[1] = {0};
    for (int i = 0; rootClasses[i]; i++) {
        uint64_t cls = r_class(rootClasses[i]);
        if (r_is_objc_ptr(cls) && sb_collect_views(window, cls, sample, 1) > 0) return true;
    }
    return false;
}

int sb_collect_control_center_windows(uint64_t *out, int cap)
{
    if (!out || cap <= 0) return 0;
    uint64_t windows[64] = {0};
    int windowCount = sb_collect_windows(windows, 64);
    int found = 0;
    for (int i = 0; i < windowCount && found < cap; i++) {
        if (sbw_window_hosts_control_center(windows[i])) out[found++] = windows[i];
    }
    static int lastFound = -1;
    if (lastFound != found) {
        printf("[SB_WALK][CC] scannedWindows=%d matchedControlCenterWindows=%d state=changed\n",
               windowCount, found);
        lastFound = found;
    }
    return found;
}

uint64_t sb_control_center_window(void)
{
    uint64_t windows[16] = {0};
    int count = sb_collect_control_center_windows(windows, 16);
    for (int i = count - 1; i >= 0; i--) {
        uint64_t hidden = sw_safe_msg(windows[i], "isHidden", 0, 0, 0, 0);
        double alpha = 1.0;
        if (r_responds_main(windows[i], "alpha")) {
            r_msg2_main_struct_ret(windows[i], "alpha", &alpha, sizeof(alpha),
                                   NULL, 0, NULL, 0, NULL, 0, NULL, 0);
        }
        if (!(hidden & 0xff) && alpha > 0.01) return windows[i];
    }
    return count > 0 ? windows[count - 1] : 0;
}
