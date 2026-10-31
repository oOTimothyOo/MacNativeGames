#import "NPStore.h"
#import "NPFoundation.h"
#include <algorithm>
#include <cmath>
#include <libproc.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <vector>

const NSUInteger NPMaximumBackups = 20;

static const unsigned long long MaximumBackupBytes = 100ull * 1024 * 1024;
static const NSUInteger MaximumFinishedSessions = 20;
static const NSUInteger MaximumRawRecordings = 3;
static const unsigned long long MaximumRawRecordingBytes = 256ull * 1024 * 1024;

static NSFileManager *FileManager() {
    return NSFileManager.defaultManager;
}

// Runs a block when the scope ends, however it ends.
struct ScopeExit {
    void (^block)(void);
    ~ScopeExit() { block(); }
};

// A game's state: its progress and its controller settings. Nothing else is backed up.
static NSArray<NSString *> *StateComponents() {
    return @[@"save", @"save.work", @"controller-layout.txt"];
}

static BOOL IsStateRelativePath(NSString *path) {
    if (!path.length || path.isAbsolutePath) {
        return NO;
    }
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    if (![StateComponents() containsObject:parts.firstObject]) {
        return NO;
    }
    if ([parts.firstObject isEqual:@"controller-layout.txt"] && parts.count != 1) {
        return NO;
    }
    for (NSString *part in parts) {
        if (!part.length || [part isEqual:@"."] || [part isEqual:@".."] || [part containsString:@"\\"]) {
            return NO;
        }
    }
    return YES;
}

// Relative path to SHA-256 for the owned state below `root`. Rejects links, devices and
// oversized input. Assets and keys never enter this store.
static NSDictionary<NSString *, NSString *> *HashState(NSURL *root, NSError **error) {
    if (!NPPathHasNoLinks(root)) {
        NPFail(error, @"A state directory is a symbolic link.");
        return nil;
    }
    NSString *rootPath = NPCanonicalPath(root);
    NSMutableDictionary *files = [NSMutableDictionary new];
    unsigned long long total = 0;
    for (NSString *name in StateComponents()) {
        NSURL *base = NPChild(root, name);
        struct stat initial;
        if (lstat(base.fileSystemRepresentation, &initial)) {
            continue;
        }
        NSMutableArray<NSURL *> *paths = [NSMutableArray arrayWithObject:base];
        if (S_ISDIR(initial.st_mode)) {
            __block NSError *enumerationError = nil;
            NSDirectoryEnumerator *enumerator = [FileManager() enumeratorAtURL:base
                                                    includingPropertiesForKeys:nil
                                                                       options:0
                                                                  errorHandler:^BOOL(NSURL *url, NSError *failure) {
                enumerationError = failure;
                return NO;
            }];
            [paths addObjectsFromArray:enumerator.allObjects];
            if (enumerationError) {
                if (error) {
                    *error = enumerationError;
                }
                return nil;
            }
        }
        for (NSURL *path in paths) {
            struct stat info;
            if (lstat(path.fileSystemRepresentation, &info) || !NPPathHasNoLinks(path) || (!S_ISDIR(info.st_mode) && !S_ISREG(info.st_mode))) {
                NPFail(error, @"Save folders must contain ordinary files and directories, without symbolic links.");
                return nil;
            }
            if (S_ISDIR(info.st_mode)) {
                continue;
            }
            total += (unsigned long long)info.st_size;
            if (total > MaximumBackupBytes) {
                NPFail(error, @"This save exceeds the adapter's 100 MB backup limit.");
                return nil;
            }
            NSString *filePath = NPCanonicalPath(path);
            if (![filePath hasPrefix:[rootPath stringByAppendingString:@"/"]]) {
                NPFail(error, @"A save file escaped its state directory.");
                return nil;
            }
            NSString *relative = [filePath substringFromIndex:rootPath.length + 1];
            NSString *hash = NPSHA256OfFile(path);
            if (!IsStateRelativePath(relative) || hash.length != 64) {
                NPFail(error, @"Could not validate a save file.");
                return nil;
            }
            files[relative] = hash;
        }
    }
    return files;
}

static BOOL IsSessionDirectoryName(NSString *name) {
    return [[NSUUID alloc] initWithUUIDString:name] != nil;
}

