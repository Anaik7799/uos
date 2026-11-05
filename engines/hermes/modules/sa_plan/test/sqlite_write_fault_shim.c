#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <errno.h>
/* PRIVATE test-only POSIX failure shim. Never linked into product libraries
 * or selected by a product environment variable. Tests explicitly LD_PRELOAD
 * this DSO into a disposable child. Production finite launch scrubs preload.
 * Deliberately violates trusted-runtime premise to test error propagation. */
static _Atomic int fired;
static int role(int fd){char key[64],path[4096];int n=snprintf(key,sizeof key,"/proc/self/fd/%d",fd);if(n<1||n>=(int)sizeof key)return 0;
 ssize_t k=syscall(SYS_readlink,key,path,sizeof path-1);if(k<=0||k>=(ssize_t)sizeof path-1)return 0;path[k]=0;
 if(strncmp(path,"/tmp/uos-write-vfs-test-",24))return 0;
 size_t len=(size_t)k;const char*base="/tasks.sqlite3";size_t bl=strlen(base);
 if(len>=bl&&!strcmp(path+len-bl,base))return 1;
 const char*wal="/tasks.sqlite3-wal";size_t wl=strlen(wal);
 if(len>=wl&&!strcmp(path+len-wl,wal))return 2;
 const char*shm="/tasks.sqlite3-shm";size_t sl=strlen(shm);
 return len>=sl&&!strcmp(path+len-sl,shm)?3:0;
}
static const char*selection(void){const char*a=getenv("UOS_PRIVATE_WRITE_ARMED");if(!a||strcmp(a,"1"))return "";const char*s=getenv("UOS_PRIVATE_WRITE_FAULT");return s&&strlen(s)<64?s:"";}
static int take(const char*name,int fd,int expected){return !strcmp(selection(),name)&&role(fd)==expected&&!atomic_exchange(&fired,1);}
static void note(const char*kind){dprintf(2,"PRIVATE_POSIX_FAULT %s\n",kind);}
static int after_success_allowed(int rc){return rc==0;}
ssize_t pwrite64(int fd,const void*p,size_t n,off64_t off){
 ssize_t(*real)(int,const void*,size_t,off64_t)=dlsym(RTLD_NEXT,"pwrite64");if(!real){errno=EIO;return -1;}
 if(take("wal-write-eio",fd,2)){note("wal-write-eio");errno=EIO;return -1;}
 if(take("wal-write-short",fd,2)){note("wal-write-short");return real(fd,p,n>1?n/2:0,off);}
 ssize_t rc=real(fd,p,n,off);
 if(take("kill-after-wal-write",fd,2)){note("kill-after-wal-write");kill(getpid(),SIGKILL);_exit(97);}return rc;
}
static int sync_call(int fd,const char*name){int(*real)(int)=dlsym(RTLD_NEXT,name);if(!real){errno=EIO;return -1;}
 if(take("wal-sync-eio",fd,2)){note("wal-sync-eio");errno=EIO;return -1;}
 if(take("kill-before-wal-sync",fd,2)){note("kill-before-wal-sync");kill(getpid(),SIGKILL);_exit(97);}
 if(take("wal-sync-real-failure-control",fd,2)){
  /* Actual EBADF from the real sync, not an invented success observation.
   * This intentionally violates FD ownership only inside a private fault. */
  if(syscall(SYS_close,fd)!=0){note("control-close-failed");errno=EIO;return -1;}
  int rc=real(fd);
  if(after_success_allowed(rc)){note("ERROR-failed-sync-classified-success");errno=EIO;return -1;}
  note("wal-sync-real-failure-control");dprintf(2,"REAL_SYNC_FAILED_NO_AFTER_SUCCESS rc=%d\n",rc);return rc;
 }
 int rc=real(fd);
 if(take("wal-sync-after-success-eio",fd,2)){
  if(!after_success_allowed(rc)){note("real-sync-failed-not-after-success");return rc;}
  note("wal-sync-after-success-eio");note("CONFIRMED_REAL_SYNC_SUCCESS");errno=EIO;return -1;}
 if(take("kill-after-wal-sync",fd,2)){
  if(!after_success_allowed(rc)){note("real-sync-failed-not-after-success");return rc;}
  note("kill-after-wal-sync");note("CONFIRMED_REAL_SYNC_SUCCESS");kill(getpid(),SIGKILL);_exit(97);}return rc;
}
int fsync(int fd){return sync_call(fd,"fsync");}
int fdatasync(int fd){return sync_call(fd,"fdatasync");}
int ftruncate64(int fd,off64_t n){int(*real)(int,off64_t)=dlsym(RTLD_NEXT,"ftruncate64");if(!real){errno=EIO;return -1;}
 if(take("main-truncate-eio",fd,1)){note("main-truncate-eio");errno=EIO;return -1;}return real(fd,n);
}
int close(int fd){int(*real)(int)=dlsym(RTLD_NEXT,"close");if(!real){errno=EIO;return -1;}
 if(take("main-close-eio",fd,1)){note("main-close-eio");errno=EIO;return -1;}return real(fd);
}
