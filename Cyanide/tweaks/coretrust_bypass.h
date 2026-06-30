#ifndef coretrust_bypass_h
#define coretrust_bypass_h

#include <stdint.h>
#include <stdbool.h>

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

// ── Test binary (pre-created at load time, before exploit) ──────────────
// Returns path to the pre-created test binary, or NULL if creation failed.
const char *coretrust_get_test_binary(void);

// ── Unified entry point ─────────────────────────────────────────────────
// Run all strategies in sequence; returns true if unsigned execution is
// verified.

bool coretrust_bypass_all(void);

#endif
