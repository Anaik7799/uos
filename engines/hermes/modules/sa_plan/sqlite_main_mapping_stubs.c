#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <sqlite3.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <stdint.h>
#include <inttypes.h>
#include <limits.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dlfcn.h>
#include <sys/sysmacros.h>
#include <sys/stat.h>
#if !defined(__linux__) || !defined(__x86_64__) || SQLITE_VERSION_NUMBER != 3053003
#error "Only Linux x86_64 with pinned SQLite 3.53.3 is supported"
#endif
/* Public SQLite ABI only. No db_wrap/unixFile casts, VFS replacement, syscall
 * hook, FD extraction, mutation SQL, dynamic extension loading or authority.
 * Observe the actual main-file xFetch mapping, not all SQLite IO or WAL/SHM.
 * Trusted single-owner process/default Unix VFS/proc and immutable DSO assumed. */
#define MAP_CAP 1048576u
#define LINE_CAP 8192u
#define FETCH_BYTES 4096u
struct map_identity { uint64_t device, inode; };
static int number(const char **p,const char *end,unsigned base,uint64_t *value) {
  const char *start=*p;uint64_t n=0;unsigned digits=0;
  while(*p<end){unsigned c=(unsigned char)**p,d;
    if(c>='0'&&c<='9')d=c-'0';else if(base==16&&c>='a'&&c<='f')d=c-'a'+10;
    else if(base==16&&c>='A'&&c<='F')d=c-'A'+10;else break;
    if(d>=base||n>(UINT64_MAX-d)/base)return 0;
    n=n*base+d;(*p)++;digits++;if(digits>(base==16?16u:20u))return 0;
  }
  if(*p==start||(base==10&&digits>1&&*start=='0'))return 0;
  *value=n;return 1;
}
static int spaces(const char **p,const char *end){const char *s=*p;while(*p<end&&**p==' ')(*p)++;return *p>s;}
/* 1=whole requested range observed, 0=absent, negative=HOLD. Parse EVERY line
 * before returning success: malformed later lines never mean absence/accept. */
