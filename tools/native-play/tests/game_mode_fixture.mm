// A synthetic game: a full-screen Metal window that closes itself. No game code or content.
// test.py launches it through Native Play's real launch path, then reads macOS's own
// verdict on Game Mode from the system log.
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

static const uint64_t RunSeconds = 5;

int main() {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = @"Native Play Game Mode check (closes itself)";
        window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;

        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = MTLCreateSystemDefaultDevice();
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        NSView *view = window.contentView;
        view.wantsLayer = YES;
        view.layer = layer;
        id<MTLCommandQueue> queue = [layer.device newCommandQueue];

        [window center];
        [window makeKeyAndOrderFront:nil];
        [application activate];
        [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
            layer.drawableSize = CGSizeMake(NSWidth(view.bounds) * window.backingScaleFactor, NSHeight(view.bounds) * window.backingScaleFactor);
            id<CAMetalDrawable> drawable = [layer nextDrawable];
            if (!drawable) {
                return;
            }
            MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture = drawable.texture;
            pass.colorAttachments[0].loadAction = MTLLoadActionClear;
            pass.colorAttachments[0].storeAction = MTLStoreActionStore;
            pass.colorAttachments[0].clearColor = MTLClearColorMake(.07, .09, .11, 1);
            id<MTLCommandBuffer> commands = [queue commandBuffer];
            [[commands renderCommandEncoderWithDescriptor:pass] endEncoding];
            [commands presentDrawable:drawable];
            [commands commit];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 500), dispatch_get_main_queue(), ^{
            [window toggleFullScreen:nil];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * RunSeconds), dispatch_get_main_queue(), ^{
            exit(0);
        });
        [application run];
    }
    return 0;
}
