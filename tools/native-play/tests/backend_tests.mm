// Backups, restore, catalog, launch policy and timings, all against synthetic state.
#import "NPFoundation.h"
#import "NPLauncher.h"
#include <cmath>
#include <sys/stat.h>
#include <unistd.h>

static NSUInteger checks;

static void Check(BOOL condition, NSString *name) {
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", name.UTF8String);
        exit(1);
    }
}

static NSFileManager *FM() {
    return NSFileManager.defaultManager;
}

static void CreateParent(NSURL *url) {
    [FM() createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:NULL];
}

static void Write(NSURL *url, NSString *text) {
    CreateParent(url);
    Check([text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write synthetic fixture");
}

static NSString *Read(NSURL *url) {
    return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL];
}

static void WriteJSON(id value, NSURL *url) {
    CreateParent(url);
    Check([[NSJSONSerialization dataWithJSONObject:value options:0 error:NULL] writeToURL:url atomically:YES], @"write synthetic metadata");
}

@interface TestStore : NPStore
@property BOOL running;
@property BOOL failInstall;
@end

@implementation TestStore

- (BOOL)gameIsRunning {
    return self.running;
}

- (BOOL)move:(NSURL *)source to:(NSURL *)destination error:(NSError **)error {
    if (self.failInstall && [source.path containsString:@"/new/"] && [source.lastPathComponent isEqual:@"save.work"]) {
        self.failInstall = NO;
        if (error) {
            *error = [NSError errorWithDomain:@"InjectedFailure" code:1 userInfo:nil];
        }
        return NO;
    }
    return [super move:source to:destination error:error];
}

@end

static TestStore *MakeStore(NSURL *base, NSString *name) {
    NSURL *home = NPChild(base, name);
    return [[TestStore alloc] initWithRoot:NPChild(home, @"hub") home:home];
}

static NSString *Jamboree() {
    return NPJamboreeTitleID;
}

static BOOL Sign(NSURL *url) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
    task.arguments = @[@"--force", @"--sign", @"-", url.path];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:NULL]) {
        return NO;
    }
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

// A signed bundle whose executables are copies of this test binary.
static NSURL *MakeSignedApp(NSURL *base, NSString *name, NSString *titleID) {
    NSURL *app = NPChild(base, [name stringByAppendingString:@".app"]);
    NSURL *main = NPChild(app, @"Contents/MacOS/Fixture");
    NSURL *host = NPChild(app, @"Contents/Resources/game/dmhost");
    for (NSURL *url in @[main, host]) {
        CreateParent(url);
        Check([FM() copyItemAtURL:NSBundle.mainBundle.executableURL toURL:url error:NULL], @"copy owned synthetic executable");
    }
    Check(Sign(host), @"sign synthetic runtime");
    WriteJSON(@{
        @"game": @{@"title_id": titleID, @"version": @"1.0"},
        @"host_sha256": NPSHA256OfFile(host),
        @"native_play": @{@"adapter": @"dmhost-v2", @"managed_state": @YES},
    }, NPChild(app, @"Contents/Resources/game/build-info.json"));
    [@{@"CFBundleExecutable": @"Fixture", @"CFBundleIdentifier": [@"org.macnativegames.fixture.g" stringByAppendingString:titleID],
       @"CFBundleName": name, @"CFBundlePackageType": @"APPL"} writeToURL:NPChild(app, @"Contents/Info.plist") atomically:YES];
    Check(Sign(app), @"sign synthetic native app");
    return app;
}

static void TestSystemAlias() {
    NSURL *temporary = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    TestStore *store = MakeStore(temporary, @"system-alias");
    Check(store != nil, @"macOS system temporary-directory alias supported");
    Write(NPChild([store stateURLForTitle:Jamboree()], @"save/file"), @"system-alias-data");
    Check([store backupTitle:Jamboree() label:@"System alias" error:NULL] != nil && [store backupsForTitle:Jamboree()].count == 1, @"backup works through macOS path aliases");
    [FM() removeItemAtURL:temporary error:NULL];
}

