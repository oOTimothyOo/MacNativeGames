// AppKit acceptance tests using two synthetic controllers; no game data or captures.
#import "../runtime/host/front_controllers.h"
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static NSMutableArray<DmControllerInfo *> *devices;
static int checks,failures,captures,opens;
static BOOL testing;
static NSUInteger last_token;
static DmControllerSetting last_setting;
static NSInteger last_value;
#define CHECK(c,s) do{checks++;if(!(c)){failures++;fprintf(stderr,"FAIL: %s\n",s);}}while(0)
static NSView *find(NSView *v,NSString *identifier){if([v.identifier isEqualToString:identifier])return v;for(NSView *child in v.subviews){NSView *r=find(child,identifier);if(r)return r;}return nil;}
static NSString *identifier(NSUInteger token,NSString *suffix){return [NSString stringWithFormat:@"controller-%lu-%@",token,suffix];}
static DmControllerInfo *device(NSUInteger token,NSInteger player,uint64_t buttons){DmControllerInfo *d=[DmControllerInfo new];d.token=token;d.player=player;d.name=@"8BitDo Ultimate 2C";d.layout=-1;d.buttons=buttons;return d;}
static void change(NSUInteger token,DmControllerSetting key,NSInteger value){
    last_token=token;last_setting=key;last_value=value;
    for(DmControllerInfo *d in devices)if(d.token==token){switch(key){
        case DmControllerPlayer:for(DmControllerInfo *other in devices)if(other!=d&&other.player==value)other.player=d.player;d.player=value;break;
        case DmControllerLayout:d.layout=value;break;
        case DmControllerSwapAB:d.swapAB=value;break;
        case DmControllerSwapXY:d.swapXY=value;break;
        case DmControllerReset:d.layout=-1;d.swapAB=d.swapXY=NO;break;
    }break;}
}
static BOOL english(NSView *v){if([v isKindOfClass:NSTextField.class]){NSString *s=((NSTextField *)v).stringValue;for(NSUInteger i=0;i<s.length;i++){unichar c=[s characterAtIndex:i];if(c>=0x3400&&c<=0x9fff)return NO;}}for(NSView *child in v.subviews)if(!english(child))return NO;return YES;}
static BOOL hitReachable(NSControl *control){
    if(!control)return NO;[control scrollRectToVisible:control.bounds];[control.window.contentView layoutSubtreeIfNeeded];
    NSPoint point=NSMakePoint(8,NSMidY(control.bounds));NSView *root=control.window.contentView;
    NSView *hit=[root hitTest:[root.superview convertPoint:point fromView:control]];
    return hit==control||[hit isDescendantOf:control];
}

