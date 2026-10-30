// Jamboree's local controller setup. Snapshots and actions stay on the AppKit thread.
#pragma once
#import <Cocoa/Cocoa.h>
#include "dm_input.h"

@interface DmControllerInfo : NSObject
@property NSUInteger token;
@property (copy) NSString *name;
@property NSInteger player, layout;
@property BOOL swapAB, swapXY;
@property uint64_t buttons;
@property int32_t lx, ly, rx, ry;
@end
typedef NS_ENUM(NSInteger, DmControllerSetting) {
    DmControllerPlayer, DmControllerLayout, DmControllerSwapAB, DmControllerReset, DmControllerSwapXY
};
typedef NSArray<DmControllerInfo *> *(^DmControllersSnapshot)(void);
typedef void (^DmControllersChange)(NSUInteger token, DmControllerSetting setting, NSInteger value);
@interface DmControllersPanel : NSWindowController <NSWindowDelegate>
- (instancetype)initWithParent:(NSWindow *)parent snapshot:(DmControllersSnapshot)snapshot
    change:(DmControllersChange)change capture:(void (^)(BOOL testing))capture;
- (void)showPanel;
- (void)refresh;
@end
