#import "NPApp.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <algorithm>
#include <cmath>

namespace {
constexpr CGFloat SidebarWidth=208, RowHeight=80;
NSColor *RGB(CGFloat r,CGFloat g,CGFloat b){return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];}
NSColor *Background(){return RGB(.065,.075,.09);}
NSColor *Surface(){return RGB(.09,.11,.13);}
NSColor *Mint(){return RGB(.43,.96,.74);}
NSColor *Muted(){return RGB(.60,.65,.70);}
void Add(NSView *parent,NSView *child){child.translatesAutoresizingMaskIntoConstraints=NO;[parent addSubview:child];}
void Fill(NSView *parent,NSView *child,CGFloat inset){Add(parent,child);[NSLayoutConstraint activateConstraints:@[
    [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:inset],
    [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-inset],
    [child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:inset],
    [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-inset]]];}
NSTextField *Label(NSString *value,CGFloat size,NSFontWeight weight,NSColor *color){
    NSTextField *text=[NSTextField wrappingLabelWithString:value?:@""];text.font=[NSFont systemFontOfSize:size weight:weight];text.textColor=color;text.maximumNumberOfLines=2;return text;
}
NSButton *Button(NSString *title,id target,SEL action,BOOL primary){
    NSButton *button=[NSButton buttonWithTitle:title target:target action:action];button.identifier=title;
    button.bordered=NO;button.wantsLayer=YES;button.layer.cornerRadius=9;button.layer.backgroundColor=(primary?Mint():RGB(.17,.20,.23)).CGColor;
    button.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];button.contentTintColor=primary?Background():NSColor.whiteColor;
    button.attributedTitle=[[NSAttributedString alloc]initWithString:title attributes:@{NSFontAttributeName:button.font,NSForegroundColorAttributeName:primary?Background():NSColor.whiteColor}];
    [button.heightAnchor constraintEqualToConstant:40].active=YES;return button;
}
BOOL Controllers(NSDictionary *game){return [game[@"controllers"] boolValue]||[game[@"id"] isEqual:@"0100965017338000"];}
}

@interface NPFlipped : NSView @end
@implementation NPFlipped
- (BOOL)isFlipped{return YES;}
@end
@interface NPPanel : NPFlipped @end
@implementation NPPanel
- (instancetype)initWithFrame:(NSRect)frame{if((self=[super initWithFrame:frame])){self.wantsLayer=YES;self.layer.backgroundColor=Surface().CGColor;self.layer.cornerRadius=12;self.layer.borderColor=RGB(.15,.18,.20).CGColor;self.layer.borderWidth=1;}return self;}
@end

@interface NPSidebarButton : NSButton
@property NSString *symbol;
@end
@implementation NPSidebarButton
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty{
    (void)dirty;BOOL selected=self.state==NSControlStateValueOn;
    if(selected||self.cell.isHighlighted){[(selected?RGB(.17,.29,.26):RGB(.13,.16,.18))setFill];[[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:9 yRadius:9]fill];}
    NSColor *color=selected?Mint():Muted();NSImage *image=[NSImage imageWithSystemSymbolName:self.symbol accessibilityDescription:nil];
    image=[image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
    [image drawInRect:NSMakeRect(16,(self.bounds.size.height-18)/2,18,18) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:selected?NSFontWeightSemibold:NSFontWeightMedium],NSForegroundColorAttributeName:color};
    NSSize size=[self.title sizeWithAttributes:attributes];[self.title drawAtPoint:NSMakePoint(46,(self.bounds.size.height-size.height)/2) withAttributes:attributes];
}
@end

@interface NPBackupCell : NSTableCellView
@property NSTextField *heading,*detail,*date,*verification;
- (void)configure:(NSDictionary *)snapshot;
@end
@implementation NPBackupCell
- (BOOL)isFlipped{return YES;}
- (instancetype)initWithFrame:(NSRect)frame{
    if((self=[super initWithFrame:frame])){
        self.heading=Label(@"",14,NSFontWeightSemibold,NSColor.whiteColor);self.detail=Label(@"",12,NSFontWeightRegular,Muted());
        self.date=Label(@"",12,NSFontWeightRegular,Muted());self.date.alignment=NSTextAlignmentRight;
        self.verification=Label(@"Verified",11,NSFontWeightMedium,Mint());self.verification.alignment=NSTextAlignmentRight;
        for(NSTextField *label in @[self.heading,self.detail,self.date,self.verification]){label.maximumNumberOfLines=1;label.lineBreakMode=NSLineBreakByTruncatingTail;[self addSubview:label];}
    }return self;
}
- (void)configure:(NSDictionary *)snapshot{
    self.heading.stringValue=snapshot[@"label"];
    NSUInteger count=[snapshot[@"files"] count];self.detail.stringValue=[NSString stringWithFormat:@"%lu %@ · Progress and controller settings",(unsigned long)count,count==1?@"file":@"files"];
    NSDateFormatter *format=[NSDateFormatter new];format.dateStyle=NSDateFormatterMediumStyle;format.timeStyle=NSDateFormatterShortStyle;
    self.date.stringValue=[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[snapshot[@"created"] doubleValue]]];self.needsLayout=YES;
}
- (void)layout{
    [super layout];CGFloat w=self.bounds.size.width,right=std::min<CGFloat>(204,w*.36),left=std::max<CGFloat>(40,w-right-56);
    self.heading.frame=NSMakeRect(20,16,left,20);self.detail.frame=NSMakeRect(20,44,left,17);
    self.date.frame=NSMakeRect(w-right-20,18,right,18);self.verification.frame=NSMakeRect(w-right-20,46,right,16);
}
@end
@interface NPBackupRow : NSTableRowView @end
@implementation NPBackupRow
- (void)drawSelectionInRect:(NSRect)dirty{(void)dirty;NSBezierPath *path=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,6,4) xRadius:9 yRadius:9];[RGB(.15,.25,.23)setFill];[path fill];[[Mint()colorWithAlphaComponent:.24]setStroke];path.lineWidth=1;[path stroke];}
@end

