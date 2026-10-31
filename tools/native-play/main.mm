// Objective-C++ is the Cocoa bridge for this C/C++ native-game library.
#import <Cocoa/Cocoa.h>
#import "NPAppDelegate.h"
#import "NPFoundation.h"
#include <sys/stat.h>
#include <unistd.h>

static int Fail(NSError *error) {
    fprintf(stderr, "%s\n", error.localizedDescription.UTF8String ?: "The action could not be completed.");
    return 1;
}

// `--register <app>`: adds or refreshes a catalog entry.
static int RegisterApp(NPStore *store, const char *path) {
    NSError *error = nil;
    if (![store importApp:[NSURL fileURLWithPath:@(path)] error:&error]) {
        return Fail(error);
    }
    puts("Signed native app registered locally.");
    return 0;
}

// `--backup`: snapshots Jamboree, the title whose saves predate the library.
static int BackUpJamboree(NPStore *store) {
    NSError *error = nil;
    NPBackup *backup = [store backupTitle:NPJamboreeTitleID label:@"Manual backup" error:&error];
    if (!backup) {
        return Fail(error);
    }
    printf("Backed up and verified %lu private state files locally.\n", (unsigned long)backup.files.count);
    return 0;
}

// `--play <app>`: launches a registered app as the Play button does, and waits for it.
static int PlayApp(NPStore *store, const char *path) {
    NSString *standardized = [NSURL fileURLWithPath:@(path)].URLByStandardizingPath.path;
    NPGame *found = nil;
    for (NPGame *game in store.games) {
        if ([game.path isEqual:standardized]) {
            found = game;
        }
    }
    if (!found) {
        fputs("That app is not in the library. Add it first.\n", stderr);
        return 1;
    }
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    NSError *error = nil;
    NPLauncher *launcher = [[NPLauncher alloc] initWithStore:store];
    NPGameSession *session = [launcher launchGame:found controllerSetup:NO completion:^(int status, NSURL *record) {
        dispatch_semaphore_signal(ended);
    } error:&error];
    if (!session) {
        return Fail(error);
    }
    printf("Started process %d.\n", session.processIdentifier);
    fflush(stdout);
    dispatch_semaphore_wait(ended, DISPATCH_TIME_FOREVER);
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        umask(0077);
        if (argc == 5 && !strcmp(argv[1], "--sandbox-probe")) {
            return NPSandboxProbe(argv[2], argv[3], argv[4]);
        }

        NSURL *home = [NSURL fileURLWithPath:NSHomeDirectory()];
        NPStore *store = [[NPStore alloc] initWithRoot:NPChild(home, @"Library/Application Support/Native Play") home:home];
        if (!store) {
            fputs("Could not create private Native Play support directories.\n", stderr);
            return 1;
        }
        if (argc == 3 && !strcmp(argv[1], "--register")) {
            return RegisterApp(store, argv[2]);
        }
        if (argc == 2 && !strcmp(argv[1], "--backup")) {
            return BackUpJamboree(store);
        }
        if (argc == 3 && !strcmp(argv[1], "--play")) {
            return PlayApp(store, argv[2]);
        }

        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        for (NSRunningApplication *running in [NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier]) {
            if (running.processIdentifier != getpid()) {
                [running activateWithOptions:0];
                return 0;
            }
        }
        NPAppDelegate *delegate = [[NPAppDelegate alloc] initWithStore:store];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