// Reads a session's JSON only when no link could redirect it.
static NSDictionary *ReadSessionFile(NSURL *session, NSString *name) {
    NSURL *url = NPChild(session, name);
    return NPPathHasNoLinks(url) ? NPDictionary(NPReadJSON(url)) : nil;
}

@interface NPBackup ()
- (instancetype)initWithURL:(NSURL *)url manifest:(NSDictionary *)manifest;
@end

@implementation NPBackup
- (instancetype)initWithURL:(NSURL *)url manifest:(NSDictionary *)manifest {
    if ((self = [super init])) {
        _url = url;
        _label = [manifest[@"label"] copy];
        _created = [NSDate dateWithTimeIntervalSince1970:[manifest[@"created"] doubleValue]];
        _files = [manifest[@"files"] copy];
    }
    return self;
}
@end

@implementation NPLaunchOptions
- (instancetype)init {
    if ((self = [super init])) {
        _fullscreen = YES;
    }
    return self;
}
@end

@interface NPFrameSummary ()
- (nullable instancetype)initWithDictionary:(NSDictionary *)summary;
@end

@implementation NPFrameSummary
- (instancetype)initWithDictionary:(NSDictionary *)summary {
    NSNumber *frames = NPNumber(summary[@"frames"]);
    NSNumber *over50 = NPNumber(summary[@"over_50_ms"]);
    NSNumber *median = NPNumber(summary[@"median_ms"]);
    NSNumber *p95 = NPNumber(summary[@"p95_ms"]);
    NSNumber *p99 = NPNumber(summary[@"p99_ms"]);
    if (!frames || !over50 || !median || !p95 || !p99) {
        return nil;
    }
    if ((self = [super init])) {
        _frames = frames.unsignedIntegerValue;
        _framesOver50ms = over50.unsignedIntegerValue;
        _medianMilliseconds = median.doubleValue;
        _p95Milliseconds = p95.doubleValue;
        _p99Milliseconds = p99.doubleValue;
    }
    return self;
}
@end

@implementation NPStore

- (instancetype)initWithRoot:(NSURL *)root home:(NSURL *)home {
    // Check for links first: canonicalizing would hide a linked ancestor.
    if (!NPPathHasNoLinks(root) || !NPPathHasNoLinks(home)) {
        return nil;
    }
    if ((self = [super init])) {
        _root = [NSURL fileURLWithPath:NPCanonicalPath(root)];
        _home = [NSURL fileURLWithPath:NPCanonicalPath(home)];
        if (!NPPathHasNoLinks(_root) || !NPCreatePrivateDirectory(_root, nil)) {
            return nil;
        }
    }
    return self;
}

#pragma mark - Catalog

- (NSURL *)catalogURL {
    return NPChild(self.root, @"library.json");
}

- (NSArray<NPGame *> *)games {
    if (!NPPathHasNoLinks(self.catalogURL)) {
        return @[];
    }
    id catalog = NPReadJSON(self.catalogURL);
    if (![catalog isKindOfClass:NSArray.class]) {
        return @[];
    }
    NSMutableArray *games = [NSMutableArray new];
    for (id row in catalog) {
        NPGame *game = NPDictionary(row) ? [[NPGame alloc] initWithCatalogEntry:row] : nil;
        if (game) {
            [games addObject:game];
        }
    }
    return games;
}

- (BOOL)writeCatalog:(NSArray<NPGame *> *)games error:(NSError **)error {
    return NPWriteJSON([games valueForKey:@"catalogEntry"], self.catalogURL, error);
}

- (NPGame *)importApp:(NSURL *)app error:(NSError **)error {
    return [self importApps:@[app] error:error].firstObject;
}

- (NSArray<NPGame *> *)importApps:(NSArray<NSURL *> *)apps error:(NSError **)error {
    NSMutableArray<NPGame *> *validated = [NSMutableArray new];
    for (NSURL *app in apps) {
        NPGame *game = [NPGame gameFromAppAtURL:app error:error];
        if (!game) {
            return nil;
        }
        [validated addObject:game];
    }
    NSMutableArray<NPGame *> *catalog = [self.games mutableCopy];
    for (NPGame *game in validated) {
        NSUInteger index = [catalog indexOfObject:game];
        if (index == NSNotFound) {
            [catalog addObject:game];
        } else {
            catalog[index] = game;
        }
    }
    return [self writeCatalog:catalog error:error] ? validated : nil;
}

