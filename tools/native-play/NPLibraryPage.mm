#import "NPPages.h"
#import "NPTheme.h"
#import <QuartzCore/QuartzCore.h>

static NSUserInterfaceItemIdentifier const TileIdentifier = @"game-tile";
static const CGFloat MinimumTileWidth = 200;
static const CGFloat TileHeight = 150;
static const CGFloat TileSpacing = 18;
static const CGFloat HeroHeightWithShelf = 300;

NSMenu *NPGameActionsMenu(void) {
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"Controller Setup" action:@selector(openControllerSetup:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Show in Finder" action:@selector(revealGame:) keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Choose Artwork…" action:@selector(chooseArtwork:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Use Game's Artwork" action:@selector(resetArtwork:) keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Remove from Library…" action:@selector(removeGame:) keyEquivalent:@""];
    return menu;
}

#pragma mark - Page base and game picker

@implementation NPPageViewController

- (instancetype)initWithLibrary:(NPLibraryController *)library actions:(id<NPPageActions>)actions {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _library = library;
        _actions = actions;
    }
    return self;
}

- (NSView *)headerAccessory {
    return nil;
}

- (void)reload {
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [self reload];
}

@end

@interface NPGamePicker ()
@property (readonly) NPLibraryController *library;
@property (readonly) NSPopUpButton *popUp;
@end

@implementation NPGamePicker

- (instancetype)initWithLibrary:(NPLibraryController *)library {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _library = library;
        _popUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        _popUp.target = self;
        _popUp.action = @selector(pick:);
        _popUp.identifier = @"game-selector";
        [_popUp.widthAnchor constraintLessThanOrEqualToConstant:520].active = YES;
        self.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        self.detachesHiddenViews = YES;
        [self addArrangedSubview:_popUp];
    }
    return self;
}

- (void)reload {
    [self.popUp removeAllItems];
    for (NPGame *game in self.library.games) {
        // Add by menu item: the pop-up's own method merges items with the same title.
        [self.popUp.menu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ · %@", game.title, game.version] action:nil keyEquivalent:@""]];
        self.popUp.lastItem.representedObject = game;
        if ([game isEqual:self.library.selectedGame]) {
            [self.popUp selectItem:self.popUp.lastItem];
        }
    }
    self.popUp.enabled = !self.library.busy;
    self.popUp.hidden = self.library.games.count < 2;
}

- (void)pick:(NSPopUpButton *)sender {
    [self.library selectGame:sender.selectedItem.representedObject];
}

@end

#pragma mark - Hero

// Darkens the bottom of the artwork so the title reads over any picture.
@interface NPScrimView : NSView
@end

@implementation NPScrimView

- (CALayer *)makeBackingLayer {
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.colors = @[(__bridge id)[NPBackgroundColor() colorWithAlphaComponent:.94].CGColor,
                     (__bridge id)[NPBackgroundColor() colorWithAlphaComponent:.45].CGColor,
                     (__bridge id)NSColor.clearColor.CGColor];
    layer.locations = @[@0, @.3, @.65];
    layer.startPoint = CGPointMake(.5, 0);
    layer.endPoint = CGPointMake(.5, 1);
    return layer;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
    }
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

@end

#pragma mark - Game tiles

// A double-click plays; single clicks continue on to the collection view's selection.
@interface NPGameTileView : NSView
@property (weak) NSCollectionViewItem *item;
@end

@implementation NPGameTileView

- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    if (event.clickCount == 2) {
        [NSApp sendAction:@selector(play:) to:nil from:self];
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSCollectionView *grid = self.item.collectionView;
    NSIndexPath *indexPath = [grid indexPathForItem:self.item];
    if (indexPath) {
        grid.selectionIndexPaths = [NSSet setWithObject:indexPath];
        [grid.delegate collectionView:grid didSelectItemsAtIndexPaths:grid.selectionIndexPaths];
    }
    return NPGameActionsMenu();
}

- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSAccessibilityRole)accessibilityRole {
    return NSAccessibilityButtonRole;
}

