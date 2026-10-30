// Local-only persistence regression; the caller supplies a private test folder.
#include "../runtime/host/controller_settings.h"
#include <dirent.h>
#include <string.h>
#include <sys/stat.h>
static int checks,failures;
#define CHECK(c,s) do{checks++;if(!(c)){failures++;fprintf(stderr,"FAIL: %s\n",s);}}while(0)
static int contents(const char *path,const char *expected){FILE *f=fopen(path,"rb");if(!f)return 0;char b[256]={0};size_t n=fread(b,1,sizeof b-1,f);fclose(f);return n==strlen(expected)&&!strcmp(b,expected);}
int main(int argc,char **argv){
    if(argc!=2)return 2;char dir[PATH_MAX],path[PATH_MAX],target[PATH_MAX];
    int n=snprintf(dir,sizeof dir,"%s/controller-prefs-XXXXXX",argv[1]);if(n<0||(size_t)n>=sizeof dir||!mkdtemp(dir))return 2;
    n=snprintf(path,sizeof path,"%s/controller-layout.txt",dir);if(n<0||(size_t)n>=sizeof path)return 2;
    n=snprintf(target,sizeof target,"%s/untouched.txt",dir);if(n<0||(size_t)n>=sizeof target)return 2;
    const char *old="layout=auto\n",*new="layout=auto\nplayer_1_layout=2\nplayer_1_swap_xy=1\nplayer_2_swap_ab=1\nplayer_2_swap_xy=1\n";
    CHECK(dm_controller_settings_write(path,old,strlen(old))&&contents(path,old),"initial local settings save");
    CHECK(dm_controller_settings_write(path,new,strlen(new))&&contents(path,new),"atomic replacement preserves per-player preferences");
    struct stat st;CHECK(!stat(path,&st)&&(st.st_mode&0777)==0600,"saved settings are private");
    CHECK(dm_controller_settings_write(target,old,strlen(old)),"create a protected destination witness");
    unlink(path);CHECK(!symlink(target,path),"install a destination symlink fixture");
    CHECK(dm_controller_settings_write(path,new,strlen(new))&&contents(target,old)&&!lstat(path,&st)&&S_ISREG(st.st_mode),"replacement does not follow a destination symlink");
    chmod(dir,0500);CHECK(!dm_controller_settings_write(path,old,strlen(old))&&contents(path,new),"failed replacement preserves the previous settings");chmod(dir,0700);
    DIR *d=opendir(dir);int temporary=0;struct dirent *entry;while(d&&(entry=readdir(d)))temporary+=strstr(entry->d_name,".tmp.")!=NULL;if(d)closedir(d);
    CHECK(!temporary,"no temporary settings files remain");
    CHECK(!dm_controller_settings_write("",old,strlen(old))&&errno==EINVAL,"invalid destination fails closed");
    unlink(path);unlink(target);rmdir(dir);printf("controller settings: %d checks, %d failed\n",checks,failures);return failures?1:0;
}