- (BOOL)removeGame:(NPGame *)game error:(NSError **)error {
    NSMutableArray<NPGame *> *catalog = [self.games mutableCopy];
    [catalog removeObject:game];
    return [self writeCatalog:catalog error:error];
}

#pragma mark - Backups

- (NSURL *)stateURLForTitle:(NSString *)titleID {
    // Jamboree's saves predate the library, and stay where they have always been.
    if ([titleID isEqual:NPJamboreeTitleID]) {
        return NPChild(self.home, @"Library/Application Support/Super Mario Party Jamboree");
    }
    return NPChild(self.root, [@"GameData/" stringByAppendingString:titleID]);
}

- (NSURL *)backupRootForTitle:(NSString *)titleID {
    return NPChild(self.root, [@"Backups/" stringByAppendingString:titleID]);
}

- (NPBackup *)validatedBackupAtURL:(NSURL *)url title:(NSString *)titleID error:(NSError **)error {
    BOOL insideStore = [NPCanonicalPath(url.URLByDeletingLastPathComponent) isEqual:NPCanonicalPath([self backupRootForTitle:titleID])];
    if (!insideStore || !IsSessionDirectoryName(url.lastPathComponent) || !NPPathHasNoLinks(url)) {
        NPFail(error, @"Backup path is outside the local snapshot store.");
        return nil;
    }
    NSURL *manifestURL = NPChild(url, @"manifest.json");
    if (!NPPathHasNoLinks(manifestURL)) {
        NPFail(error, @"Backup metadata is a symbolic link.");
        return nil;
    }
    NSDictionary *manifest = NPDictionary(NPReadJSON(manifestURL));
    if (![manifest[@"schema"] isEqual:@1] || ![manifest[@"game"] isEqual:titleID] || !NPDictionary(manifest[@"files"]) ||
        !NPNumber(manifest[@"created"]) || !NPString(manifest[@"label"])) {
        NPFail(error, @"Backup metadata is invalid.");
        return nil;
    }
    NSDictionary *files = HashState(url, error);
    if (![files isEqual:manifest[@"files"]]) {
        NPFail(error, @"Backup hashes differ. Your current progress has not been restored.");
        return nil;
    }
    return [[NPBackup alloc] initWithURL:url manifest:manifest];
}

- (NSArray<NPBackup *> *)backupsForTitle:(NSString *)titleID {
    NSURL *root = [self backupRootForTitle:titleID];
    if (!NPPathHasNoLinks(root)) {
        return @[];
    }
    NSMutableArray<NPBackup *> *backups = [NSMutableArray new];
    for (NSURL *url in [FileManager() contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil]) {
        NPBackup *backup = [self validatedBackupAtURL:url title:titleID error:nil];
        if (backup) {
            [backups addObject:backup];
        }
    }
    [backups sortUsingComparator:^NSComparisonResult(NPBackup *a, NPBackup *b) {
        return [b.created compare:a.created];
    }];
    return backups;
}

- (NPBackup *)backupTitle:(NSString *)titleID label:(NSString *)label error:(NSError **)error {
    if (self.gameIsRunning) {
        NPFail(error, @"Close the game before backing up or restoring progress.");
        return nil;
    }
    NSURL *state = [self stateURLForTitle:titleID];
    NSURL *root = [self backupRootForTitle:titleID];
    NSDictionary *files = HashState(state, error);
    if (!files || !NPPathHasNoLinks(root) || !NPCreatePrivateDirectory(root, error)) {
        return nil;
    }

    NSString *identifier = NSUUID.UUID.UUIDString;
    NSURL *pending = NPChild(root, [@".pending-" stringByAppendingString:identifier]);
    NSURL *complete = NPChild(root, identifier);
    if (!NPCreatePrivateDirectory(pending, error)) {
        return nil;
    }
    // A no-op once the snapshot has been renamed into place.
    ScopeExit discardPending{^{
        [FileManager() removeItemAtURL:pending error:nil];
    }};

    for (NSString *name in StateComponents()) {
        if (NPExists(NPChild(state, name)) && ![FileManager() copyItemAtURL:NPChild(state, name) toURL:NPChild(pending, name) error:error]) {
            return nil;
        }
    }
    NSDictionary *copied = HashState(pending, error);
    if (![copied isEqual:files]) {
        NPFail(error, @"Progress changed during backup. No restore was attempted.");
        return nil;
    }
    for (NSURL *url in [FileManager() enumeratorAtURL:pending includingPropertiesForKeys:nil options:0 errorHandler:nil]) {
        BOOL isDirectory = NO;
        [FileManager() fileExistsAtPath:url.path isDirectory:&isDirectory];
        if (![FileManager() setAttributes:@{NSFilePosixPermissions: isDirectory ? @0700 : @0600} ofItemAtPath:url.path error:error]) {
            return nil;
        }
    }
    NSDictionary *manifest = @{@"schema": @1, @"game": titleID, @"label": label, @"created": @(NSDate.date.timeIntervalSince1970), @"files": files};
    if (!NPWriteJSON(manifest, NPChild(pending, @"manifest.json"), error) || ![self move:pending to:complete error:error]) {
        return nil;
    }

    // Delete only completed, hash-validated snapshots owned by this adapter.
    NSArray<NPBackup *> *snapshots = [self backupsForTitle:titleID];
    for (NSUInteger i = NPMaximumBackups; i < snapshots.count; i++) {
        [FileManager() removeItemAtURL:snapshots[i].url error:nil];
    }
    return [self validatedBackupAtURL:complete title:titleID error:error];
}

