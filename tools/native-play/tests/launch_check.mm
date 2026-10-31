// Launches a signed synthetic app through the real launcher in a throwaway home directory.
// Usage: np-launch-check [--no-receipt] <app> <NativePlay executable that answers --sandbox-probe>
#import <Cocoa/Cocoa.h>
#import "NPFoundation.h"
#import "NPLauncher.h"
#include <sys/stat.h>

static const int64_t TimeoutSeconds = 30;

int main(int argc, const char **argv) {
    @autoreleasepool {
        umask(0077);
        // Only the restriction fixtures leave a receipt; the Game Mode fixture just runs.
        BOOL expectReceipt = !(argc > 1 && !strcmp(argv[1], "--no-receipt"));
        if (!expectReceipt) {
            argc--;
            argv++;
        }
        if (argc != 3) {
            return 2;
        }
        NSURL *temporary = [NSURL fileURLWithPath:NSTemporaryDirectory()].URLByResolvingSymlinksInPath;
        NSURL *home = NPChild(temporary, [@"native-play-launch-" stringByAppendingString:NSUUID.UUID.UUIDString]);
        NPStore *store = [[NPStore alloc] initWithRoot:NPChild(home, @"Library/Application Support/Native Play") home:home];
        NPLauncher *launcher = [[NPLauncher alloc] initWithStore:store];
        launcher.probeExecutable = [NSURL fileURLWithPath:@(argv[2])];

        NPCreatePrivateDirectory(NPChild(home, @"Documents"), NULL);
        [@"synthetic protected input" writeToURL:NPChild(home, @"Documents/blocked") atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        NSError *error = nil;
        NPGame *game = [store importApp:[NSURL fileURLWithPath:@(argv[1])] error:&error];
        dispatch_semaphore_t ended = dispatch_semaphore_create(0);
        __block int status = -2;
        __block NSURL *session = nil;
        NPGameSession *running = game ? [launcher launchGame:game controllerSetup:NO completion:^(int result, NSURL *record) {
            session = record;
            status = result;
            dispatch_semaphore_signal(ended);
        } error:&error] : nil;
        if (!running) {
            fprintf(stderr, "Fixture launch failed: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, TimeoutSeconds * (int64_t)NSEC_PER_SEC))) {
            [running terminate];
            fputs("Fixture did not finish in time.\n", stderr);
            return 2;
        }
        // Launch Services reports no exit status, so that fixture leaves a receipt instead.
        NSString *receipt = [NSString stringWithContentsOfURL:NPChild(session, @"fixture-passed") encoding:NSUTF8StringEncoding error:NULL];
        BOOL passed = status == 0 || (status == NPExitStatusUnknown && [receipt isEqual:@"restricted-bundled-fixture-passed"]);
        if (expectReceipt && !passed) {
            fprintf(stderr, "Fixture restriction checks failed: %d\n", status);
            return 3;
        }
        if (expectReceipt) {
            puts("Signed fixture verified: network denied, protected reads denied, session writes allowed; required app identity preserved.");
        }
        [NSFileManager.defaultManager removeItemAtURL:home error:NULL];
    }
    return 0;
}
