#import "NPFoundation.h"
#import <CommonCrypto/CommonDigest.h>
#include <filesystem>
#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>

NSErrorDomain const NPErrorDomain = @"NativePlay";

BOOL NPFail(NSError **error, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:NPErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

NSURL *NPChild(NSURL *url, NSString *name) {
    return [url URLByAppendingPathComponent:name];
}

BOOL NPExists(NSURL *url) {
    return [NSFileManager.defaultManager fileExistsAtPath:url.path];
}

BOOL NPCreatePrivateDirectory(NSURL *url, NSError **error) {
    return [NSFileManager.defaultManager createDirectoryAtURL:url
                                  withIntermediateDirectories:YES
                                                   attributes:@{NSFilePosixPermissions: @0700}
                                                        error:error];
}

// Foundation sometimes rewrites /private/var back to /var while standardizing URLs.
static BOOL IsSystemAlias(NSString *path, const struct stat &info) {
    if (info.st_uid != 0 || ![@[@"/var", @"/tmp", @"/etc"] containsObject:path]) {
        return NO;
    }
    char resolved[PATH_MAX];
    return realpath(path.fileSystemRepresentation, resolved) &&
           [@(resolved) isEqual:[@"/private" stringByAppendingString:path]];
}

BOOL NPPathHasNoLinks(NSURL *url) {
    NSString *path = url.path;
    if ([path.pathComponents containsObject:@".."] || ![path hasPrefix:@"/"]) {
        return NO;
    }
    while (path.length) {
        struct stat info;
        if (!lstat(path.fileSystemRepresentation, &info) && S_ISLNK(info.st_mode) && !IsSystemAlias(path, info)) {
            return NO;
        }
        NSString *parent = path.stringByDeletingLastPathComponent;
        if ([parent isEqual:path]) {
            break;
        }
        path = parent;
    }
    return YES;
}

NSString *NPCanonicalPath(NSURL *url) {
    std::error_code failure;
    auto resolved = std::filesystem::weakly_canonical(std::filesystem::path(url.fileSystemRepresentation), failure);
    return failure ? url.path : @(resolved.c_str());
}

NSString *NPString(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

NSNumber *NPNumber(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

NSDictionary *NPDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

BOOL NPIsTrue(id value) {
    return [value isEqual:@YES];
}

id NPReadJSON(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

BOOL NPWriteJSON(id value, NSURL *url, NSError **error) {
    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:options error:error];
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                          ofItemAtPath:url.path
                                                 error:error];
}

NSString *NPHexString(const unsigned char *bytes, size_t length) {
    NSMutableString *text = [NSMutableString stringWithCapacity:length * 2];
    for (size_t i = 0; i < length; i++) {
        [text appendFormat:@"%02x", bytes[i]];
    }
    return text;
}

NSString *NPSHA256OfFile(NSURL *url) {
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    [stream open];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[65536];
    NSInteger length;
    while ((length = [stream read:buffer maxLength:sizeof buffer]) > 0) {
        CC_SHA256_Update(&context, buffer, (CC_LONG)length);
    }
    [stream close];
    if (length < 0 || !stream) {
        return nil;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return NPHexString(digest, sizeof digest);
}

NSString *NPSHA256OfString(NSString *string) {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return NPHexString(digest, sizeof digest);
}

NSString *NPQuote(NSString *string) {
    NSJSONWritingOptions options = NSJSONWritingFragmentsAllowed | NSJSONWritingWithoutEscapingSlashes;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[string] options:options error:nil];
    NSString *array = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [array substringWithRange:NSMakeRange(1, array.length - 2)];
}
