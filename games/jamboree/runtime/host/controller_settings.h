// Atomic local preferences: create the temporary file beside the destination.
// Foundation's atomic writer uses operations rejected by the runtime sandbox.
#pragma once
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int dm_controller_settings_write(const char *path, const void *bytes, size_t length) {
    if (!path || !*path || (!bytes && length)) { errno=EINVAL;return 0; }
    char temporary[PATH_MAX];int n=snprintf(temporary,sizeof temporary,"%s.tmp.XXXXXX",path);
    if(n<0 || (size_t)n>=sizeof temporary){errno=ENAMETOOLONG;return 0;}
    int fd=mkstemp(temporary);if(fd<0)return 0;
    const unsigned char *p=bytes;size_t left=length;int error=0;
    while(left){ssize_t wrote=write(fd,p,left);if(wrote<0&&errno==EINTR)continue;if(wrote<=0){error=wrote<0?errno:EIO;break;}p+=wrote;left-=(size_t)wrote;}
    if(!error && fsync(fd))error=errno;
    if(close(fd) && !error)error=errno;
    if(!error && rename(temporary,path))error=errno;
    if(error){unlink(temporary);errno=error;return 0;}
    return 1;
}
