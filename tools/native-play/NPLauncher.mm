#import "NPLauncher.h"
#import "NPFoundation.h"
#import <AppKit/AppKit.h>
#include <errno.h>
#include <fcntl.h>
#include <memory>
#include <mutex>
#include <netinet/in.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>

const int NPExitStatusUnknown = -1;

static const int LaunchFailedStatus = 127;
static const int64_t LaunchServicesTimeoutSeconds = 30;

static BOOL IsDenied(int error) {
    return error == EPERM || error == EACCES;
}

int NPSandboxProbe(const char *deniedRead, const char *allowedWrite, const char *deniedWrite) {
    int fd = open(deniedRead, O_RDONLY);
    if (fd >= 0) {
        close(fd);
        return 3;
    }
    if (!IsDenied(errno)) {
        return 4;
    }
    fd = open(deniedWrite, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd >= 0) {
        close(fd);
        unlink(deniedWrite);
        return 5;
    }
    if (!IsDenied(errno)) {
        return 6;
    }
    fd = open(allowedWrite, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) {
        return 7;
    }
    close(fd);
    unlink(allowedWrite);
    int connection = socket(AF_INET, SOCK_STREAM, 0);
    if (connection < 0) {
        return IsDenied(errno) ? 0 : 8;
    }
    struct sockaddr_in loopback = {.sin_len = sizeof loopback, .sin_family = AF_INET, .sin_port = htons(9), .sin_addr = {htonl(INADDR_LOOPBACK)}, .sin_zero = {}};
    int result = connect(connection, (struct sockaddr *)&loopback, sizeof loopback);
    int failure = errno;
    close(connection);
    return result < 0 && IsDenied(failure) ? 0 : 9;
}

static void WriteResult(NSURL *session, int status) {
    NSDictionary *result = @{
        @"status": @(status),
        @"exit_status_known": @(status != NPExitStatusUnknown),
        @"finished": @(NSDate.date.timeIntervalSince1970),
    };
    NPWriteJSON(result, NPChild(session, @"result.json"), nil);
}

@interface NPGameSession ()
@property NSTask *child;
@property NSRunningApplication *application;
@property dispatch_source_t exitMonitor;
@property BOOL ended;
@end

@implementation NPGameSession

- (BOOL)isRunning {
    if (self.ended) {
        return NO;
    }
    return self.child ? self.child.running : !self.application.terminated;
}

- (int)processIdentifier {
    return self.child ? self.child.processIdentifier : self.application.processIdentifier;
}

- (void)activate {
    NSRunningApplication *running = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
    [running activateWithOptions:0];
}

- (void)terminate {
    if (self.child) {
        [self.child terminate];
    } else {
        [self.application terminate];
    }
}

@end

@interface NPLauncher ()
@property (readonly) NPStore *store;
@end

@implementation NPLauncher

- (instancetype)initWithStore:(NPStore *)store {
    if ((self = [super init])) {
        _store = store;
        _probeExecutable = NSBundle.mainBundle.executableURL;
    }
    return self;
}

- (NSURL *)readProbeURL {
    return NPChild(self.store.root, @"probe-denied");
}

- (NSString *)sandboxProfileForTitle:(NSString *)titleID session:(NSURL *)session {
    NSURL *home = self.store.home;
    NSMutableString *profile = [@"(version 1)\n(allow default)\n(deny network*)\n(deny file-write* (require-all\n" mutableCopy];
    for (NSURL *writable in @[[self.store stateURLForTitle:titleID], session]) {
        [profile appendFormat:@" (require-not (subpath %@))\n", NPQuote(NPCanonicalPath(writable))];
    }
    [profile appendString:@" (require-not (literal \"/dev/null\")) (require-not (literal \"/dev/tty\"))))\n(deny file-read*\n"];
    for (NSString *secret in @[@".ssh", @".aws", @".config", @"Documents", @"Downloads", @"Desktop", @"Library/Keychains", @"Library/Mail", @"Library/Safari",
                               @"Library/Application Support/Google", @"Library/Application Support/Firefox",
                               @"JamboreeLab/secrets", @"JamboreeLab/inputs", @"JamboreeLab/deps", @"JamboreeLab/build"]) {
        [profile appendFormat:@" (subpath %@)\n", NPQuote(NPCanonicalPath(NPChild(home, secret)))];
    }
    [profile appendFormat:@" (subpath %@)\n", NPQuote(NPCanonicalPath([self.store backupRootForTitle:titleID]))];
    [profile appendFormat:@" (subpath \"/Volumes\")\n (literal %@))\n", NPQuote(NPCanonicalPath(self.readProbeURL))];
    [profile appendString:@"(deny mach-lookup (global-name \"com.apple.securityd\"))\n"];
    return profile;
}

