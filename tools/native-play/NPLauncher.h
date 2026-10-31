// Starts a verified game under its restriction profile and records the session.
#import "NPStore.h"

NS_ASSUME_NONNULL_BEGIN

// Launch Services reports that an app ended, but not its exit status.
FOUNDATION_EXPORT const int NPExitStatusUnknown;

// Run inside a game's restriction profile before the game starts. Returns 0, or the first
// check that failed. Reads no private file; only attempts a denied connection.
FOUNDATION_EXPORT int NPSandboxProbe(const char *deniedRead, const char *allowedWrite, const char *deniedWrite);

@interface NPGameSession : NSObject
@property (readonly, getter=isRunning) BOOL running;
@property (readonly) int processIdentifier;
- (void)activate;
- (void)terminate;
@end

@interface NPLauncher : NSObject

// The executable that answers `--sandbox-probe`. Defaults to this process's own.
@property (copy) NSURL *probeExecutable;

- (instancetype)initWithStore:(NPStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSString *)sandboxProfileForTitle:(NSString *)titleID session:(NSURL *)session;
- (NSDictionary<NSString *, NSString *> *)environmentForGame:(NPGame *)game session:(NSURL *)session controllerSetup:(BOOL)controllerSetup;

// Verifies the app, backs up its progress, checks the profile, then starts the game.
// Blocks while it does that, so call it off the main thread. `completion` runs once
// on a background queue when the game ends; it gets the exit status when known.
- (nullable NPGameSession *)launchGame:(NPGame *)game
                       controllerSetup:(BOOL)controllerSetup
                            completion:(void (^)(int status, NSURL *session))completion
                                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
