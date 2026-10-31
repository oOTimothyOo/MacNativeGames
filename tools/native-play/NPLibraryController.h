// The app's state on the main thread, and the work behind every button. Slow work runs
// one job at a time on a background queue. Views refresh on NPLibraryDidChangeNotification.
#import <Foundation/Foundation.h>
#import "NPArtwork.h"
#import "NPLauncher.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const NPLibraryDidChangeNotification;

@interface NPLibraryController : NSObject

@property (readonly) NPStore *store;
@property (readonly) NPArtworkLibrary *artwork;
@property (readonly, copy) NSArray<NPGame *> *games;
@property (nullable, readonly) NPGame *selectedGame;
// The selected title's verified snapshots. Call -loadBackups to fill or refresh them.
@property (readonly, copy) NSArray<NPBackup *> *backups;
@property (readonly) BOOL loadingBackups;
// A background job is running. Actions that change state wait for it to finish.
@property (readonly) BOOL busy;
// A native game is running, whether or not this app started it.
@property (readonly) BOOL gameRunning;
// The game this app started is running.
@property (readonly) BOOL sessionRunning;
// News for the person, empty when there is none. Passing news clears itself.
@property (readonly, copy) NSString *status;
// Shows a failed action to the person using the app.
@property (copy) void (^errorHandler)(NSError *error);

- (instancetype)initWithStore:(NPStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)reload;
- (void)refreshRunningState;
- (void)selectGame:(NPGame *)game;

- (void)addApps:(NSArray<NSURL *> *)urls;
- (void)removeSelectedGame;
- (void)revealSelectedGame;
- (void)setArtworkFromURL:(NSURL *)url;
- (void)resetArtwork;
// Starts the selected game, or brings it forward if it is already running.
- (void)playWithControllerSetup:(BOOL)controllerSetup;

- (void)loadBackups;
- (void)backUp;
- (void)restoreBackup:(NPBackup *)backup;
- (void)revealBackups;

- (NPLaunchOptions *)options;
- (void)updateOptions:(void (NS_NOESCAPE ^)(NPLaunchOptions *options))change;
- (nullable NPFrameSummary *)latestFrameSummary;

@end

NS_ASSUME_NONNULL_END
