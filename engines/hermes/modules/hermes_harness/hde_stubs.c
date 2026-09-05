/* OCaml <-> Rust FFI stubs for the embedded hermes_drift_engine staticlib.
 *
 * One call: a JSON request string in, a JSON reply string out. The Rust side
 * never panics across the boundary (all failures are {"error":...} replies),
 * and the reply buffer is owned by Rust and released with hde_free after the
 * OCaml string copy -- no shared ownership across the ABI. */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/threads.h>

extern char *hde_eval(const char *input);
extern void hde_free(char *ptr);

CAMLprim value caml_hde_eval(value input)
{
    CAMLparam1(input);
    CAMLlocal1(reply);
    char *raw = hde_eval(String_val(input));
    if (raw == NULL) {
        reply = caml_copy_string("{\"error\":\"engine returned null\"}");
    } else {
        reply = caml_copy_string(raw);
        hde_free(raw);
    }
    CAMLreturn(reply);
}
