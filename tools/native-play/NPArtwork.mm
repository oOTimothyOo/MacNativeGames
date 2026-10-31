#import "NPArtwork.h"
#import "NPFoundation.h"
#import "NPTheme.h"
#import <AVFoundation/AVFoundation.h>
#include <algorithm>
#include <cmath>
#include <vector>

static const int SampledFrames = 16;
static const CGFloat MaximumWidth = 1920;
static const CGFloat JPEGQuality = .9;

double NPArtworkScore(CGImageRef image) {
    const size_t width = 32, height = 18;
    std::vector<uint8_t> pixels(width * height * 4);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels.data(), width, height, 8, width * 4, space, kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    if (!context) {
        return 0;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);

    double colorfulness = 0, brightness = 0;
    for (size_t i = 0; i < pixels.size(); i += 4) {
        auto [low, high] = std::minmax({pixels[i], pixels[i + 1], pixels[i + 2]});
        colorfulness += (high - low) / 255.0;
        brightness += (pixels[i] + pixels[i + 1] + pixels[i + 2]) / (3 * 255.0);
    }
    double count = width * height;
    colorfulness /= count;
    brightness /= count;
    // Fades and flashes are the frames to avoid; among the rest, color wins.
    if (brightness < .2 || brightness > .85) {
        return colorfulness * .1;
    }
    return colorfulness;
}

// The longest movie is the one most likely to show the game itself.
static NSURL *LargestMovie(NPGame *game) {
    NSURL *contents = NPChild([NSURL fileURLWithPath:game.path], @"Contents/Resources/game/RomFS");
    NSDirectoryEnumerator *files = [NSFileManager.defaultManager enumeratorAtURL:contents
                                                      includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey]
                                                                         options:0
                                                                    errorHandler:nil];
    NSURL *largest = nil;
    NSNumber *largestSize = @0;
    for (NSURL *url in files) {
        NSNumber *regular = nil, *size = nil;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        if (regular.boolValue && [url.pathExtension.lowercaseString isEqual:@"mp4"] && [size compare:largestSize] == NSOrderedDescending) {
            largest = url;
            largestSize = size;
        }
    }
    return largest;
}

// Blocks while it samples the movie. Returns a retained image, or NULL.
static CGImageRef CopyBestFrame(NSURL *movie) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:movie options:nil];
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
        dispatch_semaphore_signal(loaded);
    }];
    dispatch_semaphore_wait(loaded, DISPATCH_TIME_FOREVER);
    double seconds = CMTimeGetSeconds(asset.duration);
    if (!std::isfinite(seconds) || seconds <= 0) {
        return NULL;
    }

    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(MaximumWidth, 0);
    generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(1, 600);
    generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(1, 600);

    NSMutableArray<NSValue *> *times = [NSMutableArray new];
    for (int i = 0; i < SampledFrames; i++) {
        double position = seconds * (.1 + .8 * i / (SampledFrames - 1));
        [times addObject:[NSValue valueWithCMTime:CMTimeMakeWithSeconds(position, 600)]];
    }

    dispatch_semaphore_t sampled = dispatch_semaphore_create(0);
    __block CGImageRef best = NULL;
    __block double bestScore = -1;
    __block int remaining = SampledFrames;
    [generator generateCGImagesAsynchronouslyForTimes:times completionHandler:^(CMTime requested, CGImageRef image, CMTime actual, AVAssetImageGeneratorResult result, NSError *error) {
        if (result == AVAssetImageGeneratorSucceeded && image) {
            double score = NPArtworkScore(image);
            if (score > bestScore) {
                bestScore = score;
                CGImageRelease(best);
                best = CGImageRetain(image);
            }
        }
        if (--remaining == 0) {
            dispatch_semaphore_signal(sampled);
        }
    }];
    dispatch_semaphore_wait(sampled, DISPATCH_TIME_FOREVER);
    return best;
}

static BOOL WriteArtwork(CGImageRef image, NSURL *url, NSError **error) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSData *jpeg = [bitmap representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @(JPEGQuality)}];
    NSURL *directory = url.URLByDeletingLastPathComponent;
    if (!jpeg || !NPPathHasNoLinks(directory)) {
        return NPFail(error, @"Could not save this artwork.");
    }
    if (!NPCreatePrivateDirectory(directory, error) || ![jpeg writeToURL:url options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:url.path error:error];
}

