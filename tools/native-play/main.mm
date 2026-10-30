// Objective-C++ is the Cocoa bridge for this C/C++ native-game library.
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "NPApp.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>

static NSColor *Color(CGFloat r,CGFloat g,CGFloat b){return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];}
static NSColor *Ink(void){return Color(.065,.075,.09);}
static NSColor *Mint(void){return Color(.43,.96,.74);}
static int Probe(int argc,const char **argv){
    if(argc!=5)return 2;
    int fd=open(argv[2],O_RDONLY);if(fd>=0){close(fd);return 3;}if(errno!=EPERM && errno!=EACCES)return 4;
    fd=open(argv[4],O_WRONLY|O_CREAT|O_EXCL,0600);if(fd>=0){close(fd);unlink(argv[4]);return 5;}if(errno!=EPERM && errno!=EACCES)return 6;
    fd=open(argv[3],O_WRONLY|O_CREAT|O_EXCL,0600);if(fd<0)return 7;close(fd);unlink(argv[3]);
    int s=socket(AF_INET,SOCK_STREAM,0);if(s<0)return (errno==EPERM || errno==EACCES)?0:8;
    struct sockaddr_in address={.sin_len=sizeof address,.sin_family=AF_INET,.sin_port=htons(9),.sin_addr={htonl(INADDR_LOOPBACK)}};
    int result=connect(s,(struct sockaddr *)&address,sizeof address),failure=errno;close(s);
    return result<0&&(failure==EPERM||failure==EACCES)?0:9;
}
static void Icon(NSString *path){
    NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(1024,1024)];[image lockFocus];
    [Ink() setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0,0,1024,1024) xRadius:220 yRadius:220]fill];
    [Mint() setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(188,215,285,594) xRadius:140 yRadius:140]fill];
    [Color(.22,.48,.58) setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(551,215,285,594) xRadius:140 yRadius:140]fill];
    [Ink() setFill];[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(270,537,120,120)]fill];
    [Mint() setFill];for(NSUInteger i=0;i<4;i++)[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(625+(i%2)*54,340+(i/2)*54,32,32)]fill];
    [image unlockFocus];NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc]initWithData:image.TIFFRepresentation];[[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];
}
int main(int argc,const char **argv){@autoreleasepool{
    umask(0077);
    if(argc>1&&!strcmp(argv[1],"--sandbox-probe"))return Probe(argc,argv);
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    if(argc==3&&!strcmp(argv[1],"--render-icon")){Icon(@(argv[2]));return 0;}
    NSArray *args=NSProcessInfo.processInfo.arguments;BOOL test=[args containsObject:@"--ui-test"],launchCheck=[args containsObject:@"--launch-check"],preview=test||launchCheck||[args containsObject:@"--preview"];
    NSURL *home=[NSURL fileURLWithPath:NSHomeDirectory()];
    if(preview){NSURL *temporary=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByResolvingSymlinksInPath];home=[temporary URLByAppendingPathComponent:[@"native-play-preview-" stringByAppendingString:NSUUID.UUID.UUIDString]];}
    NPStore *store=[[(preview?NPPreviewStore.class:NPStore.class) alloc]initWithRoot:[home URLByAppendingPathComponent:@"Library/Application Support/Native Play"] home:home];if(!store){fputs("Could not create private Native Play support directories.\n",stderr);return 1;}
    if(argc==3&&launchCheck){
        NSURL *documents=[home URLByAppendingPathComponent:@"Documents"];[NSFileManager.defaultManager createDirectoryAtURL:documents withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"synthetic protected input" writeToURL:[documents URLByAppendingPathComponent:@"blocked"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSError *error=nil;NSDictionary *game=[store importApp:[NSURL fileURLWithPath:@(argv[2])] error:&error];
        dispatch_semaphore_t done=dispatch_semaphore_create(0);__block int status=-2;__block NSURL *completed=nil;
        NPGameSession *task=game?[store launch:game controllers:NO completion:^(int result,NSURL *session){completed=session;status=result;dispatch_semaphore_signal(done);} error:&error]:nil;
        if(!task){fprintf(stderr,"Fixture launch failed: %s\n",error.localizedDescription.UTF8String);return 1;}
        if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))){[task terminate];return 2;}
        NSString *receipt=[NSString stringWithContentsOfURL:[completed URLByAppendingPathComponent:@"fixture-passed"] encoding:NSUTF8StringEncoding error:NULL];
        if(status!=0&&!(status==-1&&[receipt isEqual:@"restricted-bundled-fixture-passed"])){fprintf(stderr,"Fixture restriction checks failed: %d\n",status);return 3;}
        puts("Signed fixture verified: network denied, protected reads denied, session writes allowed; required app identity preserved.");
        [NSFileManager.defaultManager removeItemAtURL:home error:NULL];return 0;
    }
    if(argc==3&&!strcmp(argv[1],"--register")){NSError *error=nil;if(![store importApp:[NSURL fileURLWithPath:@(argv[2])] error:&error]){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}puts("Signed native app registered locally.");return 0;}
    if(argc==2&&!strcmp(argv[1],"--backup")){NSError *error=nil;NSDictionary *snapshot=[store backup:@"Manual backup" error:&error];if(!snapshot){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}printf("Backed up and verified %lu private state files locally.\n",(unsigned long)[snapshot[@"files"] count]);return 0;}
    if(preview){
        for(NSDictionary *game in NPPreviewGames()){
            store.activeGame=game;
            NSURL *save=[store.state URLByAppendingPathComponent:@"save"];
            [NSFileManager.defaultManager createDirectoryAtURL:save withIntermediateDirectories:YES attributes:nil error:NULL];
            [@"synthetic progress" writeToURL:[save URLByAppendingPathComponent:@"preview"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            for(NSString *label in @[@"Before play",@"Manual backup"]){NSError *error=nil;if(![store backup:label error:&error]){fprintf(stderr,"Preview setup failed: %s\n",error.localizedDescription.UTF8String);return 1;}}
        }
        store.activeGame=NPPreviewGames().firstObject;
    }
    if(!preview)for(NSRunningApplication *running in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"org.macnativegames.native-play"])if(running.processIdentifier!=getpid()){[running activateWithOptions:0];return 0;}
    NPApp *delegate=[NPApp new];delegate.store=store;delegate.preview=preview;delegate.test=test;
    NSUInteger index=[args indexOfObject:@"--ui-snapshot"];if(index!=NSNotFound && index+1<args.count && preview)delegate.snapshotPath=args[index+1];
    NSApp.delegate=delegate;[NSApp run];return 0;
}}
