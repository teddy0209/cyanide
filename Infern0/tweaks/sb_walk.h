//
//  sb_walk.h
//  RemoteCall view-tree helpers shared between tweaks that need to find
//  SpringBoard views of a particular class (SBIconListView, SBIconView, etc).
//

#ifndef sb_walk_h
#define sb_walk_h

#import <stdint.h>
#import <stdbool.h>
#import <stddef.h>

// BFS from `root` collecting subviews that are instances of `klass`.
// Matched views are NOT recursed into. Returns the count written to `out`,
// capped at `cap`. Not reentrant — uses a static BFS queue. Callers are
// already serialized under the settings RemoteCall lock.
int sb_collect_views(uint64_t root, uint64_t klass, uint64_t *out, int cap);

// Walks every UIApplication window (falls back to keyWindow if -windows
// returns empty) and collects views of `klass` across all of them.
int sb_collect_views_in_windows(uint64_t klass, uint64_t *out, int cap);

// Bridge-only variant: BFS via the vphone bridge using a class name string.
int sb_collect_views_in_windows_by_name(const char *className, uint64_t *out, int cap);

// Collects UIApplication's windows in back-to-front order. This avoids the
// deprecated -keyWindow path, which is commonly nil for SpringBoard scenes.
int sb_collect_windows(uint64_t *out, int cap);

// Returns the key window when one exists, otherwise the frontmost visible
// UIApplication window.
uint64_t sb_frontmost_window(void);

// Finds SpringBoard windows that actually host Control Center. This avoids
// applying CC tweaks to the Home Screen, notification, keyboard, or alert
// window merely because it is frontmost.
int sb_collect_control_center_windows(uint64_t *out, int cap);
uint64_t sb_control_center_window(void);

// Shared live-property coordinator for Control Center tweaks. Each property is
// captured once, can have multiple named owners, and is restored to the next
// active owner's value (or the exact captured value) when an owner stops.
bool sb_cc_override_object(const char *owner, uint64_t object,
                           const char *getter, const char *setter, uint64_t value);
bool sb_cc_override_bytes(const char *owner, uint64_t object,
                          const char *getter, const char *setter,
                          const void *value, size_t valueSize);
bool sb_cc_override_bool(const char *owner, uint64_t object,
                         const char *getter, const char *setter, bool value);
int sb_cc_restore_owner(const char *owner);
void sb_cc_forget_owner(const char *owner);
void sb_cc_forget_all_overrides(void);

#endif /* sb_walk_h */
