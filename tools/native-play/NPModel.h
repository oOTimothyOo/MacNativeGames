#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *NPSHA256(NSURL *url);
FOUNDATION_EXPORT NSString *NPQuote(NSString *string);
FOUNDATION_EXPORT NSDictionary *NPProfileSummary(NSURL *session);
FOUNDATION_EXPORT void NPPruneSessions(NSURL *root);

// DM-host bundles share a resource contract. Other native engines need an adapter.
@interface NPStore : NSObject
@property (readonly) NSURL *root;
@property (readonly) NSURL *home;
@property (readonly) NSURL *state;
@property (copy, nullable) NSDictionary *activeGame;
- (instancetype)initWithRoot:(NSURL *)root home:(NSURL *)home;
- (NSArray<NSDictionary *> *)games;
- (nullable NSDictionary *)importApp:(NSURL *)app error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)importApps:(NSArray<NSURL *> *)apps error:(NSError **)error;
- (BOOL)removeGame:(NSDictionary *)game error:(NSError **)error;
- (NSString *)activeID;
- (NSString *)keyForGame:(NSDictionary *)game;
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
