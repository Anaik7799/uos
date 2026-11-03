
#include <sqlite3.h>
#include <caml/mlvalues.h>
static int persist(sqlite3*db,char**error,const sqlite3_api_routines*api){
 (void)error;(void)api;int yes=1,out=0;
 if(sqlite3_db_config(db,SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE,1,&out)!=SQLITE_OK||out!=1)return SQLITE_ERROR;
 if(sqlite3_wal_autocheckpoint(db,0)!=SQLITE_OK)return SQLITE_ERROR;
 return sqlite3_file_control(db,"main",SQLITE_FCNTL_PERSIST_WAL,&yes);
}
CAMLprim value caml_uos_control_fixture_persist(value unit){(void)unit;return Val_bool(sqlite3_auto_extension((void(*)(void))persist)==SQLITE_OK);}
