#ifndef coretrust_bypass_h
#define coretrust_bypass_h

#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>

extern char g_crash_log_path[4096];

#define CORETRUST_BYPASS_EXPLOIT_NAME    "COREbreak"
#define CORETRUST_BYPASS_EXPLOIT_VERSION "1.0"

// ── Strategy 1: amfid NOP patch ──────────────────────────────────────────
// Find amfid's `cbz w22, ...` instruction at file offset 0x2ec8 and NOP it.
// This makes MISValidateSignatureAndCopyInfo always return success.
// Returns true if the patch was applied.

bool coretrust_amfid_nop_patch(void);

// ── Strategy 2: AMFI enforcement flags ──────────────────────────────────
// Zero AMFI enforcement booleans in kernel memory (cs_enforcement_disable
// and up to 10 other flags in AMFI __DATA). Requires known kernel offsets.
// Returns true if any flag was successfully zeroed.

bool coretrust_amfi_enforcement_flags_zero(void);

// ── Strategy 3: amfid kill + execution race ────────────────────────────
// Kill amfid and immediately attempt to spawn a test binary before the
// watchdog respawns it. Returns true if the binary executed.

bool coretrust_kill_amfid_race(const char *testBinPath);

// ── Test binary ─────────────────────────────────────────────────────────
// Must be called BEFORE the kernel exploit corrupts socket structures.
// Returns path (caller must free) or NULL on failure.
const char *coretrust_write_test_binary(void);

// ── Strategy 6: TXM bypass (enhanced) ───────────────────────────────────
// Comprehensive IOKit brute-force: tries user client types 0-7, selectors
// 0-63 with IOConnectCallStructMethod, IOConnectCallMethod, and
// IOConnectTrap to find the TXM trust cache load selector.

bool coretrust_txm_bypass(void);

// ── Strategy 7: Kernel trust cache injection ────────────────────────────
// Scan kernel memory for trust cache structures via kread, then directly
// add our CDHash entry to the kernel's trust cache linked list.  Avoids
// IOKit entirely.

bool coretrust_kernel_tc_inject(void);

// ── Strategy 8: remote_call via Mach API (SPTM-safe) ────────────────────
// Create a thread in the target process using thread_create_running and
// mach_vm_write instead of kwrite-to-thread-struct.  Avoids all SPTM-
// protected memory.

bool coretrust_remotecall_sptm(const char *targetProc);

// ── Unified entry point ─────────────────────────────────────────────────
// Run all strategies in sequence; returns true if unsigned execution is
// verified.

bool coretrust_bypass_all(void);

#endif