static void TestBackupAndRestore(NSURL *base) {
    TestStore *store = MakeStore(base, @"roundtrip");
    Check(store != nil, @"store created");
    NSURL *state = [store stateURLForTitle:Jamboree()];
    NSURL *progress = NPChild(state, @"save/progress");
    NSURL *settings = NPChild(state, @"controller-layout.txt");

    Write(progress, @"original-progress");
    Write(NPChild(state, @"save.work/progress"), @"original-work");
    Write(settings, @"synthetic-controller-settings");
    NPBackup *backup = [store backupTitle:Jamboree() label:@"First" error:NULL];
    Check(backup != nil, @"snapshot created");
    Check(backup.files.count == 3, @"all state components included");

    Write(progress, @"new-progress");
    Write(NPChild(state, @"save/stale"), @"extra");
    Write(NPChild(state, @"save.work/progress"), @"new-work");
    Write(settings, @"new-settings");
    Check([store restoreBackupAtURL:backup.url title:Jamboree() error:NULL], @"restore succeeds");
    Check([Read(progress) isEqual:@"original-progress"], @"progress restored");
    Check([Read(NPChild(state, @"save.work/progress")) isEqual:@"original-work"], @"working save restored");
    Check([Read(settings) isEqual:@"synthetic-controller-settings"], @"controller settings restored");
    Check(!NPExists(NPChild(state, @"save/stale")), @"stale files removed as part of restore");
    Check([store backupsForTitle:Jamboree()].count == 2, @"pre-restore recovery snapshot retained");

    struct stat info;
    lstat(backup.url.fileSystemRepresentation, &info);
    Check((info.st_mode & 0777) == 0700, @"snapshot private");
    lstat(NPChild(backup.url, @"save/progress").fileSystemRepresentation, &info);
    Check((info.st_mode & 0777) == 0600, @"save files private");

    Write(progress, @"keep-on-failure");
    Write(settings, @"keep-settings");
    store.failInstall = YES;
    Check(![store restoreBackupAtURL:backup.url title:Jamboree() error:NULL], @"injected install failure reported");
    Check([Read(progress) isEqual:@"keep-on-failure"], @"failed restore rolls progress back");
    Check([Read(settings) isEqual:@"keep-settings"], @"failed restore preserves preferences");
    NSArray *leftovers = [[FM() contentsOfDirectoryAtPath:state.path error:NULL] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH '.native-play-restore-'"]];
    Check(leftovers.count == 0, @"recovered restore leaves no transaction behind");

    store.running = YES;
    Check([store backupTitle:Jamboree() label:@"Forbidden" error:NULL] == nil, @"backup blocked while running");
    Check(![store restoreBackupAtURL:backup.url title:Jamboree() error:NULL], @"restore blocked while running");
    store.running = NO;

    Write(NPChild(backup.url, @"save/progress"), @"tampered");
    Check(![store restoreBackupAtURL:backup.url title:Jamboree() error:NULL], @"corrupt snapshot rejected");
    Check([Read(progress) isEqual:@"keep-on-failure"], @"corruption does not touch current progress");
    Check(![store restoreBackupAtURL:base title:Jamboree() error:NULL], @"external backup path rejected");
    leftovers = [FM() contentsOfDirectoryAtPath:[store backupRootForTitle:Jamboree()].path error:NULL];
    Check(![leftovers containsObject:@".pending-"] && [leftovers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH '.pending-'"]].count == 0, @"no pending snapshot left behind");
}

static void TestFailedBackupLeavesNothing(NSURL *base) {
    TestStore *store = MakeStore(base, @"oversized");
    NSURL *save = NPChild([store stateURLForTitle:Jamboree()], @"save/huge");
    Write(save, @"x");
    Check(truncate(save.fileSystemRepresentation, 101ll * 1024 * 1024) == 0, @"create sparse oversized save");
    Check([store backupTitle:Jamboree() label:@"Too large" error:NULL] == nil, @"oversized save rejected");
    Check([store backupsForTitle:Jamboree()].count == 0, @"oversized save creates no snapshot");
}

static void TestLinksAndTraversal(NSURL *base) {
    TestStore *links = MakeStore(base, @"links");
    NSURL *outside = NPChild(base, @"outside");
    Write(NPChild(outside, @"progress"), @"unrelated");
    NSURL *state = [links stateURLForTitle:Jamboree()];
    [FM() createDirectoryAtURL:state withIntermediateDirectories:YES attributes:nil error:NULL];
    [FM() createSymbolicLinkAtURL:NPChild(state, @"save") withDestinationURL:outside error:NULL];
    Check([links backupTitle:Jamboree() label:@"Linked" error:NULL] == nil, @"symlink state root rejected");
    Check([Read(NPChild(outside, @"progress")) isEqual:@"unrelated"], @"outside file untouched");

    NSURL *linkedParent = NPChild(base, @"linked-parent");
    [FM() createSymbolicLinkAtURL:linkedParent withDestinationURL:outside error:NULL];
    Check(MakeStore(linkedParent, @"rejected") == nil, @"linked store ancestor rejected before URL normalization");

    TestStore *traversal = MakeStore(base, @"traversal");
    NSURL *file = NPChild([traversal stateURLForTitle:Jamboree()], @"save/file");
    Write(file, @"safe");
    NPBackup *good = [traversal backupTitle:Jamboree() label:@"Good" error:NULL];
    WriteJSON(@{@"schema": @1, @"game": Jamboree(), @"label": @"Evil", @"created": @1, @"files": @{@"../outside": @"fake"}}, NPChild(good.url, @"manifest.json"));
    Check(![traversal restoreBackupAtURL:good.url title:Jamboree() error:NULL], @"traversal manifest rejected");
    Check([Read(file) isEqual:@"safe"], @"traversal leaves progress intact");
}

static void TestRetention(NSURL *base) {
    TestStore *store = MakeStore(base, @"retention");
    Write(NPChild([store stateURLForTitle:Jamboree()], @"save/file"), @"retain");
    for (NSUInteger i = 0; i < NPMaximumBackups + 2; i++) {
        Check([store backupTitle:Jamboree() label:@"Rotation" error:NULL] != nil, @"rotation snapshot created");
    }
    Check([store backupsForTitle:Jamboree()].count == NPMaximumBackups, @"completed snapshot history bounded");
}

static void TestLaunchPolicy(NSURL *base) {
    TestStore *store = MakeStore(base, @"policy");
    NPLauncher *launcher = [[NPLauncher alloc] initWithStore:store];
    NPGame *game = [[NPGame alloc] initWithCatalogEntry:@{@"id": Jamboree(), @"path": @"/Synthetic/Jamboree.app", @"title": @"Jamboree", @"version": @"1"}];
    NSURL *session = NPChild(base, @"session");

    NPLaunchOptions *options = [store optionsForGame:game];
    Check(!options.metalHUD && !options.recordNextSession && options.fullscreen, @"normal play defaults to light logging in full screen");
    NSDictionary *normal = [launcher environmentForGame:game session:session controllerSetup:NO];
    Check(!normal[@"DM_NVN_TSV"] && !normal[@"MTL_DEBUG_LAYER"] && !normal[@"DYLD_INSERT_LIBRARIES"], @"no default profiler or injected libraries");

    options.metalHUD = YES;
    options.recordNextSession = YES;
    Check([store setOptions:options forGame:game error:NULL], @"options saved");
    NSDictionary *profiled = [launcher environmentForGame:game session:session controllerSetup:YES];
    Check([profiled[@"MTL_HUD_ENABLED"] isEqual:@"1"], @"HUD is per-launch environment");
    Check([profiled[@"DM_CONTROLLER_SETUP"] isEqual:@"1"], @"controller setup route");
    Check([profiled[@"DM_NVN_TSV_CALLS"] isEqual:@"0"], @"profile records timings only");

    NSString *profile = [launcher sandboxProfileForTitle:Jamboree() session:session];
    Check([profile containsString:@"(deny network*)"], @"network denial retained");
    Check([profile containsString:@"(deny file-write*"], @"filesystem writes restricted");
    Check([profile containsString:@"Library/Keychains"], @"credential store blocked");

    NSString *quoted = NPQuote(@"/tmp/a\"b\\c\n");
    Check([quoted hasPrefix:@"\""] && [quoted containsString:@"\\\""] && [quoted containsString:@"\\n"], @"sandbox paths quoted structurally");
}

static void TestSessionPruning(NSURL *base) {
    TestStore *store = MakeStore(base, @"sessions");
    NSURL *sessions = store.sessionsURL;
    NSMutableArray<NSURL *> *history = [NSMutableArray new];
    for (NSUInteger i = 0; i < 22; i++) {
        NSURL *entry = NPChild(sessions, NSUUID.UUID.UUIDString);
        [history addObject:entry];
        WriteJSON(@{@"game": Jamboree()}, NPChild(entry, @"session.json"));
        WriteJSON(@{@"finished": @(i)}, NPChild(entry, @"result.json"));
        Write(NPChild(entry, @"frames.tsv"), @"synthetic timing");
        Write(NPChild(entry, @"tmp/throwaway"), @"temporary");
    }
    Write(NPChild(sessions, @"unrelated/keep"), @"not a managed session");
    NSURL *active = NPChild(sessions, NSUUID.UUID.UUIDString);
    WriteJSON(@{@"game": Jamboree()}, NPChild(active, @"session.json"));
    Write(NPChild(active, @"frames.tsv"), @"active");

    [store pruneSessions];
    NSUInteger raw = 0, complete = 0;
    for (NSURL *entry in history) {
        complete += NPExists(entry);
        raw += NPExists(NPChild(entry, @"frames.tsv"));
        Check(!NPExists(NPChild(entry, @"tmp")), @"finished temporary files removed");
    }
    Check(complete == 20 && raw == 3, @"completed history and raw recordings bounded");
    Check([Read(NPChild(sessions, @"unrelated/keep")) isEqual:@"not a managed session"], @"unrecognized directory untouched");
    Check([Read(NPChild(active, @"frames.tsv")) isEqual:@"active"], @"active recording untouched");

    NSURL *oversized = NPChild(history.lastObject, @"frames.tsv");
    Check(truncate(oversized.fileSystemRepresentation, 257ll * 1024 * 1024) == 0, @"create sparse oversized synthetic recording");
    [store pruneSessions];
    Check(!NPExists(oversized), @"oversized completed recording removed");
}

static void TestMalformedInput(NSURL *base) {
    TestStore *store = MakeStore(base, @"malformed");
    NPGame *game = [[NPGame alloc] initWithCatalogEntry:@{@"id": Jamboree(), @"path": @"/Synthetic/A.app", @"title": @"A", @"version": @"1"}];

    Write(NPChild(store.root, @"library.json"), @"[123,\"bad\",{},{\"id\":\"0100965017338000\",\"path\":\"/a\",\"title\":\"\",\"version\":\"1\"}]");
    Check(store.games.count == 0, @"malformed catalog entries ignored, including an empty title");
    Write(NPChild(store.root, [NSString stringWithFormat:@"LaunchOptions/%@.json", game.key]), @"[]");
    Write(NPChild(store.root, @"options.json"), @"[]");
    Check(![store optionsForGame:game].recordNextSession, @"malformed options safe defaults");

    NSDictionary *wrongTypes = @{@"id": Jamboree(), @"path": @"/Synthetic/B.app", @"title": @"B", @"version": @"1", @"controllers": @[@1], @"launch_services_sandbox": @{}};
    NPGame *wrong = [[NPGame alloc] initWithCatalogEntry:wrongTypes];
    Check(wrong && !wrong.launchesThroughLaunchServices, @"wrongly typed catalog values read as absent, without crashing");

    Write(NPChild(store.root, [NSString stringWithFormat:@"LaunchOptions/%@.json", game.key]), @"{\"hud\":[1],\"record\":\"yes\",\"fullscreen\":{}}");
    NPLaunchOptions *options = [store optionsForGame:game];
    Check(!options.metalHUD && !options.recordNextSession && options.fullscreen, @"wrongly typed options read as defaults");
}

static void TestTimings(NSURL *base) {
    NSURL *session = NPChild(base, @"timings");
    Write(NPChild(session, @"frames.tsv"), @"1\t@frame_ms\t10\n2\t@frame_ms\t20\n3\t@frame_ms\t30\n4\t@frame_ms\t40\n5\t@frame_ms\t100\n6\t@frame_ms\tNaN\n1\t@gpu_ms\t2\nignored row\n");
    NSDictionary *summary = NPSummarizeFrames(session);
    Check([summary[@"frames"] intValue] == 5, @"numeric timing coverage");
    Check(std::abs([summary[@"median_ms"] doubleValue] - 30) < 1e-9, @"median");
    Check(std::abs([summary[@"p95_ms"] doubleValue] - 88) < 1e-9, @"linear p95");
    Check([summary[@"over_50_ms"] intValue] == 1, @"hitch count");
    Check([summary[@"includes_loading"] boolValue], @"loading not silently filtered");
    Check([summary[@"invalid_rows"] intValue] == 1, @"invalid timing not treated as zero");
    Check(NPSummarizeFrames(NPChild(base, @"missing-session")) == nil, @"no recording, no summary");
}

static void TestFrameSummaryLookup(NSURL *base) {
    TestStore *store = MakeStore(base, @"summaries");
    NPGame *game = [[NPGame alloc] initWithCatalogEntry:@{@"id": Jamboree(), @"path": @"/Synthetic/A.app", @"title": @"A", @"version": @"1"}];
    NPGame *other = [[NPGame alloc] initWithCatalogEntry:@{@"id": Jamboree(), @"path": @"/Synthetic/B.app", @"title": @"B", @"version": @"1"}];
    Check([store latestFrameSummaryForGame:game] == nil, @"no summary before a recording");
    NSURL *session = NPChild(store.sessionsURL, NSUUID.UUID.UUIDString);
    WriteJSON(@{@"game": Jamboree(), @"app_key": game.key}, NPChild(session, @"session.json"));
    WriteJSON(@{@"finished": @5}, NPChild(session, @"result.json"));
    WriteJSON(@{@"frames": @7, @"over_50_ms": @1, @"median_ms": @16.5, @"p95_ms": @20, @"p99_ms": @30}, NPChild(session, @"summary.json"));
    Check([store latestFrameSummaryForGame:game].frames == 7, @"summary found for its own app");
    Check([store latestFrameSummaryForGame:other] == nil, @"summary is per installed app");
}

static void TestCatalog(NSURL *base) {
    TestStore *store = MakeStore(base, @"multi-app");
    NSURL *first = MakeSignedApp(base, @"Sky Fixture", @"0100000000000001");
    NSURL *second = MakeSignedApp(base, @"Moss Fixture", @"0100000000000002");

    NSURL *unsignedApp = NPChild(base, @"unsigned.app");
    NSURL *unsignedHost = NPChild(unsignedApp, @"Contents/Resources/game/dmhost");
    Write(unsignedHost, @"synthetic unsigned host");
    Write(NPChild(unsignedApp, @"Contents/MacOS/Jamboree"), @"synthetic unsigned launcher");
    WriteJSON(@{@"game": @{@"title_id": Jamboree()}, @"host_sha256": NPSHA256OfFile(unsignedHost)}, NPChild(unsignedApp, @"Contents/Resources/game/build-info.json"));
    [@{@"CFBundleExecutable": @"Jamboree", @"CFBundleIdentifier": @"org.macnativegames.fixture.unsigned", @"CFBundlePackageType": @"APPL"} writeToURL:NPChild(unsignedApp, @"Contents/Info.plist") atomically:YES];
    Check([store importApp:unsignedApp error:NULL] == nil, @"unsigned app rejected even with a matching host hash");

    NSArray<NPGame *> *added = [store importApps:@[first, second] error:NULL];
    Check(added.count == 2 && store.games.count == 2, @"multiple apps import without replacing existing entries");
    Check([store importApp:first error:NULL] != nil && store.games.count == 2, @"same-path reimport updates only that entry");
    Check([store importApps:@[first, unsignedApp] error:NULL] == nil && store.games.count == 2, @"failed batch leaves catalog intact");

    NPGame *a = added[0];
    NPGame *b = added[1];
    Check([a verifiedGameWithError:NULL] && [b verifiedGameWithError:NULL], @"both signed identities verified independently");

    NSURL *stateA = [store stateURLForTitle:a.titleID];
    Write(NPChild(stateA, @"save/progress"), @"first-game-progress");
    NPBackup *saveA = [store backupTitle:a.titleID label:@"First game" error:NULL];
    NPLaunchOptions *optionsA = [store optionsForGame:a];
    optionsA.metalHUD = YES;
    optionsA.fullscreen = NO;
    [store setOptions:optionsA forGame:a error:NULL];

    NSURL *stateB = [store stateURLForTitle:b.titleID];
    Check(![stateB.path isEqual:stateA.path], @"different titles have different save roots");
    Check([store backupsForTitle:b.titleID].count == 0 && ![store optionsForGame:b].metalHUD, @"save history and launch settings isolated by game");
    Write(NPChild(stateB, @"save/progress"), @"second-game-progress");
    Check([store backupTitle:b.titleID label:@"Second game" error:NULL] != nil, @"second game backup");
    Check(![store restoreBackupAtURL:saveA.url title:b.titleID error:NULL], @"cross-game restore rejected");
    Check([Read(NPChild(stateB, @"save/progress")) isEqual:@"second-game-progress"], @"cross-game attempt preserves progress");

    Check([store backupsForTitle:a.titleID].count == 1 && [store optionsForGame:a].metalHUD && ![store optionsForGame:a].fullscreen, @"returning to a game restores its history and preferences");
    Check([store removeGame:b error:NULL] && store.games.count == 1, @"remove only the selected catalog entry");
    Check(NPExists(second), @"removing entry preserves installed app");

    NSMutableDictionary *changed = [a.catalogEntry mutableCopy];
    changed[@"executable_sha256"] = @"changed";
    Check(![[[NPGame alloc] initWithCatalogEntry:changed] verifiedGameWithError:NULL], @"launcher executable hash pinned in addition to runtime");
    changed = [a.catalogEntry mutableCopy];
    changed[@"launch_services_sandbox"] = @YES;
    Check(![[[NPGame alloc] initWithCatalogEntry:changed] verifiedGameWithError:NULL], @"launch route must match the signed adapter capability");

    NSURL *metadata = NPChild(second, @"Contents/Resources/game/build-info.json");
    NSMutableDictionary *unmanaged = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:metadata] options:NSJSONReadingMutableContainers error:NULL];
    unmanaged[@"native_play"] = @{@"adapter": @"dmhost-v2", @"managed_state": @NO};
    WriteJSON(unmanaged, metadata);
    Check(Sign(second), @"re-sign fixture without managed state");
    Check([store importApp:second error:NULL] == nil, @"adapter must explicitly support isolated state");

    NSURL *changedBundle = MakeSignedApp(base, @"Changed Fixture", @"0100000000000003");
    NPGame *pinned = [store importApp:changedBundle error:NULL];
    Write(NPChild(changedBundle, @"Contents/Resources/game/extra"), @"added after signing");
    Check(pinned && ![pinned verifiedGameWithError:NULL], @"a file added after signing fails verification");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        umask(0077);
        if (argc != 2) {
            return 2;
        }
        NSURL *base = [NSURL fileURLWithPath:@(argv[1])].URLByResolvingSymlinksInPath;
        Check(!NPExists(base), @"fresh private test root required");

        TestSystemAlias();
        TestBackupAndRestore(base);
        TestFailedBackupLeavesNothing(base);
        TestLinksAndTraversal(base);
        TestRetention(base);
        TestLaunchPolicy(base);
        TestSessionPruning(base);
        TestMalformedInput(base);
        TestTimings(base);
        TestFrameSummaryLookup(base);
        TestCatalog(base);

        printf("Native Play: %lu backend checks passed; all state is synthetic.\n", (unsigned long)checks);
    }
    return 0;
}
