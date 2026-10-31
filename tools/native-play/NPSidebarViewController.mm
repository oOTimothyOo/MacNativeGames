#import "NPSidebarViewController.h"
#import "NPTheme.h"

static NSString *const SectionNames[NPSectionCount] = {@"Library", @"Backups", @"Performance", @"Controllers"};
static NSString *const SectionSymbols[NPSectionCount] = {@"square.grid.2x2", @"clock.arrow.circlepath", @"waveform.path.ecg", @"gamecontroller"};

@interface NPSidebarViewController () <NSTableViewDataSource, NSTableViewDelegate>
@property NSTableView *table;
@end

@implementation NPSidebarViewController

- (void)loadView {
    NSView *root = [NSView new];
    self.view = root;

    NSTextField *wordmark = NPLineLabel(@"native play", 20, NSFontWeightHeavy, NSColor.whiteColor);

    self.table = [NSTableView new];
    self.table.identifier = @"sidebar";
    self.table.style = NSTableViewStyleSourceList;
    self.table.headerView = nil;
    self.table.rowHeight = 36;
    self.table.backgroundColor = NSColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"section"]];

    NSScrollView *scroll = [NSScrollView new];
    scroll.drawsBackground = NO;
    scroll.documentView = self.table;

    NPAddSubview(root, wordmark);
    NPAddSubview(root, scroll);
    NSLayoutGuide *safe = root.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [wordmark.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:22],
        [wordmark.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],
        [wordmark.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:wordmark.bottomAnchor constant:22],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-12],
    ]];

    [self.table reloadData];
    [self showSelection];
}

- (void)setSection:(NPSection)section {
    _section = section;
    [self showSelection];
}

- (void)showSelection {
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)self.section] byExtendingSelection:NO];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return NPSectionCount;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTableCellView *cell = [NSTableCellView new];
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:SectionSymbols[row] accessibilityDescription:nil]];
    icon.contentTintColor = row == self.table.selectedRow ? NPMintColor() : NPMutedColor();
    NSTextField *name = NPLineLabel(SectionNames[row], 13, NSFontWeightMedium, NSColor.whiteColor);
    cell.imageView = icon;
    cell.textField = name;
    cell.identifier = [@"section-" stringByAppendingString:SectionNames[row].lowercaseString];
    NPAddSubview(cell, icon);
    NPAddSubview(cell, name);
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
        [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:22],
        [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [name.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
        [name.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [NPMintRowView new];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.table.selectedRow;
    for (NSInteger other = 0; other < NPSectionCount; other++) {
        NSTableCellView *cell = [self.table viewAtColumn:0 row:other makeIfNecessary:NO];
        cell.imageView.contentTintColor = other == row ? NPMintColor() : NPMutedColor();
    }
    if (row >= 0 && (NPSection)row != _section) {
        _section = (NPSection)row;
        self.sectionChanged((NPSection)row);
    }
}

@end
