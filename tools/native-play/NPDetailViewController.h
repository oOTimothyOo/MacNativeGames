#import <Cocoa/Cocoa.h>
#import "NPPages.h"

NS_ASSUME_NONNULL_BEGIN

// The page's title, the visible page, and a status line that shows only when there is news.
@interface NPDetailViewController : NSViewController
@property (readonly, nullable) NPPageViewController *page;
- (instancetype)initWithLibrary:(NPLibraryController *)library pages:(NSArray<NPPageViewController *> *)pages NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (void)showPageAtIndex:(NSUInteger)index;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
