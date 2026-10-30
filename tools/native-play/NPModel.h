#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *NPSHA256(NSURL *url);
FOUNDATION_EXPORT NSString *NPQuote(NSString *string);
FOUNDATION_EXPORT NSDictionary *NPProfileSummary(NSURL *session);
FOUNDATION_EXPORT void NPPruneSessions(NSURL *root);

// This first adapter deliberately accepts only the verified Jamboree bundle format.
// Another title needs its own state paths and validation before it can be registered.
@interface NPStore : NSObject
@property (readonly) NSURL *root;
@property (readonly) NSURL *home;
@property (readonly) NSURL *state;
- (instancetype)initWithRoot:(NSURL *)root home:(NSURL *)home;
- (NSArray<NSDictionary *> *)games;
- (nullable NSDictionary *)importApp:(NSURL *)app error:(NSError **)error;
- (BOOL)verifyGame:(NSDictionary *)game error:(NSError **)error;
- (BOOL)gameIsRunning;
- (NSArray<NSDictionary *> *)backups;
- (nullable NSDictionary *)backup:(NSString *)label error:(NSError **)error;
- (BOOL)restore:(NSDictionary *)snapshot error:(NSError **)error;
- (BOOL)move:(NSURL *)source to:(NSURL *)destination error:(NSError **)error;
- (NSDictionary *)options;
- (void)setOptions:(NSDictionary *)options;
- (NSString *)sandboxForSession:(NSURL *)session;
- (NSDictionary<NSString *, NSString *> *)environmentForSession:(NSURL *)session controllers:(BOOL)controllers;
- (nullable NSTask *)launch:(NSDictionary *)game controllers:(BOOL)controllers completion:(void (^)(int status, NSURL *session))completion error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
