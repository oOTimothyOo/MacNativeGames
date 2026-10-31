// Game artwork. It comes from the person's own installed game or a picture they choose,
// and stays in Native Play's private support folder. None is downloaded or ever enters
// this repository or a built bundle.
#import <Cocoa/Cocoa.h>
#import "NPStore.h"

NS_ASSUME_NONNULL_BEGIN

// How good a still looks as artwork: colorful and evenly lit scores high.
FOUNDATION_EXPORT double NPArtworkScore(CGImageRef image);
// A quiet gradient for a game with no artwork of its own; its title is shown beside it.
FOUNDATION_EXPORT NSImage *NPPlaceholderArtwork(NPGame *game);

@interface NPArtworkLibrary : NSObject
// Called on the main queue when an image becomes available or changes.
@property (copy) void (^changed)(void);
- (instancetype)initWithStore:(NPStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// Never blocks: until artwork is ready this is the placeholder, and finding it starts.
- (NSImage *)imageForGame:(NPGame *)game;
- (BOOL)setImageAtURL:(NSURL *)url forGame:(NPGame *)game error:(NSError **)error;
// Forgets a chosen picture and goes back to the game's own artwork.
- (void)resetGame:(NPGame *)game;
@end

// Fills its bounds with an image, cropping rather than distorting.
@interface NPArtworkView : NSView
@property (nonatomic, nullable) NSImage *image;
@property (nonatomic) CGFloat cornerRadius;
@end

NS_ASSUME_NONNULL_END