@end

@interface NPGameTile : NSCollectionViewItem
@property (nonatomic) NPArtworkView *artwork;
@property (nonatomic) NSTextField *heading;
- (void)showGame:(NPGame *)game image:(NSImage *)image;
@end

@implementation NPGameTile

- (void)loadView {
    NPGameTileView *view = [NPGameTileView new];
    view.item = self;
    self.view = view;
    self.artwork = [NPArtworkView new];
    self.artwork.cornerRadius = 12;
    self.artwork.layer.borderColor = NPMintColor().CGColor;
    self.heading = NPLineLabel(@"", 13, NSFontWeightMedium, NSColor.whiteColor);
    NPAddSubview(view, self.artwork);
    NPAddSubview(view, self.heading);
    [NSLayoutConstraint activateConstraints:@[
        [self.artwork.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.artwork.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [self.artwork.topAnchor constraintEqualToAnchor:view.topAnchor],
        [self.heading.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:2],
        [self.heading.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-2],
        [self.heading.topAnchor constraintEqualToAnchor:self.artwork.bottomAnchor constant:9],
        [self.heading.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
    ]];
}

- (void)showGame:(NPGame *)game image:(NSImage *)image {
    (void)self.view;
    self.view.identifier = [@"game-" stringByAppendingString:game.key];
    self.view.accessibilityLabel = [NSString stringWithFormat:@"%@, version %@", game.title, game.version];
    self.heading.stringValue = game.title;
    self.artwork.image = image;
}

- (void)setSelected:(BOOL)selected {
    super.selected = selected;
    self.artwork.layer.borderWidth = selected ? 2 : 0;
}

@end

#pragma mark - Library page

@interface NPLibraryPage () <NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSSearchFieldDelegate>
@property (readwrite) NSSearchField *searchField;
@property NSStackView *accessory;
@property NSCollectionView *collectionView;
@property NSScrollView *shelf;
@property NSTextField *emptySearchLabel;
@property NPArtworkView *heroArtwork;
@property NSTextField *heroTitle;
@property NSTextField *heroDetail;
@property NSButton *playButton;
@property NSButton *moreButton;
@property NSButton *addButton;
// The hero fills the page unless there is a shelf of other games to show.
@property NSLayoutConstraint *heroFillsPage;
@property NSLayoutConstraint *heroLeavesShelf;
@property (copy) NSArray<NPGame *> *filteredGames;
@property CGFloat laidOutWidth;
@end

@implementation NPLibraryPage

- (NSString *)title {
    return @"Library";
}

- (NSView *)headerAccessory {
    (void)self.view;
    return self.accessory;
}

- (void)loadView {
    NSView *page = [NSView new];
    self.view = page;

    self.searchField = [NSSearchField new];
    self.searchField.placeholderString = @"Find a game";
    self.searchField.delegate = self;
    self.searchField.identifier = @"library-search";
    [self.searchField.widthAnchor constraintEqualToConstant:200].active = YES;
    NSButton *add = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add native apps"] target:nil action:@selector(addApps:)];
    add.identifier = @"add-apps";
    add.toolTip = @"Add native apps";
    add.controlSize = NSControlSizeLarge;
    self.accessory = [NSStackView stackViewWithViews:@[self.searchField, add]];
    self.accessory.spacing = 10;
    self.accessory.detachesHiddenViews = YES;

    NSView *hero = [self buildHero];
    [self buildShelf];
    NPAddSubview(page, hero);
    NPAddSubview(page, self.shelf);
    NPAddSubview(page, self.emptySearchLabel);
    self.heroFillsPage = [hero.bottomAnchor constraintEqualToAnchor:page.bottomAnchor];
    self.heroLeavesShelf = [hero.heightAnchor constraintEqualToConstant:HeroHeightWithShelf];
    [NSLayoutConstraint activateConstraints:@[
        [hero.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [hero.topAnchor constraintEqualToAnchor:page.topAnchor],
        [self.shelf.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [self.shelf.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [self.shelf.topAnchor constraintEqualToAnchor:hero.bottomAnchor constant:20],
        [self.shelf.bottomAnchor constraintEqualToAnchor:page.bottomAnchor],
        [self.emptySearchLabel.centerXAnchor constraintEqualToAnchor:self.shelf.centerXAnchor],
        [self.emptySearchLabel.centerYAnchor constraintEqualToAnchor:self.shelf.centerYAnchor],
    ]];
}

- (NSView *)buildHero {
    NSView *hero = [NSView new];
    self.heroArtwork = [NPArtworkView new];
    self.heroArtwork.identifier = @"hero-artwork";
    self.heroArtwork.cornerRadius = 16;
    NPScrimView *scrim = [NPScrimView new];
    scrim.layer.cornerRadius = 16;
    scrim.layer.masksToBounds = YES;
    self.heroTitle = NPLabel(@"", 30, NSFontWeightBold, NSColor.whiteColor);
    self.heroTitle.maximumNumberOfLines = 2;
    self.heroTitle.identifier = @"hero-title";
    self.heroDetail = NPLineLabel(@"", 13, NSFontWeightRegular, [NSColor colorWithWhite:1 alpha:.72]);
    self.playButton = NPPrimaryButton(@"Play", @"play", nil, @selector(play:));
    self.playButton.keyEquivalent = @"\r";
    [self.playButton.widthAnchor constraintGreaterThanOrEqualToConstant:112].active = YES;
    self.addButton = NPPrimaryButton(@"Add native apps…", @"add-first-app", nil, @selector(addApps:));
    self.moreButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:@"More"] target:self action:@selector(showGameActions:)];
    self.moreButton.identifier = @"game-actions";
    self.moreButton.controlSize = NSControlSizeLarge;

    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.moreButton, self.playButton, self.addButton]];
    buttons.spacing = 10;
    buttons.detachesHiddenViews = YES;
    NPPinEdges(hero, self.heroArtwork, 0);
    NPPinEdges(hero, scrim, 0);
    for (NSView *view in @[self.heroTitle, self.heroDetail, buttons]) {
        NPAddSubview(hero, view);
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.heroDetail.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:28],
        [self.heroDetail.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-26],
        [self.heroDetail.trailingAnchor constraintLessThanOrEqualToAnchor:buttons.leadingAnchor constant:-20],
        [self.heroTitle.leadingAnchor constraintEqualToAnchor:self.heroDetail.leadingAnchor],
        [self.heroTitle.bottomAnchor constraintEqualToAnchor:self.heroDetail.topAnchor constant:-5],
        [self.heroTitle.trailingAnchor constraintLessThanOrEqualToAnchor:buttons.leadingAnchor constant:-20],
        [buttons.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-28],
        [buttons.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-26],
    ]];
    return hero;
}

