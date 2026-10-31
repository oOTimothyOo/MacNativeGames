#import "NPTheme.h"

static NSColor *RGB(CGFloat red, CGFloat green, CGFloat blue) {
    return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:1];
}

NSColor *NPBackgroundColor(void) { return RGB(.065, .075, .09); }
NSColor *NPSurfaceColor(void) { return RGB(.09, .11, .13); }
NSColor *NPBorderColor(void) { return RGB(.15, .18, .20); }
NSColor *NPMintColor(void) { return RGB(.43, .96, .74); }
NSColor *NPMutedColor(void) { return RGB(.60, .65, .70); }
NSColor *NPIconAccentColor(void) { return RGB(.22, .48, .58); }

NSTextField *NPLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

NSTextField *NPLineLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = NPLabel(text, size, weight, color);
    label.maximumNumberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

NSButton *NPButton(NSString *title, NSString *identifier, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.identifier = identifier;
    button.controlSize = NSControlSizeLarge;
    return button;
}

NSButton *NPPrimaryButton(NSString *title, NSString *identifier, id target, SEL action) {
    NSButton *button = NPButton(title, identifier, target, action);
    button.bezelColor = NPMintColor();
    NPSetPrimaryTitle(button, title);
    return button;
}

void NPSetPrimaryTitle(NSButton *button, NSString *title) {
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: button.font,
        NSForegroundColorAttributeName: NPBackgroundColor(),
    }];
}

NSBox *NPPanel(void) {
    NSBox *panel = [NSBox new];
    panel.boxType = NSBoxCustom;
    panel.titlePosition = NSNoTitle;
    panel.fillColor = NPSurfaceColor();
    panel.borderColor = NPBorderColor();
    panel.borderWidth = 1;
    panel.cornerRadius = 12;
    panel.contentViewMargins = NSZeroSize;
    return panel;
}

void NPAddSubview(NSView *parent, NSView *child) {
    child.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:child];
}

void NPPinEdges(NSView *parent, NSView *child, CGFloat inset) {
    NPAddSubview(parent, child);
    [NSLayoutConstraint activateConstraints:@[
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:inset],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-inset],
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:inset],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-inset],
    ]];
}

@implementation NPMintRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 6, 3) xRadius:9 yRadius:9];
    [[NSColor colorWithSRGBRed:.15 green:.25 blue:.23 alpha:1] setFill];
    [path fill];
    [[NPMintColor() colorWithAlphaComponent:.24] setStroke];
    [path stroke];
}

@end

void NPConfirm(NSWindow *window, NSString *message, NSString *detail, NSString *action, void (^confirmed)(void)) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = message;
    alert.informativeText = detail;
    [alert addButtonWithTitle:action];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            confirmed();
        }
    }];
}
