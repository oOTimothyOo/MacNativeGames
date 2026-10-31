// Native Play's colors, and the few view factories every page shares.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSColor *NPBackgroundColor(void);
FOUNDATION_EXPORT NSColor *NPSurfaceColor(void);
FOUNDATION_EXPORT NSColor *NPBorderColor(void);
FOUNDATION_EXPORT NSColor *NPMintColor(void);
FOUNDATION_EXPORT NSColor *NPMutedColor(void);
FOUNDATION_EXPORT NSColor *NPIconAccentColor(void);

FOUNDATION_EXPORT NSTextField *NPLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color);
// A single line that truncates instead of pushing its neighbors.
FOUNDATION_EXPORT NSTextField *NPLineLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color);
FOUNDATION_EXPORT NSButton *NPButton(NSString *title, NSString *identifier, id _Nullable target, SEL action);
FOUNDATION_EXPORT NSButton *NPPrimaryButton(NSString *title, NSString *identifier, id _Nullable target, SEL action);
// Keeps a primary button's dark label; assigning `title` directly would lose it.
FOUNDATION_EXPORT void NPSetPrimaryTitle(NSButton *button, NSString *title);
// A rounded card; add content to `contentView`.
FOUNDATION_EXPORT NSBox *NPPanel(void);

// Adds `child` to `parent` under Auto Layout, and pins its edges at the given inset.
FOUNDATION_EXPORT void NPAddSubview(NSView *parent, NSView *child);
FOUNDATION_EXPORT void NPPinEdges(NSView *parent, NSView *child, CGFloat inset);

// Rows selected in the app's mint instead of the system accent color.
@interface NPMintRowView : NSTableRowView
@end

// Shows a two-button sheet and runs `confirmed` if the person chooses `action`.
FOUNDATION_EXPORT void NPConfirm(NSWindow *window, NSString *message, NSString *detail, NSString *action, void (^confirmed)(void));

NS_ASSUME_NONNULL_END