static int parse_maps(const char *bytes,size_t size,uint64_t ptr,uint64_t length,struct map_identity *out){
  if(!length||length>FETCH_BYTES||ptr>UINT64_MAX-length)return -3;
  if(!size||size>MAP_CAP)return -2;
  size_t position=0;unsigned lines=0;uint64_t previous_end=0;int found=0;
  while(position<size){size_t start=position;
    while(position<size&&bytes[position]!='\n'){if(!bytes[position]||position-start>=LINE_CAP)return -1;position++;}
    if(position==size||++lines>8192)return -2;
    const char *p=bytes+start,*end=bytes+position;position++;
    uint64_t lo,hi,offset,major_n,minor_n,inode;
    if(!number(&p,end,16,&lo)||p==end||*p++!='-'||!number(&p,end,16,&hi)||
       lo>=hi||lo<previous_end||!spaces(&p,end)||end-p<4)return -1;
    previous_end=hi;const char *permissions=p;p+=4;
    if(!((permissions[0]=='r'||permissions[0]=='-')&&(permissions[1]=='w'||permissions[1]=='-')&&
       (permissions[2]=='x'||permissions[2]=='-')&&(permissions[3]=='s'||permissions[3]=='p'))||
       !spaces(&p,end)||!number(&p,end,16,&offset)||!spaces(&p,end)||
       !number(&p,end,16,&major_n)||p==end||*p++!=':'||!number(&p,end,16,&minor_n)||
       major_n>UINT_MAX||minor_n>UINT_MAX||!spaces(&p,end)||!number(&p,end,10,&inode)||
       (p<end&&*p!=' '))return -1;
    if(lo<ptr+length&&hi>ptr){
      if(found||ptr<lo||length>hi-ptr||offset>UINT64_MAX-(ptr-lo)||offset+(ptr-lo)!=0||
         memcmp(permissions,"r--s",4)!=0)return -3;
      if(!inode)return -4;
      dev_t dev=makedev((unsigned)major_n,(unsigned)minor_n);
      if(major(dev)!=major_n||minor(dev)!=minor_n)return -3;
      out->device=(uint64_t)dev;out->inode=inode;found=1;
    }
  }
  return found;
}
static int proc_identity(void *pointer,struct map_identity *identity){
  int fd=open("/proc/self/maps",O_RDONLY|O_CLOEXEC|O_NOFOLLOW);if(fd<0)return -5;
  char *buffer=sqlite3_malloc64(MAP_CAP+1u);if(!buffer){close(fd);return -2;}
  size_t used=0;unsigned attempts=0;int status=-5;
  while(++attempts<=1024){ssize_t n=read(fd,buffer+used,MAP_CAP+1u-used);
    if(n<0){if(errno==EINTR)continue;goto done;}
    if(!n){status=parse_maps(buffer,used,(uint64_t)(uintptr_t)pointer,FETCH_BYTES,identity);goto done;}
    used+=(size_t)n;if(used>MAP_CAP){status=-2;goto done;}
  }
done:
  sqlite3_free(buffer);if(close(fd)!=0)status=-5;return status;
}
static int same_instance(void){
  Dl_info base,one;
  if(!dladdr((void*)sqlite3_libversion,&base)||!base.dli_fbase)return 0;
  void *symbols[]={(void*)sqlite3_open_v2,(void*)sqlite3_prepare_v2,(void*)sqlite3_step,
    (void*)sqlite3_auto_extension,(void*)sqlite3_create_function_v2,(void*)sqlite3_context_db_handle,
    (void*)sqlite3_db_mutex,(void*)sqlite3_file_control,(void*)sqlite3_sourceid};
  for(size_t i=0;i<sizeof symbols/sizeof symbols[0];i++)
    if(!dladdr(symbols[i],&one)||one.dli_fbase!=base.dli_fbase)return 0;
  return 1;
}
static void mapping_sql(sqlite3_context *context,int argc,sqlite3_value **argv){
  const char *error=NULL;sqlite3 *db=sqlite3_context_db_handle(context);
  sqlite3_mutex *mutex=sqlite3_db_mutex(db);sqlite3_file *file=NULL;sqlite3_vfs *vfs=NULL;
  void *pointer=NULL;struct map_identity observed={0,0};
  if(argc!=2||sqlite3_value_type(argv[0])!=SQLITE_INTEGER||sqlite3_value_type(argv[1])!=SQLITE_INTEGER||
    sqlite3_value_int64(argv[0])<0||sqlite3_value_int64(argv[1])<=0){sqlite3_result_error(context,"UOS_MAP_ARGUMENT",-1);return;}
  if(!mutex){sqlite3_result_error(context,"UOS_MAP_MUTEX",-1);return;}
  sqlite3_mutex_enter(mutex);
  if(!same_instance()||sqlite3_libversion_number()!=3053003||strcmp(sqlite3_sourceid(),SQLITE_SOURCE_ID)){error="UOS_MAP_RUNTIME";goto done;}
  if(sqlite3_db_readonly(db,"main")!=1||sqlite3_txn_state(db,"main")!=SQLITE_TXN_READ){error="UOS_MAP_READ_TRANSACTION";goto done;}
  if(sqlite3_file_control(db,"main",SQLITE_FCNTL_VFS_POINTER,&vfs)!=SQLITE_OK||
     !vfs||vfs!=sqlite3_vfs_find(NULL)||!vfs->zName||strcmp(vfs->zName,"unix")){error="UOS_MAP_VFS";goto done;}
  if(sqlite3_file_control(db,"main",SQLITE_FCNTL_FILE_POINTER,&file)!=SQLITE_OK||!file||
     !file->pMethods||file->pMethods->iVersion<3||!file->pMethods->xFetch||!file->pMethods->xUnfetch){error="UOS_MAP_FILE_METHODS";goto done;}
  sqlite3_int64 bytes=0;
  if(file->pMethods->xFileSize(file,&bytes)!=SQLITE_OK||bytes<FETCH_BYTES||bytes>33554432){error="UOS_MAP_FILE_BOUND";goto done;}
  if(file->pMethods->xFetch(file,0,FETCH_BYTES,&pointer)!=SQLITE_OK||!pointer){error="UOS_MAP_MMAP_UNAVAILABLE";goto done;}
  int parsed=proc_identity(pointer,&observed);
  if(parsed!=1){error=parsed==0?"UOS_MAP_ABSENT":parsed==-2?"UOS_MAP_BOUND":parsed==-5?"UOS_MAP_PROC_UNAVAILABLE":"UOS_MAP_INVALID";goto done;}
  if(observed.device!=(uint64_t)sqlite3_value_int64(argv[0])||observed.inode!=(uint64_t)sqlite3_value_int64(argv[1]))error="UOS_MAP_IDENTITY_MISMATCH";
done:
  if(pointer&&file&&file->pMethods->xUnfetch(file,0,pointer)!=SQLITE_OK)error="UOS_MAP_UNFETCH";
  sqlite3_mutex_leave(mutex);
  if(error)sqlite3_result_error(context,error,-1);
  else {char text[128];int n=snprintf(text,sizeof text,"main-mapping-v1|%"PRIu64"|%"PRIu64"|4096",observed.device,observed.inode);
    if(n<=0||(size_t)n>=sizeof text)sqlite3_result_error(context,"UOS_MAP_RESULT_BOUND",-1);
    else sqlite3_result_text(context,text,n,SQLITE_TRANSIENT);}
}
static int extension(sqlite3 *db,char **error,const sqlite3_api_routines *api){
  (void)error;(void)api;
  return sqlite3_create_function_v2(db,"uos_main_mapping_identity_v1",2,SQLITE_UTF8|SQLITE_DIRECTONLY,
    NULL,mapping_sql,NULL,NULL,NULL);
}
CAMLprim value caml_uos_main_mapping_register(value unit){
  CAMLparam1(unit);
  int good=same_instance()&&sqlite3_libversion_number()==3053003&&!strcmp(sqlite3_sourceid(),SQLITE_SOURCE_ID);
  CAMLreturn(Val_bool(good&&sqlite3_auto_extension((void(*)(void))extension)==SQLITE_OK));
}
CAMLprim value caml_uos_main_mapping_runtime(value unit){
  CAMLparam1(unit);CAMLlocal5(version,source,path,header,tuple);Dl_info info;
  version=caml_copy_string(sqlite3_libversion());source=caml_copy_string(sqlite3_sourceid());
  path=caml_copy_string(dladdr((void*)sqlite3_libversion,&info)&&info.dli_fname?info.dli_fname:"");
  header=caml_copy_string(SQLITE_SOURCE_ID);tuple=caml_alloc_tuple(4);
  Store_field(tuple,0,version);Store_field(tuple,1,source);Store_field(tuple,2,path);Store_field(tuple,3,header);CAMLreturn(tuple);
}
/* Pure parser diagnostic only, NOT an observation constructor/SQL API. Tests
 * may link this public symbol; production OCaml interface does not export it. */
