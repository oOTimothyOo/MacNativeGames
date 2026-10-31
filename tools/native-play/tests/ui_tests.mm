// Drives the real window and pages with a synthetic catalog in a throwaway home directory.
#import <Cocoa/Cocoa.h>
#import "NPAppDelegate.h"
#import "NPFoundation.h"
#include <cmath>
#include <sys/stat.h>

static NSUInteger checks;

static void Check(BOOL condition, NSString *name) {
    checks++;
    if (!condition) {
        fprintf(stderr, "UI FAIL: %s\n", name.UTF8String);
        exit(1);
    }
}

static NSArray<NPGame *> *SyntheticGames() {
    NSMutableArray *games = [NSMutableArray new];
    for (NSDictionary *row in @[
        @{@"id": NPJamboreeTitleID, @"title": @"Super Mario Party Jamboree", @"version": @"2.3.0", @"path": @"/Synthetic/Jamboree.app", @"controllers": @YES},
        @{@"id": @"0100000000000001", @"title": @"Sky Circuit", @"version": @"1.2.0", @"path": @"/Synthetic/Sky Circuit.app"},
        @{@"id": @"0100000000000002", @"title": @"Mosslight", @"version": @"0.9.4", @"path": @"/Synthetic/Mosslight.app"},
    ]) {
        [games addObject:[[NPGame alloc] initWithCatalogEntry:row]];
    }
    return games;
}

@interface SyntheticStore : NPStore
@property NSUInteger gameCount;
@end

@implementation SyntheticStore

- (NSArray<NPGame *> *)games {
    return [SyntheticGames() subarrayWithRange:NSMakeRange(0, self.gameCount)];
}

- (BOOL)gameIsRunning {
    return NO;
}

@end

static __kindof NSView *FindView(NSView *root, NSString *identifier) {
    if ([root.identifier isEqual:identifier]) {
        return root;
    }
    for (NSView *child in root.subviews) {
        NSView *found = FindView(child, identifier);
        if (found) {
            return found;
        }
    }
    return nil;
}

static NSArray<NSView *> *AllViews(NSView *root) {
    NSMutableArray *views = [NSMutableArray arrayWithObject:root];
    for (NSView *child in root.subviews) {
        [views addObjectsFromArray:AllViews(child)];
    }
    return views;
}

// The app's own Add and Play code, with a real library and a signed synthetic game.
static int AddAndPlay(NSURL *home, NSString *app) {
    NPStore *store = [[NPStore alloc] initWithRoot:NPChild(home, @"Library/Application Support/Native Play") home:home];
    NPCreatePrivateDirectory(NPChild(home, @"Documents"), NULL);
    [@"synthetic protected input" writeToURL:NPChild(home, @"Documents/blocked") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NPLibraryController *library = [[NPLibraryController alloc] initWithStore:store];
    library.errorHandler = ^(NSError *error) {
        fprintf(stderr, "Add and play failed: %s\n", error.localizedDescription.UTF8String);
        exit(1);
    };
    void (^waitUntil)(BOOL (^)(void), NSString *) = ^(BOOL (^condition)(void), NSString *name) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
        while (!condition() && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        }
        Check(condition(), name);
    };
    [library reload];
    Check(library.games.count == 0, @"the library starts empty");
    [library addApps:@[[NSURL fileURLWithPath:app]]];
    waitUntil(^BOOL { return !library.busy; }, @"adding a game finishes");
    Check(library.games.count == 1 && library.selectedGame, @"an added game is listed and selected");
    NPGame *game = library.selectedGame;

    [library playWithControllerSetup:NO];
    Check(library.busy, @"Play prepares without blocking the window");
    waitUntil(^BOOL { return !library.busy; }, @"Play starts the game");
    waitUntil(^BOOL { return !library.sessionRunning; }, @"the app notices the game ended");
    Check([library.status containsString:@"closed"], @"the app reports the game closed");

    NSArray<NSURL *> *sessions = [NSFileManager.defaultManager contentsOfDirectoryAtURL:store.sessionsURL includingPropertiesForKeys:nil options:0 error:NULL];
    Check(sessions.count == 1 && NPExists(NPChild(sessions.firstObject, @"fixture-passed")), @"the game ran under its restrictions");
    Check([store backupsForTitle:game.titleID].count == 1, @"progress was backed up before play");
    printf("Native Play: added and played a game through the app's own code (%lu checks).\n", (unsigned long)checks);
    [NSFileManager.defaultManager removeItemAtURL:home error:NULL];
    return 0;
}

