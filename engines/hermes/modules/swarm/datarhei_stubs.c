#include <stdio.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>

// Mocking the Go C-Shared FFI export for Datarhei Core
CAMLprim value caml_datarhei_start_transmuxer(value v_source, value v_sink) {
    CAMLparam2(v_source, v_sink);
    
    const char *source = String_val(v_source);
    const char *sink = String_val(v_sink);
    
    printf("[Datarhei C-FFI] Embedded Core Initialized.\n");
    printf("[Datarhei C-FFI] Source: %s\n", source);
    printf("[Datarhei C-FFI] Sink (WebRTC): %s\n", sink);
    
    // In a real FFI, this would call datarhei_core_start(source, sink)
    // exported from libdatarhei.so built via `go build -buildmode=c-shared`
    
    CAMLreturn(Val_int(0)); // 0 = Success
}