- (BOOL)move:(NSURL *)source to:(NSURL *)destination error:(NSError **)error {
    return [FileManager() moveItemAtURL:source toURL:destination error:error];
}

- (BOOL)restoreBackupAtURL:(NSURL *)source title:(NSString *)titleID error:(NSError **)error {
    if (self.gameIsRunning) {
        return NPFail(error, @"Close the game before restoring progress.");
    }
    NSURL *state = [self stateURLForTitle:titleID];
    NPBackup *backup = [self validatedBackupAtURL:source title:titleID error:error];
    if (!backup || !NPPathHasNoLinks(state) || !NPCreatePrivateDirectory(state, error)) {
        return NO;
    }

    NSURL *transaction = NPChild(state, [@".native-play-restore-" stringByAppendingString:NSUUID.UUID.UUIDString]);
    NSURL *staged = NPChild(transaction, @"new");
    NSURL *rollback = NPChild(transaction, @"previous");
    __block BOOL keepTransaction = NO;
    ScopeExit discardTransaction{^{
        if (!keepTransaction) {
            [FileManager() removeItemAtURL:transaction error:nil];
        }
    }};
    if (!NPCreatePrivateDirectory(staged, error) || !NPCreatePrivateDirectory(rollback, error)) {
        return NO;
    }
    for (NSString *name in StateComponents()) {
        if (NPExists(NPChild(source, name)) && ![FileManager() copyItemAtURL:NPChild(source, name) toURL:NPChild(staged, name) error:error]) {
            return NO;
        }
    }
    // Stage and hash-check first: the pre-restore backup may rotate this snapshot away.
    if (![HashState(staged, error) isEqual:backup.files]) {
        return NPFail(error, @"Backup contents changed during staging.");
    }
    if (![self backupTitle:titleID label:@"Before restore" error:error]) {
        return NO;
    }
    if (self.gameIsRunning) {
        return NPFail(error, @"Close the game before restoring progress.");
    }

    NSMutableArray<NSString *> *installed = [NSMutableArray new];
    NSMutableArray<NSString *> *displaced = [NSMutableArray new];
    BOOL swapped = YES;
    for (NSString *name in StateComponents()) {
        if (NPExists(NPChild(state, name))) {
            if (![self move:NPChild(state, name) to:NPChild(rollback, name) error:error]) {
                swapped = NO;
                break;
            }
            [displaced addObject:name];
        }
        if (NPExists(NPChild(staged, name))) {
            if (![self move:NPChild(staged, name) to:NPChild(state, name) error:error]) {
                swapped = NO;
                break;
            }
            [installed addObject:name];
        }
    }
    if (swapped) {
        return YES;
    }

    for (NSString *name in installed.reverseObjectEnumerator) {
        [FileManager() removeItemAtURL:NPChild(state, name) error:nil];
    }
    for (NSString *name in displaced.reverseObjectEnumerator) {
        if (![FileManager() moveItemAtURL:NPChild(rollback, name) toURL:NPChild(state, name) error:nil]) {
            keepTransaction = YES;
        }
    }
    if (keepTransaction) {
        NPFail(error, @"Restore stopped. A verified pre-restore backup and the restore transaction were retained for recovery.");
    }
    return NO;
}

