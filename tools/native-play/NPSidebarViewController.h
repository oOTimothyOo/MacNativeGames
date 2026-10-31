#import <Cocoa/Cocoa.h>
#import "NPPages.h"

NS_ASSUME_NONNULL_BEGIN

@interface NPSidebarViewController : NSViewController
// Called when the person picks a section.
@property (copy) void (^sectionChanged)(NPSection section);
@property (nonatomic) NPSection section;
@end

NS_ASSUME_NONNULL_END
