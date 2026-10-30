#import "front_controllers.h"
#import <QuartzCore/QuartzCore.h>

@implementation DmControllerInfo @end

static NSTextField *text(NSString *value, CGFloat size, NSColor *color) {
    NSTextField *v = [NSTextField wrappingLabelWithString:value];
    v.font = [NSFont systemFontOfSize:size]; v.textColor = color; return v;
}
static void place(NSView *parent, NSView *view, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    view.translatesAutoresizingMaskIntoConstraints=YES;view.frame=NSMakeRect(x,y,w,h);[parent addSubview:view];
}
@interface DmStickIndicator : NSView
@property int32_t x, y;
@property (copy) NSString *name;
@end
@implementation DmStickIndicator
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityImageRole; }
- (NSString *)accessibilityLabel { return self.name; }
- (id)accessibilityValue { return [NSString stringWithFormat:@"X %.2f, Y %.2f", self.x / 32767.0, self.y / 32767.0]; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty; NSRect circle = NSInsetRect(self.bounds, 8, 8);
    [[NSColor colorWithWhite:1 alpha:.07] setFill]; [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
    [NSColor.separatorColor setStroke]; NSBezierPath *cross = [NSBezierPath bezierPath];
    [cross moveToPoint:NSMakePoint(NSMidX(circle), NSMinY(circle))]; [cross lineToPoint:NSMakePoint(NSMidX(circle), NSMaxY(circle))];
    [cross moveToPoint:NSMakePoint(NSMinX(circle), NSMidY(circle))]; [cross lineToPoint:NSMakePoint(NSMaxX(circle), NSMidY(circle))]; [cross stroke];
    CGFloat radius = (circle.size.width - 12) / 2;
    NSPoint p = NSMakePoint(NSMidX(circle) + radius * self.x / 32767.0, NSMidY(circle) + radius * self.y / 32767.0);
    [NSColor.systemTealColor setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(p.x-5,p.y-5,10,10)] fill];
}
@end
@interface DmButtonIndicator : NSView
@property (copy) NSString *name;
@property BOOL pressed;
@end
@implementation DmButtonIndicator
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityStaticTextRole; }
- (NSString *)accessibilityLabel { return self.name; }
- (id)accessibilityValue { return self.pressed ? @"Pressed" : @"Released"; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty; [(self.pressed ? NSColor.systemTealColor : [NSColor colorWithWhite:1 alpha:.07]) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:7 yRadius:7] fill];
    NSDictionary *attrs = @{NSFontAttributeName:[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName:self.pressed ? NSColor.blackColor : NSColor.labelColor};
    NSSize size = [self.name sizeWithAttributes:attrs];
    [self.name drawAtPoint:NSMakePoint((self.bounds.size.width-size.width)/2,(self.bounds.size.height-size.height)/2) withAttributes:attrs];
}
@end
@interface DmControllerCard : NSView
@property NSUInteger token;
@property NSTextField *title, *activity;
@property NSPopUpButton *player, *layout;
@property NSButton *swap, *swapXY;
@property DmStickIndicator *left, *right;
@property NSMutableArray<DmButtonIndicator *> *buttons;
@property (copy) DmControllersChange change;
- (instancetype)initWithInfo:(DmControllerInfo *)info change:(DmControllersChange)change;
- (void)update:(DmControllerInfo *)info;
@end
@implementation DmControllerCard
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithInfo:(DmControllerInfo *)info change:(DmControllersChange)change {
    if (!(self=[super initWithFrame:NSMakeRect(0,0,600,274)])) return nil;
    self.token=info.token;self.change=change;self.wantsLayer=YES;
    self.layer.cornerRadius=12;self.layer.backgroundColor=[NSColor colorWithWhite:1 alpha:.055].CGColor;
    self.identifier=[NSString stringWithFormat:@"controller-%lu",self.token];
    self.title=text(@"",16,NSColor.labelColor);self.title.font=[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    place(self,self.title,16,14,568,25);
    place(self,text(@"Assigned player",12,NSColor.secondaryLabelColor),16,52,110,24);
    place(self,text(@"Button layout",12,NSColor.secondaryLabelColor),16,86,110,24);
    self.player=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for(NSInteger player=0;player<DM_PLAYERS;player++){[self.player addItemWithTitle:[NSString stringWithFormat:@"Player %ld",player+1]];self.player.lastItem.tag=player;}
    self.player.target=self;self.player.action=@selector(assign:);self.player.identifier=[self.identifier stringByAppendingString:@"-player"];
    place(self,self.player,138,46,260,28);
    self.layout=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray *names=@[@"Use default layout",@"Automatic",@"Xbox / PlayStation positions",@"Nintendo labels"];
    for(NSInteger i=0;i<4;i++){[self.layout addItemWithTitle:names[i]];self.layout.lastItem.tag=i-1;}
    self.layout.target=self;self.layout.action=@selector(layoutChanged:);self.layout.identifier=[self.identifier stringByAppendingString:@"-layout"];
    place(self,self.layout,138,80,260,28);
    self.swap=[NSButton checkboxWithTitle:@"Swap A / B" target:self action:@selector(swapChanged:)];self.swap.identifier=[self.identifier stringByAppendingString:@"-swap"];
    self.swapXY=[NSButton checkboxWithTitle:@"Swap X / Y" target:self action:@selector(swapXYChanged:)];self.swapXY.identifier=[self.identifier stringByAppendingString:@"-swap-xy"];
    place(self,self.swap,16,118,108,24);place(self,self.swapXY,140,118,108,24);
    NSButton *reset=[NSButton buttonWithTitle:@"Use defaults" target:self action:@selector(reset:)];reset.identifier=[self.identifier stringByAppendingString:@"-reset"];
    place(self,reset,264,116,120,28);
    self.left=[DmStickIndicator new];self.left.name=@"Left stick";self.left.identifier=[self.identifier stringByAppendingString:@"-left-stick"];
    self.right=[DmStickIndicator new];self.right.name=@"Right stick";self.right.identifier=[self.identifier stringByAppendingString:@"-right-stick"];
    place(self,self.left,16,156,72,72);place(self,self.right,384,156,72,72);
    self.buttons=[NSMutableArray new];NSArray *buttonNames=@[@"A",@"B",@"X",@"Y",@"LS",@"RS",@"L",@"R",@"ZL",@"ZR",@"+",@"−",@"←",@"↑",@"→",@"↓"];
    for(int bit=0;bit<16;bit++){
        DmButtonIndicator *b=[DmButtonIndicator new];b.name=buttonNames[bit];b.identifier=[self.identifier stringByAppendingFormat:@"-button-%d",bit];
        place(self,b,100+(bit%8)*32,160+(bit/8)*32,29,27);[self.buttons addObject:b];
    }
    self.activity=text(@"",11,NSColor.secondaryLabelColor);self.activity.identifier=[self.identifier stringByAppendingString:@"-activity"];
    place(self,self.activity,16,240,568,20);[self update:info];return self;
}
- (void)assign:(id)sender { (void)sender; self.change(self.token,DmControllerPlayer,self.player.selectedItem.tag); }
- (void)layoutChanged:(id)sender { (void)sender;self.change(self.token,DmControllerLayout,self.layout.selectedItem.tag); }
- (void)swapChanged:(id)sender { (void)sender;self.change(self.token,DmControllerSwapAB,self.swap.state==NSControlStateValueOn); }
- (void)swapXYChanged:(id)sender { (void)sender;self.change(self.token,DmControllerSwapXY,self.swapXY.state==NSControlStateValueOn); }
- (void)reset:(id)sender { (void)sender;self.change(self.token,DmControllerReset,0); }
- (void)update:(DmControllerInfo *)s {
    self.title.stringValue=[NSString stringWithFormat:@"Player %ld  ·  %@",s.player+1,s.name];
    [self.player selectItemWithTag:s.player];[self.layout selectItemWithTag:s.layout];self.swap.state=s.swapAB;self.swapXY.state=s.swapXY;
    NSMutableArray *active=[NSMutableArray new];
    for (NSUInteger bit=0;bit<self.buttons.count;bit++) { DmButtonIndicator *b=self.buttons[bit];b.pressed=(s.buttons>>bit)&1;b.needsDisplay=YES;if(b.pressed)[active addObject:b.name]; }
    self.left.x=s.lx;self.left.y=s.ly;self.right.x=s.rx;self.right.y=s.ry;self.left.needsDisplay=self.right.needsDisplay=YES;
    self.activity.stringValue=active.count ? [@"Pressed: " stringByAppendingString:[active componentsJoinedByString:@"  "]] : @"Press a button to identify this controller";
}
@end

@interface DmControllersDocument : NSView @end
@implementation DmControllersDocument
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect { [[NSColor colorWithWhite:.075 alpha:1] setFill];NSRectFill(rect); }
@end
@interface DmControllersWindow : NSPanel @end
@implementation DmControllersWindow
- (void)cancelOperation:(id)sender { [self performClose:sender]; }
@end
@interface DmControllersPanel ()
@property (weak) NSWindow *parent;
@property (copy) DmControllersSnapshot snapshot;
@property (copy) DmControllersChange change;
@property (copy) void (^capture)(BOOL);
@property NSMutableDictionary<NSNumber *,DmControllerCard *> *cards;
@property NSArray<NSNumber *> *order;
@property NSTextField *status;
@property NSButton *allAB, *allXY;
@property NSTimer *timer;
@property BOOL testing;
@end
@implementation DmControllersPanel
- (instancetype)initWithParent:(NSWindow *)parent snapshot:(DmControllersSnapshot)snapshot change:(DmControllersChange)change capture:(void (^)(BOOL))capture {
    NSPanel *window=[[DmControllersWindow alloc] initWithContentRect:NSMakeRect(0,0,640,650)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    if (!(self=[super initWithWindow:window])) return nil;
    self.parent=parent;self.snapshot=snapshot;self.change=change;self.capture=capture;
    window.title=@"Jamboree · Controller setup";window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    window.backgroundColor=[NSColor colorWithWhite:.075 alpha:1];window.titlebarAppearsTransparent=YES;
    window.releasedWhenClosed=NO;window.hidesOnDeactivate=YES;window.delegate=self;window.collectionBehavior=NSWindowCollectionBehaviorFullScreenAuxiliary;
    [self refresh];__weak DmControllersPanel *weak=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:.1 repeats:YES block:^(NSTimer *t){(void)t;if(weak.window.visible)[weak refresh];}];
    return self;
}
- (void)rebuild:(NSArray<DmControllerInfo *> *)devices {
    self.cards=[NSMutableDictionary new];
    DmControllersDocument *document=[[DmControllersDocument alloc] initWithFrame:NSMakeRect(0,0,640,400)];
    NSTextField *heading=text(@"Ready for the next player",24,NSColor.labelColor);heading.font=[NSFont systemFontOfSize:24 weight:NSFontWeightSemibold];place(document,heading,20,18,600,32);
    self.status=text(@"",12,NSColor.secondaryLabelColor);self.status.identifier=@"controllers-status";place(document,self.status,20,58,600,22);
    NSButton *pair=[NSButton buttonWithTitle:@"Pair a controller…" target:self action:@selector(pair:)];pair.identifier=@"controllers-pair";place(document,pair,20,90,160,30);
    NSButton *done=[NSButton buttonWithTitle:@"Done" target:self action:@selector(done:)];done.identifier=@"controllers-done";done.keyEquivalent=@"\r";place(document,done,192,90,76,30);
    self.allAB=[NSButton checkboxWithTitle:@"Swap A / B on all connected controllers" target:self action:@selector(swapAllAB:)];self.allAB.identifier=@"controllers-swap-all-ab";self.allAB.allowsMixedState=YES;place(document,self.allAB,20,132,600,24);
    self.allXY=[NSButton checkboxWithTitle:@"Swap X / Y on all connected controllers" target:self action:@selector(swapAllXY:)];self.allXY.identifier=@"controllers-swap-all-xy";self.allXY.allowsMixedState=YES;place(document,self.allXY,20,161,600,24);
    CGFloat y=202;__weak DmControllersPanel *weak=self;
    for(DmControllerInfo *info in devices){
        DmControllerCard *card=[[DmControllerCard alloc] initWithInfo:info change:^(NSUInteger token,DmControllerSetting key,NSInteger value){weak.change(token,key,value);[weak refresh];}];
        self.cards[@(info.token)]=card;place(document,card,20,y,600,274);y+=288;
    }
    if(!devices.count){NSTextField *empty=text(@"No controller detected\n\nTurn on your controller and pair it in macOS Bluetooth settings, or connect it by USB. Connected controllers appear here automatically.",14,NSColor.secondaryLabelColor);empty.identifier=@"controllers-empty";place(document,empty,20,y,600,96);y+=110;}
    place(document,text(@"Keyboard also controls Player 1. Button layouts are saved per player. Moving onto another player's slot swaps the two controllers.",11,NSColor.secondaryLabelColor),20,y+8,600,34);
    place(document,text(@"Input testing stays in this window. Release buttons and sticks after closing to resume game input. Then select a multiplayer mode in the game.",11,NSColor.secondaryLabelColor),20,y+50,600,44);
    document.frame=NSMakeRect(0,0,640,y+110);
    NSRect screen=(self.parent.screen ?: NSScreen.mainScreen).visibleFrame;CGFloat height=MIN(document.frame.size.height,MAX(300,screen.size.height-80));
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,640,height)];scroll.drawsBackground=NO;scroll.hasVerticalScroller=YES;
    scroll.autohidesScrollers=YES;scroll.scrollerStyle=NSScrollerStyleOverlay;scroll.documentView=document;self.window.contentView=scroll;
    [self.window setContentSize:NSMakeSize(640,height)];
    NSRect f=self.window.frame;[self.window setFrameOrigin:NSMakePoint(MAX(screen.origin.x,MIN(f.origin.x,NSMaxX(screen)-f.size.width)),MAX(screen.origin.y,MIN(f.origin.y,NSMaxY(screen)-f.size.height)))];
}
- (void)refresh {
    NSArray<DmControllerInfo *> *devices=self.snapshot();NSMutableArray *order=[NSMutableArray new];for(DmControllerInfo *d in devices)[order addObject:@(d.token)];
    if(![self.order isEqualToArray:order]){self.order=order;[self rebuild:devices];}
    self.status.stringValue=devices.count>1 ? [NSString stringWithFormat:@"%lu controllers connected · separate players ready",devices.count] : devices.count ? @"1 controller connected · connect another for local multiplayer" : @"Connect your controllers to get started";
    NSUInteger ab=0,xy=0;for(DmControllerInfo *d in devices){ab+=d.swapAB;xy+=d.swapXY;}
    self.allAB.enabled=self.allXY.enabled=devices.count>0;
    self.allAB.state=!ab ? NSControlStateValueOff:ab==devices.count ? NSControlStateValueOn:NSControlStateValueMixed;
    self.allXY.state=!xy ? NSControlStateValueOff:xy==devices.count ? NSControlStateValueOn:NSControlStateValueMixed;
    for(DmControllerInfo *d in devices)[self.cards[@(d.token)] update:d];
}
- (void)showPanel {
    [self refresh];if(!self.testing){self.testing=YES;self.capture(YES);}
    if(!self.window.visible){NSRect p=self.parent.frame,f=self.window.frame,s=(self.parent.screen ?: NSScreen.mainScreen).visibleFrame;
        [self.window setFrameOrigin:NSMakePoint(MAX(s.origin.x,MIN(NSMidX(p)-f.size.width/2,NSMaxX(s)-f.size.width)),MAX(s.origin.y,MIN(NSMidY(p)-f.size.height/2,NSMaxY(s)-f.size.height)))];
        [self.parent addChildWindow:self.window ordered:NSWindowAbove];}
    [self.window makeKeyAndOrderFront:nil];
}
- (void)windowWillClose:(NSNotification *)n {
    (void)n;if(self.testing){self.testing=NO;self.capture(NO);}[self.parent removeChildWindow:self.window];if(NSApp.active)[self.parent makeKeyAndOrderFront:nil];
}
- (void)done:(id)sender {(void)sender;[self.window performClose:nil];}
- (void)swapAllAB:(id)sender { (void)sender;NSArray *devices=self.snapshot();BOOL value=NO;for(DmControllerInfo *d in devices)if(!d.swapAB)value=YES;for(DmControllerInfo *d in devices)self.change(d.token,DmControllerSwapAB,value);[self refresh]; }
- (void)swapAllXY:(id)sender { (void)sender;NSArray *devices=self.snapshot();BOOL value=NO;for(DmControllerInfo *d in devices)if(!d.swapXY)value=YES;for(DmControllerInfo *d in devices)self.change(d.token,DmControllerSwapXY,value);[self refresh]; }
- (void)pair:(id)sender {
    (void)sender;NSURL *url=[NSURL URLWithString:@"x-apple.systempreferences:com.apple.BluetoothSettings"];
    if(![NSWorkspace.sharedWorkspace openURL:url])[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:@"/System/Applications/System Settings.app"]];
}
@end
