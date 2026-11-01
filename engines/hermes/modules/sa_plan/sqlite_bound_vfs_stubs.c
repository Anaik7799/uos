#define _GNU_SOURCE
#include <sqlite3.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <sys/syscall.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <stdatomic.h>
#if !defined(__linux__) || !defined(__x86_64__) || SQLITE_VERSION_NUMBER!=3053003
#error "Pinned Linux x86_64 SQLite 3.53.3 only"
#endif
/* EXPERIMENTAL read-only, dedicated-process VFS. Native process/VFS code and
 * the absence of other SQLite connections or closes of these inodes are TRUST
 * PREMISES, not proved by this module. POSIX locks are process/inode scoped.
 * No Store mutation, raw DB export, issuer, authority or production adapter.
 * SHM mappings are writable: READONLY SQL is not filesystem-readonly. */
#define FD_CAP 32
#define HOOKS 11
static const char *names[HOOKS]={"open","close","fcntl","fstat","pread64","pwrite64","mmap","unlink","ftruncate","fchmod","fchown"};
static sqlite3_syscall_ptr old_hooks[HOOKS],new_hooks[HOOKS];
static _Atomic int reserved;
static struct {
 int used,closed,installed,dir,held[3],fd[FD_CAP],role[FD_CAP],created;
 _Atomic int poisoned;
 unsigned count,opens[3],closes[3],reads[3],maps[3],locks[3],rw_fallback,entropy;
 pid_t owner;pthread_t thread;struct stat identity[3];char paths[4][4096];
 sqlite3 *db;sqlite3_vfs *base,*prior_default,wrapper;sqlite3_int64 schema_entries;
} g;
/* Status 0 okay,1 refused,2 unsupported,3 ownership,4 closed,5 poisoned,6 IO. */
static int owned(void){return getpid()==g.owner&&pthread_equal(pthread_self(),g.thread);}
static int reject(void){errno=EACCES;return -1;}
static int identity_same(const struct stat*a,const struct stat*b){return a->st_dev==b->st_dev&&a->st_ino==b->st_ino&&a->st_uid==b->st_uid&&a->st_gid==b->st_gid&&a->st_mode==b->st_mode&&a->st_nlink==1&&b->st_nlink==1;}
static int valid_file(const struct stat*s,int r){return S_ISREG(s->st_mode)&&s->st_uid==geteuid()&&s->st_nlink==1&&(s->st_mode&0777)==0600&&(uint64_t)s->st_dev<=INT64_MAX&&s->st_ino>0&&(uint64_t)s->st_ino<=INT64_MAX&&s->st_size>=(r==0?4096:r==1?32:32768)&&s->st_size<=(r==2?1048576:33554432);}
static int role_of_path(const char*p){if(!p)return -1;for(int i=0;i<3;i++)if(!strcmp(p,g.paths[i]))return i;return -1;}
static int role_of_fd(int fd){for(unsigned i=0;i<g.count;i++)if(g.fd[i]==fd)return g.role[i];return -1;}
static int check_fd(int fd,int r){struct stat s;return r>=0&&fstat(fd,&s)==0&&valid_file(&s,r)&&identity_same(&s,&g.identity[r]);}
static int io_ok(int fd){return owned()&&!g.poisoned&&check_fd(fd,role_of_fd(fd));}
static int bound_open(const char*p,int flags,...){
 if(!owned()||g.poisoned||g.count>=FD_CAP)return reject();
 int r=role_of_path(p);
 int allowed=O_ACCMODE|O_CREAT|O_CLOEXEC|O_NOFOLLOW|O_LARGEFILE;
 if(r<0||(flags&~allowed)||(flags&O_ACCMODE)==O_WRONLY||g.opens[r]>0)return reject();
 int access=fcntl(g.held[r],F_GETFL);if(access<0)return reject();
 if((flags&O_ACCMODE)==O_RDWR&&(access&O_ACCMODE)!=O_RDWR){if(r==1)g.rw_fallback++;return reject();}
 if((flags&O_CREAT)&&r!=1&&r!=2)return reject();
 if(!check_fd(g.held[r],r))return reject();
 int fd=fcntl(g.held[r],F_DUPFD_CLOEXEC,3);if(fd<0)return -1;
 if(!check_fd(fd,r)){int saved=errno;close(fd);errno=saved;return reject();}
 g.fd[g.count]=fd;g.role[g.count++]=r;g.opens[r]++;return fd;
}
static int bound_close(int fd){
 if(!owned()){g.poisoned=1;return reject();}
 unsigned i;for(i=0;i<g.count;i++)if(g.fd[i]==fd)break;
 if(i==g.count||!check_fd(fd,g.role[i])){g.poisoned=1;return reject();}
 int rc=((int(*)(int))old_hooks[1])(fd);
 if(rc){g.poisoned=1;return rc;}g.closes[g.role[i]]++;g.fd[i]=-1;return 0;
}
static int bound_fstat(int fd,struct stat*s){if(!io_ok(fd))return reject();return ((int(*)(int,struct stat*))old_hooks[3])(fd,s);}
static ssize_t bound_pread(int fd,void*p,size_t n,off_t off){if(!io_ok(fd)||n>1048576||off<0)return reject();g.reads[role_of_fd(fd)]++;return ((ssize_t(*)(int,void*,size_t,off_t))old_hooks[4])(fd,p,n,off);}
static ssize_t bound_pwrite(int fd,const void*p,size_t n,off_t off){(void)fd;(void)p;(void)n;(void)off;return reject();}
static void *bound_mmap(void*p,size_t n,int prot,int flags,int fd,off_t off){
 int r=role_of_fd(fd);if(!io_ok(fd)||n==0||n>33554432||off<0||(uint64_t)off>UINT64_MAX-n||flags!=MAP_SHARED||(prot&~(PROT_READ|PROT_WRITE))||(r!=2&&(prot&PROT_WRITE))){errno=EACCES;return MAP_FAILED;}
 struct stat s;if(fstat(fd,&s)||(uint64_t)off+n>(uint64_t)s.st_size){errno=EACCES;return MAP_FAILED;}
 g.maps[r]++;return ((void*(*)(void*,size_t,int,int,int,off_t))old_hooks[6])(p,n,prot,flags,fd,off);
}
static int bound_fcntl(int fd,int command,...){
 if(!io_ok(fd))return reject();
 va_list a;va_start(a,command);int rc;
 switch(command){
 case F_GETFD:case F_GETFL:rc=((int(*)(int,int,...))old_hooks[2])(fd,command);break;
 case F_SETFD:{int value=va_arg(a,int);rc=value==FD_CLOEXEC?((int(*)(int,int,...))old_hooks[2])(fd,command,value):reject();break;}
 case F_SETLK:case F_GETLK:{struct flock*l=va_arg(a,struct flock*);if(!l||l->l_whence!=SEEK_SET||l->l_start<0||l->l_len<0||(l->l_type!=F_RDLCK&&l->l_type!=F_WRLCK&&l->l_type!=F_UNLCK))rc=reject();else{g.locks[role_of_fd(fd)]++;rc=((int(*)(int,int,...))old_hooks[2])(fd,command,l);}break;}
 default:rc=reject();}
 va_end(a);return rc;
}
static int bound_unlink(const char*p){(void)p;g.poisoned=1;return reject();}
static int bound_truncate(int fd,off_t n){(void)fd;(void)n;g.poisoned=1;return reject();}
static int bound_chmod(int fd,mode_t mode){(void)fd;(void)mode;g.poisoned=1;return reject();}
static int bound_chown(int fd,uid_t u,gid_t gr){(void)fd;(void)u;(void)gr;g.poisoned=1;return reject();}
static int entropy(sqlite3_vfs*v,int n,char*p){(void)v;if(!owned()||g.poisoned||n<0||n>256)return 0;int used=0;
 for(unsigned attempt=0;used<n&&attempt<16;attempt++){ssize_t k=getrandom(p+used,(size_t)(n-used),GRND_NONBLOCK);if(k<0){if(errno==EINTR)continue;g.poisoned=1;return 0;}if(!k){g.poisoned=1;return 0;}used+=(int)k;}
 if(used!=n){g.poisoned=1;return 0;}g.entropy++;return used;
}
static int wrapper_open(sqlite3_vfs*v,const char*p,sqlite3_file*f,int flags,int*out){(void)v;
 /* Unix WAL xOpen receives CREATE/RW even for a read-only main. Only the
  * existing retained WAL can be returned; its RW attempt is refused inside
  * bound_open, letting pinned Unix VFS perform the observed RO retry. */
 int r=role_of_path(p);if(!owned()||g.poisoned||r<0||r==2||(flags&SQLITE_OPEN_DELETEONCLOSE)||(r==0&&((flags&SQLITE_OPEN_CREATE)||!(flags&SQLITE_OPEN_MAIN_DB)||!(flags&SQLITE_OPEN_READONLY)))||(r==1&&!(flags&SQLITE_OPEN_WAL)))return SQLITE_CANTOPEN;
 return g.base->xOpen(g.base,p,f,flags,out);
}
static int wrapper_access(sqlite3_vfs*v,const char*p,int flags,int*out){(void)v;if(!owned()||g.poisoned)return SQLITE_IOERR_ACCESS;
 int r=role_of_path(p);if(r<0){if(p&&!strcmp(p,g.paths[3])){*out=0;return SQLITE_OK;}return SQLITE_IOERR_ACCESS;}
 if(flags!=SQLITE_ACCESS_EXISTS&&flags!=SQLITE_ACCESS_READ&&flags!=SQLITE_ACCESS_READWRITE)return SQLITE_IOERR_ACCESS;
 *out=check_fd(g.held[r],r)&&(flags!=SQLITE_ACCESS_READWRITE||r==2);return SQLITE_OK;
}
static int wrapper_full(sqlite3_vfs*v,const char*p,int n,char*out){(void)v;int r=role_of_path(p);if(!owned()||r<0||n<=0||(size_t)n<=strlen(p))return SQLITE_CANTOPEN;memcpy(out,p,strlen(p)+1);return SQLITE_OK;}
static int wrapper_delete(sqlite3_vfs*v,const char*p,int sync){(void)v;(void)p;(void)sync;g.poisoned=1;return SQLITE_IOERR_DELETE;}
static void *wrapper_dl(sqlite3_vfs*v,const char*p){(void)v;(void)p;g.poisoned=1;return NULL;}
static int runtime_ok(void){Dl_info base,one;if(sqlite3_libversion_number()!=3053003||strcmp(sqlite3_sourceid(),SQLITE_SOURCE_ID)||!dladdr((void*)sqlite3_libversion,&base))return 0;
 void *symbols[]={(void*)sqlite3_open_v2,(void*)sqlite3_prepare_v2,(void*)sqlite3_step,(void*)sqlite3_vfs_find,(void*)sqlite3_vfs_register,(void*)sqlite3_close};
 for(unsigned i=0;i<sizeof symbols/sizeof symbols[0];i++)if(!dladdr(symbols[i],&one)||one.dli_fbase!=base.dli_fbase)return 0;
 return 1;
}
static int hooks_intact(void){
 if(!g.installed||sqlite3_vfs_find(NULL)!=&g.wrapper)return 0;
 for(int i=0;i<HOOKS;i++)if(g.base->xGetSystemCall(g.base,names[i])!=new_hooks[i])return 0;
 return 1;
}
static int finish(void){
 if(!owned())return 3;
 if(g.closed)return g.poisoned?5:0;
 if(g.installed&&!hooks_intact()){g.poisoned=1;return 5;}
 if(g.db){int rc=sqlite3_close(g.db);if(rc!=SQLITE_OK){g.poisoned=1;return 5;}g.db=NULL;}
 for(unsigned i=0;i<g.count;i++)if(g.fd[i]>=0){g.poisoned=1;return 5;}
 if(g.installed){
  if(sqlite3_vfs_find(NULL)!=&g.wrapper){g.poisoned=1;return 5;}
  for(int i=0;i<HOOKS;i++)if(g.base->xGetSystemCall(g.base,names[i])!=new_hooks[i]){g.poisoned=1;return 5;}
  for(int i=0;i<HOOKS;i++)if(g.base->xSetSystemCall(g.base,names[i],old_hooks[i])!=SQLITE_OK){g.poisoned=1;return 5;}
  if(sqlite3_vfs_register(g.prior_default,1)!=SQLITE_OK||sqlite3_vfs_unregister(&g.wrapper)!=SQLITE_OK){g.poisoned=1;return 5;}
  g.installed=0;
 }
 for(int i=0;i<3;i++)if(g.held[i]>=0){if(close(g.held[i]))g.poisoned=1;g.held[i]=-1;}
 if(g.dir>=0){if(close(g.dir))g.poisoned=1;g.dir=-1;}g.closed=1;return g.poisoned?5:0;
}
static int scalar(const char*sql,int text,sqlite3_int64*out){sqlite3_stmt*st=NULL;int good=sqlite3_prepare_v2(g.db,sql,-1,&st,NULL)==SQLITE_OK;
 if(good){good=sqlite3_step(st)==SQLITE_ROW;if(good){if(text){const unsigned char*s=sqlite3_column_text(st,0);good=s&&!strcmp((const char*)s,"wal");}else *out=sqlite3_column_int64(st,0);}if(good)good=sqlite3_step(st)==SQLITE_DONE;}
 if(st&&sqlite3_finalize(st)!=SQLITE_OK)good=0;
 return good;
}
CAMLprim value caml_uos_bound_vfs_reserve(value unit){
 (void)unit;int zero=0;
 if(atomic_load(&g.poisoned))return Val_int(5);
 if(!atomic_compare_exchange_strong(&reserved,&zero,1))return Val_int(1);
 g.owner=getpid();g.thread=pthread_self();return Val_int(0);
}
CAMLprim value caml_uos_bound_vfs_open(value directory,value basename,value expected){
 CAMLparam3(directory,basename,expected);int status=1;
 if(!atomic_load(&reserved)||!owned())CAMLreturn(Val_int(3));
 if(g.used)CAMLreturn(Val_int(g.poisoned?5:1));
 g.used=1;g.dir=-1;for(int i=0;i<3;i++)g.held[i]=-1;
 if(!runtime_ok())CAMLreturn(Val_int(2));
 const char*d=String_val(directory),*b=String_val(basename);size_t dl=caml_string_length(directory),bl=caml_string_length(basename);
 if(dl<2||dl>3900||d[0]!='/'||memchr(d,0,dl)||!bl||bl>128||memchr(b,0,bl)||Wosize_val(expected)!=3)goto fail;
 for(size_t i=0;i<bl;i++)if(!((b[i]>='a'&&b[i]<='z')||(b[i]>='A'&&b[i]<='Z')||(b[i]>='0'&&b[i]<='9')||b[i]=='_'||b[i]=='-'||b[i]=='.'))goto fail;
 if(!strcmp(b,".")||!strcmp(b,".."))goto fail;
 g.dir=open(d,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);struct stat ds;
 if(g.dir<0||fstat(g.dir,&ds)||ds.st_uid!=geteuid()||(ds.st_mode&0777)!=0700)goto fail;
 const char*suffix[]={"","-wal","-shm","-journal"};
 for(int i=0;i<4;i++)if(snprintf(g.paths[i],4096,"%s/%s%s",d,b,suffix[i])>=4096)goto fail;
 struct stat unexpected;if(fstatat(g.dir,strrchr(g.paths[3],'/')+1,&unexpected,AT_SYMLINK_NOFOLLOW)==0||errno!=ENOENT)goto fail;
 for(int i=0;i<3;i++){
  g.held[i]=openat(g.dir,strrchr(g.paths[i],'/')+1,(i==2?O_RDWR:O_RDONLY)|O_NOFOLLOW|O_CLOEXEC);
  value pair=Field(expected,i);if(g.held[i]<0||fstat(g.held[i],&g.identity[i])||!valid_file(&g.identity[i],i)||Int64_val(Field(pair,0))<0||Int64_val(Field(pair,1))<=0||(uint64_t)Int64_val(Field(pair,0))!=(uint64_t)g.identity[i].st_dev||(uint64_t)Int64_val(Field(pair,1))!=(uint64_t)g.identity[i].st_ino)goto fail;
  for(int j=0;j<i;j++)if(g.identity[i].st_dev==g.identity[j].st_dev&&g.identity[i].st_ino==g.identity[j].st_ino)goto fail;
 }
 g.base=sqlite3_vfs_find("unix");g.prior_default=sqlite3_vfs_find(NULL);
 if(!g.base||g.base!=g.prior_default||g.base->iVersion!=3||!g.base->xGetSystemCall||!g.base->xSetSystemCall){status=2;goto fail;}
 sqlite3_syscall_ptr hooks[HOOKS]={(sqlite3_syscall_ptr)bound_open,(sqlite3_syscall_ptr)bound_close,(sqlite3_syscall_ptr)bound_fcntl,(sqlite3_syscall_ptr)bound_fstat,(sqlite3_syscall_ptr)bound_pread,(sqlite3_syscall_ptr)bound_pwrite,(sqlite3_syscall_ptr)bound_mmap,(sqlite3_syscall_ptr)bound_unlink,(sqlite3_syscall_ptr)bound_truncate,(sqlite3_syscall_ptr)bound_chmod,(sqlite3_syscall_ptr)bound_chown};
 for(int i=0;i<HOOKS;i++){old_hooks[i]=g.base->xGetSystemCall(g.base,names[i]);new_hooks[i]=hooks[i];if(!old_hooks[i]){status=2;goto fail;}}
 /* No connection exists yet. Failed partial hook installation is terminal;
  * retain the static context and FDs, never free a live hook's state. */
 for(int i=0;i<HOOKS;i++)if(g.base->xSetSystemCall(g.base,names[i],new_hooks[i])!=SQLITE_OK){g.poisoned=1;CAMLreturn(Val_int(5));}
 g.wrapper=*g.base;g.wrapper.zName="uos-bound-readonly-v1";g.wrapper.pNext=NULL;g.wrapper.xOpen=wrapper_open;g.wrapper.xAccess=wrapper_access;g.wrapper.xFullPathname=wrapper_full;g.wrapper.xDelete=wrapper_delete;g.wrapper.xDlOpen=wrapper_dl;g.wrapper.xRandomness=entropy;
 if(sqlite3_vfs_register(&g.wrapper,1)!=SQLITE_OK){g.poisoned=1;CAMLreturn(Val_int(5));}g.installed=1;
 g.created=1;if(sqlite3_open_v2(g.paths[0],&g.db,SQLITE_OPEN_READONLY|SQLITE_OPEN_FULLMUTEX|SQLITE_OPEN_PRIVATECACHE,g.wrapper.zName)!=SQLITE_OK)goto fail;
 g.created=2;if(sqlite3_db_readonly(g.db,"main")!=1||sqlite3_busy_timeout(g.db,0)!=SQLITE_OK||sqlite3_exec(g.db,"BEGIN",NULL,NULL,NULL)!=SQLITE_OK)goto fail;
 g.created=3;if(!scalar("SELECT count(*) FROM sqlite_schema",0,&g.schema_entries))goto fail;
 g.created=4;if(!scalar("PRAGMA journal_mode",1,NULL)||g.poisoned)goto fail;
 g.created=5;
 for(int i=0;i<3;i++)if(g.opens[i]!=1||!check_fd(g.held[i],i))goto fail;
 if(!g.entropy||!g.reads[0]||!g.reads[1]||!g.maps[2])goto fail;
 CAMLreturn(Val_int(0));
fail:if(finish()!=0)status=5;CAMLreturn(Val_int(status));
}
CAMLprim value caml_uos_bound_vfs_snapshot(value unit){
 CAMLparam1(unit);CAMLlocal2(array,n);
 int status=!owned()?3:g.poisoned?5:g.closed?4:0;
 if(!status){if(!hooks_intact()){g.poisoned=1;status=5;}
  for(int i=0;i<3;i++)if(!check_fd(g.held[i],i)){g.poisoned=1;status=5;}
  if(!status&&!scalar("SELECT count(*) FROM sqlite_schema",0,&g.schema_entries))status=6;
  if(g.poisoned)status=5;}
 array=caml_alloc(26,0);
 /* Initialize EVERY scanned slot before ANY allocation can trigger GC. */
 for(int i=0;i<26;i++)Store_field(array,i,Val_unit);
 for(int i=0;i<26;i++){n=caml_copy_int64(0);Store_field(array,i,n);}
 n=caml_copy_int64(status);Store_field(array,0,n);
 if(!status){for(int r=0;r<3;r++){sqlite3_int64 a[]={g.identity[r].st_dev,g.identity[r].st_ino,g.opens[r],g.closes[r],g.reads[r],g.maps[r],g.locks[r]};for(int j=0;j<7;j++){n=caml_copy_int64(a[j]);Store_field(array,1+7*r+j,n);}}
  n=caml_copy_int64(g.entropy);Store_field(array,22,n);n=caml_copy_int64(g.rw_fallback);Store_field(array,23,n);n=caml_copy_int64(g.schema_entries);Store_field(array,24,n);}
 CAMLreturn(array);
}
CAMLprim value caml_uos_bound_vfs_close(value unit){CAMLparam1(unit);CAMLreturn(Val_int(g.used?finish():1));}
CAMLprim value caml_uos_bound_vfs_poisoned(value unit){(void)unit;return Val_bool(g.poisoned);}
