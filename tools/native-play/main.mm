// Objective-C++ is the Cocoa bridge for this C/C++ native-game library.
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "NPModel.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>

static NSColor *Color(CGFloat r,CGFloat g,CGFloat b){return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];}
static NSColor *Ink(void){return Color(.065,.075,.09);}
static NSColor *Mint(void){return Color(.43,.96,.74);}
static NSColor *Muted(void){return Color(.58,.63,.67);}
static NSTextField *Text(NSString *text,CGFloat size,NSFontWeight weight){
    NSTextField *label=[NSTextField wrappingLabelWithString:text];label.font=[NSFont systemFontOfSize:size weight:weight];label.textColor=NSColor.whiteColor;label.maximumNumberOfLines=0;return label;
}
static void Place(NSView *parent,NSView *view,CGFloat x,CGFloat y,CGFloat w,CGFloat h){view.frame=NSMakeRect(x,y,w,h);[parent addSubview:view];}
static NSButton *Button(NSString *title,id target,SEL action,BOOL primary){
    NSButton *button=[NSButton buttonWithTitle:title target:target action:action];button.bezelStyle=NSBezelStyleRounded;
    button.font=[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];button.bezelColor=primary?Mint():Color(.17,.20,.23);
    button.bordered=NO;button.wantsLayer=YES;button.layer.backgroundColor=(primary?Mint():Color(.17,.20,.23)).CGColor;button.layer.cornerRadius=11;
    button.attributedTitle=[[NSAttributedString alloc]initWithString:title attributes:@{NSFontAttributeName:button.font,NSForegroundColorAttributeName:primary?Ink():NSColor.whiteColor}];
    button.contentTintColor=primary?Ink():NSColor.whiteColor;button.identifier=title;return button;
}
@interface NPFlipped : NSView @end
@implementation NPFlipped
- (BOOL)isFlipped{return YES;}
@end

@interface NPArt : NSView @end
@implementation NPArt
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty{
    (void)dirty;NSRect b=self.bounds;[[NSBezierPath bezierPathWithRoundedRect:b xRadius:23 yRadius:23] addClip];
    [Color(.18,.26,.38) setFill];NSRectFill(b);
    [Color(.20,.38,.42) setFill];[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(-110,120,480,480)] fill];
    [Color(.40,.82,.67) setStroke];NSBezierPath *orbit=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(-120,95,530,530)];orbit.lineWidth=2;[orbit stroke];
    [Color(.34,.65,.62) setStroke];NSBezierPath *other=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(-70,145,430,430)];other.lineWidth=1;[other stroke];
    NSDictionary *small=@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium],NSForegroundColorAttributeName:Mint()};
    [@"NATIVE COLLECTION  /  01" drawAtPoint:NSMakePoint(25,25) withAttributes:small];
    [@"SUPER\nMARIO PARTY" drawInRect:NSMakeRect(25,74,b.size.width-50,100) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:31 weight:NSFontWeightHeavy],NSForegroundColorAttributeName:NSColor.whiteColor}];
    [@"JAMBOREE" drawAtPoint:NSMakePoint(24,162) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:34 weight:NSFontWeightHeavy],NSForegroundColorAttributeName:Mint()}];
    for(NSUInteger i=0;i<4;i++){
        CGFloat x=36+(i%2)*54,y=b.size.height-137+(i/2)*47;
        [@[Mint(),Color(.97,.72,.42),Color(.92,.48,.57),Color(.54,.67,.97)][i] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x,y,34,34) xRadius:11 yRadius:11] fill];
    }
    [@"YOUR GAME. ON YOUR MAC." drawAtPoint:NSMakePoint(25,b.size.height-32) withAttributes:small];
}
@end