#pragma mark - Launch options

- (NSURL *)optionsURLForGame:(NPGame *)game {
    return NPChild(self.root, [NSString stringWithFormat:@"LaunchOptions/%@.json", game.key]);
}

- (NPLaunchOptions *)optionsForGame:(NPGame *)game {
    NSURL *url = [self optionsURLForGame:game];
    NSDictionary *stored = NPPathHasNoLinks(url) ? NPDictionary(NPReadJSON(url)) : nil;
    // Written by the first release, when Jamboree was the only game.
    NSURL *legacy = NPChild(self.root, @"options.json");
    if (!stored && [game.titleID isEqual:NPJamboreeTitleID] && NPPathHasNoLinks(legacy)) {
        stored = NPDictionary(NPReadJSON(legacy));
    }
    NPLaunchOptions *options = [NPLaunchOptions new];
    options.metalHUD = NPIsTrue(stored[@"hud"]);
    options.recordNextSession = NPIsTrue(stored[@"record"]);
    if (NPNumber(stored[@"fullscreen"])) {
        options.fullscreen = [stored[@"fullscreen"] boolValue];
    }
    return options;
}

- (BOOL)setOptions:(NPLaunchOptions *)options forGame:(NPGame *)game error:(NSError **)error {
    NSURL *url = [self optionsURLForGame:game];
    NSURL *directory = url.URLByDeletingLastPathComponent;
    if (!NPPathHasNoLinks(directory)) {
        return NPFail(error, @"The launch options folder is a symbolic link.");
    }
    if (!NPCreatePrivateDirectory(directory, error)) {
        return NO;
    }
    NSDictionary *stored = @{@"hud": @(options.metalHUD), @"record": @(options.recordNextSession), @"fullscreen": @(options.fullscreen)};
    return NPWriteJSON(stored, url, error);
}

#pragma mark - Running games

- (BOOL)gameIsRunning {
    int bytes = proc_listallpids(NULL, 0);
    std::vector<pid_t> pids((size_t)std::max(bytes, 0) / sizeof(pid_t) + 64);
    int count = proc_listallpids(pids.data(), (int)(pids.size() * sizeof(pid_t)));
    if (count <= 0) {
        return YES;  // Unknown: the callers guard save data, so assume running.
    }
    NSMutableSet<NSString *> *executables = [NSMutableSet new];
    for (NPGame *game in self.games) {
        [executables addObject:[game.path stringByAppendingPathComponent:game.executable]];
        NSString *host = NPString(game.catalogEntry[@"host_executable"]) ?: @"Contents/Resources/game/dmhost";
        [executables addObject:[game.path stringByAppendingPathComponent:host]];
    }
    for (int i = 0; i < count; i++) {
        char buffer[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[(size_t)i], buffer, sizeof buffer) <= 0) {
            continue;
        }
        NSString *path = @(buffer);
        if ([path hasSuffix:@"/Contents/Resources/game/dmhost"] || [path hasSuffix:@"/Contents/MacOS/GameHost"] ||
            [path hasSuffix:@"/Contents/MacOS/Jamboree"] || [executables containsObject:path]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Sessions

- (NSURL *)sessionsURL {
    return NPChild(self.root, @"Sessions");
}

- (NPFrameSummary *)latestFrameSummaryForGame:(NPGame *)game {
    if (!NPPathHasNoLinks(self.sessionsURL)) {
        return nil;
    }
    NSDictionary *latest = nil;
    double latestFinish = 0;
    for (NSURL *session in [FileManager() contentsOfDirectoryAtURL:self.sessionsURL includingPropertiesForKeys:nil options:0 error:nil]) {
        NSDictionary *record = ReadSessionFile(session, @"session.json");
        NSDictionary *result = ReadSessionFile(session, @"result.json");
        NSDictionary *summary = ReadSessionFile(session, @"summary.json");
        if (!record || !summary || ![record[@"game"] isEqual:game.titleID]) {
            continue;
        }
        if (record[@"app_key"] && ![record[@"app_key"] isEqual:game.key]) {
            continue;
        }
        double finish = [NPNumber(result[@"finished"]) doubleValue];
        if (finish > latestFinish) {
            latestFinish = finish;
            latest = summary;
        }
    }
    return latest ? [[NPFrameSummary alloc] initWithDictionary:latest] : nil;
}

- (void)pruneSessions {
    if (!NPPathHasNoLinks(self.sessionsURL)) {
        return;
    }
    NSMutableArray<NSDictionary *> *finished = [NSMutableArray new];
    for (NSURL *url in [FileManager() contentsOfDirectoryAtURL:self.sessionsURL includingPropertiesForKeys:nil options:0 error:nil]) {
        if (!IsSessionDirectoryName(url.lastPathComponent) || !NPPathHasNoLinks(url)) {
            continue;
        }
        NSDictionary *record = ReadSessionFile(url, @"session.json");
        NSNumber *finish = NPNumber(ReadSessionFile(url, @"result.json")[@"finished"]);
        if (NPIsTitleID(record[@"game"]) && finish) {
            [finished addObject:@{@"url": url, @"finished": finish}];
        }
    }
    [finished sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"finished"] compare:a[@"finished"]];
    }];

    unsigned long long keptBytes = 0;
    NSUInteger keptRecordings = 0;
    for (NSUInteger i = 0; i < finished.count; i++) {
        NSURL *url = finished[i][@"url"];
        if (i >= MaximumFinishedSessions) {
            [FileManager() removeItemAtURL:url error:nil];
            continue;
        }
        NSURL *frames = NPChild(url, @"frames.tsv");
        if (NPPathHasNoLinks(frames) && NPExists(frames)) {
            unsigned long long size = [[FileManager() attributesOfItemAtPath:frames.path error:nil][NSFileSize] unsignedLongLongValue];
            if (keptRecordings < MaximumRawRecordings && keptBytes + size <= MaximumRawRecordingBytes) {
                keptBytes += size;
                keptRecordings++;
            } else {
                [FileManager() removeItemAtURL:frames error:nil];
            }
        }
        NSURL *temporary = NPChild(url, @"tmp");
        if (NPPathHasNoLinks(temporary)) {
            [FileManager() removeItemAtURL:temporary error:nil];
        }
    }
}

