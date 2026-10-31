// One installed native app: its validated identity and what the launcher may do with it.
// DM-host bundles share a resource contract; other native engines need an adapter.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The first supported port. It predates the adapter contract, so it gets a compatible
// path for its existing saves and needs no managed-state declaration.
FOUNDATION_EXPORT NSString *const NPJamboreeTitleID;
// A fresh, independent `.app` check succeeded and its identity is pinned in the entry.
FOUNDATION_EXPORT BOOL NPIsTitleID(id _Nullable value);

@interface NPGame : NSObject

@property (readonly, copy) NSString *titleID;
@property (readonly, copy) NSString *title;
@property (readonly, copy) NSString *version;
@property (readonly, copy) NSString *path;
// Stable per-installation key: separate builds of one title have separate preferences.
@property (readonly, copy) NSString *key;
// Bundle-relative path of the primary executable.
@property (readonly, copy) NSString *executable;
@property (readonly) BOOL supportsControllerSetup;
// The bundle declares it applies the restriction profile itself after a normal app launch.
@property (readonly) BOOL launchesThroughLaunchServices;
// The JSON object stored in library.json.
@property (readonly, copy) NSDictionary *catalogEntry;

// Nil when a library.json row lacks the fields every game needs.
- (nullable instancetype)initWithCatalogEntry:(NSDictionary *)entry NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Checks the bundle, its signature and its adapter declaration, and pins its identity.
+ (nullable instancetype)gameFromAppAtURL:(NSURL *)app error:(NSError **)error;

// Re-checks the installed bundle against the identity pinned when it was added.
- (nullable NPGame *)verifiedGameWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