@interface NPGameTile : NSButton
@property NSDictionary *game;
@end
@implementation NPGameTile
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty{
    (void)dirty;NSRect b=NSInsetRect(self.bounds,2,2);NSBezierPath *card=[NSBezierPath bezierPathWithRoundedRect:b xRadius:13 yRadius:13];
    [Surface()setFill];[card fill];[(self.state==NSControlStateValueOn?Mint():RGB(.20,.24,.27))setStroke];card.lineWidth=self.state==NSControlStateValueOn?2:1;[card stroke];
    NSRect art=NSMakeRect(14,14,b.size.width-24,134);[NSGraphicsContext saveGraphicsState];[[NSBezierPath bezierPathWithRoundedRect:art xRadius:9 yRadius:9]addClip];
    NSUInteger hue=[self.game[@"id"] hash]%3;NSColor *base=@[RGB(.16,.28,.36),RGB(.29,.20,.31),RGB(.18,.30,.27)][hue];[base setFill];NSRectFill(art);
    [[Mint()colorWithAlphaComponent:.14]setFill];[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(art.origin.x+art.size.width*.38,art.origin.y-35,200,200)]fill];
    [[Mint()colorWithAlphaComponent:.45]setStroke];NSBezierPath *orbit=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(art.origin.x+art.size.width*.38-12,art.origin.y-47,224,224)];orbit.lineWidth=1;[orbit stroke];
    NSString *initial=[self.game[@"title"] substringToIndex:1];[initial.uppercaseString drawAtPoint:NSMakePoint(art.origin.x+18,art.origin.y+29) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:44 weight:NSFontWeightHeavy],NSForegroundColorAttributeName:NSColor.whiteColor}];
    [@"MAC NATIVE" drawAtPoint:NSMakePoint(art.origin.x+18,art.origin.y+15) withAttributes:@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:9 weight:NSFontWeightMedium],NSForegroundColorAttributeName:Mint()}];
    [NSGraphicsContext restoreGraphicsState];
    NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByWordWrapping;
    [self.game[@"title"] drawWithRect:NSMakeRect(18,163,b.size.width-32,38) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingTruncatesLastVisibleLine attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.whiteColor,NSParagraphStyleAttributeName:style} context:nil];
    [[NSString stringWithFormat:@"Version %@",self.game[@"version"]]drawAtPoint:NSMakePoint(18,211) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11 weight:NSFontWeightRegular],NSForegroundColorAttributeName:Muted()}];
}
@end
@interface NPGrid : NPFlipped
@property NSArray<NPGameTile *> *tiles;
@property BOOL arranging;
- (void)arrange;
@end
@implementation NPGrid
- (void)setFrameSize:(NSSize)size{[super setFrameSize:size];[self arrange];}
- (void)arrange{
    if(self.arranging)return;self.arranging=YES;
    CGFloat w=self.bounds.size.width;NSUInteger columns=std::max<NSUInteger>(1,(NSUInteger)((w+20)/240));CGFloat width=(w-(columns-1)*20)/columns;
    NSUInteger rows=(self.tiles.count+columns-1)/columns;CGFloat height=std::max<CGFloat>(self.enclosingScrollView.contentSize.height,rows?rows*248+(rows-1)*20:0);
    [super setFrameSize:NSMakeSize(w,height)];
    for(NSUInteger i=0;i<self.tiles.count;i++)self.tiles[i].frame=NSMakeRect((i%columns)*(width+20),(i/columns)*268,width,248);
    self.arranging=NO;
}
@end

@interface NPSettingRow : NPPanel
@property NSTextField *heading,*detail;
@property NSSwitch *toggle;
- (instancetype)initWithTitle:(NSString *)title detail:(NSString *)detail identifier:(NSString *)identifier on:(BOOL)on target:(id)target action:(SEL)action;
@end
@implementation NPSettingRow
- (instancetype)initWithTitle:(NSString *)title detail:(NSString *)detail identifier:(NSString *)identifier on:(BOOL)on target:(id)target action:(SEL)action{
    if((self=[super initWithFrame:NSZeroRect])){
        self.heading=Label(title,14,NSFontWeightSemibold,NSColor.whiteColor);self.detail=Label(detail,12,NSFontWeightRegular,Muted());
        self.toggle=[NSSwitch new];self.toggle.target=target;self.toggle.action=action;self.toggle.identifier=identifier;self.toggle.state=on?NSControlStateValueOn:NSControlStateValueOff;
        self.toggle.accessibilityLabel=title;[self addSubview:self.heading];[self addSubview:self.detail];[self addSubview:self.toggle];
        [self.heightAnchor constraintEqualToConstant:88].active=YES;
    }return self;
}
- (void)layout{[super layout];CGFloat w=self.bounds.size.width;self.heading.frame=NSMakeRect(20,15,std::max<CGFloat>(40,w-100),21);self.detail.frame=NSMakeRect(20,42,std::max<CGFloat>(40,w-100),32);self.toggle.frame=NSMakeRect(w-60,31,40,25);}
@end

@interface NPApp ()
@property NSWindow *window;
@property NPFlipped *canvas,*content,*page;
@property NSTextField *pageTitle,*subtitle,*status,*count;
@property NSView *context;
@property NSScrollView *gridScroll;
@property NPGrid *grid;
@property NSSearchField *search;
@property NSPopUpButton *picker;
@property NSDictionary *game;
@property NSArray<NSDictionary *> *catalog,*filtered,*snapshots;
@property NSMutableArray<NPSidebarButton *> *navigation;
@property NSTableView *table;
@property NSTask *task;
@property NSString *runningKey,*section,*selectedSnapshot;
@property BOOL busy,externalRunning;
@end

