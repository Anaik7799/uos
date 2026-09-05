/* =============================================================================
   [C3I-SIL6-MSTS] Hardened C-ABI Erlang NIF Wrapper for OCaml Logic Substrate
   =============================================================================
   Enables zero-latency in-process invocation of OCaml logic from BEAM (Gleam).
   Hardened per Directives D-1, D-3, D-4 (Claude Fable 5.1 & Codex consensus):
   - Strict length validation: buffer overflows reject fail-closed (D-1)
   - Exception-safe callbacks: caml_callback2_exn traps OCaml exceptions (D-3)
   - CPU-bound routing: marked ERL_NIF_DIRTY_JOB_CPU_BOUND (D-4)
   - Multicore Domain Lock safety via caml_c_thread_register() + acquire/release
*/

#include <erl_nif.h>
#include <caml/mlvalues.h>
#include <caml/callback.h>
#include <caml/alloc.h>
#include <caml/threads.h>
#include <caml/memory.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>

static int ocaml_initialized = 0;
static pthread_mutex_t init_mutex = PTHREAD_MUTEX_INITIALIZER;
static __thread int thread_registered = 0;
static char cached_version[512] = "{\"ocaml_version\":\"5.5.0\",\"harness\":\"hermes-bionic/zigvm-unified\",\"gate\":\"SIL-6-RETE-UL\",\"contracts\":\"Gospel-v0.3\"}";

static void init_ocaml_runtime(void) {
    pthread_mutex_lock(&init_mutex);
    if (!ocaml_initialized) {
        /* Directive D-25: Sanitize environment so OCAMLRUNPARAM cannot destabilize embedded OCaml */
        unsetenv("OCAMLRUNPARAM");
        char* dummy_argv[] = { "c3i_ocaml_nif", NULL };
        caml_startup(dummy_argv);
        /* caml_startup leaves runtime acquired; release it so workers can acquire */
        caml_release_runtime_system();
        ocaml_initialized = 1;
    }
    pthread_mutex_unlock(&init_mutex);
}

static void enter_ocaml(void) {
    init_ocaml_runtime();
    if (!thread_registered) {
        caml_c_thread_register();
        thread_registered = 1;
    }
    caml_acquire_runtime_system();
}

static void leave_ocaml(void) {
    caml_release_runtime_system();
}

/* Helper to convert Erlang string or binary to C string with strict overflow and embedded-NUL detection */
static int get_string_or_binary(ErlNifEnv* env, ERL_NIF_TERM term, char* buf, size_t buf_size) {
    memset(buf, 0, buf_size);
    ErlNifBinary bin;
    if (enif_inspect_binary(env, term, &bin)) {
        if (bin.size >= buf_size) {
            /* Fail-closed: reject overflow rather than truncating */
            return -1;
        }
        /* Strict Fail-Closed: check for embedded NUL characters before the end of the binary */
        if (memchr(bin.data, '\0', bin.size) != NULL) {
            return -2;
        }
        memcpy(buf, bin.data, bin.size);
        buf[bin.size] = '\0';
        return 1;
    }
    unsigned len = 0;
    if (enif_get_string_length(env, term, &len, ERL_NIF_LATIN1) > 0) {
        if (len >= buf_size) {
            return -1;
        }
        if (enif_get_string(env, term, buf, buf_size, ERL_NIF_LATIN1) > 0) {
            if (strlen(buf) < len) {
                return -2;
            }
            return 1;
        }
    }
    return 0;
}

/* Helper to return C string as Erlang binary */
static ERL_NIF_TERM make_binary_string(ErlNifEnv* env, const char* str) {
    size_t len = strlen(str);
    ERL_NIF_TERM ret_bin;
    unsigned char* p = enif_make_new_binary(env, len, &ret_bin);
    if (!p) {
        return enif_make_badarg(env);
    }
    memcpy(p, str, len);
    return ret_bin;
}

/* NIF: version/0 - Directive D-24: Lockless zero-wait query on normal schedulers */
static ERL_NIF_TERM nif_ocaml_version(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    return make_binary_string(env, cached_version);
}

