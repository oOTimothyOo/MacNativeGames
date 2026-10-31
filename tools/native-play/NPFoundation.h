// Small file, JSON and hashing helpers shared by the model. No AppKit.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const NPErrorDomain;

// Fills *error and returns NO, so a failure reads `return NPFail(error, @"…");`.
FOUNDATION_EXPORT BOOL NPFail(NSError **error, NSString *message);

FOUNDATION_EXPORT NSURL *NPChild(NSURL *url, NSString *name);
FOUNDATION_EXPORT BOOL NPExists(NSURL *url);
FOUNDATION_EXPORT BOOL NPCreatePrivateDirectory(NSURL *url, NSError **error);

// YES when no component of the path is a symbolic link, apart from macOS's own
// /var, /tmp and /etc aliases. Checks each component with lstat because resolving
// and comparing misses dangling links.
FOUNDATION_EXPORT BOOL NPPathHasNoLinks(NSURL *url);
// The resolved path sandbox rules must name; the kernel matches rules against these.
FOUNDATION_EXPORT NSString *NPCanonicalPath(NSURL *url);

// Values read from JSON or a plist can have any type; these return nil on a mismatch.
FOUNDATION_EXPORT NSString *_Nullable NPString(id _Nullable value);
FOUNDATION_EXPORT NSNumber *_Nullable NPNumber(id _Nullable value);
FOUNDATION_EXPORT NSDictionary *_Nullable NPDictionary(id _Nullable value);
// YES only for a real JSON/plist true, never for a truthy value of another type.
FOUNDATION_EXPORT BOOL NPIsTrue(id _Nullable value);

FOUNDATION_EXPORT id _Nullable NPReadJSON(NSURL *url);
// Written atomically and readable only by the current user.
FOUNDATION_EXPORT BOOL NPWriteJSON(id value, NSURL *url, NSError **error);

FOUNDATION_EXPORT NSString *NPHexString(const unsigned char *bytes, size_t length);
FOUNDATION_EXPORT NSString *_Nullable NPSHA256OfFile(NSURL *url);
FOUNDATION_EXPORT NSString *NPSHA256OfString(NSString *string);

// A double-quoted literal, safe to embed in a sandbox profile.
FOUNDATION_EXPORT NSString *NPQuote(NSString *string);

NS_ASSUME_NONNULL_END
