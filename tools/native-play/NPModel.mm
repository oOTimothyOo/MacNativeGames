#import "NPModel.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <math.h>
#include <vector>
#include <algorithm>
#include <filesystem>

static NSFileManager *FM(void) { return NSFileManager.defaultManager; }
static NSURL *Child(NSURL *url, NSString *name) { return [url URLByAppendingPathComponent:name]; }
static BOOL Fail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"NativePlay" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static BOOL Directory(NSURL *url, NSError **error) {
    return [FM() createDirectoryAtURL:url withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error];
}
static BOOL Exists(NSURL *url) { return [FM() fileExistsAtPath:url.path]; }
static BOOL TitleID(id value) {
    if(![value isKindOfClass:NSString.class]||[value length]!=16)return NO;
    return [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location==NSNotFound;
}
static NSString *RulePath(NSURL *url) {
    std::error_code error;auto resolved=std::filesystem::weakly_canonical(std::filesystem::path(url.fileSystemRepresentation),error);
    return error?url.path:@(resolved.c_str());
}
// lstat every component: resolve-and-compare alone misses dangling symlinks.
static BOOL NoLinks(NSURL *url) {
    NSString *path=url.path;
    if([path.pathComponents containsObject:@".."]||![path hasPrefix:@"/"])return NO;
    while(path.length) {
        struct stat info;
        if (!lstat(path.fileSystemRepresentation, &info) && S_ISLNK(info.st_mode)) {
            // macOS exposes these root-owned system aliases. Foundation sometimes
            // rewrites /private/var back to /var while standardizing URLs.
            char resolved[4096];BOOL systemAlias=[@[@"/var",@"/tmp",@"/etc"] containsObject:path]&&info.st_uid==0;
            if(!systemAlias||!realpath(path.fileSystemRepresentation,resolved)||![@(resolved) isEqual:[@"/private" stringByAppendingString:path]])return NO;
        }
        NSString *parent=path.stringByDeletingLastPathComponent;
        if ([parent isEqual:path]) break;
        path=parent;
    }
    return YES;
}
static id JSON(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}
static BOOL WriteJSON(id value, NSURL *url, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:error];
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    return [FM() setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:error];
}
NSString *NPSHA256(NSURL *url) {
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    [stream open]; CC_SHA256_CTX context; CC_SHA256_Init(&context);
    uint8_t buffer[65536]; NSInteger length;
    while ((length = [stream read:buffer maxLength:sizeof buffer]) > 0) CC_SHA256_Update(&context, buffer, (CC_LONG)length);
    [stream close]; if (length < 0) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &context);
    NSMutableString *text = [NSMutableString new];
    for (NSUInteger i=0; i<sizeof digest; i++) [text appendFormat:@"%02x", digest[i]];
    return text;
}
NSString *NPQuote(NSString *string) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[string] options:NSJSONWritingFragmentsAllowed|NSJSONWritingWithoutEscapingSlashes error:nil];
    NSString *array = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [array substringWithRange:NSMakeRange(1,array.length-2)];
}
NSDictionary *NPProfileSummary(NSURL *session) {
    NSInputStream *stream=[NSInputStream inputStreamWithURL:Child(session,@"frames.tsv")];[stream open];
    NSMutableData *pending=[NSMutableData new];std::vector<double> frames,gpu;
    uint8_t bytes[65536];NSInteger count;NSUInteger invalid=0;
    while((count=[stream read:bytes maxLength:sizeof bytes])>0){
        [pending appendBytes:bytes length:(NSUInteger)count];
        const uint8_t *data=static_cast<const uint8_t *>(pending.bytes);NSUInteger start=0;
        for(NSUInteger i=0;i<pending.length;i++)if(data[i]=='\n'){
            NSString *line=[[NSString alloc]initWithBytes:data+start length:i-start encoding:NSUTF8StringEncoding];start=i+1;
            NSArray *row=[line componentsSeparatedByString:@"\t"];if(row.count!=3)continue;
            if(![row[1] isEqual:@"@frame_ms"]&&![row[1] isEqual:@"@gpu_ms"])continue;
            NSScanner *scanner=[NSScanner scannerWithString:row[2]];double value;
            if(![scanner scanDouble:&value]||!scanner.isAtEnd||!isfinite(value)||value<=0){invalid++;continue;}
            ([row[1] isEqual:@"@frame_ms"]?frames:gpu).push_back(value);
        }
        if(start)[pending replaceBytesInRange:NSMakeRange(0,start) withBytes:NULL length:0];
        if(pending.length>1024*1024){invalid++;[pending setLength:0];}
    }
    [stream close];if(frames.empty())return @{};
    std::sort(frames.begin(),frames.end());std::sort(gpu.begin(),gpu.end());
    auto quantile=[](const std::vector<double>& values,double q){if(values.empty())return 0.0;double i=(values.size()-1)*q;size_t lo=(size_t)i,hi=std::min(lo+1,values.size()-1);return values[lo]+(values[hi]-values[lo])*(i-lo);};
    size_t hitches=std::count_if(frames.begin(),frames.end(),[](double value){return value>50;});
    NSDictionary *report=@{@"frames":@(frames.size()),@"median_ms":@(quantile(frames,.5)),@"p95_ms":@(quantile(frames,.95)),@"p99_ms":@(quantile(frames,.99)),@"gpu_median_ms":@(quantile(gpu,.5)),@"over_50_ms":@(hitches),@"invalid_rows":@(invalid),@"includes_loading":@YES};
    WriteJSON(report,Child(session,@"summary.json"),nil);return report;
}
void NPPruneSessions(NSURL *root) {
    NSURL *sessions=Child(root,@"Sessions");if(!NoLinks(sessions))return;
    NSMutableArray *completed=[NSMutableArray new];
    for(NSURL *url in [FM() contentsOfDirectoryAtURL:sessions includingPropertiesForKeys:nil options:0 error:nil]){
        if(![[NSUUID alloc]initWithUUIDString:url.lastPathComponent]||!NoLinks(url)||!NoLinks(Child(url,@"session.json"))||!NoLinks(Child(url,@"result.json")))continue;
        NSDictionary *session=JSON(Child(url,@"session.json")),*result=JSON(Child(url,@"result.json"));
        if(![session isKindOfClass:NSDictionary.class]||!TitleID(session[@"game"])||![result isKindOfClass:NSDictionary.class]||![result[@"finished"] isKindOfClass:NSNumber.class])continue;
        [completed addObject:@{@"url":url,@"finished":result[@"finished"]}];
    }
    [completed sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"finished"] compare:a[@"finished"]];}];
    unsigned long long total=0;NSUInteger kept=0,index=0;
    for(NSDictionary *entry in completed){
        NSURL *url=entry[@"url"];
        if(index++>=20){[FM() removeItemAtURL:url error:nil];continue;}
        NSURL *frames=Child(url,@"frames.tsv");
        if(NoLinks(frames)&&Exists(frames)){
            unsigned long long size=[[FM() attributesOfItemAtPath:frames.path error:nil][NSFileSize] unsignedLongLongValue];
            if(kept<3&&total+size<=256ull*1024*1024){total+=size;kept++;}else [FM() removeItemAtURL:frames error:nil];
        }
        NSURL *temporary=Child(url,@"tmp");if(NoLinks(temporary))[FM() removeItemAtURL:temporary error:nil];
    }
}
static BOOL Command(NSString *program, NSArray *arguments, NSString **output, NSError **error) {
    NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:program]; task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
    if (![task launchAndReturnError:error]) return NO;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile]; [task waitUntilExit];
    if (output) *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    return task.terminationStatus == 0 || Fail(error,[NSString stringWithFormat:@"Verification failed (%@, exit %d).",program.lastPathComponent,task.terminationStatus]);
}
static NSArray *Roots(void) { return @[@"save",@"save.work",@"controller-layout.txt"]; }
static BOOL SafeRelative(NSString *path) {
    if (![path isKindOfClass:NSString.class] || !path.length || path.isAbsolutePath) return NO;
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    if (![Roots() containsObject:parts.firstObject]) return NO;
    if ([parts.firstObject isEqual:@"controller-layout.txt"] && parts.count != 1) return NO;
    for (NSString *part in parts) if (!part.length || [part isEqual:@"."] || [part isEqual:@".."] || [part containsString:@"\\"]) return NO;
    return YES;
}
// Enumerate owned state only; no links, devices, or oversized input. Assets and keys
// never enter this store. The returned values are hashes, not save contents.
static NSDictionary *Files(NSURL *root, NSError **error) {
    NSMutableDictionary *files = [NSMutableDictionary new]; unsigned long long total = 0;
    if (!NoLinks(root)) { Fail(error,@"A state directory is a symbolic link."); return nil; }
    for (NSString *name in Roots()) {
        NSURL *base = Child(root,name);
        struct stat initial;
        if (lstat(base.fileSystemRepresentation,&initial)) continue;
        NSMutableArray<NSURL *> *paths = [NSMutableArray arrayWithObject:base];
        if (S_ISDIR(initial.st_mode)) {
            __block NSError *enumerationError = nil;
            NSDirectoryEnumerator *enumerator = [FM() enumeratorAtURL:base includingPropertiesForKeys:nil options:0 errorHandler:^BOOL(NSURL *url,NSError *failure){(void)url;enumerationError=failure;return NO;}];
            [paths addObjectsFromArray:enumerator.allObjects];
            if (enumerationError) { if(error)*error=enumerationError; return nil; }
        }
        for (NSURL *path in paths) {
            struct stat info;
            if (lstat(path.fileSystemRepresentation,&info) || !NoLinks(path) || (!S_ISDIR(info.st_mode)&&!S_ISREG(info.st_mode))) {
                Fail(error,@"Save folders must contain ordinary files and directories, without symbolic links."); return nil;
            }
            if (S_ISDIR(info.st_mode)) continue;
            total += (unsigned long long)info.st_size;
            if (total > 100*1024*1024) { Fail(error,@"This save exceeds the adapter's 100 MB backup limit.");return nil; }
            NSString *rootPath=RulePath(root),*filePath=RulePath(path);
            if(![filePath hasPrefix:[rootPath stringByAppendingString:@"/"]]){Fail(error,@"A save file escaped its state directory.");return nil;}
            NSString *relative = [filePath substringFromIndex:rootPath.length+1];
            NSString *hash = NPSHA256(path);
            if (!SafeRelative(relative) || hash.length != 64) { Fail(error,@"Could not validate a save file.");return nil; }
            files[relative] = hash;
        }
    }
    return files;
}