/* NIF: rete_eval/1 (facts_csv) - Directive D-1 & D-3 & D-4 */
static ERL_NIF_TERM nif_ocaml_rete_eval(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char facts_buf[4096];
    int rc = get_string_or_binary(env, argv[0], facts_buf, sizeof(facts_buf));
    if (rc == -1) {
        /* Directive D-1: Fail closed on buffer overflow */
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: buffer overflow (input exceeds 4095 bytes)\"}");
    }
    if (rc == -2) {
        /* Strict Fail-Closed on embedded NUL */
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: embedded NUL character detected in facts input\"}");
    }
    if (rc == 0) {
        return enif_make_badarg(env);
    }

    enter_ocaml();
    CAMLparam0();
    CAMLlocal2(arg, res);
    const value* cb = caml_named_value("ocaml_rete_eval");
    if (!cb) {
        CAMLdrop;
        leave_ocaml();
        return make_binary_string(env, "{\"error\":\"ocaml_rete_eval callback not registered\"}");
    }
    arg = caml_copy_string(facts_buf);
    res = caml_callback_exn(*cb, arg);
    if (Is_exception_result(res)) {
        CAMLdrop;
        leave_ocaml();
        /* Directive D-3: Intercept exception safely */
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: OCaml runtime exception in rete_eval\"}");
    }
    char* str = strdup(String_val(res));
    CAMLdrop;
    leave_ocaml();
    if (!str) {
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: out of memory in rete_eval\"}");
    }

    ERL_NIF_TERM term = make_binary_string(env, str);
    free(str);
    return term;
}

/* NIF: gospel_verify/2 (spec_name, input_str) */
static ERL_NIF_TERM nif_ocaml_gospel_verify(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char spec_buf[256];
    char input_buf[4096];
    int rc1 = get_string_or_binary(env, argv[0], spec_buf, sizeof(spec_buf));
    int rc2 = get_string_or_binary(env, argv[1], input_buf, sizeof(input_buf));
    if (rc1 == -1 || rc2 == -1) {
        return make_binary_string(env, "{\"valid\":false,\"status\":\"rejected\",\"error\":\"FAIL_CLOSED: buffer overflow in gospel_verify inputs\"}");
    }
    if (rc1 == -2 || rc2 == -2) {
        return make_binary_string(env, "{\"valid\":false,\"status\":\"rejected\",\"error\":\"FAIL_CLOSED: embedded NUL character in gospel_verify inputs\"}");
    }
    if (rc1 == 0 || rc2 == 0) {
        return enif_make_badarg(env);
    }

    enter_ocaml();
    CAMLparam0();
    CAMLlocal3(arg1, arg2, res);
    const value* cb = caml_named_value("ocaml_gospel_verify");
    if (!cb) {
        CAMLdrop;
        leave_ocaml();
        return make_binary_string(env, "{\"error\":\"ocaml_gospel_verify callback not registered\"}");
    }
    arg1 = caml_copy_string(spec_buf);
    arg2 = caml_copy_string(input_buf);
    res = caml_callback2_exn(*cb, arg1, arg2);
    if (Is_exception_result(res)) {
        CAMLdrop;
        leave_ocaml();
        return make_binary_string(env, "{\"valid\":false,\"status\":\"rejected\",\"error\":\"FAIL_CLOSED: OCaml runtime exception in gospel_verify\"}");
    }
    char* str = strdup(String_val(res));
    CAMLdrop;
    leave_ocaml();
    if (!str) {
        return make_binary_string(env, "{\"valid\":false,\"status\":\"rejected\",\"error\":\"FAIL_CLOSED: out of memory in gospel_verify\"}");
    }

    ERL_NIF_TERM term = make_binary_string(env, str);
    free(str);
    return term;
}