@interface UITestRunner : NSObject <NSApplicationDelegate>
@property NPAppDelegate *app;
@property NSString *snapshotPath;
@property BOOL capturesScreen;
@property (readonly) NPWindowController *controller;
@property (readonly) NPLibraryController *library;
@property (readonly) NSView *contentView;
@end

@implementation UITestRunner

- (NPWindowController *)controller {
    return self.app.windowController;
}

- (NPLibraryController *)library {
    return self.app.library;
}

- (NSView *)contentView {
    return self.controller.window.contentView;
}

// Lets queued background work finish and report back to the main queue.
- (void)settle {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    do {
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    } while ((self.library.busy || self.library.loadingBackups) && deadline.timeIntervalSinceNow > 0);
    Check(!self.library.busy && !self.library.loadingBackups, @"background work finishes in time");
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    [self.contentView layoutSubtreeIfNeeded];
}

- (void)checkControlsInsideWindow:(NSString *)context {
    NSRect bounds = self.contentView.bounds;
    for (NSView *view in AllViews(self.contentView)) {
        if (view.hiddenOrHasHiddenAncestor || ![view isKindOfClass:NSControl.class] || view.enclosingScrollView) {
            continue;
        }
        NSRect frame = [view convertRect:view.bounds toView:self.contentView];
        if (NSIsEmptyRect(frame)) {
            continue;
        }
        Check(NSContainsRect(NSInsetRect(bounds, -1, -1), frame), [NSString stringWithFormat:@"%@: %@ stays inside the window", context, view.className]);
    }
}

- (void)checkLayoutAtEveryWindowSize {
    NSWindow *window = self.controller.window;
    // Largest first: shrinking is what leaves a grid with stale tile sizes.
    for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(1440, 920)], [NSValue valueWithSize:NSMakeSize(1140, 780)], [NSValue valueWithSize:NSMakeSize(960, 720)]]) {
        [window setContentSize:size.sizeValue];
        for (NSInteger section = 0; section < NPSectionCount; section++) {
            [self.controller showSection:(NPSection)section];
            [self settle];
            NSString *context = [NSString stringWithFormat:@"%.0f wide, section %ld", size.sizeValue.width, (long)section];
            Check(!self.contentView.hasAmbiguousLayout, [context stringByAppendingString:@": unambiguous layout"]);
            [self checkControlsInsideWindow:context];

            if (section == NPSectionLibrary) {
                NSCollectionView *grid = FindView(self.contentView, @"library-grid");
                Check(grid.visibleItems.count == 3, [context stringByAppendingString:@": three app tiles"]);
                for (NSCollectionViewItem *item in grid.visibleItems) {
                    Check(NSWidth(item.view.frame) >= 200 && NSMaxX(item.view.frame) <= NSWidth(grid.bounds) + 1, [context stringByAppendingString:@": tile fits the grid"]);
                    if (NSMinX(item.view.frame) > 1) {
                        Check(NSMinX(item.view.frame) >= NSWidth(item.view.frame), [context stringByAppendingString:@": tiles do not overlap"]);
                        Check(fmod(NSMinX(item.view.frame), NSWidth(item.view.frame) + 18) <= 2, [context stringByAppendingString:@": tiles fill each row evenly"]);
                    }
                }
                if (size.sizeValue.width >= 1140) {
                    Check(NSMinY([grid frameForItemAtIndex:2]) == NSMinY([grid frameForItemAtIndex:0]), [context stringByAppendingString:@": three tiles share a row"]);
                }
            }
            if (section == NPSectionBackups) {
                NSTableView *table = FindView(self.contentView, @"backups");
                Check(table.numberOfRows == 2, [context stringByAppendingString:@": two backup rows"]);
                NSView *cell = [table viewAtColumn:0 row:0 makeIfNecessary:YES];
                Check(NSWidth(cell.bounds) > 400, [context stringByAppendingString:@": backup row spans the table"]);
                Check(table.selectedRow == 0, [context stringByAppendingString:@": a backup starts selected"]);
            }
        }
    }
}

- (void)checkSidebarSelectsSections {
    NSTableView *sidebar = FindView(self.contentView, @"sidebar");
    Check(sidebar.numberOfRows == NPSectionCount, @"sidebar lists every section");
    for (NSInteger section = NPSectionCount - 1; section >= 0; section--) {
        [sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)section] byExtendingSelection:NO];
        [self settle];
        Check(self.controller.section == section, @"selecting a sidebar row shows its page");
    }
    [self.controller showSection:NPSectionBackups];
    Check(sidebar.selectedRow == NPSectionBackups, @"showing a page selects its sidebar row");
}