int main(int argc,const char **argv){@autoreleasepool{
    BOOL test=argc>1&&!strcmp(argv[1],"--self-test");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];
    NSWindow *parent=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,800) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    parent.title=@"Controller setup preview · synthetic devices";[parent center];
    DmControllerInfo *first=device(1,0,DM_BTN_A),*second=device(2,1,DM_BTN_B);first.lx=-16000;second.lx=16000;
    devices=[NSMutableArray arrayWithArray:@[first,second]];
    DmControllersPanel *panel=[[DmControllersPanel alloc] initWithParent:parent snapshot:^{return [devices sortedArrayUsingComparator:^NSComparisonResult(DmControllerInfo *a,DmControllerInfo *b){return a.player<b.player?NSOrderedAscending:a.player>b.player?NSOrderedDescending:NSOrderedSame;}];}
        change:^(NSUInteger token,DmControllerSetting key,NSInteger value){change(token,key,value);}
        capture:^(BOOL value){testing=value;captures++;if(value)opens++;}];
    [parent makeKeyAndOrderFront:nil];[panel showPanel];[panel.window.contentView layoutSubtreeIfNeeded];
    if(test){
        [NSApp activateIgnoringOtherApps:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        CHECK(NSApp.running&&NSApp.active&&panel.window.keyWindow,"mouse acceptance runs inside an active AppKit event loop");
        CHECK(testing&&captures==1&&opens==1,"opening setup captures game input once");
        [panel showPanel];CHECK(captures==1,"reopening an already visible panel does not nest capture");
        CHECK(find(panel.window.contentView,@"controller-1")&&find(panel.window.contentView,@"controller-2"),"two same-model controllers have distinct cards");
        CHECK(english(panel.window.contentView),"controller setup contains English text only");
        NSView *swapHit=find(panel.window.contentView,identifier(1,@"swap"));
        NSPoint swapPoint=[panel.window.contentView.superview convertPoint:NSMakePoint(NSMidX(swapHit.bounds),NSMidY(swapHit.bounds)) fromView:swapHit];
        NSView *hit=[panel.window.contentView hitTest:swapPoint];
        CHECK(hit==swapHit||[hit isDescendantOf:swapHit],"mouse hit-testing reaches the A/B checkbox through its parent rows");
        if(hit!=swapHit&&![hit isDescendantOf:swapHit])for(NSView *v=swapHit;v;v=v.superview)fprintf(stderr,"hit path %s frame %.0f %.0f %.0f %.0f\n",NSStringFromClass(v.class).UTF8String,v.frame.origin.x,v.frame.origin.y,v.frame.size.width,v.frame.size.height);
        CHECK(NSContainsRect(NSInsetRect((parent.screen?:NSScreen.mainScreen).visibleFrame,-1,-1),panel.window.frame),"setup fits the display work area");
        NSView *a=find(panel.window.contentView,identifier(1,@"button-0")),*b=find(panel.window.contentView,identifier(2,@"button-0"));
        CHECK([[a valueForKey:@"pressed"] boolValue]&&![[b valueForKey:@"pressed"] boolValue],"A input highlights only its own controller");
        CHECK([[find(panel.window.contentView,identifier(2,@"button-1")) valueForKey:@"pressed"] boolValue],"the other controller independently highlights B");
        CHECK([[find(panel.window.contentView,identifier(1,@"left-stick")) valueForKey:@"x"] intValue]==-16000&&[[find(panel.window.contentView,identifier(2,@"left-stick")) valueForKey:@"x"] intValue]==16000,"stick previews remain independent");
        NSPopUpButton *player=(id)find(panel.window.contentView,identifier(1,@"player"));[player selectItemWithTag:1];[NSApp sendAction:player.action to:player.target from:player];
        CHECK(last_token==1&&last_setting==DmControllerPlayer&&last_value==1&&first.player==1&&second.player==0,"player assignment addresses the correct device and swaps occupied slots");
        CHECK(((NSPopUpButton *)find(panel.window.contentView,identifier(2,@"player"))).selectedItem.tag==0,"the swapped controller's player control refreshes");
        NSPopUpButton *layout=(id)find(panel.window.contentView,identifier(2,@"layout"));[layout selectItemWithTag:2];[NSApp sendAction:layout.action to:layout.target from:layout];
        CHECK(last_token==2&&last_setting==DmControllerLayout&&last_value==2&&first.layout==-1,"layout selection is isolated to its target");
        NSButton *swap=(id)find(panel.window.contentView,identifier(1,@"swap"));[swap performClick:nil];
        CHECK(last_token==1&&first.swapAB&&!second.swapAB,"A/B swap targets one controller");
        [(NSButton *)find(panel.window.contentView,identifier(1,@"swap-xy")) performClick:nil];CHECK(first.swapXY&&!second.swapXY,"X/Y swap targets one controller");
        [(NSButton *)find(panel.window.contentView,identifier(1,@"reset")) performClick:nil];CHECK(first.layout==-1&&!first.swapAB&&!first.swapXY,"reset restores inherited defaults");
        [(NSButton *)find(panel.window.contentView,@"controllers-swap-all-ab") performClick:nil];CHECK(first.swapAB&&second.swapAB,"bulk A/B swap updates both connected controllers");
        [(NSButton *)find(panel.window.contentView,@"controllers-swap-all-xy") performClick:nil];CHECK(first.swapXY&&second.swapXY,"bulk X/Y swap updates both connected controllers");
        NSButton *allAB=(id)find(panel.window.contentView,@"controllers-swap-all-ab");
        CHECK(hitReachable(allAB),"the bulk A/B checkbox has a reachable click target");[allAB performClick:nil];
        CHECK(!first.swapAB&&!second.swapAB,"the bulk A/B action toggles both controllers off");
        NSButton *oneAB=(id)find(panel.window.contentView,identifier(1,@"swap"));
        CHECK(hitReachable(oneAB),"the first controller's A/B checkbox has a reachable click target");[oneAB performClick:nil];
        CHECK(first.swapAB&&!second.swapAB,"the first controller's A/B action remains independent");
        CHECK(((NSButton *)find(panel.window.contentView,@"controllers-swap-all-ab")).state==NSControlStateValueMixed,"mixed per-player settings are reflected in the bulk switch");
        NSButton *twoXY=(id)find(panel.window.contentView,identifier(2,@"swap-xy"));
        CHECK(hitReachable(twoXY),"the second controller's X/Y checkbox is reachable after scrolling");[twoXY performClick:nil];
        CHECK(first.swapXY&&!second.swapXY,"the second controller's X/Y action remains independent");
        [devices removeObject:second];[panel refresh];CHECK(!find(panel.window.contentView,@"controller-2")&&find(panel.window.contentView,@"controller-1"),"disconnect removes only the absent controller");
        [devices addObject:device(3,0,0)];[panel refresh];CHECK(find(panel.window.contentView,@"controller-3")&&find(panel.window.contentView,@"controller-1"),"reconnect creates a separate live card");
        [devices removeAllObjects];[panel refresh];CHECK(find(panel.window.contentView,@"controllers-empty")!=nil,"empty state explains how to connect");
        [(NSButton *)find(panel.window.contentView,@"controllers-done") performClick:nil];CHECK(!testing&&captures==2&&!panel.window.visible,"Done closes setup and releases input capture once");
        [panel showPanel];CHECK(testing&&opens==2,"setup reopens after all controllers disconnect");[panel.window performClose:nil];CHECK(!testing&&captures==4,"window close also releases capture");
        printf("controller UI: %d checks, %d failed\n",checks,failures);exit(failures?1:0);
        });[NSApp run];return 0;
    }
    if(argc>2&&!strcmp(argv[1],"--snapshot")){
        NSView *v=((NSScrollView *)panel.window.contentView).documentView;[v layoutSubtreeIfNeeded];
        NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)v.bounds.size.width pixelsHigh:(NSInteger)v.bounds.size.height
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        if(!rep){fprintf(stderr,"UI bitmap unavailable: %.0fx%.0f\n",v.bounds.size.width,v.bounds.size.height);return 2;}
        [panel.window.effectiveAppearance performAsCurrentDrawingAppearance:^{[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];}];
        NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if(!png){fprintf(stderr,"UI PNG encoding unavailable\n");return 3;}
        FILE *out=fopen(argv[2],"wb");if(!out){perror("UI snapshot");return 1;}
        BOOL saved=fwrite(png.bytes,1,png.length,out)==png.length;int closed=fclose(out);return saved&&!closed?0:1;
    }
    [NSApp activateIgnoringOtherApps:YES];[NSApp run];return 0;
}}