@end

#pragma mark - Frame timings

static double Quantile(const std::vector<double> &sorted, double q) {
    if (sorted.empty()) {
        return 0;
    }
    double position = (double)(sorted.size() - 1) * q;
    size_t low = (size_t)position;
    size_t high = std::min(low + 1, sorted.size() - 1);
    return sorted[low] + (sorted[high] - sorted[low]) * (position - (double)low);
}

NSDictionary *NPSummarizeFrames(NSURL *session) {
    FILE *file = fopen(NPChild(session, @"frames.tsv").fileSystemRepresentation, "r");
    if (!file) {
        return nil;
    }
    std::vector<double> frames, gpu;
    NSUInteger invalid = 0;
    // Rows are "<index>\t@frame_ms|@gpu_ms\t<value>". A fixed buffer bounds memory on a
    // damaged file; an overlong line splits into fragments that no longer match a row.
    char line[4096];
    while (fgets(line, sizeof line, file)) {
        char *name = strchr(line, '\t');
        char *value = name ? strchr(name + 1, '\t') : nullptr;
        if (!value || strchr(value + 1, '\t')) {
            continue;
        }
        *value++ = 0;
        name++;
        BOOL isFrame = !strcmp(name, "@frame_ms");
        if (!isFrame && strcmp(name, "@gpu_ms")) {
            continue;
        }
        value[strcspn(value, "\r\n")] = 0;
        char *end = nullptr;
        double number = strtod(value, &end);
        if (end == value || *end || !std::isfinite(number) || number <= 0) {
            invalid++;
            continue;
        }
        (isFrame ? frames : gpu).push_back(number);
    }
    fclose(file);
    if (frames.empty()) {
        return nil;
    }
    std::sort(frames.begin(), frames.end());
    std::sort(gpu.begin(), gpu.end());
    auto over50 = std::count_if(frames.begin(), frames.end(), [](double ms) { return ms > 50; });
    NSDictionary *summary = @{
        @"frames": @(frames.size()),
        @"median_ms": @(Quantile(frames, .5)),
        @"p95_ms": @(Quantile(frames, .95)),
        @"p99_ms": @(Quantile(frames, .99)),
        @"gpu_median_ms": @(Quantile(gpu, .5)),
        @"over_50_ms": @(over50),
        @"invalid_rows": @(invalid),
        @"includes_loading": @YES,
    };
    NPWriteJSON(summary, NPChild(session, @"summary.json"), nil);
    return summary;
}