- (NSDictionary<NSString *, NSString *> *)environmentForGame:(NPGame *)game session:(NSURL *)session controllerSetup:(BOOL)controllerSetup {
    NSURL *state = [self.store stateURLForTitle:game.titleID];
    NPLaunchOptions *options = [self.store optionsForGame:game];
    NSMutableDictionary *environment = [@{
        @"HOME": self.store.home.path,
        @"PATH": @"/usr/bin:/bin:/usr/sbin:/sbin",
        @"LANG": @"en_US.UTF-8",
        @"TMPDIR": [NPChild(session, @"tmp").path stringByAppendingString:@"/"],
        @"CLANG_MODULE_CACHE_PATH": NPChild(state, @"native-play-clang-cache").path,
        @"DM_SCREEN_MATCH": @"0",
        @"DM_BOOTPROF": @"0",
        @"DM_NVN_FRAMES": @"0",
        @"DM_FULLSCREEN": options.fullscreen ? @"1" : @"0",
        @"DM_STATE_DIR": state.path,
        @"DM_SAVE": NPChild(state, @"save").path,
        @"DM_TEMP": NPChild(state, @"temp").path,
    } mutableCopy];
    if (controllerSetup) {
        environment[@"DM_CONTROLLER_SETUP"] = @"1";
    }
    if (options.metalHUD) {
        environment[@"MTL_HUD_ENABLED"] = @"1";
    }
    if (options.recordNextSession) {
        environment[@"DM_NVN_TSV"] = NPChild(session, @"frames.tsv").path;
        environment[@"DM_NVN_TSV_CALLS"] = @"0";
    }
    return environment;
}

// The same signed executable probes the profile without reading a private file or making
// an outbound connection (only a denied loopback socket attempt).
- (BOOL)checkProfile:(NSURL *)profile session:(NSURL *)session error:(NSError **)error {
    NSURL *readProbe = self.readProbeURL;
    [@"Synthetic permission probe" writeToURL:readProbe atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sandbox-exec"];
    task.arguments = @[@"-f", profile.path, self.probeExecutable.path, @"--sandbox-probe", readProbe.path,
                       NPChild(session, @"probe-allowed").path, NPChild(self.store.home, @".native-play-denied-write").path];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:error]) {
        return NO;
    }
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        return NPFail(error, [NSString stringWithFormat:@"The launch restrictions could not be verified (check %d).", task.terminationStatus]);
    }
    return YES;
}

// A normal app launch keeps the game's bundle identity, which macOS requires for Game Mode.
- (NSRunningApplication *)openGame:(NPGame *)game environment:(NSDictionary *)environment error:(NSError **)error {
    NSWorkspaceOpenConfiguration *configuration = NSWorkspaceOpenConfiguration.configuration;
    configuration.environment = environment;
    configuration.createsNewApplicationInstance = YES;
    configuration.allowsRunningApplicationSubstitution = NO;

    dispatch_semaphore_t opened = dispatch_semaphore_create(0);
    NSObject *gate = [NSObject new];
    __block BOOL abandoned = NO;
    __block NSRunningApplication *application = nil;
    __block NSError *failure = nil;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:[NSURL fileURLWithPath:game.path]
                                        configuration:configuration
                                    completionHandler:^(NSRunningApplication *app, NSError *openError) {
        @synchronized (gate) {
            if (abandoned) {
                [app terminate];
            } else {
                application = app;
                failure = openError;
            }
        }
        dispatch_semaphore_signal(opened);
    }];
    if (dispatch_semaphore_wait(opened, dispatch_time(DISPATCH_TIME_NOW, LaunchServicesTimeoutSeconds * (int64_t)NSEC_PER_SEC))) {
        @synchronized (gate) {
            abandoned = YES;
            [application terminate];
        }
        NPFail(error, @"macOS did not finish opening the game. The launch was stopped.");
        return nil;
    }
    if (!application && error) {
        *error = failure;
    }
    return application;
}

