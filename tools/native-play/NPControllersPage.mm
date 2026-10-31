#import "NPPages.h"
#import "NPTheme.h"

@interface NPControllersPage ()
@property NPGamePicker *picker;
@property NSTextField *heading;
@property NSTextField *detail;
@property NSButton *openButton;
@end

@implementation NPControllersPage

- (NSString *)title {
    return @"Controllers";
}

- (void)loadView {
    self.picker = [[NPGamePicker alloc] initWithLibrary:self.library];
    self.heading = NPLabel(@"", 19, NSFontWeightSemibold, NSColor.whiteColor);
    self.detail = NPLabel(@"", 14, NSFontWeightRegular, NPMutedColor());
    self.openButton = NPPrimaryButton(@"", @"open-controllers", self, @selector(open:));

    NSBox *panel = NPPanel();
    NSView *content = panel.contentView;
    for (NSView *view in @[self.heading, self.detail, self.openButton]) {
        NPAddSubview(content, view);
    }
    NSStackView *stack = [NSStackView stackViewWithViews:@[self.picker, panel]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;
    stack.detachesHiddenViews = YES;

    NSView *page = [NSView new];
    self.view = page;
    NPAddSubview(page, stack);
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:page.topAnchor],
        [panel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.heading.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [self.heading.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [self.heading.topAnchor constraintEqualToAnchor:content.topAnchor constant:24],
        [self.detail.leadingAnchor constraintEqualToAnchor:self.heading.leadingAnchor],
        [self.detail.trailingAnchor constraintEqualToAnchor:self.heading.trailingAnchor],
        [self.detail.topAnchor constraintEqualToAnchor:self.heading.bottomAnchor constant:10],
        [self.openButton.leadingAnchor constraintEqualToAnchor:self.heading.leadingAnchor],
        [self.openButton.topAnchor constraintEqualToAnchor:self.detail.bottomAnchor constant:20],
        [self.openButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
    ]];
}

- (void)reload {
    (void)self.view;
    [self.picker reload];
    BOOL supported = self.library.selectedGame.supportsControllerSetup;
    self.heading.stringValue = supported ? @"Every controller. The right player." : @"This game has its own controller menu.";
    self.detail.stringValue = supported
        ? @"Turn your controllers on, then assign players, swap buttons and test sticks. In the game, press F2 to come back here."
        : @"Open the game and use its own menu.";
    NPSetPrimaryTitle(self.openButton, supported ? @"Open controller setup" : @"Open game");
    self.openButton.enabled = self.library.selectedGame && !self.library.busy;
}

- (void)open:(id)sender {
    [self.library playWithControllerSetup:self.library.selectedGame.supportsControllerSetup];
}

@end
