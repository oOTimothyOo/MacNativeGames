// Synthetic runtime for the packaging test; never reads game inputs.
#import <Foundation/Foundation.h>
#include <cstdlib>

int main(int argc, const char **argv) {
    @autoreleasepool {
        const char *state = getenv("DM_STATE_DIR");
        if (!state || argc != 2) return 1;
        NSDictionary *report = @{
            @"bundle_id": NSBundle.mainBundle.bundleIdentifier ?: @"",
            @"bundle_path": NSBundle.mainBundle.bundlePath,
            @"save": @(getenv("DM_SAVE") ?: ""),
            @"temporary": @(getenv("DM_TEMP") ?: ""),
            @"patched": @(argv[1]),
            @"language": @(getenv("DM_LANG") ?: "")
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:0 error:NULL];
        NSString *path = [@(state) stringByAppendingPathComponent:@"identity.json"];
        return [json writeToFile:path atomically:YES] ? 0 : 2;
    }
}