@implementation NPPreviewStore
- (BOOL)gameIsRunning{return NO;}
@end
NSArray<NSDictionary *> *NPPreviewGames(void){return @[
    @{@"id":@"0100965017338000",@"title":@"Super Mario Party Jamboree",@"version":@"2.3.0",@"path":@"/Synthetic/Jamboree.app",@"controllers":@YES},
    @{@"id":@"0100000000000001",@"title":@"Sky Circuit",@"version":@"1.2.0",@"path":@"/Synthetic/Sky Circuit.app"},
    @{@"id":@"0100000000000002",@"title":@"Mosslight",@"version":@"0.9.4",@"path":@"/Synthetic/Mosslight.app"}];}

@implementation NPApp
- (void)applicationDidFinishLaunching:(NSNotification *)note{
    (void)note;self.catalog=self.preview?NPPreviewGames():self.store.games;self.game=self.catalog.firstObject;self.store.activeGame=self.game;self.section=@"Library";
    self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1140,780) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Native Play";self.window.minSize=NSMakeSize(960,720);self.window.titlebarAppearsTransparent=YES;self.window.backgroundColor=Background();self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];self.window.delegate=self;
    [self buildShell];[self installMenu];[self showSection:@"Library"];[self.window center];
    if(!self.test){[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];}
    if(self.test||self.snapshotPath)dispatch_async(dispatch_get_main_queue(),^{[self runUITest];});
}
- (void)installMenu{
    NSMenu *bar=[NSMenu new],*app=[NSMenu new],*file=[NSMenu new];[app addItemWithTitle:@"About Native Play" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];[app addItem:NSMenuItem.separatorItem];[app addItemWithTitle:@"Quit Native Play" action:@selector(terminate:) keyEquivalent:@"q"];
    [[bar addItemWithTitle:@"Native Play" action:nil keyEquivalent:@""]setSubmenu:app];
    for(NSArray *row in @[@[@"Add native apps…",@"addGames:",@"o"],@[@"Refresh library",@"refresh:",@"r"],@[@"Back up selected game",@"backup:",@"b"]]){NSMenuItem *item=[file addItemWithTitle:row[0] action:NSSelectorFromString(row[1]) keyEquivalent:row[2]];item.target=self;}
    [[bar addItemWithTitle:@"File" action:nil keyEquivalent:@""]setSubmenu:file];NSApp.mainMenu=bar;
}
- (void)buildShell{
    self.canvas=[NPFlipped new];self.canvas.wantsLayer=YES;self.canvas.layer.backgroundColor=Background().CGColor;self.window.contentView=self.canvas;
    NPPanel *rail=[NPPanel new];rail.layer.cornerRadius=0;rail.layer.borderWidth=0;Add(self.canvas,rail);
    [NSLayoutConstraint activateConstraints:@[[rail.leadingAnchor constraintEqualToAnchor:self.canvas.leadingAnchor],[rail.topAnchor constraintEqualToAnchor:self.canvas.topAnchor],[rail.bottomAnchor constraintEqualToAnchor:self.canvas.bottomAnchor],[rail.widthAnchor constraintEqualToConstant:SidebarWidth]]];
    NSTextField *brand=Label(@"native play",23,NSFontWeightHeavy,NSColor.whiteColor);Add(rail,brand);[NSLayoutConstraint activateConstraints:@[[brand.leadingAnchor constraintEqualToAnchor:rail.leadingAnchor constant:24],[brand.topAnchor constraintEqualToAnchor:rail.topAnchor constant:28]]];
    NSTextField *tag=Label(@"YOUR MAC. YOUR GAMES.",9,NSFontWeightSemibold,Mint());Add(rail,tag);[NSLayoutConstraint activateConstraints:@[[tag.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],[tag.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:10]]];
    self.navigation=[NSMutableArray new];NSArray *names=@[@"Library",@"Backups",@"Performance",@"Controllers"],*symbols=@[@"square.grid.2x2",@"clock.arrow.circlepath",@"waveform.path.ecg",@"gamecontroller"];
    for(NSUInteger i=0;i<names.count;i++){NPSidebarButton *button=[NPSidebarButton buttonWithTitle:names[i] target:self action:@selector(navigate:)];button.bordered=NO;button.symbol=symbols[i];button.identifier=names[i];button.tag=(NSInteger)i;Add(rail,button);[NSLayoutConstraint activateConstraints:@[[button.leadingAnchor constraintEqualToAnchor:rail.leadingAnchor constant:16],[button.trailingAnchor constraintEqualToAnchor:rail.trailingAnchor constant:-16],[button.topAnchor constraintEqualToAnchor:rail.topAnchor constant:132+i*52],[button.heightAnchor constraintEqualToConstant:44]]];[self.navigation addObject:button];}
    NSTextField *local=Label(@"●  Local and offline",11,NSFontWeightMedium,Mint());Add(rail,local);[NSLayoutConstraint activateConstraints:@[[local.leadingAnchor constraintEqualToAnchor:rail.leadingAnchor constant:24],[local.bottomAnchor constraintEqualToAnchor:rail.bottomAnchor constant:-28]]];
    self.content=[NPFlipped new];Add(self.canvas,self.content);[NSLayoutConstraint activateConstraints:@[[self.content.leadingAnchor constraintEqualToAnchor:rail.trailingAnchor constant:32],[self.content.trailingAnchor constraintEqualToAnchor:self.canvas.trailingAnchor constant:-32],[self.content.topAnchor constraintEqualToAnchor:self.canvas.topAnchor constant:28],[self.content.bottomAnchor constraintEqualToAnchor:self.canvas.bottomAnchor constant:-20]]];
    self.pageTitle=Label(@"Library",28,NSFontWeightBold,NSColor.whiteColor);self.subtitle=Label(@"",13,NSFontWeightRegular,Muted());self.status=Label(@"Games and progress stay on this Mac.",11,NSFontWeightRegular,Muted());self.status.identifier=@"status";
    NSButton *add=Button(@"Add native apps…",self,@selector(addGames:),NO);for(NSView *view in @[self.pageTitle,self.subtitle,self.status,add])Add(self.content,view);
    [NSLayoutConstraint activateConstraints:@[[self.pageTitle.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],[self.pageTitle.topAnchor constraintEqualToAnchor:self.content.topAnchor],[self.pageTitle.trailingAnchor constraintLessThanOrEqualToAnchor:add.leadingAnchor constant:-24],[add.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],[add.topAnchor constraintEqualToAnchor:self.content.topAnchor],[add.widthAnchor constraintEqualToConstant:160],[self.subtitle.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],[self.subtitle.topAnchor constraintEqualToAnchor:self.pageTitle.bottomAnchor constant:8],[self.subtitle.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],[self.status.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],[self.status.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],[self.status.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor],[self.status.heightAnchor constraintEqualToConstant:20]]];
    self.context=[NPFlipped new];Add(self.content,self.context);self.page=[NPFlipped new];Add(self.content,self.page);
    [NSLayoutConstraint activateConstraints:@[[self.context.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],[self.context.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],[self.context.topAnchor constraintEqualToAnchor:self.subtitle.bottomAnchor constant:24],[self.context.heightAnchor constraintEqualToConstant:34],[self.page.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],[self.page.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],[self.page.topAnchor constraintEqualToAnchor:self.context.bottomAnchor constant:20],[self.page.bottomAnchor constraintEqualToAnchor:self.status.topAnchor constant:-20]]];
}
- (void)notice:(NSString *)text{self.status.stringValue=text;}
- (void)showSection:(NSString *)name{
    self.section=name;self.store.activeGame=self.game;self.externalRunning=self.store.gameIsRunning;
    for(NPSidebarButton *button in self.navigation){button.state=[button.title isEqual:name]?NSControlStateValueOn:NSControlStateValueOff;button.needsDisplay=YES;}
    for(NSView *view in self.context.subviews.copy)[view removeFromSuperview];for(NSView *view in self.page.subviews.copy)[view removeFromSuperview];self.table=nil;self.grid=nil;
    self.pageTitle.stringValue=[name isEqual:@"Backups"]?@"Save backups":name;
    self.subtitle.stringValue=[@{@"Library":@"Your installed native apps, together in one place.",@"Backups":@"Verified progress and controller settings for the selected game.",@"Performance":@"Launch preferences belong to each app.",@"Controllers":@"Choose a game to access its controller setup."} objectForKey:name];
    if([name isEqual:@"Library"]){[self libraryPage];return;}
    [self gameContext];if(!self.game){NSTextField *empty=Label(@"Add a native app to get started.",16,NSFontWeightMedium,Muted());Fill(self.page,empty,24);return;}
    if([name isEqual:@"Backups"]){self.snapshots=self.store.backups;[self backupsPage];}else if([name isEqual:@"Performance"])[self performancePage];else[self controllersPage];
}
- (void)gameContext{
    NSTextField *label=Label(@"Game",12,NSFontWeightMedium,Muted());Add(self.context,label);self.picker=[[NSPopUpButton alloc]initWithFrame:NSZeroRect pullsDown:NO];self.picker.target=self;self.picker.action=@selector(pickGame:);self.picker.identifier=@"game-selector";
    for(NSUInteger i=0;i<self.catalog.count;i++){NSDictionary *game=self.catalog[i];[self.picker addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",game[@"title"],game[@"version"]]];self.picker.lastItem.tag=(NSInteger)i;if([game[@"path"] isEqual:self.game[@"path"]])[self.picker selectItemAtIndex:(NSInteger)i];}
    self.picker.enabled=self.catalog.count>0&&!self.busy;Add(self.context,self.picker);[NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:self.context.leadingAnchor],[label.centerYAnchor constraintEqualToAnchor:self.context.centerYAnchor],[self.picker.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],[self.picker.topAnchor constraintEqualToAnchor:self.context.topAnchor],[self.picker.bottomAnchor constraintEqualToAnchor:self.context.bottomAnchor],[self.picker.widthAnchor constraintLessThanOrEqualToConstant:520],[self.picker.trailingAnchor constraintLessThanOrEqualToAnchor:self.context.trailingAnchor]]];
}
- (void)libraryPage{
    self.count=Label([NSString stringWithFormat:@"%lu native %@",(unsigned long)self.catalog.count,self.catalog.count==1?@"app":@"apps"],12,NSFontWeightMedium,Muted());Add(self.context,self.count);
    self.search=[NSSearchField new];self.search.placeholderString=@"Find a game";self.search.delegate=self;self.search.identifier=@"library-search";Add(self.context,self.search);
    [NSLayoutConstraint activateConstraints:@[[self.count.leadingAnchor constraintEqualToAnchor:self.context.leadingAnchor],[self.count.centerYAnchor constraintEqualToAnchor:self.context.centerYAnchor],[self.search.trailingAnchor constraintEqualToAnchor:self.context.trailingAnchor],[self.search.topAnchor constraintEqualToAnchor:self.context.topAnchor],[self.search.bottomAnchor constraintEqualToAnchor:self.context.bottomAnchor],[self.search.widthAnchor constraintEqualToConstant:240]]];
    NPPanel *details=[NPPanel new];Add(self.page,details);[NSLayoutConstraint activateConstraints:@[[details.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[details.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[details.bottomAnchor constraintEqualToAnchor:self.page.bottomAnchor],[details.heightAnchor constraintEqualToConstant:90]]];
    NSTextField *title=Label(self.game?self.game[@"title"]:@"Add your first native app",16,NSFontWeightSemibold,NSColor.whiteColor),*version=Label(self.game?[NSString stringWithFormat:@"Version %@ · Native on Apple Silicon",self.game[@"version"]]:@"Choose a supported built .app. No game content is downloaded.",12,NSFontWeightRegular,Muted());
    NSButton *play=Button(self.busy?@"Preparing…":(self.task.running?@"Game running":@"Play"),self,@selector(play:),YES);play.enabled=self.game&&!self.busy;play.identifier=@"play";play.keyEquivalent=@"\r";
    NSButton *more=Button(@"Reveal",self,@selector(revealGame:),NO);more.enabled=self.game!=nil;more.identifier=@"reveal-game";
    NSButton *remove=Button(@"Remove",self,@selector(removeGame:),NO);remove.enabled=self.game&&!self.busy&&!self.task.running;remove.toolTip=@"Remove this library entry. The app and saves stay on disk.";remove.identifier=@"remove-game";
    for(NSView *view in @[title,version,play,more,remove])Add(details,view);
    [NSLayoutConstraint activateConstraints:@[[title.leadingAnchor constraintEqualToAnchor:details.leadingAnchor constant:20],[title.topAnchor constraintEqualToAnchor:details.topAnchor constant:17],[title.trailingAnchor constraintLessThanOrEqualToAnchor:remove.leadingAnchor constant:-20],[version.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[version.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:7],[version.trailingAnchor constraintLessThanOrEqualToAnchor:remove.leadingAnchor constant:-20],[play.trailingAnchor constraintEqualToAnchor:details.trailingAnchor constant:-20],[play.centerYAnchor constraintEqualToAnchor:details.centerYAnchor],[play.widthAnchor constraintEqualToConstant:96],[more.trailingAnchor constraintEqualToAnchor:play.leadingAnchor constant:-10],[more.centerYAnchor constraintEqualToAnchor:play.centerYAnchor],[more.widthAnchor constraintEqualToConstant:72],[remove.trailingAnchor constraintEqualToAnchor:more.leadingAnchor constant:-10],[remove.centerYAnchor constraintEqualToAnchor:play.centerYAnchor],[remove.widthAnchor constraintEqualToConstant:72]]];
    self.gridScroll=[NSScrollView new];self.gridScroll.hasVerticalScroller=YES;self.gridScroll.drawsBackground=NO;Add(self.page,self.gridScroll);
    [NSLayoutConstraint activateConstraints:@[[self.gridScroll.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[self.gridScroll.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[self.gridScroll.topAnchor constraintEqualToAnchor:self.page.topAnchor],[self.gridScroll.bottomAnchor constraintEqualToAnchor:details.topAnchor constant:-20]]];
    self.grid=[[NPGrid alloc]initWithFrame:NSMakeRect(0,0,800,300)];self.grid.autoresizingMask=NSViewWidthSizable;self.gridScroll.documentView=self.grid;[self filterLibrary];
}
- (void)filterLibrary{
    NSString *query=self.search.stringValue.lowercaseString;NSMutableArray *filtered=[NSMutableArray new];for(NSDictionary *game in self.catalog)if(!query.length||[[game[@"title"] lowercaseString] containsString:query])[filtered addObject:game];self.filtered=filtered;
    for(NSView *view in self.grid.subviews.copy)[view removeFromSuperview];NSMutableArray *tiles=[NSMutableArray new];
    for(NSDictionary *game in filtered){NPGameTile *tile=[NPGameTile buttonWithTitle:game[@"title"] target:self action:@selector(selectTile:)];tile.game=game;tile.bordered=NO;tile.identifier=[@"game-" stringByAppendingString:[self.store keyForGame:game]];tile.state=[game[@"path"] isEqual:self.game[@"path"]]?NSControlStateValueOn:NSControlStateValueOff;tile.accessibilityLabel=[NSString stringWithFormat:@"%@, version %@",game[@"title"],game[@"version"]];[self.grid addSubview:tile];[tiles addObject:tile];}
    self.grid.tiles=tiles;[self.grid arrange];
    if(!filtered.count){NSTextField *empty=Label(self.catalog.count?@"No matching apps.":@"Add a native app to begin your library.",15,NSFontWeightMedium,Muted());empty.frame=NSMakeRect(12,30,500,50);[self.grid addSubview:empty];}
}
- (void)backupsPage{
    NSTextField *heading=Label(@"Progress + controller settings",18,NSFontWeightSemibold,NSColor.whiteColor),*hint=Label(@"A snapshot before play. Restoring first protects your current progress with another backup.",12,NSFontWeightRegular,Muted());
    NSButton *backup=Button(@"Back up now",self,@selector(backup:),YES);backup.enabled=!self.busy&&!self.externalRunning;backup.identifier=@"backup-now";
    NSButton *restore=Button(@"Restore selected…",self,@selector(restore:),NO);restore.identifier=@"restore-backup";restore.enabled=self.snapshots.count>0&&!self.externalRunning&&!self.busy;
    NSButton *reveal=Button(@"Open backup folder",self,@selector(revealBackups:),NO);NSTextField *retention=Label([NSString stringWithFormat:@"%lu of 20 snapshots",(unsigned long)self.snapshots.count],11,NSFontWeightRegular,Muted());retention.alignment=NSTextAlignmentRight;
    NPPanel *panel=[NPPanel new];NSScrollView *scroll=[NSScrollView new];scroll.hasVerticalScroller=YES;scroll.drawsBackground=NO;Fill(panel,scroll,4);
    self.table=[[NSTableView alloc]initWithFrame:NSMakeRect(0,0,600,self.snapshots.count*RowHeight)];self.table.identifier=@"backups";self.table.headerView=nil;self.table.rowHeight=RowHeight;self.table.intercellSpacing=NSMakeSize(0,0);self.table.backgroundColor=Surface();self.table.dataSource=self;self.table.delegate=self;self.table.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
    NSTableColumn *column=[[NSTableColumn alloc]initWithIdentifier:@"snapshot"];column.width=600;[self.table addTableColumn:column];scroll.documentView=self.table;[self.table reloadData];
    for(NSView *view in @[heading,hint,backup,panel,restore,reveal,retention])Add(self.page,view);
    [NSLayoutConstraint activateConstraints:@[[heading.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[heading.topAnchor constraintEqualToAnchor:self.page.topAnchor constant:4],[heading.trailingAnchor constraintLessThanOrEqualToAnchor:backup.leadingAnchor constant:-16],[backup.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[backup.topAnchor constraintEqualToAnchor:self.page.topAnchor],[backup.widthAnchor constraintEqualToConstant:148],[hint.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[hint.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[hint.topAnchor constraintEqualToAnchor:backup.bottomAnchor constant:14],[panel.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[panel.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[panel.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:20],[panel.bottomAnchor constraintEqualToAnchor:restore.topAnchor constant:-20],[restore.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[restore.bottomAnchor constraintEqualToAnchor:self.page.bottomAnchor],[restore.widthAnchor constraintEqualToConstant:174],[reveal.leadingAnchor constraintEqualToAnchor:restore.trailingAnchor constant:12],[reveal.centerYAnchor constraintEqualToAnchor:restore.centerYAnchor],[reveal.widthAnchor constraintEqualToConstant:180],[retention.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[retention.centerYAnchor constraintEqualToAnchor:restore.centerYAnchor]]];
    if(self.snapshots.count){NSUInteger selected=0;for(NSUInteger i=0;i<self.snapshots.count;i++)if([self.snapshots[i][@"path"] isEqual:self.selectedSnapshot])selected=i;[self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:selected] byExtendingSelection:NO];}
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table{(void)table;return (NSInteger)self.snapshots.count;}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row{(void)column;NPBackupCell *cell=[table makeViewWithIdentifier:@"backup-cell" owner:self];if(!cell){cell=[NPBackupCell new];cell.identifier=@"backup-cell";}[cell configure:self.snapshots[(NSUInteger)row]];return cell;}
- (NSTableRowView *)tableView:(NSTableView *)table rowViewForRow:(NSInteger)row{(void)table;(void)row;return [NPBackupRow new];}
- (void)tableViewSelectionDidChange:(NSNotification *)notification{(void)notification;if(self.table.selectedRow>=0)self.selectedSnapshot=self.snapshots[(NSUInteger)self.table.selectedRow][@"path"];}
- (void)performancePage{
    NSDictionary *options=self.store.options;
    NSArray *rows=@[
        [[NPSettingRow alloc]initWithTitle:@"Start in full screen" detail:@"Native full screen is required for macOS Game Mode." identifier:@"fullscreen" on:[options[@"fullscreen"] boolValue] target:self action:@selector(setting:)],
        [[NPSettingRow alloc]initWithTitle:@"Show Metal performance stats" detail:@"FPS, frame timing and GPU memory for this app only." identifier:@"hud" on:[options[@"hud"] boolValue] target:self action:@selector(setting:)],
        [[NPSettingRow alloc]initWithTitle:@"Record the next session" detail:@"One session, then off. Finished captures: up to 3 files / 256 MB." identifier:@"record" on:[options[@"record"] boolValue] target:self action:@selector(setting:)]];
    NSView *previous=nil;
    for(NSView *row in rows){Add(self.page,row);[NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[row.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[row.topAnchor constraintEqualToAnchor:previous?previous.bottomAnchor:self.page.topAnchor constant:previous?12:0]]];previous=row;}
    NSDictionary *summary=[self latestSummary];NSString *text=summary.count?[NSString stringWithFormat:@"Last recording · %@ frames\nMedian %.2f ms   ·   p95 %.2f ms   ·   p99 %.2f ms\n%@ gaps over 50 ms. Loading and transitions are included.",summary[@"frames"],[summary[@"median_ms"] doubleValue],[summary[@"p95_ms"] doubleValue],[summary[@"p99_ms"] doubleValue],summary[@"over_50_ms"]]:@"No recording for this app yet.\nRecord one session to see its frame-time summary here.";
    NSTextField *report=Label(text,13,NSFontWeightRegular,Muted());report.maximumNumberOfLines=3;Add(self.page,report);[NSLayoutConstraint activateConstraints:@[[report.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor constant:4],[report.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor constant:-4],[report.topAnchor constraintEqualToAnchor:previous.bottomAnchor constant:22]]];
}
- (NSDictionary *)latestSummary{
    NSURL *sessions=[self.store.root URLByAppendingPathComponent:@"Sessions"];NSDictionary *latest=@{};double time=0;
    for(NSURL *dir in [NSFileManager.defaultManager contentsOfDirectoryAtURL:sessions includingPropertiesForKeys:nil options:0 error:NULL]){
        NSData *m=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"session.json"]],*r=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"result.json"]],*s=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"summary.json"]];if(!m||!r||!s)continue;
        id meta=[NSJSONSerialization JSONObjectWithData:m options:0 error:NULL],result=[NSJSONSerialization JSONObjectWithData:r options:0 error:NULL],summary=[NSJSONSerialization JSONObjectWithData:s options:0 error:NULL];
        if(![meta isKindOfClass:NSDictionary.class]||![result isKindOfClass:NSDictionary.class]||![summary isKindOfClass:NSDictionary.class]||![meta[@"game"] isEqual:self.game[@"id"]])continue;
        if(meta[@"app_key"]&&![meta[@"app_key"] isEqual:[self.store keyForGame:self.game]])continue;
        if([result[@"finished"] doubleValue]>time){time=[result[@"finished"] doubleValue];latest=summary;}
    }return latest;
}
- (void)controllersPage{
    NPPanel *panel=[NPPanel new];Add(self.page,panel);[NSLayoutConstraint activateConstraints:@[[panel.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[panel.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[panel.topAnchor constraintEqualToAnchor:self.page.topAnchor],[panel.heightAnchor constraintEqualToConstant:230]]];
    NSTextField *title=Label(Controllers(self.game)?@"Every controller. The right player.":@"Use this game's controller controls.",19,NSFontWeightSemibold,NSColor.whiteColor);
    NSTextField *detail=Label(Controllers(self.game)?@"Turn on your controllers, then open the game's live setup. Assign players, swap A/B and X/Y, and check buttons and sticks.\n\nWhile playing, press F2 or Command-Shift-C to reopen setup.":@"This app has not declared the shared controller setup. Open the game and use its own controller menu.",14,NSFontWeightRegular,Muted());detail.maximumNumberOfLines=6;
    NSButton *open=Button(Controllers(self.game)?@"Open game + controller setup":@"Open game",self,@selector(controllers:),YES);open.enabled=!self.busy;[open.widthAnchor constraintEqualToConstant:280].active=YES;
    for(NSView *view in @[title,detail,open])Add(panel,view);[NSLayoutConstraint activateConstraints:@[[title.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:24],[title.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-24],[title.topAnchor constraintEqualToAnchor:panel.topAnchor constant:22],[detail.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[detail.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],[detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],[open.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[open.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-22]]];
}
- (void)navigate:(NSButton *)sender{[self showSection:@[@"Library",@"Backups",@"Performance",@"Controllers"][(NSUInteger)sender.tag]];}
- (void)select:(NSDictionary *)game{if(self.busy)return;self.game=game;self.store.activeGame=game;self.selectedSnapshot=nil;[self showSection:self.section];}
- (void)selectTile:(NPGameTile *)sender{[self select:sender.game];}
- (void)pickGame:(NSPopUpButton *)sender{if(sender.selectedItem.tag>=0&&(NSUInteger)sender.selectedItem.tag<self.catalog.count)[self select:self.catalog[(NSUInteger)sender.selectedItem.tag]];}
- (void)controlTextDidChange:(NSNotification *)note{if(note.object==self.search)[self filterLibrary];}
- (void)error:(NSError *)error{NSAlert *alert=[NSAlert new];alert.messageText=@"Native Play";alert.informativeText=error.localizedDescription?:@"The action could not be completed.";[alert runModal];}
- (void)addGames:(id)sender{
    (void)sender;if(self.preview||self.busy)return;NSOpenPanel *panel=[NSOpenPanel openPanel];panel.allowedContentTypes=@[UTTypeApplicationBundle];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=YES;panel.prompt=@"Add native apps";if([panel runModal]!=NSModalResponseOK)return;
    NSArray *urls=panel.URLs;self.busy=YES;[self notice:@"Checking app signatures and build identities…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSArray *added=[self.store importApps:urls error:&error];dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;if(!added){[self error:error];return;}self.catalog=self.store.games;self.game=added.firstObject;[self showSection:@"Library"];[self notice:@"Native apps added. Your existing library and progress are preserved."];});});
}
- (void)refresh:(id)sender{(void)sender;if(!self.preview)self.catalog=self.store.games;[self showSection:self.section];}
- (void)revealGame:(id)sender{(void)sender;if(!self.preview&&self.game)[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:self.game[@"path"]]]];}
- (void)removeGame:(id)sender{(void)sender;if(!self.game||self.preview||self.busy)return;NSAlert *alert=[NSAlert new];alert.messageText=@"Remove this library entry?";alert.informativeText=@"The installed app, saves and backups stay on disk.";[alert addButtonWithTitle:@"Remove entry"];[alert addButtonWithTitle:@"Cancel"];if([alert runModal]!=NSAlertFirstButtonReturn)return;NSError *error=nil;if(![self.store removeGame:self.game error:&error]){[self error:error];return;}self.catalog=self.store.games;self.game=self.catalog.firstObject;[self showSection:@"Library"];}
- (void)play:(id)sender{(void)sender;[self start:NO];}
- (void)controllers:(id)sender{(void)sender;[self start:Controllers(self.game)];}
- (void)start:(BOOL)controllers{
    if(self.preview||self.busy||!self.game)return;
    if(self.task.running){[[NSRunningApplication runningApplicationWithProcessIdentifier:self.task.processIdentifier]activateWithOptions:0];return;}
    self.busy=YES;[self notice:@"Verifying the app and backing up its progress…"];NSDictionary *game=self.game;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSTask *task=[self.store launch:game controllers:controllers completion:^(int status,NSURL *session){(void)session;dispatch_async(dispatch_get_main_queue(),^{self.task=nil;[self showSection:self.section];[self notice:status==0?@"Game closed. Progress is saved locally.":@"Game stopped. Its pre-launch backup is available."];if(!self.window.isVisible)[NSApp terminate:nil];});} error:&error];
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.task=task;self.runningKey=[self.store keyForGame:game];if(!task)[self error:error];[self showSection:self.section];[self notice:task?@"Playing offline. Quit the game normally to finish its recording.":@"Launch stopped; your saved progress is preserved."];});});
}
- (void)setting:(NSSwitch *)sender{NSMutableDictionary *options=[self.store.options mutableCopy];options[sender.identifier]=@(sender.state==NSControlStateValueOn);[self.store setOptions:options];[self notice:@"Launch preference saved for this app."];}
- (void)backup:(id)sender{(void)sender;if(!self.game||self.busy)return;NSError *error=nil;if(![self.store backup:@"Manual backup" error:&error]){[self error:error];return;}[self showSection:@"Backups"];[self notice:@"Progress and controller settings backed up and verified."];}
- (void)restore:(id)sender{(void)sender;NSInteger row=self.table.selectedRow;if(self.busy||row<0||(NSUInteger)row>=self.snapshots.count)return;NSAlert *alert=[NSAlert new];alert.messageText=@"Restore this game's backup?";alert.informativeText=@"Your current progress and controller settings are backed up first. Other games are unaffected.";[alert addButtonWithTitle:@"Restore backup"];[alert addButtonWithTitle:@"Cancel"];if([alert runModal]!=NSAlertFirstButtonReturn)return;NSError *error=nil;if(![self.store restore:self.snapshots[(NSUInteger)row] error:&error]){[self error:error];return;}[self showSection:@"Backups"];[self notice:@"Backup restored; the previous state is also kept."];}
- (void)revealBackups:(id)sender{(void)sender;[NSWorkspace.sharedWorkspace openURL:[self.store.root URLByAppendingPathComponent:[@"Backups/" stringByAppendingString:self.store.activeID]]];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible{(void)app;if(!visible)[self.window makeKeyAndOrderFront:nil];return YES;}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app{(void)app;return !self.task.running&&!self.busy;}
- (void)check:(BOOL)condition message:(NSString *)message{if(!condition){fprintf(stderr,"UI FAIL: %s\n",message.UTF8String);exit(1);}}
- (void)runUITest{
    NSUInteger checks=0;
    for(NSValue *size in @[[NSValue valueWithSize:NSMakeSize(960,720)],[NSValue valueWithSize:NSMakeSize(1140,780)],[NSValue valueWithSize:NSMakeSize(1440,920)]]){
        [self.window setContentSize:size.sizeValue];
        for(NSString *section in @[@"Library",@"Backups",@"Performance",@"Controllers"]){[self showSection:section];[self.window.contentView layoutSubtreeIfNeeded];
            [self check:!self.canvas.hasAmbiguousLayout&&!self.page.hasAmbiguousLayout message:@"unambiguous page layout"];checks++;
            for(NPSidebarButton *button in self.navigation){NSPoint p=[self.canvas.superview convertPoint:NSMakePoint(NSMidX(button.bounds),NSMidY(button.bounds)) fromView:button];NSView *hit=[self.canvas hitTest:p];[self check:hit==button||[hit isDescendantOf:button] message:[@"navigation hit: " stringByAppendingString:button.title]];checks++;}
            if([section isEqual:@"Backups"]){[self check:self.table.numberOfRows==2 message:@"two padded backup rows"];NPBackupCell *cell=(NPBackupCell *)[self.table viewAtColumn:0 row:0 makeIfNecessary:YES];[cell layoutSubtreeIfNeeded];[self check:cell.heading.frame.origin.x>=16&&cell.heading.frame.origin.y>=12&&NSMaxY(cell.detail.frame)<=RowHeight-12 message:@"backup row insets"];checks+=2;}
            if([section isEqual:@"Library"]){[self.grid arrange];[self check:self.grid.tiles.count==3 message:@"three native app tiles"];for(NPGameTile *tile in self.grid.tiles)[self check:NSMaxX(tile.frame)<=self.grid.bounds.size.width+1 message:@"tile stays inside grid"];checks+=4;}
        }
    }
    [self select:self.catalog[1]];[self check:[self.store.activeID isEqual:self.catalog[1][@"id"]] message:@"selection scopes store"];checks++;
    [self showSection:@"Library"];self.search.stringValue=@"Moss";[self filterLibrary];[self check:self.grid.tiles.count==1 message:@"library search"];checks++;
    [self select:self.catalog.firstObject];[self showSection:@"Performance"];
    for(NPSettingRow *row in self.page.subviews)if([row isKindOfClass:NPSettingRow.class]&&[row.toggle.identifier isEqual:@"hud"]){row.toggle.state=NSControlStateValueOn;[NSApp sendAction:row.toggle.action to:row.toggle.target from:row.toggle];}
    [self check:[self.store.options[@"hud"] boolValue] message:@"native switch persists"];checks++;
    [self.store setOptions:@{@"hud":@NO,@"record":@NO,@"fullscreen":@YES}];[self.window setContentSize:NSMakeSize(1140,780)];[self notice:@"Games and progress stay on this Mac."];
    if(self.snapshotPath)for(NSString *section in @[@"Library",@"Backups",@"Performance",@"Controllers"]){[self showSection:section];[self.window.contentView layoutSubtreeIfNeeded];[self.window displayIfNeeded];NSBitmapImageRep *bitmap=[self.canvas bitmapImageRepForCachingDisplayInRect:self.canvas.bounds];[self.canvas cacheDisplayInRect:self.canvas.bounds toBitmapImageRep:bitmap];NSString *path=[section isEqual:@"Library"]?self.snapshotPath:[[self.snapshotPath.stringByDeletingPathExtension stringByAppendingFormat:@"-%@",section] stringByAppendingPathExtension:@"png"];[[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];}
    printf("Native Play: %lu responsive multi-app UI checks passed (synthetic data).\n",(unsigned long)checks);fflush(stdout);if(self.test)[NSApp terminate:nil];
}
@end
