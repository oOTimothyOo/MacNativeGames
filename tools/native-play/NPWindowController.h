#import <Cocoa/Cocoa.h>
#import "NPPages.h"

NS_ASSUME_NONNULL_BEGIN

// The main window, and the first-responder target of the menus and page buttons.
@interface NPWindowController : NSWindowController <NPPageActions, NSMenuItemValidation>
@property (readonly) NPLibraryController *library;
@property (readonly) NPSection section;
- (instancetype)initWithLibrary:(NPLibraryController *)library NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (void)showSection:(NPSection)section;

// Reached through the responder chain.
- (IBAction)addApps:(nullable id)sender;
- (IBAction)removeGame:(nullable id)sender;
- (IBAction)play:(nullable id)sender;
- (IBAction)openControllerSetup:(nullable id)sender;
- (IBAction)revealGame:(nullable id)sender;
- (IBAction)chooseArtwork:(nullable id)sender;
- (IBAction)resetArtwork:(nullable id)sender;
- (IBAction)refreshLibrary:(nullable id)sender;
- (IBAction)backUp:(nullable id)sender;
- (IBAction)selectSection:(NSMenuItem *)sender;
- (IBAction)focusSearch:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
