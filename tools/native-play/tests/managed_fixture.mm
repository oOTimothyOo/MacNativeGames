// Actual Launch Services + sandbox-exec integration, with synthetic inputs only.
#import <Cocoa/Cocoa.h>
#define main RestrictionChecks
#include "fixture.c"
#undef main

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *identifier = NSRunningApplication.currentApplication.bundleIdentifier;
        fprintf(stderr,"Synthetic fixture: running identity=%s; main bundle=%s\n",identifier.UTF8String?:"missing",NSBundle.mainBundle.bundleIdentifier.UTF8String?:"missing");
        if (![identifier isEqual:@"org.macnativegames.fixture.launchservices"]) return 70;
        if (!getenv("DM_NATIVE_PLAY_POLICY")) return 71;
        int result = RestrictionChecks();
        fprintf(stderr,"Synthetic fixture restriction result=%d\n",result);
        if (result) return result;
        NSString *receipt = [[@(getenv("DM_NATIVE_PLAY_POLICY")) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"fixture-passed"];
        FILE *file=fopen(receipt.fileSystemRepresentation,"wb");
        if(!file){fprintf(stderr,"Synthetic success receipt failed: %d\n",errno);return 72;}
        int wrote=fputs("restricted-bundled-fixture-passed",file),closed=fclose(file);
        return wrote>=0&&closed==0 ? 0 : 72;
    }
}
