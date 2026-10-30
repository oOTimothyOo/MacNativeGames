#import <Cocoa/Cocoa.h>
#import "NPModel.h"

// Synthetic previews use a separate home and never launch real games.
@interface NPPreviewStore : NPStore @end
FOUNDATION_EXPORT NSArray<NSDictionary *> *NPPreviewGames(void);

@interface NPApp : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate>
@property NPStore *store;
@property BOOL preview, test;
@property NSString *snapshotPath;
@end