NSImage *NPPlaceholderArtwork(NPGame *game) {
    const NSInteger width = 1280, height = 720;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:width
                                                                       pixelsHigh:height
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSDeviceRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    NSUInteger digest = 0;
    for (NSUInteger i = 0; i < game.titleID.length; i++) {
        digest += [game.titleID characterAtIndex:i];
    }
    NSArray<NSColor *> *bases = @[
        [NSColor colorWithSRGBRed:.13 green:.25 blue:.33 alpha:1],
        [NSColor colorWithSRGBRed:.25 green:.17 blue:.29 alpha:1],
        [NSColor colorWithSRGBRed:.14 green:.27 blue:.24 alpha:1],
    ];
    NSColor *base = bases[digest % bases.count];
    [[[NSGradient alloc] initWithStartingColor:base endingColor:[base blendedColorWithFraction:.55 ofColor:NPBackgroundColor()]] drawInRect:NSMakeRect(0, 0, width, height) angle:-60];
    [[NPMintColor() colorWithAlphaComponent:.09] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(width * .52, -height * .25, height * 1.3, height * 1.3)] fill];
    NSGraphicsContext.currentContext = nil;
    return [[NSImage alloc] initWithCGImage:bitmap.CGImage size:NSMakeSize(width, height)];
}

@interface NPArtworkLibrary ()
@property (readonly) NPStore *store;
@property (readonly) dispatch_queue_t queue;
// Main-queue state. Absent means not looked for yet.
@property (readonly) NSMutableDictionary<NSString *, NSImage *> *images;
@property (readonly) NSMutableSet<NSString *> *searched;
@end

@implementation NPArtworkLibrary

- (instancetype)initWithStore:(NPStore *)store {
    if ((self = [super init])) {
        _store = store;
        _queue = dispatch_queue_create("org.macnativegames.native-play.artwork", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        _images = [NSMutableDictionary new];
        _searched = [NSMutableSet new];
        _changed = ^{};
    }
    return self;
}

- (NSURL *)cacheURLForGame:(NPGame *)game {
    return NPChild(self.store.root, [NSString stringWithFormat:@"Artwork/%@.jpg", game.key]);
}

- (NSImage *)imageForGame:(NPGame *)game {
    NSImage *known = self.images[game.key];
    if (known) {
        return known;
    }
    NSImage *placeholder = NPPlaceholderArtwork(game);
    self.images[game.key] = placeholder;
    [self findArtworkForGame:game];
    return placeholder;
}

- (void)findArtworkForGame:(NPGame *)game {
    if ([self.searched containsObject:game.key]) {
        return;
    }
    [self.searched addObject:game.key];
    NSURL *cache = [self cacheURLForGame:game];
    dispatch_async(self.queue, ^{
        NSImage *image = nil;
        if (NPPathHasNoLinks(cache)) {
            image = [[NSImage alloc] initWithContentsOfURL:cache];
        }
        if (!image) {
            NSURL *movie = LargestMovie(game);
            CGImageRef frame = movie ? CopyBestFrame(movie) : NULL;
            if (frame) {
                if (WriteArtwork(frame, cache, nil)) {
                    image = [[NSImage alloc] initWithContentsOfURL:cache];
                }
                CGImageRelease(frame);
            }
        }
        if (image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.images[game.key] = image;
                self.changed();
            });
        }
    });
}

- (BOOL)setImageAtURL:(NSURL *)url forGame:(NPGame *)game error:(NSError **)error {
    NSImage *chosen = [[NSImage alloc] initWithContentsOfURL:url];
    NSImageRep *rep = chosen.representations.firstObject;
    if (!rep || rep.pixelsWide <= 0 || rep.pixelsHigh <= 0) {
        return NPFail(error, @"That file is not a picture Native Play can open.");
    }
    CGFloat scale = MIN(1, MaximumWidth / (CGFloat)rep.pixelsWide);
    NSInteger width = MAX(1, (NSInteger)(rep.pixelsWide * scale)), height = MAX(1, (NSInteger)(rep.pixelsHigh * scale));
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:width
                                                                       pixelsHigh:height
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSDeviceRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [chosen drawInRect:NSMakeRect(0, 0, width, height)];
    NSGraphicsContext.currentContext = nil;
    NSURL *cache = [self cacheURLForGame:game];
    if (!WriteArtwork(bitmap.CGImage, cache, error)) {
        return NO;
    }
    self.images[game.key] = [[NSImage alloc] initWithContentsOfURL:cache];
    [self.searched addObject:game.key];
    self.changed();
    return YES;
}

- (void)resetGame:(NPGame *)game {
    NSURL *cache = [self cacheURLForGame:game];
    if (NPPathHasNoLinks(cache)) {
        [NSFileManager.defaultManager removeItemAtURL:cache error:nil];
    }
    self.images[game.key] = NPPlaceholderArtwork(game);
    [self.searched removeObject:game.key];
    [self findArtworkForGame:game];
    self.changed();
}

@end

@implementation NPArtworkView

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.contentsGravity = kCAGravityResizeAspectFill;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    self.layer.contents = self.image;
    self.layer.cornerRadius = self.cornerRadius;
}

- (void)setImage:(NSImage *)image {
    _image = image;
    self.needsDisplay = YES;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.needsDisplay = YES;
}

@end
