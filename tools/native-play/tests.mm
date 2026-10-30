#import "NPModel.h"
#include <cmath>
#include <sys/stat.h>
#include <unistd.h>

static NSUInteger checks;
static void Check(BOOL condition,NSString *name){checks++;if(!condition){fprintf(stderr,"FAIL: %s\n",name.UTF8String);exit(1);}}
static NSURL *Child(NSURL *root,NSString *name){return [root URLByAppendingPathComponent:name];}
static void Write(NSURL *url,NSString *text){[NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];Check([text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL],@"write synthetic fixture");}
static NSString *Read(NSURL *url){return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL];}
static void JSON(id value,NSURL *url){[NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];Check([[NSJSONSerialization dataWithJSONObject:value options:0 error:NULL]writeToURL:url atomically:YES],@"write synthetic metadata");}
@interface TestStore : NPStore
@property BOOL running,failInstall;
@end
@implementation TestStore
- (BOOL)gameIsRunning{return self.running;}
- (BOOL)move:(NSURL *)source to:(NSURL *)destination error:(NSError **)error{
    if(self.failInstall && [source.path containsString:@"/new/"] && [source.lastPathComponent isEqual:@"save.work"]){self.failInstall=NO;if(error)*error=[NSError errorWithDomain:@"InjectedFailure" code:1 userInfo:nil];return NO;}
    return [super move:source to:destination error:error];
}
@end
static TestStore *Store(NSURL *base,NSString *name){NSURL *home=Child(base,name);return [[TestStore alloc]initWithRoot:Child(home,@"hub") home:home];}
static BOOL Sign(NSURL *url){NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/codesign"];task.arguments=@[@"--force",@"--sign",@"-",url.path];task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;if(![task launchAndReturnError:NULL])return NO;[task waitUntilExit];return task.terminationStatus==0;}
static NSURL *SignedApp(NSURL *base,NSString *name,NSString *identifier){
    NSURL *app=Child(base,[name stringByAppendingString:@".app"]),*main=Child(app,@"Contents/MacOS/Fixture"),*host=Child(app,@"Contents/Resources/game/dmhost");
    for(NSURL *url in @[main,host]){[NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];Check([NSFileManager.defaultManager copyItemAtURL:NSBundle.mainBundle.executableURL toURL:url error:NULL],@"copy owned synthetic executable");}
    Check(Sign(host),@"sign synthetic runtime");JSON(@{@"game":@{@"title_id":identifier,@"version":@"1.0"},@"host_sha256":NPSHA256(host),@"native_play":@{@"adapter":@"dmhost-v2",@"managed_state":@YES}},Child(app,@"Contents/Resources/game/build-info.json"));
    [@{@"CFBundleExecutable":@"Fixture",@"CFBundleIdentifier":[@"org.macnativegames.fixture.g" stringByAppendingString:identifier],@"CFBundleName":name,@"CFBundlePackageType":@"APPL"}writeToURL:Child(app,@"Contents/Info.plist") atomically:YES];Check(Sign(app),@"sign synthetic native app");return app;
}

int main(int argc,const char **argv){@autoreleasepool{
    umask(0077);if(argc!=2)return 2;NSURL *base=[[NSURL fileURLWithPath:@(argv[1])] URLByResolvingSymlinksInPath];
    Check(![NSFileManager.defaultManager fileExistsAtPath:base.path],@"fresh private test root required");
    NSURL *temporary=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    TestStore *alias=Store(temporary,@"system-alias");Check(alias!=nil,@"macOS system temporary-directory alias supported");Write(Child(alias.state,@"save/file"),@"system-alias-data");Check([alias backup:@"System alias" error:NULL]!=nil&&alias.backups.count==1,@"backup works through macOS path aliases");
    [NSFileManager.defaultManager removeItemAtURL:temporary error:NULL];
    TestStore *store=Store(base,@"roundtrip");Check(store!=nil,@"store created");
    Write(Child(store.state,@"save/progress"),@"original-progress");Write(Child(store.state,@"save.work/progress"),@"original-work");Write(Child(store.state,@"controller-layout.txt"),@"synthetic-controller-settings");
    NSDictionary *snapshot=[store backup:@"First" error:NULL];Check(snapshot!=nil,@"snapshot created");Check([snapshot[@"files"] count]==3,@"all state components included");
    Write(Child(store.state,@"save/progress"),@"new-progress");Write(Child(store.state,@"save/stale"),@"extra");Write(Child(store.state,@"save.work/progress"),@"new-work");Write(Child(store.state,@"controller-layout.txt"),@"new-settings");
    Check([store restore:snapshot error:NULL],@"restore succeeds");Check([Read(Child(store.state,@"save/progress")) isEqual:@"original-progress"],@"progress restored");
    Check([Read(Child(store.state,@"save.work/progress")) isEqual:@"original-work"],@"working save restored");Check([Read(Child(store.state,@"controller-layout.txt")) isEqual:@"synthetic-controller-settings"],@"controller settings restored");
    Check(![NSFileManager.defaultManager fileExistsAtPath:Child(store.state,@"save/stale").path],@"stale files removed as part of restore");
    Check(store.backups.count==2,@"pre-restore recovery snapshot retained");
    struct stat info;lstat([snapshot[@"path"] fileSystemRepresentation],&info);Check((info.st_mode&0777)==0700,@"snapshot private");lstat(Child([NSURL fileURLWithPath:snapshot[@"path"]],@"save/progress").fileSystemRepresentation,&info);Check((info.st_mode&0777)==0600,@"save files private");
    Write(Child(store.state,@"save/progress"),@"keep-on-failure");Write(Child(store.state,@"controller-layout.txt"),@"keep-settings");store.failInstall=YES;
    Check(![store restore:snapshot error:NULL],@"injected install failure reported");Check([Read(Child(store.state,@"save/progress")) isEqual:@"keep-on-failure"],@"failed restore rolls progress back");Check([Read(Child(store.state,@"controller-layout.txt")) isEqual:@"keep-settings"],@"failed restore preserves preferences");
    store.running=YES;Check([store backup:@"Forbidden" error:NULL]==nil,@"backup blocked while running");Check(![store restore:snapshot error:NULL],@"restore blocked while running");store.running=NO;
    NSURL *snapshotURL=[NSURL fileURLWithPath:snapshot[@"path"]];Write(Child(snapshotURL,@"save/progress"),@"tampered");
    Check(![store restore:snapshot error:NULL],@"corrupt snapshot rejected");Check([Read(Child(store.state,@"save/progress")) isEqual:@"keep-on-failure"],@"corruption does not touch current progress");
    NSMutableDictionary *evil=[snapshot mutableCopy];evil[@"path"]=base.path;Check(![store restore:evil error:NULL],@"external backup path rejected");
    TestStore *links=Store(base,@"links");Write(Child(base,@"outside/progress"),@"unrelated");[NSFileManager.defaultManager createDirectoryAtURL:links.state withIntermediateDirectories:YES attributes:nil error:NULL];
    [NSFileManager.defaultManager createSymbolicLinkAtURL:Child(links.state,@"save") withDestinationURL:Child(base,@"outside") error:NULL];
    Check([links backup:@"Linked" error:NULL]==nil,@"symlink state root rejected");Check([Read(Child(base,@"outside/progress")) isEqual:@"unrelated"],@"outside file untouched");
    [NSFileManager.defaultManager createSymbolicLinkAtURL:Child(base,@"linked-parent") withDestinationURL:Child(base,@"outside") error:NULL];Check(Store(Child(base,@"linked-parent"),@"rejected")==nil,@"linked store ancestor rejected before URL normalization");
    TestStore *traversal=Store(base,@"traversal");Write(Child(traversal.state,@"save/file"),@"safe");NSDictionary *good=[traversal backup:@"Good" error:NULL];NSMutableDictionary *bad=[good mutableCopy];bad[@"files"]=@{@"../outside":@"fake"};[bad removeObjectForKey:@"path"];JSON(bad,Child([NSURL fileURLWithPath:good[@"path"]],@"manifest.json"));
    Check(![traversal restore:good error:NULL],@"traversal manifest rejected");Check([Read(Child(traversal.state,@"save/file")) isEqual:@"safe"],@"traversal leaves progress intact");
    TestStore *retention=Store(base,@"retention");Write(Child(retention.state,@"save/file"),@"retain");for(NSUInteger i=0;i<22;i++)Check([retention backup:@"Rotation" error:NULL]!=nil,@"rotation snapshot created");Check(retention.backups.count==20,@"completed snapshot history bounded");
    Check(![store.options[@"hud"] boolValue]&&![store.options[@"record"] boolValue],@"normal play defaults to light logging");NSDictionary *normal=[store environmentForSession:Child(base,@"session") controllers:NO];Check(normal[@"DM_NVN_TSV"]==nil&&normal[@"MTL_DEBUG_LAYER"]==nil&&normal[@"DYLD_INSERT_LIBRARIES"]==nil,@"no default profiler or injected libraries");
    [store setOptions:@{@"hud":@YES,@"record":@YES}];NSDictionary *profile=[store environmentForSession:Child(base,@"session") controllers:YES];Check([profile[@"MTL_HUD_ENABLED"] isEqual:@"1"],@"HUD is per-launch environment");Check([profile[@"DM_CONTROLLER_SETUP"] isEqual:@"1"],@"controller setup route");Check([profile[@"DM_NVN_TSV_CALLS"] isEqual:@"0"],@"profile records timings only");
    NSString *sandbox=[store sandboxForSession:Child(base,@"session")];Check([sandbox containsString:@"(deny network*)"],@"network denial retained");Check([sandbox containsString:@"(deny file-write*"],@"filesystem writes restricted");Check([sandbox containsString:@"Library/Keychains"],@"credential store blocked");
    NSString *quoted=NPQuote(@"/tmp/a\"b\\c\n");Check([quoted hasPrefix:@"\""]&&[quoted containsString:@"\\\""]&&[quoted containsString:@"\\n"],@"sandbox paths quoted structurally");
    NSURL *sessions=Child(store.root,@"Sessions");NSMutableArray *history=[NSMutableArray new];
    for(NSUInteger i=0;i<22;i++){NSURL *entry=Child(sessions,NSUUID.UUID.UUIDString);[history addObject:entry];JSON(@{@"game":@"0100965017338000"},Child(entry,@"session.json"));JSON(@{@"finished":@(i)},Child(entry,@"result.json"));Write(Child(entry,@"frames.tsv"),@"synthetic timing");Write(Child(entry,@"tmp/throwaway"),@"temporary");}
    Write(Child(sessions,@"unrelated/keep"),@"not a managed session");NSURL *active=Child(sessions,NSUUID.UUID.UUIDString);JSON(@{@"game":@"0100965017338000"},Child(active,@"session.json"));Write(Child(active,@"frames.tsv"),@"active");
    NPPruneSessions(store.root);NSUInteger raw=0,complete=0;for(NSURL *entry in history){if([NSFileManager.defaultManager fileExistsAtPath:entry.path])complete++;if([NSFileManager.defaultManager fileExistsAtPath:Child(entry,@"frames.tsv").path])raw++;Check(![NSFileManager.defaultManager fileExistsAtPath:Child(entry,@"tmp").path],@"finished temporary files removed");}
    Check(complete==20&&raw==3,@"completed history and raw recordings bounded");Check([Read(Child(sessions,@"unrelated/keep")) isEqual:@"not a managed session"],@"unrecognized directory untouched");Check([Read(Child(active,@"frames.tsv")) isEqual:@"active"],@"active recording untouched");
    NSURL *oversized=Child(history.lastObject,@"frames.tsv");Check(truncate(oversized.fileSystemRepresentation,257ll*1024*1024)==0,@"create sparse oversized synthetic recording");NPPruneSessions(store.root);Check(![NSFileManager.defaultManager fileExistsAtPath:oversized.path],@"oversized completed recording removed");
    Write(Child(store.root,@"library.json"),@"[123,\"bad\",{}]");Check(store.games.count==0,@"malformed catalog entries ignored");Write(Child(store.root,[@"LaunchOptions/" stringByAppendingFormat:@"%@.json",[store keyForGame:@{}]]),@"[]");Write(Child(store.root,@"options.json"),@"[]");Check(![store.options[@"record"] boolValue],@"malformed options safe defaults");
    NSURL *fake=Child(base,@"unsigned.app");Write(Child(fake,@"Contents/Resources/game/dmhost"),@"synthetic unsigned host");Write(Child(fake,@"Contents/MacOS/Jamboree"),@"synthetic unsigned launcher");JSON(@{@"game":@{@"title_id":@"0100965017338000"},@"host_sha256":NPSHA256(Child(fake,@"Contents/Resources/game/dmhost"))},Child(fake,@"Contents/Resources/game/build-info.json"));
    [@{@"CFBundleExecutable":@"Jamboree",@"CFBundleIdentifier":@"org.macnativegames.fixture.unsigned",@"CFBundlePackageType":@"APPL"}writeToURL:Child(fake,@"Contents/Info.plist") atomically:YES];Check([store importApp:fake error:NULL]==nil,@"unsigned app rejected even with a matching host hash");
    NSURL *session=Child(base,@"timings");Write(Child(session,@"frames.tsv"),@"1\t@frame_ms\t10\n2\t@frame_ms\t20\n3\t@frame_ms\t30\n4\t@frame_ms\t40\n5\t@frame_ms\t100\n6\t@frame_ms\tNaN\n1\t@gpu_ms\t2\n");NSDictionary *summary=NPProfileSummary(session);Check([summary[@"frames"] intValue]==5,@"numeric timing coverage");Check(std::abs([summary[@"median_ms"] doubleValue]-30)<1e-9,@"median");Check(std::abs([summary[@"p95_ms"] doubleValue]-88)<1e-9,@"linear p95");Check([summary[@"over_50_ms"] intValue]==1,@"hitch count");Check([summary[@"includes_loading"] boolValue],@"loading not silently filtered");Check([summary[@"invalid_rows"] intValue]==1,@"invalid timing not treated as zero");
    TestStore *multi=Store(base,@"multi-app");NSURL *first=SignedApp(base,@"Sky Fixture",@"0100000000000001"),*second=SignedApp(base,@"Moss Fixture",@"0100000000000002");
    NSArray *added=[multi importApps:@[first,second] error:NULL];Check(added.count==2&&multi.games.count==2,@"multiple apps import without replacing existing entries");Check([multi importApp:first error:NULL]!=nil&&multi.games.count==2,@"same-path reimport updates only that entry");Check([multi importApps:@[first,fake] error:NULL]==nil&&multi.games.count==2,@"failed batch leaves catalog intact");
    NSDictionary *a=added[0],*b=added[1];Check([multi verifyGame:a error:NULL]&&[multi verifyGame:b error:NULL],@"both signed identities verified independently");
    multi.activeGame=a;Write(Child(multi.state,@"save/progress"),@"first-game-progress");NSDictionary *saveA=[multi backup:@"First game" error:NULL];[multi setOptions:@{@"hud":@YES,@"record":@NO,@"fullscreen":@NO}];NSURL *stateA=multi.state;
    multi.activeGame=b;Check(![multi.state.path isEqual:stateA.path],@"different titles have different save roots");Check(multi.backups.count==0&&! [multi.options[@"hud"] boolValue],@"save history and launch settings isolated by game");Write(Child(multi.state,@"save/progress"),@"second-game-progress");Check([multi backup:@"Second game" error:NULL]!=nil,@"second game backup");Check(![multi restore:saveA error:NULL],@"cross-game restore rejected");Check([Read(Child(multi.state,@"save/progress")) isEqual:@"second-game-progress"],@"cross-game attempt preserves progress");
    multi.activeGame=a;Check(multi.backups.count==1&&[multi.options[@"hud"] boolValue]&&![multi.options[@"fullscreen"] boolValue],@"returning to a game restores its history and preferences");Check([multi removeGame:b error:NULL]&&multi.games.count==1,@"remove only the selected catalog entry");Check([NSFileManager.defaultManager fileExistsAtPath:second.path],@"removing entry preserves installed app");
    NSDictionary *changed=[a mutableCopy];((NSMutableDictionary *)changed)[@"executable_sha256"]=@"changed";Check(![multi verifyGame:changed error:NULL],@"launcher executable hash pinned in addition to runtime");
    NSURL *metadata=Child(second,@"Contents/Resources/game/build-info.json");NSMutableDictionary *unmanaged=[[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:metadata] options:NSJSONReadingMutableContainers error:NULL]mutableCopy];unmanaged[@"native_play"]=@{@"adapter":@"dmhost-v2",@"managed_state":@NO};JSON(unmanaged,metadata);Check(Sign(second),@"re-sign fixture without managed state");Check([multi importApp:second error:NULL]==nil,@"adapter must explicitly support isolated state");
    printf("Native Play: %lu backend checks passed; all state is synthetic.\n",(unsigned long)checks);return 0;
}}