- (void)buildShelf {
    NSCollectionViewFlowLayout *layout = [NSCollectionViewFlowLayout new];
    // A point less than the tile width calculation assumes: a row that fits exactly must not wrap.
    layout.minimumInteritemSpacing = TileSpacing - 1;
    layout.minimumLineSpacing = TileSpacing;
    self.collectionView = [NSCollectionView new];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.identifier = @"library-grid";
    self.collectionView.backgroundColors = @[NSColor.clearColor];
    self.collectionView.selectable = YES;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:NPGameTile.class forItemWithIdentifier:TileIdentifier];
    self.shelf = [NSScrollView new];
    self.shelf.hasVerticalScroller = YES;
    self.shelf.autohidesScrollers = YES;
    self.shelf.drawsBackground = NO;
    self.shelf.documentView = self.collectionView;
    self.emptySearchLabel = NPLineLabel(@"No matching games.", 14, NSFontWeightMedium, NPMutedColor());
}

// Tile sizes depend on the width, and the flow layout does not ask again by itself.
- (void)viewDidLayout {
    [super viewDidLayout];
    CGFloat width = NSWidth(self.shelf.contentView.bounds);
    if (width != self.laidOutWidth) {
        self.laidOutWidth = width;
        [self.collectionView.collectionViewLayout invalidateLayout];
    }
}