@interface NPStore ()
@property NSURL *root, *home;
- (nullable NSTask *)launchScoped:(NSDictionary *)game controllers:(BOOL)controllers completion:(void (^)(int,NSURL *))completion error:(NSError **)error;
@end
@implementation NPStore
- (instancetype)initWithRoot:(NSURL *)root home:(NSURL *)home {
    if ((self=[super init])) {
        if(!NoLinks(root)||!NoLinks(home))return nil;
        _root=[NSURL fileURLWithPath:RulePath(root)]; _home=[NSURL fileURLWithPath:RulePath(home)];
        if (!NoLinks(_root) || !Directory(_root,nil)) return nil;
    } return self;
}
- (NSString *)activeID { return TitleID(self.activeGame[@"id"])?[self.activeGame[@"id"] lowercaseString]:@"0100965017338000"; }
- (NSURL *)state {
    return [self.activeID isEqual:@"0100965017338000"]?Child(self.home,@"Library/Application Support/Super Mario Party Jamboree"):Child(self.root,[@"GameData/" stringByAppendingString:self.activeID]);
}
- (NSString *)keyForGame:(NSDictionary *)game {
    NSString *path=[game[@"path"] isKindOfClass:NSString.class]?game[@"path"]:@"legacy";
    NSData *data=[path dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *key=[NSMutableString new];for(NSUInteger i=0;i<sizeof digest;i++)[key appendFormat:@"%02x",digest[i]];return key;
}
- (NSArray<NSDictionary *> *)games {
    if(!NoLinks(Child(self.root,@"library.json")))return @[];
    id value=JSON(Child(self.root,@"library.json"));
    if(![value isKindOfClass:NSArray.class])return @[];
    NSMutableArray *valid=[NSMutableArray new];
    for(id row in value)if([row isKindOfClass:NSDictionary.class]&&TitleID(row[@"id"])&&
        [row[@"path"] isKindOfClass:NSString.class]&&[row[@"title"] isKindOfClass:NSString.class]&&[row[@"version"] isKindOfClass:NSString.class])[valid addObject:row];
    return valid;
}
- (NSDictionary *)validatedApp:(NSURL *)app error:(NSError **)error {
    if(!NoLinks(app)){Fail(error,@"Choose an app without linked parent directories.");return nil;}
    app=app.URLByStandardizingPath;
    if (![app.pathExtension isEqual:@"app"] || !NoLinks(app)) { Fail(error,@"Choose a local .app without symbolic-link parents.");return nil; }
    NSDictionary *plist=[NSDictionary dictionaryWithContentsOfURL:Child(app,@"Contents/Info.plist")];
    NSString *executable=plist[@"CFBundleExecutable"];
    if(![executable isKindOfClass:NSString.class]||!executable.length||![executable.lastPathComponent isEqual:executable]||[executable isEqual:@"."]||[executable isEqual:@".."]) {Fail(error,@"The native app has an invalid executable name.");return nil;}
    NSString *entrypoint=[@"Contents/MacOS/" stringByAppendingString:executable];
    if(!NoLinks(Child(app,@"Contents/Resources/game/build-info.json"))||!NoLinks(Child(app,entrypoint))){Fail(error,@"The app contains linked launch metadata.");return nil;}
    NSDictionary *info=JSON(Child(app,@"Contents/Resources/game/build-info.json"));
    if (![info isKindOfClass:NSDictionary.class] || ![info[@"game"] isKindOfClass:NSDictionary.class] ||
        !TitleID(info[@"game"][@"title_id"]) || ![info[@"host_sha256"] isKindOfClass:NSString.class]) {
        Fail(error,@"Choose a built DM-host native app with build provenance. Other native engines need an adapter; raw game archives cannot be launched here.");return nil;
    }
    BOOL legacy=[info[@"game"][@"title_id"] isEqual:@"0100965017338000"];
    if(!legacy && (![info[@"native_play"] isKindOfClass:NSDictionary.class] || ![info[@"native_play"][@"adapter"] isEqual:@"dmhost-v2"] || ![info[@"native_play"][@"managed_state"] isEqual:@YES])) {Fail(error,@"This app needs a managed-state DM-host adapter before it can be launched safely.");return nil;}
    NSString *hostPath=info[@"host_executable"]?:@"Contents/Resources/game/dmhost";
    if(![@[@"Contents/Resources/game/dmhost",@"Contents/MacOS/GameHost"] containsObject:hostPath]){Fail(error,@"Unsupported native runtime location.");return nil;}
    NSURL *host=Child(app,hostPath);
    if (!NoLinks(host) || ![NPSHA256(host) isEqual:info[@"host_sha256"]] || !Command(@"/usr/bin/codesign",@[@"--verify",@"--deep",@"--strict",app.path],nil,error)) {
        Fail(error,@"The app is incomplete or its signed host hash has changed.");return nil;
    }
    NSString *signing=nil;
    if (!Command(@"/usr/bin/codesign",@[@"-d",@"--verbose=4",app.path],&signing,error)) return nil;
    NSString *cdhash=@"";
    for (NSString *line in [signing componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) if ([line hasPrefix:@"CDHash="]) cdhash=[line substringFromIndex:7];
    if (!cdhash.length || !Exists(Child(app,entrypoint))) { Fail(error,@"The native launcher is missing.");return nil; }
    NSString *title=plist[@"CFBundleDisplayName"]?:plist[@"CFBundleName"]?:app.lastPathComponent.stringByDeletingPathExtension;
    if(![title isKindOfClass:NSString.class]||!title.length)title=@"Native game";
    NSString *version=info[@"game"][@"version"];
    if(![version isKindOfClass:NSString.class])version=@"unknown";
    return @{@"id":[info[@"game"][@"title_id"] lowercaseString],@"title":title,@"path":app.path,
             @"host_sha256":info[@"host_sha256"],@"bundle_cdhash":cdhash,@"version":version,
             @"chain":info[@"chain"]?:@"unknown",@"language":info[@"language"]?:@"en-US",@"executable":entrypoint,
             @"executable_sha256":NPSHA256(Child(app,entrypoint)),@"host_executable":hostPath,@"adapter":@"dmhost",@"game_mode_supported":@([plist[@"LSSupportsGameMode"] boolValue]),
             @"controllers":@([info[@"game"][@"title_id"] isEqual:@"0100965017338000"]||[info[@"controller_setup"] boolValue])};
}
- (NSDictionary *)importApp:(NSURL *)app error:(NSError **)error {
    return [self importApps:@[app] error:error].firstObject;
}
- (NSArray<NSDictionary *> *)importApps:(NSArray<NSURL *> *)apps error:(NSError **)error {
    NSMutableArray *validated=[NSMutableArray new];
    for(NSURL *app in apps){NSDictionary *game=[self validatedApp:app error:error];if(!game)return nil;[validated addObject:game];}
    NSMutableArray *catalog=[self.games mutableCopy];
    for(NSDictionary *game in validated){NSUInteger i=[catalog indexOfObjectPassingTest:^BOOL(NSDictionary *old,NSUInteger index,BOOL *stop){(void)index;(void)stop;return [old[@"path"] isEqual:game[@"path"]];}];if(i==NSNotFound)[catalog addObject:game];else catalog[i]=game;}
    if(!WriteJSON(catalog,Child(self.root,@"library.json"),error))return nil;return validated;
}
- (BOOL)removeGame:(NSDictionary *)game error:(NSError **)error {
    NSMutableArray *catalog=[self.games mutableCopy];[catalog filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings){(void)bindings;return ![item[@"path"] isEqual:game[@"path"]];}]];
    return WriteJSON(catalog,Child(self.root,@"library.json"),error);
}
- (BOOL)verifyGame:(NSDictionary *)game error:(NSError **)error {
    if (![game[@"path"] isKindOfClass:NSString.class]) return Fail(error,@"Choose an installed native app.");
    NSDictionary *actual=[self validatedApp:[NSURL fileURLWithPath:game[@"path"]] error:error]; if (!actual) return NO;
    for(NSString *key in @[@"id",@"path",@"host_sha256",@"bundle_cdhash",@"executable",@"executable_sha256",@"host_executable"])
        if(game[key]&&![game[key] isEqual:actual[key]])return Fail(error,@"This app changed since it was added. Add the updated build again to review its identity.");
    return YES;
}
- (BOOL)gameIsRunning {
    NSString *processes=nil;
    if (!Command(@"/bin/ps",@[@"-axo",@"comm="],&processes,nil)) return YES;
    NSMutableSet *executables=[NSMutableSet new];
    for(NSDictionary *game in self.games){NSString *entry=game[@"executable"]?:@"Contents/MacOS/Jamboree";[executables addObject:[game[@"path"] stringByAppendingPathComponent:entry]];[executables addObject:[game[@"path"] stringByAppendingPathComponent:game[@"host_executable"]?:@"Contents/Resources/game/dmhost"]];}
    for (NSString *line in [processes componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
        if ([line hasSuffix:@"/Contents/Resources/game/dmhost"] || [line hasSuffix:@"/Contents/MacOS/GameHost"] || [line hasSuffix:@"/Contents/MacOS/Jamboree"] || [executables containsObject:[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]]) return YES;
    return NO;
}
- (NSURL *)backupRoot { return Child(self.root,[@"Backups/" stringByAppendingString:self.activeID]); }
- (NSDictionary *)validatedBackup:(NSURL *)url error:(NSError **)error {
    if (![RulePath(url.URLByDeletingLastPathComponent) isEqual:RulePath(self.backupRoot)] || ![[NSUUID alloc] initWithUUIDString:url.lastPathComponent] || !NoLinks(url)) {
        Fail(error,@"Backup path is outside the local snapshot store.");return nil;
    }
    if(!NoLinks(Child(url,@"manifest.json"))){Fail(error,@"Backup metadata is a symbolic link.");return nil;}
    NSDictionary *manifest=JSON(Child(url,@"manifest.json"));
    if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"schema"] isEqual:@1] ||
        ![manifest[@"game"] isEqual:self.activeID] || ![manifest[@"files"] isKindOfClass:NSDictionary.class] ||
        ![manifest[@"created"] isKindOfClass:NSNumber.class] || ![manifest[@"label"] isKindOfClass:NSString.class]) {
        Fail(error,@"Backup metadata is invalid.");return nil;
    }
    NSDictionary *files=Files(url,error);
    if (!files || ![files isEqual:manifest[@"files"]]) { Fail(error,@"Backup hashes differ. Your current progress has not been restored.");return nil; }
    NSMutableDictionary *result=[manifest mutableCopy];result[@"path"]=url.path;return result;
}
- (NSArray<NSDictionary *> *)backups {
    NSMutableArray *rows=[NSMutableArray new];
    if (!NoLinks(self.backupRoot)) return rows;
    for (NSURL *url in [FM() contentsOfDirectoryAtURL:self.backupRoot includingPropertiesForKeys:nil options:0 error:nil]) {
        NSDictionary *row=[self validatedBackup:url error:nil];if(row)[rows addObject:row];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"created"] compare:a[@"created"]];}];return rows;
}
- (NSDictionary *)backup:(NSString *)label error:(NSError **)error {
    if ([self gameIsRunning]) {Fail(error,@"Close the game before backing up or restoring progress.");return nil;}
    NSDictionary *files=Files(self.state,error);if(!files)return nil;
    if (!NoLinks(self.backupRoot)||!Directory(self.backupRoot,error))return nil;
    NSString *identifier=NSUUID.UUID.UUIDString;
    NSURL *pending=Child(self.backupRoot,[@".pending-" stringByAppendingString:identifier]);
    NSURL *complete=Child(self.backupRoot,identifier);
    if(!Directory(pending,error))return nil;
    for(NSString *name in Roots())if(Exists(Child(self.state,name))) {
        if(![FM() copyItemAtURL:Child(self.state,name) toURL:Child(pending,name) error:error])return nil;
    }
    NSDictionary *copied=Files(pending,error);
    if(!copied||![copied isEqual:files]){Fail(error,@"Progress changed during backup. No restore was attempted.");return nil;}
    for(NSURL *url in [FM() enumeratorAtURL:pending includingPropertiesForKeys:nil options:0 errorHandler:nil]) {
        BOOL isDirectory=NO;[FM() fileExistsAtPath:url.path isDirectory:&isDirectory];
        if(![FM() setAttributes:@{NSFilePosixPermissions:isDirectory?@0700:@0600} ofItemAtPath:url.path error:error])return nil;
    }
    NSDictionary *manifest=@{@"schema":@1,@"game":self.activeID,@"label":label,@"created":@(NSDate.date.timeIntervalSince1970),@"files":files};
    if(!WriteJSON(manifest,Child(pending,@"manifest.json"),error)||![self move:pending to:complete error:error])return nil;
    NSArray *snapshots=self.backups;
    // Delete only completed, hash-validated snapshots owned by this adapter.
    for(NSUInteger i=20;i<snapshots.count;i++)[FM() removeItemAtURL:[NSURL fileURLWithPath:snapshots[i][@"path"]] error:nil];
    return [self validatedBackup:complete error:error];
}
- (BOOL)move:(NSURL *)source to:(NSURL *)destination error:(NSError **)error { return [FM() moveItemAtURL:source toURL:destination error:error]; }
- (BOOL)restore:(NSDictionary *)snapshot error:(NSError **)error {
    if([self gameIsRunning])return Fail(error,@"Close the game before restoring progress.");
    if(![snapshot[@"path"] isKindOfClass:NSString.class])return Fail(error,@"Choose a local backup.");
    NSURL *source=[NSURL fileURLWithPath:snapshot[@"path"]];
    if(![self validatedBackup:source error:error]||!NoLinks(self.state)||!Directory(self.state,error))return NO;
    NSURL *transaction=Child(self.state,[@".native-play-restore-" stringByAppendingString:NSUUID.UUID.UUIDString]);
    NSURL *staged=Child(transaction,@"new"),*rollback=Child(transaction,@"previous");
    if(!Directory(staged,error)||!Directory(rollback,error))return NO;
    for(NSString *name in Roots())if(Exists(Child(source,name)))
        if(![FM() copyItemAtURL:Child(source,name) toURL:Child(staged,name) error:error])return NO;
    // Stage and hash-check first: the pre-restore backup may rotate the oldest snapshot.
    NSDictionary *stagedFiles=Files(staged,error);
    if(!stagedFiles || ![stagedFiles isEqual:snapshot[@"files"]])return Fail(error,@"Backup contents changed during staging.");
    if(![self backup:@"Before restore" error:error] || [self gameIsRunning])return NO;
    NSMutableArray *installed=[NSMutableArray new],*displaced=[NSMutableArray new];BOOL success=YES;
    for(NSString *name in Roots()) {
        if(Exists(Child(self.state,name))) {
            if(![self move:Child(self.state,name) to:Child(rollback,name) error:error]){success=NO;break;}
            [displaced addObject:name];
        }
        if(Exists(Child(staged,name))) {
            if(![self move:Child(staged,name) to:Child(self.state,name) error:error]){success=NO;break;}
            [installed addObject:name];
        }
    }
    if(!success) {
        for(NSString *name in installed.reverseObjectEnumerator)[FM() removeItemAtURL:Child(self.state,name) error:nil];
        BOOL recovered=YES;
        for(NSString *name in displaced.reverseObjectEnumerator)if(![FM() moveItemAtURL:Child(rollback,name) toURL:Child(self.state,name) error:nil])recovered=NO;
        if(!recovered)return Fail(error,@"Restore stopped. A verified pre-restore backup and the restore transaction were retained for recovery.");
    }
    if(success || !Exists(Child(rollback,@"save"))) [FM() removeItemAtURL:transaction error:nil];
    return success;
}
- (NSDictionary *)options {
    NSURL *path=Child(self.root,[@"LaunchOptions/" stringByAppendingFormat:@"%@.json",[self keyForGame:self.activeGame?:@{}]]);
    NSDictionary *value=NoLinks(path)?JSON(path):nil;
    if(![value isKindOfClass:NSDictionary.class]&&[self.activeID isEqual:@"0100965017338000"]&&NoLinks(Child(self.root,@"options.json")))value=JSON(Child(self.root,@"options.json"));
    if(![value isKindOfClass:NSDictionary.class])value=@{};
    return @{@"hud":@([value[@"hud"] isEqual:@YES]),@"record":@([value[@"record"] isEqual:@YES]),@"fullscreen":@([value[@"fullscreen"] isKindOfClass:NSNumber.class]?[value[@"fullscreen"] boolValue]:YES)};
}
- (void)setOptions:(NSDictionary *)options {NSURL *directory=Child(self.root,@"LaunchOptions");if(NoLinks(directory)&&Directory(directory,nil))WriteJSON(options,Child(directory,[[self keyForGame:self.activeGame?:@{}] stringByAppendingString:@".json"]),nil);}
- (NSString *)sandboxForSession:(NSURL *)session {
    NSMutableString *profile=[NSMutableString stringWithString:@"(version 1)\n(allow default)\n(deny network*)\n(deny file-write* (require-all\n"];
    for(NSURL *url in @[self.state,session]) [profile appendFormat:@" (require-not (subpath %@))\n",NPQuote(RulePath(url))];
    [profile appendString:@" (require-not (literal \"/dev/null\")) (require-not (literal \"/dev/tty\"))))\n(deny file-read*\n"];
    for(NSString *path in @[@".ssh",@".aws",@".config",@"Documents",@"Downloads",@"Desktop",@"Library/Keychains",@"Library/Mail",@"Library/Safari",@"Library/Application Support/Google",@"Library/Application Support/Firefox",@"JamboreeLab/secrets",@"JamboreeLab/inputs",@"JamboreeLab/deps",@"JamboreeLab/build"]) [profile appendFormat:@" (subpath %@)\n",NPQuote(RulePath(Child(self.home,path)))];
    [profile appendFormat:@" (subpath %@) (subpath \"/Volumes\") (literal %@))\n(deny mach-lookup (global-name \"com.apple.securityd\"))\n",NPQuote(RulePath(self.backupRoot)),NPQuote(RulePath(Child(self.root,@"probe-denied")))];
    return profile;
}
- (NSDictionary<NSString *,NSString *> *)environmentForSession:(NSURL *)session controllers:(BOOL)controllers {
    NSMutableDictionary *environment=[NSMutableDictionary dictionaryWithDictionary:@{@"HOME":self.home.path,@"PATH":@"/usr/bin:/bin:/usr/sbin:/sbin",@"LANG":@"en_US.UTF-8",@"TMPDIR":[Child(session,@"tmp").path stringByAppendingString:@"/"],@"CLANG_MODULE_CACHE_PATH":Child(self.state,@"native-play-clang-cache").path,@"DM_SCREEN_MATCH":@"0",@"DM_BOOTPROF":@"0",@"DM_NVN_FRAMES":@"0"}];
    if(controllers)environment[@"DM_CONTROLLER_SETUP"]=@"1";
    environment[@"DM_FULLSCREEN"]=[self.options[@"fullscreen"] boolValue]?@"1":@"0";
    environment[@"DM_STATE_DIR"]=self.state.path;
    environment[@"DM_SAVE"]=Child(self.state,@"save").path;
    environment[@"DM_TEMP"]=Child(self.state,@"temp").path;
    if([self.options[@"hud"] boolValue])environment[@"MTL_HUD_ENABLED"]=@"1";
    if([self.options[@"record"] boolValue]){environment[@"DM_NVN_TSV"]=Child(session,@"frames.tsv").path;environment[@"DM_NVN_TSV_CALLS"]=@"0";}
    return environment;
}
- (NSTask *)launch:(NSDictionary *)game controllers:(BOOL)controllers completion:(void (^)(int,NSURL *))completion error:(NSError **)error {
    NPStore *scoped=[[[self class] alloc]initWithRoot:self.root home:self.home];scoped.activeGame=game;
    return [scoped launchScoped:game controllers:controllers completion:completion error:error];
}
- (NSTask *)launchScoped:(NSDictionary *)game controllers:(BOOL)controllers completion:(void (^)(int,NSURL *))completion error:(NSError **)error {
    if([self gameIsRunning]){Fail(error,@"The game is already running. Return to it and press F2 for controllers.");return nil;}
    if(![self verifyGame:game error:error]||![self backup:@"Before play" error:error])return nil;
    if([self gameIsRunning]){Fail(error,@"Another game session started. Close it before launching again.");return nil;}
    NSURL *session=Child(self.root,[@"Sessions/" stringByAppendingString:NSUUID.UUID.UUIDString]);
    if(!Directory(Child(session,@"tmp"),error)||!Directory(self.state,error))return nil;
    NSURL *profile=Child(session,@"runtime.sb");
    if(![[self sandboxForSession:session] writeToURL:profile atomically:YES encoding:NSUTF8StringEncoding error:error])return nil;
    [@"Synthetic permission probe" writeToURL:Child(self.root,@"probe-denied") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // The same signed executable probes restrictions without reading a private file
    // or making an outbound connection (only a denied loopback socket attempt).
    if(!Command(@"/usr/bin/sandbox-exec",@[@"-f",profile.path,NSBundle.mainBundle.executablePath,@"--sandbox-probe",Child(self.root,@"probe-denied").path,Child(session,@"probe-allowed").path,Child(self.home,@".native-play-denied-write").path],nil,error))return nil;
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/sandbox-exec"];
    NSDictionary *launchInfo=[NSDictionary dictionaryWithContentsOfURL:Child([NSURL fileURLWithPath:game[@"path"]],@"Contents/Info.plist")];
    NSString *entry=game[@"executable"]?:[@"Contents/MacOS/" stringByAppendingString:launchInfo[@"CFBundleExecutable"]];
    task.arguments=@[@"-f",profile.path,[game[@"path"] stringByAppendingPathComponent:entry]];
    task.environment=[self environmentForSession:session controllers:controllers];task.currentDirectoryURL=self.state;
    BOOL recording=task.environment[@"DM_NVN_TSV"]!=nil,hud=task.environment[@"MTL_HUD_ENABLED"]!=nil;
    [FM() createFileAtPath:Child(session,@"launcher.log").path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
    NSFileHandle *log=[NSFileHandle fileHandleForWritingAtPath:Child(session,@"launcher.log").path];task.standardOutput=log;task.standardError=log;
    task.terminationHandler=^(NSTask *finished){[log closeFile];NPProfileSummary(session);WriteJSON(@{@"status":@(finished.terminationStatus),@"finished":@(NSDate.date.timeIntervalSince1970)},Child(session,@"result.json"),nil);NPPruneSessions(self.root);completion(finished.terminationStatus,session);};
    if(![task launchAndReturnError:error])return nil;
    WriteJSON(@{@"game":game[@"id"],@"app_key":[self keyForGame:game],@"started":@(NSDate.date.timeIntervalSince1970),@"network_denied":@YES,@"hud":@(hud),@"record":@(recording)},Child(session,@"session.json"),nil);
    if(recording){NSMutableDictionary *options=[self.options mutableCopy];options[@"record"]=@NO;[self setOptions:options];}
    return task;
}
@end
