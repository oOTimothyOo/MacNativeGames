#import "NPGame.h"
#import "NPFoundation.h"
#import <Security/Security.h>

NSString *const NPJamboreeTitleID = @"0100965017338000";

static NSString *const LegacyHostPath = @"Contents/Resources/game/dmhost";
static NSString *const BuildInfoPath = @"Contents/Resources/game/build-info.json";

BOOL NPIsTitleID(id value) {
    NSString *text = NPString(value);
    if (text.length != 16) {
        return NO;
    }
    NSCharacterSet *hexadecimal = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [text rangeOfCharacterFromSet:hexadecimal.invertedSet].location == NSNotFound;
}

// The bundle's content directory hash, after checking nested code, every architecture
// and strict signature validity. Nil when the bundle is unsigned or was modified.
static NSString *VerifiedCodeDirectoryHash(NSURL *app) {
    SecStaticCodeRef rawCode = NULL;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)app, kSecCSDefaultFlags, &rawCode) != errSecSuccess) {
        return nil;
    }
    id code = CFBridgingRelease(rawCode);
    SecCSFlags checks = kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate;
    if (SecStaticCodeCheckValidity((__bridge SecStaticCodeRef)code, checks, NULL) != errSecSuccess) {
        return nil;
    }
    CFDictionaryRef rawInformation = NULL;
    if (SecCodeCopySigningInformation((__bridge SecStaticCodeRef)code, kSecCSDefaultFlags, &rawInformation) != errSecSuccess) {
        return nil;
    }
    NSDictionary *information = CFBridgingRelease(rawInformation);
    NSData *unique = information[(__bridge NSString *)kSecCodeInfoUnique];
    return unique ? NPHexString(static_cast<const unsigned char *>(unique.bytes), unique.length) : nil;
}

@implementation NPGame

- (instancetype)initWithCatalogEntry:(NSDictionary *)entry {
    if (!NPIsTitleID(entry[@"id"]) || !NPString(entry[@"path"]) || !NPString(entry[@"title"]).length || !NPString(entry[@"version"])) {
        return nil;
    }
    if ((self = [super init])) {
        _catalogEntry = [entry copy];
        _titleID = [entry[@"id"] lowercaseString];
        _title = [entry[@"title"] copy];
        _version = [entry[@"version"] copy];
        _path = [entry[@"path"] copy];
        _key = NPSHA256OfString(_path);
        _executable = [NPString(entry[@"executable"]) ?: @"Contents/MacOS/Jamboree" copy];
        _supportsControllerSetup = NPIsTrue(entry[@"controllers"]) || [_titleID isEqual:NPJamboreeTitleID];
        _launchesThroughLaunchServices = NPIsTrue(entry[@"launch_services_sandbox"]);
    }
    return self;
}

- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:NPGame.class] && [self.path isEqual:((NPGame *)other).path];
}

- (NSUInteger)hash {
    return self.path.hash;
}

