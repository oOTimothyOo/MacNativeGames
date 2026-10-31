#import "NPPages.h"
#import "NPTheme.h"

static NSUserInterfaceItemIdentifier const CellIdentifier = @"backup-cell";
static const CGFloat RowHeight = 58;

static NSString *FormattedDate(NSDate *date) {
    static NSDateFormatter *formatter = ^{
        NSDateFormatter *shared = [NSDateFormatter new];
        shared.dateStyle = NSDateFormatterMediumStyle;
        shared.timeStyle = NSDateFormatterShortStyle;
        return shared;
    }();
    return [formatter stringFromDate:date];
}

@interface NPBackupCell : NSTableCellView
- (void)showBackup:(NPBackup *)backup;
@end

@implementation NPBackupCell {
    NSTextField *_heading;
    NSTextField *_date;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _heading = NPLineLabel(@"", 14, NSFontWeightMedium, NSColor.whiteColor);
        _date = NPLineLabel(@"", 13, NSFontWeightRegular, NPMutedColor());
        _date.alignment = NSTextAlignmentRight;
        [_date setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        NPAddSubview(self, _heading);
        NPAddSubview(self, _date);
        [NSLayoutConstraint activateConstraints:@[
            [_heading.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [_heading.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_heading.trailingAnchor constraintLessThanOrEqualToAnchor:_date.leadingAnchor constant:-16],
            [_date.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [_date.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)showBackup:(NPBackup *)backup {
    _heading.stringValue = backup.label;
    _date.stringValue = FormattedDate(backup.created);
}

@end

@interface NPBackupsPage () <NSTableViewDataSource, NSTableViewDelegate>
@property NPGamePicker *picker;
@property NSButton *backupButton;
@property NSButton *restoreButton;
@property NSButton *revealButton;
@property NSTextField *note;
@property NSTableView *table;
@property (copy) NSArray<NPBackup *> *shownBackups;
@property (nullable) NSURL *selectedBackupURL;
@end

@implementation NPBackupsPage

- (NSString *)title {
    return @"Backups";
}

- (NSView *)headerAccessory {
    (void)self.view;
    return self.backupButton;
}

- (void)loadView {
    NSView *page = [NSView new];
    self.view = page;

    self.picker = [[NPGamePicker alloc] initWithLibrary:self.library];
    self.backupButton = NPPrimaryButton(@"Back up now", @"backup-now", self, @selector(backUp:));
    self.restoreButton = NPButton(@"Restore…", @"restore-backup", self, @selector(restore:));
    self.revealButton = NPButton(@"Show in Finder", @"reveal-backups", self, @selector(reveal:));
    self.note = NPLineLabel(@"", 12, NSFontWeightRegular, NPMutedColor());
    self.note.alignment = NSTextAlignmentRight;

    self.table = [NSTableView new];
    self.table.identifier = @"backups";
    self.table.headerView = nil;
    self.table.style = NSTableViewStylePlain;
    self.table.rowHeight = RowHeight;
    self.table.intercellSpacing = NSZeroSize;
    self.table.backgroundColor = NSColor.clearColor;
    self.table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"snapshot"]];

    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = self.table;
    NSBox *panel = NPPanel();
    NPPinEdges(panel.contentView, scroll, 4);

    NSStackView *column = [NSStackView stackViewWithViews:@[self.picker, panel]];
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.alignment = NSLayoutAttributeLeading;
    column.spacing = 16;
    column.detachesHiddenViews = YES;
    [panel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [panel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];

    for (NSView *view in @[column, self.restoreButton, self.revealButton, self.note]) {
        NPAddSubview(page, view);
    }
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [column.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [column.topAnchor constraintEqualToAnchor:page.topAnchor],
        [column.bottomAnchor constraintEqualToAnchor:self.restoreButton.topAnchor constant:-16],
        [panel.widthAnchor constraintEqualToAnchor:column.widthAnchor],
        [self.restoreButton.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [self.restoreButton.bottomAnchor constraintEqualToAnchor:page.bottomAnchor],
        [self.revealButton.leadingAnchor constraintEqualToAnchor:self.restoreButton.trailingAnchor constant:10],
        [self.revealButton.centerYAnchor constraintEqualToAnchor:self.restoreButton.centerYAnchor],
        [self.note.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.revealButton.trailingAnchor constant:16],
        [self.note.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [self.note.centerYAnchor constraintEqualToAnchor:self.restoreButton.centerYAnchor],
    ]];
}

- (void)reload {
    (void)self.view;
    NPLibraryController *library = self.library;
    [self.picker reload];
    [library loadBackups];

    if (![self.shownBackups isEqualToArray:library.backups]) {
        self.shownBackups = library.backups;
        NSURL *remembered = self.selectedBackupURL;
        [self.table reloadData];
        NSUInteger index = [self.shownBackups indexOfObjectPassingTest:^BOOL(NPBackup *backup, NSUInteger i, BOOL *stop) {
            return [backup.url isEqual:remembered];
        }];
        if (self.shownBackups.count) {
            NSUInteger row = index == NSNotFound ? 0 : index;
            [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        }
    }

    BOOL available = library.selectedGame && !library.busy && !library.gameRunning;
    self.backupButton.enabled = available;
    self.restoreButton.enabled = available && !library.loadingBackups && self.table.selectedRow >= 0;
    self.revealButton.enabled = library.selectedGame != nil;
    self.note.stringValue = [NSString stringWithFormat:@"%lu of %lu kept · each one verified", (unsigned long)self.shownBackups.count, (unsigned long)NPMaximumBackups];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.shownBackups.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NPBackupCell *cell = [tableView makeViewWithIdentifier:CellIdentifier owner:self];
    if (!cell) {
        cell = [NPBackupCell new];
        cell.identifier = CellIdentifier;
    }
    [cell showBackup:self.shownBackups[(NSUInteger)row]];
    return cell;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [NPMintRowView new];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.table.selectedRow;
    self.selectedBackupURL = row >= 0 ? self.shownBackups[(NSUInteger)row].url : nil;
    self.restoreButton.enabled = row >= 0 && !self.library.busy && !self.library.gameRunning;
}

- (void)backUp:(id)sender {
    [self.library backUp];
}

- (void)restore:(id)sender {
    NSInteger row = self.table.selectedRow;
    if (row >= 0) {
        [self.actions restoreBackup:self.shownBackups[(NSUInteger)row]];
    }
}

- (void)reveal:(id)sender {
    [self.library revealBackups];
}

@end
