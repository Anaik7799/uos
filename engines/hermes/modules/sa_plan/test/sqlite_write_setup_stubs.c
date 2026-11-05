#include <sqlite3.h>
#include <caml/mlvalues.h>
#include <string.h>
#if SQLITE_VERSION_NUMBER != 3053003
#error "Private setup fixture requires pinned SQLite3.53.3"
#endif
/* TEST ONLY. Keep preexisting sidecar inodes after ALL initializer connections
 * close; no exported database handle or production configuration change. */
static int fixture_persist(sqlite3*db,char**error,const sqlite3_api_routines*api){
 (void)error;(void)api;const char*path=sqlite3_db_filename(db,"main");
 if(!path||strncmp(path,"/tmp/uos-write-vfs-test-",24))return SQLITE_AUTH;
 int observed=0,yes=1;
 if(sqlite3_db_config(db,SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE,1,&observed)!=SQLITE_OK||observed!=1||sqlite3_wal_autocheckpoint(db,0)!=SQLITE_OK||sqlite3_file_control(db,"main",SQLITE_FCNTL_PERSIST_WAL,&yes)!=SQLITE_OK)return SQLITE_ERROR;
 return SQLITE_OK;
}
CAMLprim value caml_private_write_setup_persist(value unit){(void)unit;return Val_bool(sqlite3_libversion_number()==3053003&&sqlite3_auto_extension((void(*)(void))fixture_persist)==SQLITE_OK);}