- (void)checkSelectionKeepsSearch {
    [self.controller showSection:NPSectionLibrary];
    [self settle];
    NSSearchField *search = FindView(self.contentView, @"library-search");
    NSCollectionView *grid = FindView(self.contentView, @"library-grid");
    search.stringValue = @"moss";
    [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:search];
    [self settle];
    Check([grid numberOfItemsInSection:0] == 1, @"search filters the grid, ignoring case");

    search.stringValue = @"o";
    [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:search];
    [self settle];
    Check([grid numberOfItemsInSection:0] == 2, @"a broader search shows more tiles");
    [self.library selectGame:SyntheticGames()[2]];
    [self settle];
    Check([search.stringValue isEqual:@"o"], @"selecting a game keeps the search text");
    Check([FindView(self.contentView, @"library-search") isEqual:search], @"selecting a game keeps the same search field");
    Check(grid.selectionIndexPaths.count == 1, @"the selected game's tile is selected");

    search.stringValue = @"no such game";
    [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:search];
    [self settle];
    Check([grid numberOfItemsInSection:0] == 0, @"an unmatched search empties the grid");
    search.stringValue = @"";
    [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:search];
    [self settle];
    Check([grid numberOfItemsInSection:0] == 3, @"clearing the search restores every tile");
    [self.library selectGame:SyntheticGames().firstObject];
    [self settle];
}

- (void)checkOptionsPersist {
    [self.controller showSection:NPSectionPerformance];
    [self settle];
    NSSwitch *hud = FindView(self.contentView, @"hud");
    Check(hud.state == NSControlStateValueOff, @"Metal HUD starts off");
    hud.state = NSControlStateValueOn;
    [NSApp sendAction:hud.action to:hud.target from:hud];
    [self settle];
    Check(self.library.options.metalHUD, @"native switch persists");
    Check(hud.state == NSControlStateValueOn, @"switch keeps its state after the reload");

    [self.library selectGame:SyntheticGames()[1]];
    [self settle];
    Check(hud.state == NSControlStateValueOff, @"the next game has its own preferences");
    [self.library selectGame:SyntheticGames().firstObject];
    [self settle];
    Check(hud.state == NSControlStateValueOn, @"returning restores this game's preference");
    hud.state = NSControlStateValueOff;
    [NSApp sendAction:hud.action to:hud.target from:hud];
    [self settle];
}

- (void)checkControllerPageFollowsGame {
    [self.controller showSection:NPSectionControllers];
    [self settle];
    NSButton *open = FindView(self.contentView, @"open-controllers");
    Check([open.title isEqual:@"Open controller setup"], @"a declared controller setup is offered");
    [self.library selectGame:SyntheticGames()[1]];
    [self settle];
    Check([open.title isEqual:@"Open game"], @"a game without the shared setup opens plainly");
    [self.library selectGame:SyntheticGames().firstObject];
    [self settle];
}

- (void)checkBackupActionsRunOffTheMainThread {
    [self.controller showSection:NPSectionBackups];
    [self settle];
    NSTableView *table = FindView(self.contentView, @"backups");
    NSButton *backup = FindView(self.contentView, @"backup-now");
    Check(backup.enabled, @"backup is available");
    [self.library backUp];
    Check(self.library.busy, @"backing up reports busy immediately, without blocking");
    Check(!backup.enabled, @"backup button disables while busy");
    [self settle];
    Check(!self.library.busy, @"backup finishes");
    [self.library loadBackups];
    [self settle];
    Check(table.numberOfRows == 3, @"the new backup appears");
    Check(backup.enabled, @"backup button returns");

    NSButton *restore = FindView(self.contentView, @"restore-backup");
    Check(restore.enabled, @"restore is available with a selected backup");
    [self.library restoreBackup:self.library.backups.lastObject];
    [self settle];
    [self.library loadBackups];
    [self settle];
    Check(table.numberOfRows == 4, @"restoring keeps a pre-restore backup");
    Check([((NSTextField *)FindView(self.contentView, @"status")).stringValue containsString:@"restored"], @"status reports the restore");
}

