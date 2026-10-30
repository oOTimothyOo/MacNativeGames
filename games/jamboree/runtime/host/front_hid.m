// Only the observed Ultimate 2C Bluetooth gamepad is matched: no keyboard,
// mouse, exclusive capture, output reports, pairing or firmware operations.
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>
#include "dm.h"
#include "front_hid.h"

static IOHIDManagerRef manager;
static struct { IOHIDDeviceRef device; hid_8bitdo state; } pads[DM_PLAYERS];
static front_hid_callbacks cb;

int front_hid_count(void) { int n = 0; for (int i = 0; i < DM_PLAYERS; i++) n += pads[i].device != NULL; return n; }
void front_hid_refresh(void) {
    for (int i = 0; i < DM_PLAYERS; i++) if (pads[i].device) cb.input(pads[i].device, &pads[i].state);
}
static void value_changed(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    (void)context; (void)sender; if (result != kIOReturnSuccess) return;
    IOHIDElementRef e = IOHIDValueGetElement(value);
    IOHIDDeviceRef device = IOHIDElementGetDevice(e);
    for (int i = 0; i < DM_PLAYERS; i++) if (pads[i].device == device) {
        hid_8bitdo_value(&pads[i].state, IOHIDElementGetUsagePage(e), IOHIDElementGetUsage(e),
            IOHIDValueGetIntegerValue(value), IOHIDElementGetLogicalMin(e), IOHIDElementGetLogicalMax(e));
        cb.input(device, &pads[i].state); break;
    }
}
static void connected(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    (void)context; (void)sender; if (result != kIOReturnSuccess) return;
    int slot = -1;
    for (int i = 0; i < DM_PLAYERS; i++) {
        if (pads[i].device == device) return;
        if (slot < 0 && !pads[i].device) slot = i;
    }
    if (slot < 0) return;
    pads[slot].device = (IOHIDDeviceRef)CFRetain(device);
    pads[slot].state = (hid_8bitdo){0};
    cb.connected(device, "8BitDo Ultimate 2C Wireless (Bluetooth HID)");
    cb.input(device, &pads[slot].state);
}
static void removed(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    (void)context; (void)sender; (void)result;
    for (int i = 0; i < DM_PLAYERS; i++) if (pads[i].device == device) {
        // Mark absent before notifying: the front end can inspect the live count.
        IOHIDDeviceRef keep = pads[i].device; pads[i].device = NULL;
        cb.removed(device); CFRelease(keep); pads[i].state = (hid_8bitdo){0}; break;
    }
}
void front_hid_start(front_hid_callbacks callbacks) {
    if (manager) return;
    cb = callbacks;
    manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)@{@(kIOHIDVendorIDKey): @0x2dc8,
        @(kIOHIDProductIDKey): @0x301b, @(kIOHIDPrimaryUsagePageKey): @1, @(kIOHIDPrimaryUsageKey): @5});
    IOHIDManagerRegisterDeviceMatchingCallback(manager, connected, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, removed, NULL);
    IOHIDManagerRegisterInputValueCallback(manager, value_changed, NULL);
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    IOReturn result = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    if (result != kIOReturnSuccess) {
        LOG("[RED] Ultimate 2C HID input could not open: %#x", result);
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFRelease(manager); manager = NULL; return;
    }
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    for (id item in (__bridge NSSet *)devices) connected(NULL, kIOReturnSuccess, NULL, (__bridge IOHIDDeviceRef)item);
    if (devices) CFRelease(devices);
}