- (BOOL)startGame:(NPGame *)game
         inSession:(NPGameSession *)handle
           profile:(NSURL *)profile
       environment:(NSDictionary *)environment
           session:(NSURL *)session
          finished:(void (^)(int))finished
             error:(NSError **)error {
    if (!game.launchesThroughLaunchServices) {
        // Ports without the declared capability keep the direct restricted child process.
        NSURL *logURL = NPChild(session, @"launcher.log");
        [NSFileManager.defaultManager createFileAtPath:logURL.path contents:nil attributes:@{NSFilePosixPermissions: @0600}];
        NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
        if (!log) {
            return NPFail(error, @"Could not create the session log.");
        }
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sandbox-exec"];
        task.arguments = @[@"-f", profile.path, [game.path stringByAppendingPathComponent:game.executable]];
        task.environment = environment;
        task.currentDirectoryURL = [self.store stateURLForTitle:game.titleID];
        task.standardOutput = log;
        task.standardError = log;
        task.terminationHandler = ^(NSTask *child) {
            [log closeFile];
            finished(child.terminationStatus);
        };
        if (![task launchAndReturnError:error]) {
            return NO;
        }
        handle.child = task;
        return YES;
    }

    NSRunningApplication *application = [self openGame:game environment:environment error:error];
    if (!application) {
        return NO;
    }
    handle.application = application;
    pid_t pid = application.processIdentifier;
    dispatch_source_t monitor = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid, DISPATCH_PROC_EXIT, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    if (!monitor) {
        [application terminate];
        return NPFail(error, @"Could not monitor the game; the launch was stopped.");
    }
    handle.exitMonitor = monitor;
    dispatch_source_set_event_handler(monitor, ^{
        handle.ended = YES;
        dispatch_source_cancel(monitor);
        finished(NPExitStatusUnknown);
    });
    dispatch_source_set_cancel_handler(monitor, ^{
        handle.exitMonitor = nil;
    });
    dispatch_resume(monitor);
    // A game that already ended produces no event for a monitor armed after it.
    if (kill(pid, 0) && errno == ESRCH) {
        handle.ended = YES;
        dispatch_source_cancel(monitor);
        finished(NPExitStatusUnknown);
    }
    return YES;
}

- (NPGameSession *)launchGame:(NPGame *)game
              controllerSetup:(BOOL)controllerSetup
                   completion:(void (^)(int, NSURL *))completion
                        error:(NSError **)error {
    NPStore *store = self.store;
    if (store.gameIsRunning) {
        NPFail(error, @"The game is already running. Return to it and press F2 for controllers.");
        return nil;
    }
    NPGame *verified = [game verifiedGameWithError:error];
    if (!verified || ![store backupTitle:verified.titleID label:@"Before play" error:error]) {
        return nil;
    }
    if (store.gameIsRunning) {
        NPFail(error, @"Another game session started. Close it before launching again.");
        return nil;
    }

    NSURL *session = NPChild(store.sessionsURL, NSUUID.UUID.UUIDString);
    if (!NPCreatePrivateDirectory(NPChild(session, @"tmp"), error) || !NPCreatePrivateDirectory([store stateURLForTitle:verified.titleID], error)) {
        return nil;
    }
    NSURL *profile = NPChild(session, @"runtime.sb");
    NSString *profileText = [self sandboxProfileForTitle:verified.titleID session:session];
    if (![profileText writeToURL:profile atomically:YES encoding:NSUTF8StringEncoding error:error] ||
        ![NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:profile.path error:error] ||
        ![self checkProfile:profile session:session error:error]) {
        return nil;
    }

    NSMutableDictionary *environment = [[self environmentForGame:verified session:session controllerSetup:controllerSetup] mutableCopy];
    if (verified.launchesThroughLaunchServices) {
        environment[@"DM_NATIVE_PLAY_POLICY"] = profile.path;
    }
    NPLaunchOptions *options = [store optionsForGame:verified];
    NPWriteJSON(@{
        @"game": verified.titleID,
        @"app_key": verified.key,
        @"started": @(NSDate.date.timeIntervalSince1970),
        @"network_denied": @YES,
        @"hud": @(options.metalHUD),
        @"record": @(options.recordNextSession),
        @"launch_services": @(verified.launchesThroughLaunchServices),
    }, NPChild(session, @"session.json"), nil);

    auto finishOnce = std::make_shared<std::once_flag>();
    void (^finished)(int) = ^(int status) {
        std::call_once(*finishOnce, [&] {
            NPSummarizeFrames(session);
            WriteResult(session, status);
            [store pruneSessions];
            completion(status, session);
        });
    };

    NPGameSession *handle = [NPGameSession new];
    if (![self startGame:verified inSession:handle profile:profile environment:environment session:session finished:finished error:error]) {
        WriteResult(session, LaunchFailedStatus);
        return nil;
    }
    if (options.recordNextSession) {
        options.recordNextSession = NO;
        [store setOptions:options forGame:verified error:nil];
    }
    return handle;
}

@end