- (void)checkArtwork {
    [self.controller showSection:NPSectionLibrary];
    [self settle];
    NPGame *game = self.library.selectedGame;
    NPArtworkView *hero = FindView(self.contentView, @"hero-artwork");
    Check(hero.image != nil, @"a game without artwork of its own gets a placeholder");

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:64 pixelsHigh:36 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSColor.blackColor setFill];
    NSRectFill(NSMakeRect(0, 0, 64, 36));
    NSGraphicsContext.currentContext = nil;
    double dark = NPArtworkScore(bitmap.CGImage);
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [[NSColor colorWithSRGBRed:.1 green:.4 blue:.9 alpha:1] setFill];
    NSRectFill(NSMakeRect(0, 0, 64, 36));
    NSGraphicsContext.currentContext = nil;
    Check(NPArtworkScore(bitmap.CGImage) > dark, @"a colorful frame beats a dark one");

    NSURL *picture = NPChild(self.library.store.home, @"picture.png");
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToURL:picture atomically:YES];
    NSURL *cache = NPChild(self.library.store.root, [NSString stringWithFormat:@"Artwork/%@.jpg", game.key]);
    [self.library setArtworkFromURL:picture];
    [self settle];
    Check(NPExists(cache), @"a chosen picture is kept in the private folder");
    Check((([NSFileManager.defaultManager attributesOfItemAtPath:cache.path error:NULL].filePosixPermissions) & 0777) == 0600, @"kept artwork is private");
    Check(hero.image == [self.library.artwork imageForGame:game] && hero.image.size.width == 64, @"the hero shows the chosen picture");
    [self.library resetArtwork];
    [self settle];
    Check(!NPExists(cache) && hero.image.size.width != 64, @"resetting forgets the chosen picture");

    NSURL *notPicture = NPChild(self.library.store.home, @"not-a-picture.png");
    [@"synthetic" writeToURL:notPicture atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    __block BOOL reported = NO;
    void (^original)(NSError *) = self.library.errorHandler;
    self.library.errorHandler = ^(NSError *error) {
        reported = YES;
    };
    [self.library setArtworkFromURL:notPicture];
    self.library.errorHandler = original;
    Check(reported && !NPExists(cache), @"a file that is not a picture is refused");
}

- (void)checkLibrarySizes {
    SyntheticStore *store = (SyntheticStore *)self.library.store;
    [self.controller showSection:NPSectionLibrary];
    NSSearchField *search = FindView(self.contentView, @"library-search");
    NSView *grid = FindView(self.contentView, @"library-grid");
    NSButton *play = FindView(self.contentView, @"play");
    NSButton *firstApp = FindView(self.contentView, @"add-first-app");
    NSView *hero = FindView(self.contentView, @"hero-artwork");

    store.gameCount = 1;
    [self.library reload];
    [self settle];
    Check(search.hiddenOrHasHiddenAncestor && grid.hiddenOrHasHiddenAncestor, @"one game needs no search or shelf");
    Check(NSHeight(hero.frame) > 400, @"one game's artwork fills the page");
    Check(play.enabled && !play.hiddenOrHasHiddenAncestor && firstApp.hiddenOrHasHiddenAncestor, @"one game can be played");

    store.gameCount = 0;
    [self.library reload];
    [self settle];
    Check(play.hiddenOrHasHiddenAncestor && !firstApp.hiddenOrHasHiddenAncestor && firstApp.enabled, @"an empty library offers adding a game");
    for (NSInteger section = 0; section < NPSectionCount; section++) {
        [self.controller showSection:(NPSection)section];
        [self settle];
        Check(!self.contentView.hasAmbiguousLayout, @"an empty library still lays out");
    }

    store.gameCount = 3;
    [self.library reload];
    [self.controller showSection:NPSectionLibrary];
    [self settle];
    Check(!search.hiddenOrHasHiddenAncestor && !grid.hiddenOrHasHiddenAncestor, @"adding games brings the shelf back");
    Check(NSHeight(hero.frame) <= 300, @"the artwork makes room for the shelf");
}

- (void)checkMenus {
    NSMenu *menu = NSApp.mainMenu;
    NSMutableSet<NSString *> *selectors = [NSMutableSet new];
    for (NSMenuItem *top in menu.itemArray) {
        for (NSMenuItem *item in top.submenu.itemArray) {
            if (item.action) {
                [selectors addObject:NSStringFromSelector(item.action)];
            }
        }
    }
    for (NSString *required in @[@"terminate:", @"hide:", @"cut:", @"copy:", @"paste:", @"selectAll:", @"undo:", @"performClose:", @"performMiniaturize:", @"addApps:", @"backUp:", @"selectSection:", @"refreshLibrary:", @"play:", @"chooseArtwork:", @"resetArtwork:", @"removeGame:"]) {
        Check([selectors containsObject:required], [@"menu has " stringByAppendingString:required]);
    }
    for (NSString *action in @[@"addApps:", @"backUp:", @"play:", @"selectSection:", @"refreshLibrary:", @"focusSearch:", @"openControllerSetup:", @"revealGame:", @"chooseArtwork:", @"resetArtwork:", @"removeGame:"]) {
        Check([self.controller respondsToSelector:NSSelectorFromString(action)], [@"window controller handles " stringByAppendingString:action]);
    }
}

