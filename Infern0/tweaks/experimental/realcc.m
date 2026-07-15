#import "realcc.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <errno.h>
#import <stdlib.h>
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>

static bool gRealccWifiDisabled = false;
static bool gRealccBtDisabled = false;
static NSString * const kRealCCWiFiChangedKey = @"RealCCRuntimeWiFiChanged";
static NSString * const kRealCCBluetoothChangedKey = @"RealCCRuntimeBluetoothChanged";

static bool realcc_kill_daemon(const char *daemonName)
{
    if (!daemonName) return false;
    pid_t pid = 0;
    const char *argv[] = { "/usr/bin/killall", daemonName, NULL };
    int ret = posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, NULL);
    if (ret == 0 && pid > 0) {
        int status = 0;
        pid_t waited = 0;
        for (int i = 0; i < 100 && waited == 0; i++) {
            waited = waitpid(pid, &status, WNOHANG);
            if (waited == 0) usleep(20000);
        }
        if (waited == 0) {
            kill(pid, SIGKILL);
            (void)waitpid(pid, &status, 0);
            ret = ETIMEDOUT;
        } else {
            ret = (waited == pid && WIFEXITED(status)) ? WEXITSTATUS(status) : -1;
        }
    }
    printf("[REALCC] killed %s: ret=%d\n", daemonName, ret);
    return ret == 0;
}

static bool realcc_write_plist_bool(NSString *path, NSString *key, BOOL value)
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    // Never manufacture a replacement system preference file. Doing so can
    // silently lose unrelated keys or create it with the wrong ownership.
    if (!plist) {
        printf("[REALCC] refused missing/unreadable plist: %s\n", path.UTF8String);
        return false;
    }
    plist[key] = @(value);
    return [plist writeToFile:path atomically:YES];
}

static bool realcc_read_plist_bool(NSString *path, NSString *key, BOOL *value)
{
    if (!value) return false;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    id raw = plist[key];
    if (![raw respondsToSelector:@selector(boolValue)]) return false;
    *value = [raw boolValue];
    return true;
}

bool realcc_apply(bool disableWifi, bool disableBt)
{
    printf("[REALCC] apply wifi=%d bt=%d\n", disableWifi, disableBt);

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    gRealccWifiDisabled = gRealccWifiDisabled || [defaults boolForKey:kRealCCWiFiChangedKey];
    gRealccBtDisabled = gRealccBtDisabled || [defaults boolForKey:kRealCCBluetoothChangedKey];
    bool requested = disableWifi || disableBt;
    bool allOK = true;

    if (disableWifi) {
        NSString *path = @"/private/var/preferences/SystemConfiguration/com.apple.wifi.plist";
        BOOL wasEnabled = NO;
        BOOL readable = realcc_read_plist_bool(path, @"AllowEnable", &wasEnabled);
        BOOL ok = readable && (!wasEnabled || realcc_write_plist_bool(path, @"AllowEnable", NO));
        if (ok) {
            if (wasEnabled) {
                realcc_kill_daemon("wificond");
                realcc_kill_daemon("WiFiAgent");
                gRealccWifiDisabled = true;
                [defaults setBool:YES forKey:kRealCCWiFiChangedKey];
            }
        }
        allOK &= ok;
        printf("[REALCC] wifi %s\n", ok ? "disabled" : "failed");
    } else if (gRealccWifiDisabled) {
        bool ok = realcc_write_plist_bool(@"/private/var/preferences/SystemConfiguration/com.apple.wifi.plist",
                                          @"AllowEnable", YES);
        if (ok) {
            realcc_kill_daemon("wificond");
            realcc_kill_daemon("WiFiAgent");
            gRealccWifiDisabled = false;
            [defaults setBool:NO forKey:kRealCCWiFiChangedKey];
        }
    }

    if (disableBt) {
        NSString *path = @"/private/var/preferences/SystemConfiguration/com.apple.Bluetooth.plist";
        BOOL wasEnabled = NO;
        BOOL readable = realcc_read_plist_bool(path, @"BluetoothState", &wasEnabled);
        BOOL ok = readable && (!wasEnabled || realcc_write_plist_bool(path, @"BluetoothState", NO));
        if (ok) {
            if (wasEnabled) {
                realcc_kill_daemon("bluetoothd");
                gRealccBtDisabled = true;
                [defaults setBool:YES forKey:kRealCCBluetoothChangedKey];
            }
        }
        allOK &= ok;
        printf("[REALCC] bluetooth %s\n", ok ? "disabled" : "failed");
    } else if (gRealccBtDisabled) {
        bool ok = realcc_write_plist_bool(@"/private/var/preferences/SystemConfiguration/com.apple.Bluetooth.plist",
                                          @"BluetoothState", YES);
        if (ok) {
            realcc_kill_daemon("bluetoothd");
            gRealccBtDisabled = false;
            [defaults setBool:NO forKey:kRealCCBluetoothChangedKey];
        }
    }

    [defaults synchronize];

    return requested && allOK;
}

bool realcc_restore(void)
{
    printf("[REALCC] restore\n");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    gRealccWifiDisabled = gRealccWifiDisabled || [defaults boolForKey:kRealCCWiFiChangedKey];
    gRealccBtDisabled = gRealccBtDisabled || [defaults boolForKey:kRealCCBluetoothChangedKey];

    if (gRealccWifiDisabled) {
        bool ok = realcc_write_plist_bool(@"/private/var/preferences/SystemConfiguration/com.apple.wifi.plist",
                                          @"AllowEnable", YES);
        if (ok) {
            realcc_kill_daemon("wificond");
            realcc_kill_daemon("WiFiAgent");
            gRealccWifiDisabled = false;
            [defaults setBool:NO forKey:kRealCCWiFiChangedKey];
        }
    }

    if (gRealccBtDisabled) {
        bool ok = realcc_write_plist_bool(@"/private/var/preferences/SystemConfiguration/com.apple.Bluetooth.plist",
                                          @"BluetoothState", YES);
        if (ok) {
            realcc_kill_daemon("bluetoothd");
            gRealccBtDisabled = false;
            [defaults setBool:NO forKey:kRealCCBluetoothChangedKey];
        }
    }

    [defaults synchronize];
    return !gRealccWifiDisabled && !gRealccBtDisabled;
}
