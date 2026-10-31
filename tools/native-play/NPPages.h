// The four pages in the main window's detail area.
#import <Cocoa/Cocoa.h>
#import "NPLibraryController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NPSection) {
    NPSectionLibrary,
    NPSectionBackups,
    NPSectionPerformance,
    NPSectionControllers,
};
static const NSInteger NPSectionCount = 4;

// Actions that need a sheet first. Everything else travels the responder chain.
@protocol NPPageActions <NSObject>
- (void)restoreBackup:(NPBackup *)backup;
@end

// What the selected game can do, for its "…" button, right-click and the Game menu.
// The items' actions reach the window controller through the responder chain.
FOUNDATION_EXPORT NSMenu *NPGameActionsMenu(void);

@interface NPPageViewController : NSViewController
@property (readonly) NPLibraryController *library;
@property (readonly, weak) id<NPPageActions> actions;
// Shown at the trailing end of the page's title.
@property (readonly, nullable) NSView *headerAccessory;
- (instancetype)initWithLibrary:(NPLibraryController *)library actions:(id<NPPageActions>)actions NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
// Brings the page up to date with the library, keeping selections and text the person made.
- (void)reload;
@end

// Picks the selected game. Takes no space when there is only one game to pick.
@interface NPGamePicker : NSStackView
- (instancetype)initWithLibrary:(NPLibraryController *)library;
- (void)reload;
@end

@interface NPLibraryPage : NPPageViewController
@property (readonly) NSSearchField *searchField;
@end

@interface NPBackupsPage : NPPageViewController @end
@interface NPPerformancePage : NPPageViewController @end
@interface NPControllersPage : NPPageViewController @end

NS_ASSUME_NONNULL_END
