// Content-free process fixture: execute only through the launcher's test adapter.
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

int main(void) {
    char path[4096];
    const char *home=getenv("HOME"),*temporary=getenv("TMPDIR");
    if(!home||!temporary||getenv("DM_NVN_TSV")||getenv("MTL_DEBUG_LAYER"))return 1;
    if(snprintf(path,sizeof path,"%s/Documents/blocked",home)>=(int)sizeof path)return 2;
    FILE *file=fopen(path,"rb");if(file){fclose(file);return 3;}
    if(errno!=EPERM&&errno!=EACCES)return 4;
    if(snprintf(path,sizeof path,"%sallowed",temporary)>=(int)sizeof path)return 5;
    file=fopen(path,"wb");if(!file)return 6;fputs("synthetic",file);fclose(file);
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return (errno==EPERM||errno==EACCES)?0:7;
    struct sockaddr_in address={.sin_len=sizeof address,.sin_family=AF_INET,.sin_port=htons(9),.sin_addr={htonl(INADDR_LOOPBACK)}};
    int result=connect(fd,(struct sockaddr *)&address,sizeof address),failure=errno;close(fd);
    return result<0&&(failure==EPERM||failure==EACCES)?0:8;
}
