#import "NPDetailViewController.h"
#import "NPTheme.h"

@interface NPDetailViewController ()
@property (readonly) NPLibraryController *library;
@property (readonly, copy) NSArray<NPPageViewController *> *pages;
@property (readwrite, nullable) NPPageViewController *page;
@property NSTextField *pageTitle;
@property NSView *accessoryContainer;
@property NSTextField *statusLabel;
@property NSProgressIndicator *spinner;
@property NSView *pageContainer;
@end

@implementation NPDetailViewController

- (instancetype)initWithLibrary:(NPLibraryController *)library pages:(NSArray<NPPageViewController *> *)pages {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _library = library;
        _pages = [pages copy];
    }
    return self;
}

- (void)loadView {
    NSBox *root = [NSBox new];
    root.boxType = NSBoxCustom;
    root.titlePosition = NSNoTitle;
    root.borderWidth = 0;
    root.cornerRadius = 0;
    root.fillColor = NPBackgroundColor();
    root.contentViewMargins = NSZeroSize;
    self.view = root;
    NSView *content = root.contentView;

    self.pageTitle = NPLineLabel(@"", 26, NSFontWeightBold, NSColor.whiteColor);
    self.accessoryContainer = [NSView new];
    self.statusLabel = NPLineLabel(@"", 12, NSFontWeightRegular, NPMutedColor());
    self.statusLabel.identifier = @"status";
    self.spinner = [NSProgressIndicator new];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    self.pageContainer = [NSView new];

    NSStackView *statusRow = [NSStackView stackViewWithViews:@[self.spinner, self.statusLabel]];
    statusRow.spacing = 8;
    statusRow.detachesHiddenViews = YES;
    for (NSView *view in @[self.pageTitle, self.accessoryContainer, self.pageContainer, statusRow]) {
        NPAddSubview(content, view);
    }
    NSLayoutGuide *safe = content.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.pageTitle.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:32],
        [self.pageTitle.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6],
        [self.pageTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.accessoryContainer.leadingAnchor constant:-24],
        [self.accessoryContainer.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-32],
        [self.accessoryContainer.centerYAnchor constraintEqualToAnchor:self.pageTitle.centerYAnchor],
        [self.pageContainer.leadingAnchor constraintEqualToAnchor:self.pageTitle.leadingAnchor],
        [self.pageContainer.trailingAnchor constraintEqualToAnchor:self.accessoryContainer.trailingAnchor],
        [self.pageContainer.topAnchor constraintEqualToAnchor:self.pageTitle.bottomAnchor constant:20],
        // Room stays reserved for the status line, so nothing moves when it appears.
        [self.pageContainer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-40],
        [statusRow.leadingAnchor constraintEqualToAnchor:self.pageTitle.leadingAnchor],
        [statusRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.accessoryContainer.trailingAnchor],
        [statusRow.centerYAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
    ]];
}

- (void)showPageAtIndex:(NSUInteger)index {
    (void)self.view;
    NPPageViewController *next = self.pages[index];
    if (next == self.page) {
        return;
    }
    [self.page.view removeFromSuperview];
    [self.page removeFromParentViewController];
    self.page = next;
    [self addChildViewController:next];
    NPPinEdges(self.pageContainer, next.view, 0);
    self.pageTitle.stringValue = next.title;
    [self.accessoryContainer.subviews.firstObject removeFromSuperview];
    NSView *accessory = next.headerAccessory;
    if (accessory) {
        NPPinEdges(self.accessoryContainer, accessory, 0);
    }
    [next reload];
}

- (void)reload {
    (void)self.view;
    self.statusLabel.stringValue = self.library.status;
    self.spinner.hidden = !self.library.busy;
    if (self.library.busy) {
        [self.spinner startAnimation:nil];
    } else {
        [self.spinner stopAnimation:nil];
    }
    [self.page reload];
}

@end