@class NPApp;
@interface NPCanvas : NPFlipped
@property(weak) NPApp *owner;
@property NSSize lastSize;
@end
@interface NPApp : NSObject <NSApplicationDelegate,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate>
@property NSWindow *window;
@property NPCanvas *canvas;
@property NPFlipped *page;
@property NPStore *store;
@property NSDictionary *game;
@property NSTask *task;
@property NSString *section,*notice;
@property NSMutableArray<NSButton *> *navigation;
@property NSArray<NSDictionary *> *snapshots;
@property NSTableView *table;
@property BOOL preview,busy;
@property NSString *snapshotPath;
@property BOOL test;
- (void)layout;
- (void)showSection:(NSString *)name;
@end
@implementation NPCanvas
- (void)layout{[super layout];if(!NSEqualSizes(self.lastSize,self.bounds.size)){self.lastSize=self.bounds.size;[self.owner layout];}}
- (void)drawRect:(NSRect)dirty{[Ink() setFill];NSRectFill(dirty);}
@end
@implementation NPApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification{
    (void)notification;
    self.section=@"Library";self.notice=@"Your games and progress stay on this Mac.";
    self.game=self.preview?@{@"title":@"Super Mario Party Jamboree",@"version":@"2.3.0",@"path":@"/Synthetic/Jamboree.app",@"id":@"0100965017338000"}:self.store.games.firstObject;
    self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1140,740) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Native Play";self.window.minSize=NSMakeSize(1080,710);self.window.titlebarAppearsTransparent=YES;
    self.window.backgroundColor=Ink();self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];self.window.delegate=self;
    self.canvas=[NPCanvas new];self.canvas.owner=self;self.window.contentView=self.canvas;
    [self installMenu];[self showSection:@"Library"];[self.window center];[self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if(self.test || self.snapshotPath)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self runUITest];});
}
- (void)installMenu{
    NSMenu *bar=[NSMenu new],*app=[NSMenu new],*file=[NSMenu new];
    [app addItemWithTitle:@"About Native Play" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];[app addItemWithTitle:@"Quit Native Play" action:@selector(terminate:) keyEquivalent:@"q"];
    [[bar addItemWithTitle:@"Native Play" action:nil keyEquivalent:@""]setSubmenu:app];
    NSMenuItem *add=[file addItemWithTitle:@"Add native app…" action:@selector(addGame:) keyEquivalent:@"o"];add.target=self;
    NSMenuItem *backup=[file addItemWithTitle:@"Back up progress" action:@selector(backup:) keyEquivalent:@"b"];backup.target=self;
    [[bar addItemWithTitle:@"File" action:nil keyEquivalent:@""]setSubmenu:file];NSApp.mainMenu=bar;
}
- (void)showSection:(NSString *)name{self.section=name;self.table=nil;[self layout];}
- (void)layout{
    if(!self.canvas)return;
    for(NSView *view in self.canvas.subviews.copy)[view removeFromSuperview];
    CGFloat width=self.canvas.bounds.size.width,height=self.canvas.bounds.size.height,x=248,w=width-x-38;
    NSView *rail=[NPFlipped new];rail.wantsLayer=YES;rail.layer.backgroundColor=Color(.08,.095,.11).CGColor;Place(self.canvas,rail,0,0,211,height);
    NSTextField *brand=Text(@"native\nplay",32,NSFontWeightHeavy);Place(rail,brand,27,29,160,85);
    NSTextField *tag=Text(@"MADE FOR YOUR MAC",9,NSFontWeightBold);tag.textColor=Mint();Place(rail,tag,29,115,170,20);
    self.navigation=[NSMutableArray new];NSArray *names=@[@"Library",@"Backups",@"Performance",@"Controllers"];
    NSArray *symbols=@[@"square.grid.2x2",@"clock.arrow.circlepath",@"waveform.path.ecg",@"gamecontroller"];
    for(NSUInteger i=0;i<names.count;i++){
        NSButton *button=Button(names[i],self,@selector(navigate:),NO);button.image=[NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:nil];button.imagePosition=NSImageLeading;
        button.bezelColor=[self.section isEqual:names[i]]?Color(.20,.31,.29):Color(.08,.095,.11);button.contentTintColor=[self.section isEqual:names[i]]?Mint():Muted();
        button.layer.backgroundColor=([self.section isEqual:names[i]]?Color(.20,.31,.29):Color(.08,.095,.11)).CGColor;
        button.attributedTitle=[[NSAttributedString alloc]initWithString:names[i] attributes:@{NSFontAttributeName:button.font,NSForegroundColorAttributeName:[self.section isEqual:names[i]]?Mint():Muted()}];
        button.tag=(NSInteger)i;Place(rail,button,18,176+i*55,175,43);[self.navigation addObject:button];
    }
    NSTextField *local=Text(@"●  LOCAL & OFFLINE",10,NSFontWeightSemibold);local.textColor=Mint();Place(rail,local,28,height-78,175,20);
    NSTextField *machine=Text(@"Apple Silicon · Native ports",10,NSFontWeightRegular);machine.textColor=Muted();Place(rail,machine,28,height-53,175,20);
    NSString *title=[self.section isEqual:@"Library"]?@"Pick up where you left off.":[@{@"Backups":@"A little peace of mind.",@"Performance":@"Keep play feeling smooth.",@"Controllers":@"Bring everyone along."} objectForKey:self.section];
    Place(self.canvas,Text(title,30,NSFontWeightBold),x,34,w-200,46);
    NSTextField *sub=Text([self.section isEqual:@"Library"]?@"Your collection. Ready on this Mac.":self.section,13,NSFontWeightRegular);sub.textColor=Muted();Place(self.canvas,sub,x,87,w-160,25);
    Place(self.canvas,Button(@"Add native app…",self,@selector(addGame:),NO),width-197,42,159,38);
    self.page=[NPFlipped new];Place(self.canvas,self.page,x,137,w,height-217);
    if([self.section isEqual:@"Library"])[self libraryPage];
    else if([self.section isEqual:@"Backups"])[self backupsPage];
    else if([self.section isEqual:@"Performance"])[self performancePage];
    else [self controllersPage];
    NSTextField *notice=Text(self.notice,11,NSFontWeightRegular);notice.textColor=Muted();notice.identifier=@"status";Place(self.canvas,notice,x,height-53,w,40);
}
- (void)libraryPage{
    CGFloat w=self.page.bounds.size.width;
    if(!self.game){Place(self.page,Text(@"A home for native games.",26,NSFontWeightBold),12,55,w-40,45);Place(self.page,Text(@"Add your locally built Jamboree app to begin. Game files, keys and downloads are never included.",15,NSFontWeightRegular),12,117,w-80,80);Place(self.page,Button(@"Add native app…",self,@selector(addGame:),YES),12,230,220,48);return;}
    Place(self.page,[NPArt new],0,0,350,435);
    CGFloat x=389,remaining=w-x;
    NSTextField *type=Text(@"NATIVE PORT  /  INSTALLED",10,NSFontWeightBold);type.textColor=Mint();Place(self.page,type,x,23,remaining,22);
    Place(self.page,Text(self.game[@"title"],27,NSFontWeightBold),x,64,remaining,92);
    NSTextField *meta=Text([NSString stringWithFormat:@"Version %@  ·  English\nBuilt for Apple Silicon",self.game[@"version"]],13,NSFontWeightRegular);meta.textColor=Muted();Place(self.page,meta,x,164,remaining,57);
    NSButton *play=Button(self.busy?@"Preparing…":(self.task.running?@"Return to game":@"Play"),self,@selector(play:),YES);play.enabled=!self.busy;play.keyEquivalent=@"\r";Place(self.page,play,x,240,remaining,52);
    NSButton *controllers=Button(@"Controller setup",self,@selector(openControllers:),NO);controllers.enabled=!self.busy;Place(self.page,controllers,x,307,remaining,40);
    NSButton *hud=[NSButton checkboxWithTitle:@"Show performance stats" target:self action:@selector(toggleHUD:)];hud.identifier=@"hud";hud.state=[self.store.options[@"hud"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;Place(self.page,hud,x,366,remaining,26);
    NSTextField *safe=Text(@"✓  Automatic backup before play\n✓  Network blocked for game sessions",11,NSFontWeightRegular);safe.textColor=Muted();Place(self.page,safe,x,407,remaining,48);
}
- (void)backupsPage{
    CGFloat w=self.page.bounds.size.width;self.snapshots=self.store.backups;
    Place(self.page,Text(@"Progress + controller settings",21,NSFontWeightSemibold),0,3,w-220,35);
    NSButton *backup=Button(@"Back up now",self,@selector(backup:),YES);backup.enabled=!self.busy&&!self.task.running;Place(self.page,backup,w-177,0,177,40);
    NSTextField *explanation=Text(@"A verified snapshot before every launch. Keep the latest 20. Restoring also creates a backup of your current progress.",13,NSFontWeightRegular);explanation.textColor=Muted();Place(self.page,explanation,0,56,w,50);
    NSScrollView *scroll=[NSScrollView new];scroll.hasVerticalScroller=YES;scroll.borderType=NSNoBorder;
    self.table=[NSTableView new];self.table.headerView=nil;self.table.rowHeight=66;self.table.backgroundColor=Color(.09,.11,.13);self.table.dataSource=self;self.table.delegate=self;self.table.identifier=@"backups";
    NSTableColumn *column=[[NSTableColumn alloc]initWithIdentifier:@"snapshot"];column.width=w-20;[self.table addTableColumn:column];self.table.frame=NSMakeRect(0,0,w,MAX(255,self.snapshots.count*66));[self.table reloadData];scroll.documentView=self.table;Place(self.page,scroll,0,121,w,255);
    if(self.snapshots.count)[self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    NSButton *restore=Button(@"Restore selected…",self,@selector(restore:),NO);restore.enabled=self.snapshots.count>0&&!self.task.running&&!self.busy;Place(self.page,restore,0,400,195,43);
    NSButton *reveal=Button(@"Open backup folder",self,@selector(revealBackups:),NO);Place(self.page,reveal,212,400,195,43);
    if(!self.snapshots.count){NSTextField *empty=Text(@"Your first backup appears here when you play or choose Back up now.",13,NSFontWeightRegular);empty.textColor=Muted();Place(self.page,empty,20,149,w-40,60);}
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table{(void)table;return (NSInteger)self.snapshots.count;}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row{
    (void)table;(void)column;NSDictionary *item=self.snapshots[(NSUInteger)row];NSDateFormatter *format=[NSDateFormatter new];format.dateStyle=NSDateFormatterMediumStyle;format.timeStyle=NSDateFormatterShortStyle;
    NSString *date=[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[item[@"created"] doubleValue]]];
    NSTextField *text=Text([NSString stringWithFormat:@"%@    ·    %@\n%lu verified files",item[@"label"],date,(unsigned long)[item[@"files"] count]],13,NSFontWeightMedium);return text;
}
- (void)performancePage{
    CGFloat w=self.page.bounds.size.width;
    Place(self.page,Text(@"Fast by default.",23,NSFontWeightBold),0,8,w,40);
    NSTextField *intro=Text(@"Normal play skips continuous frame recording and diagnostic validation. Turn on only what you need for the next launch.",14,NSFontWeightRegular);intro.textColor=Muted();Place(self.page,intro,0,62,w,65);
    NSButton *hud=[NSButton checkboxWithTitle:@"In-game Metal performance stats" target:self action:@selector(toggleHUD:)];hud.state=[self.store.options[@"hud"] boolValue];hud.identifier=@"hud";Place(self.page,hud,0,142,w,28);
    NSTextField *hint=Text(@"FPS, frame timing and GPU memory. Applies only to games launched here; your system settings stay as they are.",12,NSFontWeightRegular);hint.textColor=Muted();Place(self.page,hint,25,179,w-25,47);
    NSButton *record=[NSButton checkboxWithTitle:@"Record timing for one session" target:self action:@selector(toggleRecord:)];record.state=[self.store.options[@"record"] boolValue];record.identifier=@"record";Place(self.page,record,0,239,w,28);
    NSTextField *detail=Text(@"Automatically turns off after launch. Finished recordings: at most 3 files / 256 MB, plus 20 summaries. Loading transitions are included.",12,NSFontWeightRegular);detail.textColor=Muted();Place(self.page,detail,25,278,w-25,52);
    NSDictionary *summary=[self latestSummary];
    NSString *result=summary.count?[NSString stringWithFormat:@"Last recording  ·  %@ frames\nMedian %.2f ms    p95 %.2f ms    p99 %.2f ms\n%@ frame gaps over 50 ms (loading included)",summary[@"frames"],[summary[@"median_ms"] doubleValue],[summary[@"p95_ms"] doubleValue],[summary[@"p99_ms"] doubleValue],summary[@"over_50_ms"]]:@"No timing recording yet.\nEnable recording, play, then quit the game to see a summary here.";
    Place(self.page,Text(result,15,NSFontWeightMedium),0,363,w,100);
}
- (NSDictionary *)latestSummary{
    NSURL *sessions=[self.store.root URLByAppendingPathComponent:@"Sessions"];NSArray *dirs=[NSFileManager.defaultManager contentsOfDirectoryAtURL:sessions includingPropertiesForKeys:nil options:0 error:nil];
    NSDictionary *latest=@{};double time=0;
    for(NSURL *dir in dirs){NSData *r=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"result.json"]],*s=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"summary.json"]];if(!r||!s)continue;NSDictionary *result=[NSJSONSerialization JSONObjectWithData:r options:0 error:nil],*summary=[NSJSONSerialization JSONObjectWithData:s options:0 error:nil];if([result[@"finished"] doubleValue]>time && [summary isKindOfClass:NSDictionary.class]){time=[result[@"finished"] doubleValue];latest=summary;}}
    return latest;
}
- (void)controllersPage{
    CGFloat w=self.page.bounds.size.width;
    Place(self.page,Text(@"Your setup. Every player.",24,NSFontWeightBold),0,10,w,43);
    Place(self.page,Text(@"Keep using your working Bluetooth controllers. The game's live setup shows each pad, player assignment, button swaps and stick input.",15,NSFontWeightRegular),0,81,w,76);
    NSTextField *details=Text(@"1   Turn on both controllers.\n\n2   Open controller setup and choose each player.\n\n3   Keep A/B and X/Y swaps as you prefer.\n\nWhile playing, press F2 or Command-Shift-C to reopen setup.",14,NSFontWeightRegular);details.textColor=Muted();Place(self.page,details,0,183,w,178);
    NSButton *open=Button(self.task.running?@"Return to game · then F2":@"Open game + controller setup",self,@selector(openControllers:),YES);open.enabled=self.game&&!self.busy;Place(self.page,open,0,390,320,50);
}
- (void)navigate:(NSButton *)sender{[self showSection:@[@"Library",@"Backups",@"Performance",@"Controllers"][(NSUInteger)sender.tag]];}
- (void)error:(NSError *)error{NSAlert *alert=[NSAlert new];alert.messageText=@"Native Play";alert.informativeText=error.localizedDescription?:@"The action could not be completed.";[alert runModal];}
- (void)addGame:(id)sender{
    (void)sender;if(self.preview)return;
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowedContentTypes=@[UTTypeApplicationBundle];panel.prompt=@"Add native app";
    if([panel runModal]!=NSModalResponseOK)return;
    NSError *error=nil;NSDictionary *game=[self.store importApp:panel.URL error:&error];if(!game){[self error:error];return;}
    self.game=game;self.notice=@"Signed app verified. Ready to play.";[self showSection:@"Library"];
}
- (void)play:(id)sender{(void)sender;[self start:NO];}
- (void)openControllers:(id)sender{(void)sender;[self start:YES];}
- (void)start:(BOOL)controllers{
    if(self.preview || self.busy)return;
    if(self.task.running){[[NSRunningApplication runningApplicationWithProcessIdentifier:self.task.processIdentifier]activateWithOptions:0];return;}
    if(!self.game){[self addGame:nil];return;}
    self.busy=YES;self.notice=@"Verifying your game and backing up progress…";[self layout];
    NSDictionary *game=self.game;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;
        NSTask *task=[self.store launch:game controllers:controllers completion:^(int status,NSURL *session){(void)session;dispatch_async(dispatch_get_main_queue(),^{self.task=nil;self.notice=status==0?@"Game closed. Your progress is saved locally.":@"The game stopped unexpectedly. Your pre-launch backup is available.";[self layout];});} error:&error];
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.task=task;if(!task){[self error:error];self.notice=@"Launch stopped. Check the message and try again.";}else self.notice=@"Playing offline. Press F2 in the game for controller setup.";[self layout];});
    });
}
- (void)toggleHUD:(NSButton *)sender{NSMutableDictionary *options=[self.store.options mutableCopy];options[@"hud"]=@(sender.state==NSControlStateValueOn);[self.store setOptions:options];self.notice=@"Performance stats preference saved for the next launch.";}
- (void)toggleRecord:(NSButton *)sender{NSMutableDictionary *options=[self.store.options mutableCopy];options[@"record"]=@(sender.state==NSControlStateValueOn);[self.store setOptions:options];self.notice=@"Recording preference saved for the next launch.";}
- (void)backup:(id)sender{(void)sender;if(self.busy)return;NSError *error=nil;if(![self.store backup:@"Manual backup" error:&error]){[self error:error];return;}self.notice=@"Progress and controller settings backed up and verified.";[self showSection:@"Backups"];}
- (void)restore:(id)sender{
    (void)sender;if(self.busy)return;NSInteger row=self.table.selectedRow;if(row<0||(NSUInteger)row>=self.snapshots.count)return;
    NSAlert *alert=[NSAlert new];alert.messageText=@"Restore this backup?";alert.informativeText=@"This restores progress and controller settings. Your current state is backed up first. Close the game before continuing.";[alert addButtonWithTitle:@"Restore backup"];[alert addButtonWithTitle:@"Cancel"];
    if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSError *error=nil;if(![self.store restore:self.snapshots[(NSUInteger)row] error:&error]){[self error:error];return;}self.notice=@"Backup restored. Your previous progress is also kept in a backup.";[self showSection:@"Backups"];
}
- (void)revealBackups:(id)sender{(void)sender;[NSWorkspace.sharedWorkspace openURL:[self.store.root URLByAppendingPathComponent:@"Backups"]];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible{(void)app;if(!visible)[self.window makeKeyAndOrderFront:nil];return YES;}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app{(void)app;return !self.task.running&&!self.busy;}
- (void)runUITest{
    NSUInteger checks=0;
    for(NSString *section in @[@"Library",@"Backups",@"Performance",@"Controllers"]){
        [self showSection:section];[self.window.contentView layoutSubtreeIfNeeded];
        if([section isEqual:@"Backups"]){if(self.snapshots.count!=1||self.table.numberOfRows!=1){fputs("UI FAIL: synthetic backup row\n",stderr);exit(1);}checks++;}
        for(NSButton *button in self.navigation){NSPoint p=[self.canvas.superview convertPoint:NSMakePoint(NSMidX(button.bounds),NSMidY(button.bounds)) fromView:button];NSView *hit=[self.canvas hitTest:p];if(hit!=button && ![hit isDescendantOf:button]){fprintf(stderr,"UI FAIL: navigation hit area: %s\n",button.title.UTF8String);exit(1);}checks++;}
        for(NSView *view in self.page.subviews)if([view isKindOfClass:NSButton.class]){
            NSPoint p=[self.canvas.superview convertPoint:NSMakePoint(NSMidX(view.bounds),NSMidY(view.bounds)) fromView:view];NSView *hit=[self.canvas hitTest:p];if(hit!=view && ![hit isDescendantOf:view]){fprintf(stderr,"UI FAIL: control hit area: %s in %s\n",view.identifier.UTF8String,self.section.UTF8String);exit(1);}checks++;
        }
    }
    [self showSection:@"Performance"];
    for(NSView *view in self.page.subviews)if([view isKindOfClass:NSButton.class]&&[@[@"hud",@"record"] containsObject:view.identifier]){[(NSButton *)view performClick:nil];checks++;}
    if(![self.store.options[@"hud"] boolValue]||![self.store.options[@"record"] boolValue]){fprintf(stderr,"UI FAIL: preference click persistence (hud=%d, record=%d)\n",[self.store.options[@"hud"] boolValue],[self.store.options[@"record"] boolValue]);exit(1);}
    [self.store setOptions:@{@"hud":@NO,@"record":@NO}];self.notice=@"Your games and progress stay on this Mac.";[self showSection:@"Library"];[self.window displayIfNeeded];
    if(self.snapshotPath)for(NSString *section in @[@"Library",@"Backups",@"Performance",@"Controllers"]){[self showSection:section];[self.window displayIfNeeded];NSBitmapImageRep *bitmap=[self.canvas bitmapImageRepForCachingDisplayInRect:self.canvas.bounds];[self.canvas cacheDisplayInRect:self.canvas.bounds toBitmapImageRep:bitmap];NSString *path=[section isEqual:@"Library"]?self.snapshotPath:[[self.snapshotPath.stringByDeletingPathExtension stringByAppendingFormat:@"-%@",section] stringByAppendingPathExtension:@"png"];[[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];}
    printf("Native Play: %lu native UI interaction/hit checks passed (synthetic library).\n",(unsigned long)checks);fflush(stdout);
    if(self.test)[NSApp terminate:nil];
}
@end

static int Probe(int argc,const char **argv){
    if(argc!=5)return 2;
    int fd=open(argv[2],O_RDONLY);if(fd>=0){close(fd);return 3;}if(errno!=EPERM && errno!=EACCES)return 4;
    fd=open(argv[4],O_WRONLY|O_CREAT|O_EXCL,0600);if(fd>=0){close(fd);unlink(argv[4]);return 5;}if(errno!=EPERM && errno!=EACCES)return 6;
    fd=open(argv[3],O_WRONLY|O_CREAT|O_EXCL,0600);if(fd<0)return 7;close(fd);unlink(argv[3]);
    int s=socket(AF_INET,SOCK_STREAM,0);if(s<0)return (errno==EPERM || errno==EACCES)?0:8;
    struct sockaddr_in address={.sin_len=sizeof address,.sin_family=AF_INET,.sin_port=htons(9),.sin_addr={htonl(INADDR_LOOPBACK)}};
    int result=connect(s,(struct sockaddr *)&address,sizeof address),failure=errno;close(s);
    return result<0&&(failure==EPERM||failure==EACCES)?0:9;
}
static void Icon(NSString *path){
    NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(1024,1024)];[image lockFocus];
    [Ink() setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0,0,1024,1024) xRadius:220 yRadius:220]fill];
    [Mint() setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(188,215,285,594) xRadius:140 yRadius:140]fill];
    [Color(.22,.48,.58) setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(551,215,285,594) xRadius:140 yRadius:140]fill];
    [Ink() setFill];[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(270,537,120,120)]fill];
    [Mint() setFill];for(NSUInteger i=0;i<4;i++)[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(625+(i%2)*54,340+(i/2)*54,32,32)]fill];
    [image unlockFocus];NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc]initWithData:image.TIFFRepresentation];[[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];
}
int main(int argc,const char **argv){@autoreleasepool{
    umask(0077);
    if(argc>1&&!strcmp(argv[1],"--sandbox-probe"))return Probe(argc,argv);
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    if(argc==3&&!strcmp(argv[1],"--render-icon")){Icon(@(argv[2]));return 0;}
    NSArray *args=NSProcessInfo.processInfo.arguments;BOOL test=[args containsObject:@"--ui-test"],launchCheck=[args containsObject:@"--launch-check"],preview=test||launchCheck||[args containsObject:@"--preview"];
    NSURL *home=[NSURL fileURLWithPath:NSHomeDirectory()];
    if(preview){NSURL *temporary=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByResolvingSymlinksInPath];home=[temporary URLByAppendingPathComponent:[@"native-play-preview-" stringByAppendingString:NSUUID.UUID.UUIDString]];}
    NPStore *store=[[NPStore alloc]initWithRoot:[home URLByAppendingPathComponent:@"Library/Application Support/Native Play"] home:home];if(!store){fputs("Could not create private Native Play support directories.\n",stderr);return 1;}
    if(argc==3&&launchCheck){
        NSURL *documents=[home URLByAppendingPathComponent:@"Documents"];[NSFileManager.defaultManager createDirectoryAtURL:documents withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"synthetic protected input" writeToURL:[documents URLByAppendingPathComponent:@"blocked"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSError *error=nil;NSDictionary *game=[store importApp:[NSURL fileURLWithPath:@(argv[2])] error:&error];
        dispatch_semaphore_t done=dispatch_semaphore_create(0);__block int status=-1;
        NSTask *task=game?[store launch:game controllers:NO completion:^(int result,NSURL *session){(void)session;status=result;dispatch_semaphore_signal(done);} error:&error]:nil;
        if(!task){fprintf(stderr,"Fixture launch failed: %s\n",error.localizedDescription.UTF8String);return 1;}
        if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))){[task terminate];return 2;}
        if(status!=0){fprintf(stderr,"Fixture restriction checks failed: %d\n",status);return 3;}
        puts("Signed fixture launched: network denied, protected reads denied, session writes allowed, clean exit.");
        [NSFileManager.defaultManager removeItemAtURL:home error:NULL];return 0;
    }
    if(argc==3&&!strcmp(argv[1],"--register")){NSError *error=nil;if(![store importApp:[NSURL fileURLWithPath:@(argv[2])] error:&error]){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}puts("Signed native app registered locally.");return 0;}
    if(argc==2&&!strcmp(argv[1],"--backup")){NSError *error=nil;NSDictionary *snapshot=[store backup:@"Manual backup" error:&error];if(!snapshot){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}printf("Backed up and verified %lu private state files locally.\n",(unsigned long)[snapshot[@"files"] count]);return 0;}
    if(preview){NSURL *save=[store.state URLByAppendingPathComponent:@"save"];[NSFileManager.defaultManager createDirectoryAtURL:save withIntermediateDirectories:YES attributes:nil error:NULL];[@"synthetic progress" writeToURL:[save URLByAppendingPathComponent:@"preview"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];NSError *error=nil;if(![store backup:@"Preview backup" error:&error]){fprintf(stderr,"Preview setup failed: %s\n",error.localizedDescription.UTF8String);return 1;}}
    if(!preview)for(NSRunningApplication *running in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"org.macnativegames.native-play"])if(running.processIdentifier!=getpid()){[running activateWithOptions:0];return 0;}
    NPApp *delegate=[NPApp new];delegate.store=store;delegate.preview=preview;delegate.test=test;
    NSUInteger index=[args indexOfObject:@"--ui-snapshot"];if(index!=NSNotFound && index+1<args.count && preview)delegate.snapshotPath=args[index+1];
    NSApp.delegate=delegate;[NSApp run];return 0;
}}
