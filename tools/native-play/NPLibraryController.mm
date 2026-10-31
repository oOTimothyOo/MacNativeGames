#import "NPLibraryController.h"
#import "NPFoundation.h"
#import <AppKit/AppKit.h>

NSNotificationName const NPLibraryDidChangeNotification = @"NPLibraryDidChangeNotification";

static const NSTimeInterval StatusSeconds = 6;

@interface NPLibraryController ()
@property (readwrite, copy) NSArray<NPGame *> *games;
@property (nullable, readwrite) NPGame *selectedGame;
@property (readwrite, copy) NSArray<NPBackup *> *backups;
@property (readwrite) BOOL loadingBackups;
@property (readwrite) BOOL busy;
@property (readwrite) BOOL gameRunning;
@property (nonatomic, readwrite, copy) NSString *status;
@property (nullable, copy) NSString *backupsTitleID;
@property (readonly) NPLauncher *launcher;
@property (readonly) dispatch_queue_t workQueue;
@property (nullable) NPGameSession *session;
@end

@implementation NPLibraryController

- (instancetype)initWithStore:(NPStore *)store {
    if ((self = [super init])) {
        _store = store;
        _launcher = [[NPLauncher alloc] initWithStore:store];
        _workQueue = dispatch_queue_create("org.macnativegames.native-play.work", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
        _games = @[];
        _backups = @[];
        _status = @"";
        _artwork = [[NPArtworkLibrary alloc] initWithStore:store];
        __weak NPLibraryController *weakSelf = self;
        _artwork.changed = ^{
            [weakSelf changed];
        };
        _errorHandler = ^(NSError *error) {};
    }
    return self;
}

- (BOOL)sessionRunning {
    return self.session.running;
}

- (void)setStatus:(NSString *)status {
    _status = [status copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearStatus) object:nil];
    [self performSelector:@selector(clearStatus) withObject:nil afterDelay:StatusSeconds];
}

- (void)clearStatus {
    // Progress and "playing" stay until they end.
    if (!self.busy && !self.sessionRunning && self.status.length) {
        self.status = @"";
        [self changed];
    }
}

- (void)changed {
    [NSNotificationCenter.defaultCenter postNotificationName:NPLibraryDidChangeNotification object:self];
}

#pragma mark - Library

- (void)reload {
    self.games = self.store.games;
    NSUInteger selected = self.selectedGame ? [self.games indexOfObject:self.selectedGame] : NSNotFound;
    self.selectedGame = selected == NSNotFound ? self.games.firstObject : self.games[selected];
    self.gameRunning = self.store.gameIsRunning;
    self.backupsTitleID = nil;
    [self changed];
}

- (void)refreshRunningState {
    BOOL running = self.store.gameIsRunning;
    if (running != self.gameRunning) {
        self.gameRunning = running;
        [self changed];
    }
}

- (void)selectGame:(NPGame *)game {
    if (self.busy || [game isEqual:self.selectedGame]) {
        return;
    }
    self.selectedGame = game;
    [self changed];
}

// Runs `work` on the background queue, then `finished` with its result on the main queue.
// A nil result is a failure: the error goes to the error handler and `failedStatus` shows.
- (void)perform:(NSString *)progress
   failedStatus:(NSString *)failedStatus
           work:(id (^)(NSError **error))work
       finished:(void (^)(id result))finished {
    if (self.busy) {
        return;
    }
    self.busy = YES;
    self.status = progress;
    [self changed];
    dispatch_async(self.workQueue, ^{
        NSError *error = nil;
        id result = work(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            self.gameRunning = self.store.gameIsRunning;
            if (result) {
                finished(result);
            } else {
                self.status = failedStatus;
                self.errorHandler(error ?: [NSError errorWithDomain:NPErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"The action could not be completed."}]);
            }
            [self changed];
        });
    });
}

- (void)addApps:(NSArray<NSURL *> *)urls {
    NPStore *store = self.store;
    [self perform:@"Checking app signatures and build identities…"
     failedStatus:@"No apps were added."
             work:^id(NSError **error) {
        return [store importApps:urls error:error];
    } finished:^(NSArray<NPGame *> *added) {
        self.selectedGame = added.firstObject;
        [self reload];
        self.status = @"Native apps added. Your existing library and progress are preserved.";
    }];
}

- (void)removeSelectedGame {
    if (!self.selectedGame || self.busy) {
        return;
    }
    NSError *error = nil;
    if (![self.store removeGame:self.selectedGame error:&error]) {
        self.errorHandler(error);
        return;
    }
    self.selectedGame = nil;
    [self reload];
    self.status = @"Removed from the library. The app, saves and backups stay on disk.";
    [self changed];
}