+ (instancetype)gameFromAppAtURL:(NSURL *)app error:(NSError **)error {
    if (!NPPathHasNoLinks(app)) {
        NPFail(error, @"Choose an app without linked parent directories.");
        return nil;
    }
    app = app.URLByStandardizingPath;
    if (![app.pathExtension isEqual:@"app"] || !NPPathHasNoLinks(app)) {
        NPFail(error, @"Choose a local .app without symbolic-link parents.");
        return nil;
    }

    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfURL:NPChild(app, @"Contents/Info.plist")];
    NSString *executable = NPString(plist[@"CFBundleExecutable"]);
    if (!executable.length || ![executable.lastPathComponent isEqual:executable] || [executable isEqual:@"."] || [executable isEqual:@".."]) {
        NPFail(error, @"The native app has an invalid executable name.");
        return nil;
    }
    NSString *entrypoint = [@"Contents/MacOS/" stringByAppendingString:executable];
    NSURL *buildInfo = NPChild(app, BuildInfoPath);
    if (!NPPathHasNoLinks(buildInfo) || !NPPathHasNoLinks(NPChild(app, entrypoint))) {
        NPFail(error, @"The app contains linked launch metadata.");
        return nil;
    }

    NSDictionary *info = NPDictionary(NPReadJSON(buildInfo));
    NSDictionary *metadata = NPDictionary(info[@"game"]);
    NSString *hostHash = NPString(info[@"host_sha256"]);
    if (!NPIsTitleID(metadata[@"title_id"]) || !hostHash) {
        NPFail(error, @"Choose a built DM-host native app with build provenance. Other native engines need an adapter; raw game archives cannot be launched here.");
        return nil;
    }
    NSString *titleID = [metadata[@"title_id"] lowercaseString];
    BOOL isJamboree = [titleID isEqual:NPJamboreeTitleID];

    NSDictionary *adapter = NPDictionary(info[@"native_play"]);
    BOOL managed = [adapter[@"adapter"] isEqual:@"dmhost-v2"] && NPIsTrue(adapter[@"managed_state"]);
    if (!isJamboree && !managed) {
        NPFail(error, @"This app needs a managed-state DM-host adapter before it can be launched safely.");
        return nil;
    }

    NSString *hostPath = NPString(info[@"host_executable"]) ?: LegacyHostPath;
    if (![@[LegacyHostPath, @"Contents/MacOS/GameHost"] containsObject:hostPath]) {
        NPFail(error, @"Unsupported native runtime location.");
        return nil;
    }
    NSURL *host = NPChild(app, hostPath);
    NSString *codeDirectoryHash = NPPathHasNoLinks(host) && [NPSHA256OfFile(host) isEqual:hostHash] ? VerifiedCodeDirectoryHash(app) : nil;
    if (!codeDirectoryHash) {
        NPFail(error, @"The app is incomplete or its signed host hash has changed.");
        return nil;
    }
    NSString *executableHash = NPSHA256OfFile(NPChild(app, entrypoint));
    if (!executableHash) {
        NPFail(error, @"The native launcher is missing.");
        return nil;
    }

    NSString *title = NPString(plist[@"CFBundleDisplayName"]) ?: NPString(plist[@"CFBundleName"]) ?: app.lastPathComponent.stringByDeletingPathExtension;
    return [[self alloc] initWithCatalogEntry:@{
        @"id": titleID,
        @"title": title.length ? title : @"Native game",
        @"path": app.path,
        @"version": NPString(metadata[@"version"]) ?: @"unknown",
        @"host_sha256": hostHash,
        @"bundle_cdhash": codeDirectoryHash,
        @"executable": entrypoint,
        @"executable_sha256": executableHash,
        @"host_executable": hostPath,
        @"chain": NPString(info[@"chain"]) ?: @"unknown",
        @"language": NPString(info[@"language"]) ?: @"en-US",
        @"adapter": @"dmhost",
        @"game_mode_supported": @(NPIsTrue(plist[@"LSSupportsGameMode"])),
        @"launch_services_sandbox": @([adapter[@"sandbox_entry"] isEqual:@"sandbox-exec-v1"]),
        @"controllers": @(isJamboree || NPIsTrue(info[@"controller_setup"])),
    }];
}

- (NPGame *)verifiedGameWithError:(NSError **)error {
    NPGame *actual = [NPGame gameFromAppAtURL:[NSURL fileURLWithPath:self.path] error:error];
    if (!actual) {
        return nil;
    }
    for (NSString *pin in @[@"id", @"path", @"host_sha256", @"bundle_cdhash", @"executable", @"executable_sha256", @"host_executable", @"launch_services_sandbox"]) {
        id pinned = self.catalogEntry[pin];
        if (pinned && ![pinned isEqual:actual.catalogEntry[pin]]) {
            NPFail(error, @"This app changed since it was added. Add the updated build again to review its identity.");
            return nil;
        }
    }
    return actual;
}

@end