- (void)reload {
    (void)self.view;
    NPLibraryController *library = self.library;
    BOOL hasShelf = library.games.count > 1;
    self.searchField.hidden = !hasShelf;
    self.shelf.hidden = !hasShelf;
    self.heroFillsPage.active = !hasShelf;
    self.heroLeavesShelf.active = hasShelf;
    [self filter];

    NPGame *game = library.selectedGame;
    self.heroTitle.stringValue = game ? game.title : @"Add your first game";
    self.heroDetail.stringValue = game ? [NSString stringWithFormat:@"Version %@", game.version] : @"Choose a built native app. Your games and progress stay on this Mac.";
    self.heroArtwork.image = game ? [library.artwork imageForGame:game] : nil;
    self.heroArtwork.layer.backgroundColor = NPSurfaceColor().CGColor;
    NPSetPrimaryTitle(self.playButton, library.busy ? @"Preparing…" : library.sessionRunning ? @"Playing" : @"Play");
    self.playButton.enabled = game && !library.busy;
    self.playButton.hidden = !game;
    self.moreButton.hidden = !game;
    self.addButton.hidden = game != nil;
    self.addButton.enabled = !library.busy;

    for (NSCollectionViewItem *item in self.collectionView.visibleItems) {
        NSIndexPath *indexPath = [self.collectionView indexPathForItem:item];
        if (indexPath && (NSUInteger)indexPath.item < self.filteredGames.count) {
            NPGame *shown = self.filteredGames[(NSUInteger)indexPath.item];
            [(NPGameTile *)item showGame:shown image:[library.artwork imageForGame:shown]];
        }
    }
}

- (void)filter {
    NSString *query = self.searchField.stringValue;
    NSMutableArray<NPGame *> *filtered = [NSMutableArray new];
    for (NPGame *game in self.library.games) {
        if (!query.length || [game.title localizedCaseInsensitiveContainsString:query]) {
            [filtered addObject:game];
        }
    }
    if (![filtered isEqualToArray:self.filteredGames]) {
        self.filteredGames = filtered;
        [self.collectionView reloadData];
    }
    NSUInteger selected = self.library.selectedGame ? [filtered indexOfObject:self.library.selectedGame] : NSNotFound;
    NSSet *selection = selected == NSNotFound ? [NSSet set] : [NSSet setWithObject:[NSIndexPath indexPathForItem:(NSInteger)selected inSection:0]];
    if (![self.collectionView.selectionIndexPaths isEqualToSet:selection]) {
        self.collectionView.selectionIndexPaths = selection;
    }
    self.emptySearchLabel.hidden = filtered.count > 0 || self.shelf.hidden;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    [self filter];
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.filteredGames.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    NPGameTile *tile = [collectionView makeItemWithIdentifier:TileIdentifier forIndexPath:indexPath];
    NPGame *game = self.filteredGames[(NSUInteger)indexPath.item];
    [tile showGame:game image:[self.library.artwork imageForGame:game]];
    return tile;
}

- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat available = NSWidth(self.shelf.contentView.bounds);
    CGFloat columns = MAX(1, floor((available + TileSpacing) / (MinimumTileWidth + TileSpacing)));
    return NSMakeSize(floor((available - (columns - 1) * TileSpacing) / columns), TileHeight);
}

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (indexPath) {
        [self.library selectGame:self.filteredGames[(NSUInteger)indexPath.item]];
    }
}

- (void)showGameActions:(NSButton *)sender {
    [NPGameActionsMenu() popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(sender.bounds) + 4) inView:sender];
}

@end