/* NIF: zenoh_dispatch/2 (key, payload) */
static ERL_NIF_TERM nif_ocaml_zenoh_dispatch(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char key_buf[512];
    char payload_buf[4096];
    int rc1 = get_string_or_binary(env, argv[0], key_buf, sizeof(key_buf));
    int rc2 = get_string_or_binary(env, argv[1], payload_buf, sizeof(payload_buf));
    if (rc1 == -1 || rc2 == -1) {
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: buffer overflow in zenoh_dispatch\"}");
    }
    if (rc1 == -2 || rc2 == -2) {
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: embedded NUL character in zenoh_dispatch inputs\"}");
    }
    if (rc1 == 0 || rc2 == 0) {
        return enif_make_badarg(env);
    }

    enter_ocaml();
    CAMLparam0();
    CAMLlocal3(arg1, arg2, res);
    const value* cb = caml_named_value("ocaml_zenoh_dispatch");
    if (!cb) {
        CAMLdrop;
        leave_ocaml();
        return make_binary_string(env, "{\"error\":\"ocaml_zenoh_dispatch callback not registered\"}");
    }
    arg1 = caml_copy_string(key_buf);
    arg2 = caml_copy_string(payload_buf);
    res = caml_callback2_exn(*cb, arg1, arg2);
    if (Is_exception_result(res)) {
        CAMLdrop;
        leave_ocaml();
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: OCaml runtime exception in zenoh_dispatch\"}");
    }
    char* str = strdup(String_val(res));
    CAMLdrop;
    leave_ocaml();
    if (!str) {
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: out of memory in zenoh_dispatch\"}");
    }

    ERL_NIF_TERM term = make_binary_string(env, str);
    free(str);
    return term;
}

/* NIF: parity_check/1 (query) */
static ERL_NIF_TERM nif_ocaml_parity_check(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char query_buf[1024];
    int rc = get_string_or_binary(env, argv[0], query_buf, sizeof(query_buf));
    if (rc == -1) {
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: buffer overflow in parity_check\"}");
    }
    if (rc == -2) {
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: embedded NUL character in parity_check input\"}");
    }
    if (rc == 0) {
        return enif_make_badarg(env);
    }

    enter_ocaml();
    CAMLparam0();
    CAMLlocal2(arg, res);
    const value* cb = caml_named_value("ocaml_parity_check");
    if (!cb) {
        CAMLdrop;
        leave_ocaml();
        return make_binary_string(env, "{\"error\":\"ocaml_parity_check callback not registered\"}");
    }
    arg = caml_copy_string(query_buf);
    res = caml_callback_exn(*cb, arg);
    if (Is_exception_result(res)) {
        CAMLdrop;
        leave_ocaml();
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: OCaml runtime exception in parity_check\"}");
    }
    char* str = strdup(String_val(res));
    CAMLdrop;
    leave_ocaml();
    if (!str) {
        return make_binary_string(env, "{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: out of memory in parity_check\"}");
    }

    ERL_NIF_TERM term = make_binary_string(env, str);
    free(str);
    return term;
}

/* Directive D-4: Mark computation-heavy NIF functions as dirty CPU bound */
static ErlNifFunc nif_funcs[] = {
    {"version", 0, nif_ocaml_version, 0},
    {"rete_eval", 1, nif_ocaml_rete_eval, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"gospel_verify", 2, nif_ocaml_gospel_verify, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"zenoh_dispatch", 2, nif_ocaml_zenoh_dispatch, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"parity_check", 1, nif_ocaml_parity_check, ERL_NIF_DIRTY_JOB_CPU_BOUND}
};

static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    init_ocaml_runtime();
    enter_ocaml();
    CAMLparam0();
    CAMLlocal1(res);
    const value* cb = caml_named_value("ocaml_version");
    if (cb) {
        res = caml_callback_exn(*cb, Val_unit);
        if (!Is_exception_result(res)) {
            strncpy(cached_version, String_val(res), sizeof(cached_version) - 1);
            cached_version[sizeof(cached_version) - 1] = '\0';
        }
    }
    CAMLdrop;
    leave_ocaml();
    return 0;
}

ERL_NIF_INIT(c3i_ocaml_nif, nif_funcs, load, NULL, NULL, NULL)