CAMLprim value caml_uos_main_mapping_parse_test(value bytes,value ptr,value length){
  CAMLparam3(bytes,ptr,length);struct map_identity ignored;
  int result=parse_maps(String_val(bytes),caml_string_length(bytes),(uint64_t)Int64_val(ptr),(uint64_t)Int64_val(length),&ignored);
  CAMLreturn(Val_int(result));
}
/* Never project native unsigned identity through OCaml's narrower tagged int.
 * SQLite INTEGER is signed64; reject the unsupported upper half explicitly. */
static int identity_representable(uint64_t device,uint64_t inode){
  return device<=INT64_MAX&&inode>0&&inode<=INT64_MAX;
}
CAMLprim value caml_uos_main_mapping_retained_identity(value fd){
  CAMLparam1(fd);CAMLlocal4(device,inode,pair,some);struct stat st;
  if(!Is_long(fd)||Long_val(fd)<0||Long_val(fd)>INT_MAX||fstat((int)Long_val(fd),&st)||
     !identity_representable((uint64_t)st.st_dev,(uint64_t)st.st_ino))CAMLreturn(Val_int(0));
  device=caml_copy_int64((int64_t)st.st_dev);inode=caml_copy_int64((int64_t)st.st_ino);
  pair=caml_alloc_tuple(2);Store_field(pair,0,device);Store_field(pair,1,inode);
  some=caml_alloc(1,0);Store_field(some,0,pair);CAMLreturn(some);
}
/* Pure boundary diagnostic; not an identity observation constructor. */
CAMLprim value caml_uos_main_mapping_identity_range_test(value device,value inode){
  CAMLparam2(device,inode);
  CAMLreturn(Val_bool(identity_representable((uint64_t)Int64_val(device),(uint64_t)Int64_val(inode))));
}
