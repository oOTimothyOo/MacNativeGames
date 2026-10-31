#import "NPWindowController.h"
#import "NPDetailViewController.h"
#import "NPSidebarViewController.h"
#import "NPTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat SidebarWidth = 200;

@interface NPWindowController () <NSWindowDelegate>
@property (readwrite) NPLibraryController *library;
@property (readwrite) NPSection section;
@property NPSidebarViewController *sidebar;
@property NPDetailViewController *detail;
@property NPLibraryPage *libraryPage;
@end

@implementation NPWindowController

- (instancetype)initWithLibrary:(NPLibraryController *)library {
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1140, 780) styleMask:style backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        _library = library;
        window.title = @"Native Play";
        window.titleVisibility = NSWindowTitleHidden;
        window.titlebarAppearsTransparent = YES;
        window.backgroundColor = NPBackgroundColor();
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        window.delegate = self;

        self.libraryPage = [[NPLibraryPage alloc] initWithLibrary:library actions:self];
        NSArray<NPPageViewController *> *pages = @[
            self.libraryPage,
            [[NPBackupsPage alloc] initWithLibrary:library actions:self],
            [[NPPerformancePage alloc] initWithLibrary:library actions:self],
            [[NPControllersPage alloc] initWithLibrary:library actions:self],
        ];
        self.detail = [[NPDetailViewController alloc] initWithLibrary:library pages:pages];
        self.sidebar = [NPSidebarViewController new];
        __weak NPWindowController *weakSelf = self;
        self.sidebar.sectionChanged = ^(NPSection section) {
            [weakSelf showSection:section];
        };

        NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:self.sidebar];
        sidebarItem.canCollapse = NO;
        sidebarItem.minimumThickness = SidebarWidth;
        sidebarItem.maximumThickness = SidebarWidth;
        NSSplitViewController *split = [NSSplitViewController new];
        [split addSplitViewItem:sidebarItem];
        [split addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.detail]];
        window.contentViewController = split;

        // Setting the content view controller sizes the window to its content first.
        window.minSize = NSMakeSize(960, 680);
        [window setContentSize:NSMakeSize(1140, 780)];
        [window center];
        window.frameAutosaveName = @"NativePlayMain";

        [self showSection:NPSectionLibrary];
        library.errorHandler = ^(NSError *error) {
            [weakSelf presentFailure:error];
        };
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(libraryChanged:) name:NPLibraryDidChangeNotification object:library];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)libraryChanged:(NSNotification *)notification {
    [self.detail reload];
}

- (void)showSection:(NPSection)section {
    self.section = section;
    self.sidebar.section = section;
    [self.detail showPageAtIndex:(NSUInteger)section];
    [self.detail reload];
}

- (void)presentFailure:(NSError *)error {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Native Play";
    alert.informativeText = error.localizedDescription ?: @"The action could not be completed.";
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - Actions

- (void)addApps:(id)sender {
    if (self.library.busy) {
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeApplicationBundle];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.prompt = @"Add";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            [self.library addApps:panel.URLs];
            [self showSection:NPSectionLibrary];
        }
    }];
}

- (void)removeGame:(id)sender {
    NPConfirm(self.window, @"Remove this game from the library?", @"The installed app, saves and backups stay on disk.", @"Remove", ^{
        [self.library removeSelectedGame];
    });
}

- (void)restoreBackup:(NPBackup *)backup {
    NPConfirm(self.window, @"Restore this backup?", @"Your current progress and controller settings are backed up first.", @"Restore", ^{
        [self.library restoreBackup:backup];
    });
}

- (void)play:(id)sender {
    [self.library playWithControllerSetup:NO];
}

- (void)openControllerSetup:(id)sender {
    [self showSection:NPSectionControllers];
}

- (void)revealGame:(id)sender {
    [self.library revealSelectedGame];
}

- (void)chooseArtwork:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeImage];
    panel.prompt = @"Use Picture";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            [self.library setArtworkFromURL:panel.URL];
        }
    }];
}

- (void)resetArtwork:(id)sender {
    [self.library resetArtwork];
}

- (void)refreshLibrary:(id)sender {
    [self.library reload];
}

- (void)backUp:(id)sender {
    [self.library backUp];
    [self showSection:NPSectionBackups];
}

- (void)selectSection:(NSMenuItem *)sender {
    [self showSection:(NPSection)sender.tag];
}

- (void)focusSearch:(id)sender {
    [self showSection:NPSectionLibrary];
    [self.window makeFirstResponder:self.libraryPage.searchField];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    NPLibraryController *library = self.library;
    SEL action = item.action;
    if (action == @selector(addApps:)) {
        return !library.busy;
    }
    if (action == @selector(play:)) {
        return library.selectedGame && !library.busy;
    }
    if (action == @selector(removeGame:)) {
        return library.selectedGame && !library.busy && !library.sessionRunning;
    }
    if (action == @selector(revealGame:) || action == @selector(chooseArtwork:) || action == @selector(resetArtwork:) || action == @selector(openControllerSetup:)) {
        return library.selectedGame != nil;
    }
    if (action == @selector(backUp:)) {
        return library.selectedGame && !library.busy && !library.gameRunning;
    }
    if (action == @selector(focusSearch:)) {
        return library.games.count > 1;
    }
    if (action == @selector(selectSection:)) {
        item.state = item.tag == self.section ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self.library refreshRunningState];
}

@end
