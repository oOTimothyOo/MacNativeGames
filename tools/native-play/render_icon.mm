// Build tool: draws the app icon, from authored shapes only, to a 1024 px PNG.
#import <Cocoa/Cocoa.h>
#import "NPTheme.h"

static void DrawIcon() {
    [NPBackgroundColor() setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, 1024, 1024) xRadius:220 yRadius:220] fill];
    [NPMintColor() setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(188, 215, 285, 594) xRadius:140 yRadius:140] fill];
    [NPIconAccentColor() setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(551, 215, 285, 594) xRadius:140 yRadius:140] fill];
    [NPBackgroundColor() setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(270, 537, 120, 120)] fill];
    [NPMintColor() setFill];
    for (NSUInteger i = 0; i < 4; i++) {
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(625 + (i % 2) * 54, 340 + (i / 2) * 54, 32, 32)] fill];
    }
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) {
            fputs("usage: np-render-icon <output.png>\n", stderr);
            return 2;
        }
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                           pixelsWide:1024
                                                                           pixelsHigh:1024
                                                                        bitsPerSample:8
                                                                      samplesPerPixel:4
                                                                             hasAlpha:YES
                                                                             isPlanar:NO
                                                                       colorSpaceName:NSDeviceRGBColorSpace
                                                                          bytesPerRow:0
                                                                         bitsPerPixel:0];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        DrawIcon();
        NSGraphicsContext.currentContext = nil;
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:@(argv[1]) atomically:YES] ? 0 : 1;
    }
}
