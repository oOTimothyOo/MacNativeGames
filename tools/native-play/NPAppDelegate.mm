#import "NPAppDelegate.h"
#import "NPPages.h"

NSMenu *NPMainMenu(void) {
    NSMenu *bar = [NSMenu new];
    NSMenu *(^submenu)(NSString *) = ^NSMenu *(NSString *title) {
        NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
        [bar addItemWithTitle:title action:nil keyEquivalent:@""].submenu = menu;
        return menu;
    };

    NSMenu *application = submenu(@"Native Play");
    [application addItemWithTitle:@"About Native Play" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [application addItem:NSMenuItem.separatorItem];
    NSMenuItem *services = [application addItemWithTitle:@"Services" action:nil keyEquivalent:@""];
    services.submenu = [[NSMenu alloc] initWithTitle:@"Services"];
    NSApp.servicesMenu = services.submenu;
    [application addItem:NSMenuItem.separatorItem];
    [application addItemWithTitle:@"Hide Native Play" action:@selector(hide:) keyEquivalent:@"h"];
    [application addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"].keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [application addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [application addItem:NSMenuItem.separatorItem];
    [application addItemWithTitle:@"Quit Native Play" action:@selector(terminate:) keyEquivalent:@"q"];

    NSMenu *file = submenu(@"File");
    [file addItemWithTitle:@"Add Native Apps…" action:@selector(addApps:) keyEquivalent:@"o"];
    [file addItemWithTitle:@"Back Up Selected Game" action:@selector(backUp:) keyEquivalent:@"b"];
    [file addItem:NSMenuItem.separatorItem];
    [file addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];

    NSMenu *edit = submenu(@"Edit");
    [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [edit addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [edit addItem:NSMenuItem.separatorItem];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [edit addItem:NSMenuItem.separatorItem];
    [edit addItemWithTitle:@"Find a Game" action:@selector(focusSearch:) keyEquivalent:@"f"];

    NSMenu *view = submenu(@"View");
    NSArray<NSString *> *sections = @[@"Library", @"Backups", @"Performance", @"Controllers"];
    for (NSUInteger i = 0; i < sections.count; i++) {
        NSMenuItem *item = [view addItemWithTitle:sections[i] action:@selector(selectSection:) keyEquivalent:[NSString stringWithFormat:@"%lu", (unsigned long)i + 1]];
        item.tag = (NSInteger)i;
    }
    [view addItem:NSMenuItem.separatorItem];
    [view addItemWithTitle:@"Refresh Library" action:@selector(refreshLibrary:) keyEquivalent:@"r"];
    [view addItem:NSMenuItem.separatorItem];
    [view addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"].keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;

    NSMenu *game = submenu(@"Game");
    [game addItemWithTitle:@"Play" action:@selector(play:) keyEquivalent:@"p"];
    [game addItem:NSMenuItem.separatorItem];
    for (NSMenuItem *item in NPGameActionsMenu().itemArray.copy) {
        [item.menu removeItem:item];
        [game addItem:item];
    }

    NSMenu *window = submenu(@"Window");
    [window addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [window addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [window addItem:NSMenuItem.separatorItem];
    [window addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    NSApp.windowsMenu = window;

    return bar;
}

@interface NPAppDelegate ()
@property (readwrite) NPLibraryController *library;
@property (readwrite) NPWindowController *windowController;
@end

@implementation NPAppDelegate

- (instancetype)initWithStore:(NPStore *)store {
    if ((self = [super init])) {
        _library = [[NPLibraryController alloc] initWithStore:store];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSApp.mainMenu = NPMainMenu();
    [self.library reload];
    self.windowController = [[NPWindowController alloc] initWithLibrary:self.library];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(libraryChanged:) name:NPLibraryDidChangeNotification object:self.library];
    if (!self.hidesWindow) {
        [self.windowController showWindow:nil];
        [NSApp activate];
    }
}

// The window can close while a game plays; finish once that game has ended.
- (void)libraryChanged:(NSNotification *)notification {
    if (!self.hidesWindow && !self.windowController.window.visible && [self applicationShouldTerminateAfterLastWindowClosed:NSApp]) {
        [NSApp terminate:nil];
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    if (!visible) {
        [self.windowController showWindow:nil];
    }
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {
    return !self.library.sessionRunning && !self.library.busy;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)application {
    return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self.library refreshRunningState];
}

@end