- (void)revealSelectedGame {
    if (self.selectedGame) {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:self.selectedGame.path]]];
    }
}

- (void)setArtworkFromURL:(NSURL *)url {
    NSError *error = nil;
    if (self.selectedGame && ![self.artwork setImageAtURL:url forGame:self.selectedGame error:&error]) {
        self.errorHandler(error);
    }
}

- (void)resetArtwork {
    if (self.selectedGame) {
        [self.artwork resetGame:self.selectedGame];
    }
}

- (void)playWithControllerSetup:(BOOL)controllerSetup {
    if (self.session.running) {
        [self.session activate];
        return;
    }
    NPGame *game = self.selectedGame;
    if (!game) {
        return;
    }
    NPLauncher *launcher = self.launcher;
    __weak NPLibraryController *weakSelf = self;
    [self perform:@"Verifying the app and backing up its progress…"
     failedStatus:@"Launch stopped; your saved progress is preserved."
             work:^id(NSError **error) {
        return [launcher launchGame:game controllerSetup:controllerSetup completion:^(int status, NSURL *session) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf gameEndedWithStatus:status];
            });
        } error:error];
    } finished:^(NPGameSession *session) {
        // A game that already ended has reported it, so must not stay marked running.
        self.session = session.running ? session : nil;
        self.backupsTitleID = nil;
        self.status = @"Playing offline.";
    }];
}

- (void)gameEndedWithStatus:(int)status {
    self.session = nil;
    self.gameRunning = self.store.gameIsRunning;
    self.backupsTitleID = nil;
    self.status = status <= 0 ? @"Game closed. Its pre-launch backup is available." : @"Game stopped. Its pre-launch backup is available.";
    [self changed];
}

#pragma mark - Backups

- (void)loadBackups {
    NSString *titleID = self.selectedGame.titleID;
    if (!titleID || self.loadingBackups || [titleID isEqual:self.backupsTitleID]) {
        return;
    }
    self.loadingBackups = YES;
    NPStore *store = self.store;
    dispatch_async(self.workQueue, ^{
        NSArray<NPBackup *> *backups = [store backupsForTitle:titleID];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loadingBackups = NO;
            self.backups = backups;
            self.backupsTitleID = titleID;
            [self changed];
        });
    });
}

- (void)backUp {
    NSString *titleID = self.selectedGame.titleID;
    if (!titleID) {
        return;
    }
    NPStore *store = self.store;
    [self perform:@"Backing up and verifying progress…"
     failedStatus:@"No backup was made. Your saved progress is unchanged."
             work:^id(NSError **error) {
        return [store backupTitle:titleID label:@"Manual backup" error:error];
    } finished:^(NPBackup *backup) {
        self.backupsTitleID = nil;
        self.status = @"Progress and controller settings backed up and verified.";
    }];
}

- (void)restoreBackup:(NPBackup *)backup {
    NSString *titleID = self.selectedGame.titleID;
    if (!titleID) {
        return;
    }
    NPStore *store = self.store;
    [self perform:@"Verifying and restoring the backup…"
     failedStatus:@"The backup was not restored."
             work:^id(NSError **error) {
        return [store restoreBackupAtURL:backup.url title:titleID error:error] ? backup : nil;
    } finished:^(NPBackup *restored) {
        self.backupsTitleID = nil;
        self.status = @"Backup restored; the previous state is also kept.";
    }];
}

- (void)revealBackups {
    if (!self.selectedGame) {
        return;
    }
    NSURL *root = [self.store backupRootForTitle:self.selectedGame.titleID];
    if (NPCreatePrivateDirectory(root, nil)) {
        [NSWorkspace.sharedWorkspace openURL:root];
    }
}

#pragma mark - Launch options

- (NPLaunchOptions *)options {
    return self.selectedGame ? [self.store optionsForGame:self.selectedGame] : [NPLaunchOptions new];
}

- (void)updateOptions:(void (NS_NOESCAPE ^)(NPLaunchOptions *))change {
    if (!self.selectedGame) {
        return;
    }
    NPLaunchOptions *options = self.options;
    change(options);
    NSError *error = nil;
    if ([self.store setOptions:options forGame:self.selectedGame error:&error]) {
        self.status = @"Launch preference saved for this app.";
    } else {
        self.errorHandler(error);
    }
    [self changed];
}

- (NPFrameSummary *)latestFrameSummary {
    return self.selectedGame ? [self.store latestFrameSummaryForGame:self.selectedGame] : nil;
}

@end
