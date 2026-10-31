#import <Cocoa/Cocoa.h>
#import "NPWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface NPAppDelegate : NSObject <NSApplicationDelegate>
@property (readonly) NPLibraryController *library;
@property (readonly) NPWindowController *windowController;
// Leaves the window off screen and the app inactive, for automated UI tests.
@property BOOL hidesWindow;
- (instancetype)initWithStore:(NPStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

// The complete menu bar, whose editing items make the search field's shortcuts work.
FOUNDATION_EXPORT NSMenu *NPMainMenu(void);

NS_ASSUME_NONNULL_END
