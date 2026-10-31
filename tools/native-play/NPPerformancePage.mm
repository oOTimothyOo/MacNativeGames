#import "NPPages.h"
#import "NPTheme.h"

static const CGFloat SettingRowHeight = 68;

// One row of the settings group: a title, a short explanation and a switch.
static NSView *SettingRow(NSString *title, NSString *detail, NSSwitch *toggle) {
    NSView *row = [NSView new];
    NSTextField *heading = NPLineLabel(title, 14, NSFontWeightMedium, NSColor.whiteColor);
    NSTextField *explanation = NPLineLabel(detail, 12, NSFontWeightRegular, NPMutedColor());
    toggle.accessibilityLabel = title;
    for (NSView *view in @[heading, explanation, toggle]) {
        NPAddSubview(row, view);
    }
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:SettingRowHeight],
        [heading.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:20],
        [heading.bottomAnchor constraintEqualToAnchor:row.centerYAnchor constant:-1],
        [heading.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-16],
        [explanation.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
        [explanation.topAnchor constraintEqualToAnchor:row.centerYAnchor constant:3],
        [explanation.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-16],
        [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-20],
        [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

static NSBox *Separator(void) {
    NSBox *line = [NSBox new];
    line.boxType = NSBoxCustom;
    line.titlePosition = NSNoTitle;
    line.borderWidth = 0;
    line.fillColor = NPBorderColor();
    [line.heightAnchor constraintEqualToConstant:1].active = YES;
    return line;
}

@interface NPPerformancePage ()
@property NPGamePicker *picker;
@property NSSwitch *fullscreenSwitch;
@property NSSwitch *hudSwitch;
@property NSSwitch *recordSwitch;
@property NSTextField *reportHeading;
@property NSTextField *report;
@end

@implementation NPPerformancePage

- (NSString *)title {
    return @"Performance";
}

- (NSSwitch *)switchWithIdentifier:(NSString *)identifier {
    NSSwitch *toggle = [NSSwitch new];
    toggle.identifier = identifier;
    toggle.target = self;
    toggle.action = @selector(optionChanged:);
    return toggle;
}

- (void)loadView {
    self.picker = [[NPGamePicker alloc] initWithLibrary:self.library];
    self.fullscreenSwitch = [self switchWithIdentifier:@"fullscreen"];
    self.hudSwitch = [self switchWithIdentifier:@"hud"];
    self.recordSwitch = [self switchWithIdentifier:@"record"];
    self.reportHeading = NPLineLabel(@"Last recording", 13, NSFontWeightMedium, NSColor.whiteColor);
    self.report = NPLabel(@"", 13, NSFontWeightRegular, NPMutedColor());

    NSArray<NSView *> *rows = @[
        SettingRow(@"Full screen", @"macOS Game Mode needs it.", self.fullscreenSwitch),
        Separator(),
        SettingRow(@"Metal performance stats", @"Frame rate and GPU memory, over the game.", self.hudSwitch),
        Separator(),
        SettingRow(@"Record next session", @"Frame timings for one session, then off.", self.recordSwitch),
    ];
    NSStackView *group = [NSStackView stackViewWithViews:rows];
    group.orientation = NSUserInterfaceLayoutOrientationVertical;
    group.spacing = 0;
    NSBox *panel = NPPanel();
    NPPinEdges(panel.contentView, group, 0);

    NSStackView *stack = [NSStackView stackViewWithViews:@[self.picker, panel, self.reportHeading, self.report]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.detachesHiddenViews = YES;
    [stack setCustomSpacing:16 afterView:self.picker];
    [stack setCustomSpacing:22 afterView:panel];

    NSView *page = [NSView new];
    self.view = page;
    NPAddSubview(page, stack);
    NSMutableArray<NSLayoutConstraint *> *constraints = [@[
        [stack.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:page.topAnchor],
        [panel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ] mutableCopy];
    for (NSView *row in rows) {
        [constraints addObject:[row.widthAnchor constraintEqualToAnchor:group.widthAnchor]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)reload {
    (void)self.view;
    [self.picker reload];
    BOOL hasGame = self.library.selectedGame != nil;
    NPLaunchOptions *options = self.library.options;
    self.fullscreenSwitch.state = options.fullscreen ? NSControlStateValueOn : NSControlStateValueOff;
    self.hudSwitch.state = options.metalHUD ? NSControlStateValueOn : NSControlStateValueOff;
    self.recordSwitch.state = options.recordNextSession ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSSwitch *toggle in @[self.fullscreenSwitch, self.hudSwitch, self.recordSwitch]) {
        toggle.enabled = hasGame;
    }

    NPFrameSummary *summary = self.library.latestFrameSummary;
    self.reportHeading.hidden = !summary;
    self.report.hidden = !summary;
    if (summary) {
        self.report.stringValue = [NSString stringWithFormat:@"%lu frames · median %.1f ms · p95 %.1f ms · p99 %.1f ms · %lu over 50 ms, loading included",
                                   (unsigned long)summary.frames, summary.medianMilliseconds, summary.p95Milliseconds, summary.p99Milliseconds, (unsigned long)summary.framesOver50ms];
    }
}

- (void)optionChanged:(NSSwitch *)sender {
    BOOL on = sender.state == NSControlStateValueOn;
    [self.library updateOptions:^(NPLaunchOptions *options) {
        if (sender == self.fullscreenSwitch) {
            options.fullscreen = on;
        } else if (sender == self.hudSwitch) {
            options.metalHUD = on;
        } else {
            options.recordNextSession = on;
        }
    }];
}

@end
