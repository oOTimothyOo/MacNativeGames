// The on-disk library: catalog, per-title saves and backups, per-app launch options
// and finished session records. Holds no mutable state, so any queue can call it, but
// backup, restore and listing backups hash files and belong off the main thread.
#import "NPGame.h"

NS_ASSUME_NONNULL_BEGIN

// Completed snapshots kept per title; older ones are deleted after each backup.
FOUNDATION_EXPORT const NSUInteger NPMaximumBackups;

@interface NPBackup : NSObject
@property (readonly) NSURL *url;
@property (readonly, copy) NSString *label;
@property (readonly) NSDate *created;
// Relative file path to SHA-256. Hashes only, never save contents.
@property (readonly, copy) NSDictionary<NSString *, NSString *> *files;
@end

// Launch preferences for one installed app.
@interface NPLaunchOptions : NSObject
@property BOOL fullscreen;
@property BOOL metalHUD;
@property BOOL recordNextSession;
@end

// Frame timings of one recorded session. Includes loading and transitions.
@interface NPFrameSummary : NSObject
@property (readonly) NSUInteger frames;
@property (readonly) NSUInteger framesOver50ms;
@property (readonly) double medianMilliseconds;
@property (readonly) double p95Milliseconds;
@property (readonly) double p99Milliseconds;
@end

@interface NPStore : NSObject

@property (readonly) NSURL *root;
@property (readonly) NSURL *home;

- (nullable instancetype)initWithRoot:(NSURL *)root home:(NSURL *)home NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Catalog. A failed batch leaves it unchanged; removal keeps the app, saves and backups.
- (NSArray<NPGame *> *)games;
- (nullable NPGame *)importApp:(NSURL *)app error:(NSError **)error;
- (nullable NSArray<NPGame *> *)importApps:(NSArray<NSURL *> *)apps error:(NSError **)error;
- (BOOL)removeGame:(NPGame *)game error:(NSError **)error;

// Saves belong to a title, so separate builds of one title share progress.
- (NSURL *)stateURLForTitle:(NSString *)titleID;
- (NSURL *)backupRootForTitle:(NSString *)titleID;
- (NSArray<NPBackup *> *)backupsForTitle:(NSString *)titleID;
- (nullable NPBackup *)backupTitle:(NSString *)titleID label:(NSString *)label error:(NSError **)error;
// Validates the snapshot from disk, stages it, backs up the current state, then swaps
// it in and rolls back on a filesystem failure. Rejects a backup of another title.
- (BOOL)restoreBackupAtURL:(NSURL *)url title:(NSString *)titleID error:(NSError **)error;

- (NPLaunchOptions *)optionsForGame:(NPGame *)game;
- (BOOL)setOptions:(NPLaunchOptions *)options forGame:(NPGame *)game error:(NSError **)error;

// Whether any native game is running, in this library or not.
- (BOOL)gameIsRunning;

// Session records. Every session lives in its own directory below `sessionsURL`.
- (NSURL *)sessionsURL;
- (nullable NPFrameSummary *)latestFrameSummaryForGame:(NPGame *)game;
// Keeps 20 finished sessions and 3 raw recordings up to 256 MB. Never touches
// unrecognized directories or a session that has not finished.
- (void)pruneSessions;

// Overridable so tests can inject a failure in the middle of a restore.
- (BOOL)move:(NSURL *)source to:(NSURL *)destination error:(NSError **)error;

@end

// Summarizes `frames.tsv` into `summary.json` in the session directory. Nil without frames.
FOUNDATION_EXPORT NSDictionary *_Nullable NPSummarizeFrames(NSURL *session);

NS_ASSUME_NONNULL_END