- (void)writeSnapshot:(NSString *)path {
    NSWindow *window = self.controller.window;
    if (self.capturesScreen) {
        // What the person sees. Needs Screen Recording permission for the calling terminal.
        NSTask *capture = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/sbin/screencapture"]
                                                      arguments:@[@"-x", @"-o", [NSString stringWithFormat:@"-l%ld", (long)window.windowNumber], path]
                                                          error:NULL
                                             terminationHandler:nil];
        [capture waitUntilExit];
        Check(capture.terminationStatus == 0, @"window captured from the screen");
        return;
    }
    // Off screen: sidebar glass and active-window tints do not render.
    [window displayIfNeeded];
    NSView *view = window.contentView;
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

- (void)writeSnapshots {
    NSWindow *window = self.controller.window;
    [window setContentSize:NSMakeSize(1140, 780)];
    if (self.capturesScreen) {
        NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
        [window makeKeyAndOrderFront:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Cooperative activation will not take focus from the terminal running this tool.
        [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    }
    NSArray<NSString *> *names = @[@"Library", @"Backups", @"Performance", @"Controllers"];
    for (NSUInteger i = 0; i < names.count; i++) {
        [self.controller showSection:(NPSection)i];
        [self settle];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:self.capturesScreen ? .3 : 0]];
        [self writeSnapshot:i == 0 ? self.snapshotPath : [[self.snapshotPath.stringByDeletingPathExtension stringByAppendingFormat:@"-%@", names[i]] stringByAppendingPathExtension:@"png"]];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self.app applicationDidFinishLaunching:notification];
    // From a timer, because a run loop nested in a main-queue block never drains that queue.
    [self performSelector:@selector(runChecks) withObject:nil afterDelay:0];
}

- (void)runChecks {
    [self checkLayoutAtEveryWindowSize];
    [self checkSidebarSelectsSections];
    [self checkSelectionKeepsSearch];
    [self checkOptionsPersist];
    [self checkControllerPageFollowsGame];
    [self checkBackupActionsRunOffTheMainThread];
    [self checkArtwork];
    [self checkLibrarySizes];
    [self checkMenus];
    if (self.snapshotPath) {
        [self writeSnapshots];
    }
    printf("Native Play: %lu UI checks passed on the real window (synthetic data).\n", (unsigned long)checks);
    fflush(stdout);
    [NSFileManager.defaultManager removeItemAtURL:self.library.store.home error:NULL];
    exit(0);
}

@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        umask(0077);
        // The launcher asks this same executable to probe the restriction profile.
        if (argc == 5 && !strcmp(argv[1], "--sandbox-probe")) {
            return NPSandboxProbe(argv[2], argv[3], argv[4]);
        }
        NSURL *temporary = [NSURL fileURLWithPath:NSTemporaryDirectory()].URLByResolvingSymlinksInPath;
        NSURL *home = NPChild(temporary, [@"native-play-ui-" stringByAppendingString:NSUUID.UUID.UUIDString]);
        if (argc == 3 && !strcmp(argv[1], "--add-and-play")) {
            return AddAndPlay(home, @(argv[2]));
        }
        SyntheticStore *store = [[SyntheticStore alloc] initWithRoot:NPChild(home, @"Library/Application Support/Native Play") home:home];
        store.gameCount = SyntheticGames().count;
        if (!store) {
            fputs("Could not create the synthetic home.\n", stderr);
            return 1;
        }
        for (NPGame *game in SyntheticGames()) {
            NSURL *save = NPChild([store stateURLForTitle:game.titleID], @"save");
            NPCreatePrivateDirectory(save, NULL);
            [@"synthetic progress" writeToURL:NPChild(save, @"preview") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            for (NSString *label in @[@"Before play", @"Manual backup"]) {
                NSError *error = nil;
                if (![store backupTitle:game.titleID label:label error:&error]) {
                    fprintf(stderr, "Synthetic setup failed: %s\n", error.localizedDescription.UTF8String);
                    return 1;
                }
            }
        }

        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyProhibited;
        UITestRunner *runner = [UITestRunner new];
        runner.app = [[NPAppDelegate alloc] initWithStore:store];
        runner.app.hidesWindow = YES;
        if (argc == 3 && (!strcmp(argv[1], "--snapshot") || !strcmp(argv[1], "--screen-snapshot"))) {
            runner.snapshotPath = @(argv[2]);
            runner.capturesScreen = !strcmp(argv[1], "--screen-snapshot");
        }
        application.delegate = runner;
        [application run];
    }
    return 0;
}
