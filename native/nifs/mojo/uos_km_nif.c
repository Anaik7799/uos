/* =============================================================================
   UOS KM PROVENANCE METRICS — C-ABI Erlang NIF facade over the Mojo kernel
   -----------------------------------------------------------------------------
   Contract: SC-PROVENANCE-001. Layer L3_TRANSACTION.

   This file is a dispatch facade only: it validates and marshals, then calls
   native/nifs/mojo/uos_km_kernel.mojo. It contains no policy and no analysis.

   Boundedness (UOS native/ rule: short, deterministic, bounded, explicit ABI):
     - every list length is checked against UOS_KM_MAX_ELEMS before allocation;
     - allocation uses enif_alloc and is always freed on every exit path;
     - no I/O, no locks, no blocking; the kernel itself cannot block;
     - a rejected argument returns an {error, Reason} tuple, never a crash.

   These are short numeric reductions over bounded buffers, so they run on the
   normal scheduler. If UOS_KM_MAX_ELEMS is ever raised past a few thousand,
   move them to ERL_NIF_DIRTY_JOB_CPU_BOUND.
   ============================================================================= */

#include <erl_nif.h>
#include <stdint.h>

/* Kernel entry points (Mojo, C ABI). */
extern float   uos_km_conformance_score(const float *f, const float *w, long n);
extern int32_t uos_km_matrix_column_means(const float *m, long rows, long cols, float *dest);
extern float   uos_km_shannon_entropy_bits(const float *c, long n);
extern int32_t uos_km_fmea_band(int32_t s, int32_t o, int32_t d);
extern float   uos_km_drift_distance(const float *o, const float *nom, long n);
extern int32_t uos_km_kernel_abi_version(void);
extern float   uos_km_cosine_similarity(const float *a, const float *b, long n);
extern float   uos_km_ewma(const float *s, long n, float alpha);
extern float   uos_km_linear_slope(const float *s, long n);
extern float   uos_km_trend_residual(const float *s, long n);

#define UOS_KM_MAX_ELEMS 4096

static ERL_NIF_TERM err(ErlNifEnv *env, const char *reason) {
    return enif_make_tuple2(env, enif_make_atom(env, "error"),
                            enif_make_atom(env, reason));
}

/* Reads an Erlang list of numbers into a caller-freed float buffer.
   Returns the length, or -1 on any malformed/oversize input. */
static long read_float_list(ErlNifEnv *env, ERL_NIF_TERM list, float **out) {
    unsigned len = 0;
    if (!enif_get_list_length(env, list, &len)) return -1;
    if (len == 0 || len > UOS_KM_MAX_ELEMS) return -1;

    float *buf = (float *)enif_alloc(sizeof(float) * len);
    if (!buf) return -1;

    ERL_NIF_TERM head, tail = list;
    for (unsigned i = 0; i < len; i++) {
        if (!enif_get_list_cell(env, tail, &head, &tail)) { enif_free(buf); return -1; }
        double d;
        long l;
        if (enif_get_double(env, head, &d))      buf[i] = (float)d;
        else if (enif_get_long(env, head, &l))   buf[i] = (float)l;
        else { enif_free(buf); return -1; }
    }
    *out = buf;
    return (long)len;
}

static ERL_NIF_TERM nif_abi_version(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc; (void)argv;
    return enif_make_int(env, uos_km_kernel_abi_version());
}

static ERL_NIF_TERM nif_conformance_score(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    float *f = NULL, *w = NULL;
    long nf = read_float_list(env, argv[0], &f);
    if (nf < 0) return err(env, "bad_features");
    long nw = read_float_list(env, argv[1], &w);
    if (nw < 0) { enif_free(f); return err(env, "bad_weights"); }
    if (nf != nw) { enif_free(f); enif_free(w); return err(env, "length_mismatch"); }

    float r = uos_km_conformance_score(f, w, nf);
    enif_free(f); enif_free(w);
    if (r < 0.0f) return err(env, "rejected_by_kernel");
    return enif_make_double(env, (double)r);
}

static ERL_NIF_TERM nif_shannon_entropy_bits(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    float *c = NULL;
    long n = read_float_list(env, argv[0], &c);
    if (n < 0) return err(env, "bad_counts");

    float r = uos_km_shannon_entropy_bits(c, n);
    enif_free(c);
    if (r < 0.0f) return err(env, "rejected_by_kernel");
    return enif_make_double(env, (double)r);
}

static ERL_NIF_TERM nif_drift_distance(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    float *o = NULL, *nom = NULL;
    long no = read_float_list(env, argv[0], &o);
    if (no < 0) return err(env, "bad_observed");
    long nn = read_float_list(env, argv[1], &nom);
    if (nn < 0) { enif_free(o); return err(env, "bad_nominal"); }
    if (no != nn) { enif_free(o); enif_free(nom); return err(env, "length_mismatch"); }

    float r = uos_km_drift_distance(o, nom, no);
    enif_free(o); enif_free(nom);
    if (r < 0.0f) return err(env, "rejected_by_kernel");
    return enif_make_double(env, (double)r);
}

static ERL_NIF_TERM nif_fmea_band(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    int s, o, d;
    if (!enif_get_int(env, argv[0], &s)) return err(env, "bad_severity");
    if (!enif_get_int(env, argv[1], &o)) return err(env, "bad_occurrence");
    if (!enif_get_int(env, argv[2], &d)) return err(env, "bad_detection");

    int32_t band = uos_km_fmea_band((int32_t)s, (int32_t)o, (int32_t)d);
    if (band < 0) return err(env, "rejected_by_kernel");
    return enif_make_int(env, band);
}

/* column_means(Matrix :: [[float]]) -> {ok, [float]} | {error, atom()}
   The matrix is flattened row-major here; the kernel does the reduction. */
static ERL_NIF_TERM nif_column_means(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    unsigned rows = 0;
    if (!enif_get_list_length(env, argv[0], &rows)) return err(env, "bad_matrix");
    if (rows == 0 || rows > UOS_KM_MAX_ELEMS) return err(env, "bad_matrix");

    ERL_NIF_TERM head, tail = argv[0];
    float *flat = NULL;
    long cols = -1;
    unsigned filled = 0;

    for (unsigned r = 0; r < rows; r++) {
        if (!enif_get_list_cell(env, tail, &head, &tail)) { if (flat) enif_free(flat); return err(env, "bad_matrix"); }
        float *row = NULL;
        long n = read_float_list(env, head, &row);
        if (n < 0) { if (flat) enif_free(flat); return err(env, "bad_row"); }

        if (cols < 0) {
            cols = n;
            if ((long)rows * cols > UOS_KM_MAX_ELEMS) { enif_free(row); return err(env, "matrix_too_large"); }
            flat = (float *)enif_alloc(sizeof(float) * (size_t)rows * (size_t)cols);
            if (!flat) { enif_free(row); return err(env, "alloc_failed"); }
        } else if (n != cols) {
            enif_free(row); enif_free(flat); return err(env, "ragged_matrix");
        }
        for (long c = 0; c < cols; c++) flat[filled * cols + c] = row[c];
        filled++;
        enif_free(row);
    }

    float *means = (float *)enif_alloc(sizeof(float) * (size_t)cols);
    if (!means) { enif_free(flat); return err(env, "alloc_failed"); }

    int32_t got = uos_km_matrix_column_means(flat, (long)rows, cols, means);
    enif_free(flat);
    if (got != (int32_t)cols) { enif_free(means); return err(env, "rejected_by_kernel"); }

    ERL_NIF_TERM out = enif_make_list(env, 0);
    for (long c = cols - 1; c >= 0; c--)
        out = enif_make_list_cell(env, enif_make_double(env, (double)means[c]), out);
    enif_free(means);
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), out);
}

static ERL_NIF_TERM nif_cosine_similarity(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    float *a = NULL, *b = NULL;
    long na = read_float_list(env, argv[0], &a);
    if (na < 0) return err(env, "bad_vector_a");
    long nb = read_float_list(env, argv[1], &b);
    if (nb < 0) { enif_free(a); return err(env, "bad_vector_b"); }
    if (na != nb) { enif_free(a); enif_free(b); return err(env, "length_mismatch"); }

    float r = uos_km_cosine_similarity(a, b, na);
    enif_free(a); enif_free(b);
    /* -1.0 is both the rejection sentinel and a legal similarity (opposed
       vectors). Non-negative term-frequency vectors can never be opposed, so
       within this contract a negative result is unambiguously a rejection. */
    if (r < 0.0f) return err(env, "rejected_by_kernel");
    return enif_make_double(env, (double)r);
}

static ERL_NIF_TERM nif_ewma(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    float *v = NULL;
    long n = read_float_list(env, argv[0], &v);
    if (n < 0) return err(env, "bad_series");
    double alpha;
    if (!enif_get_double(env, argv[1], &alpha)) { enif_free(v); return err(env, "bad_alpha"); }
    float r = uos_km_ewma(v, n, (float)alpha);
    enif_free(v);
    if (r == -1.0f) return err(env, "rejected_by_kernel");
    return enif_make_double(env, (double)r);
}

static ERL_NIF_TERM nif_linear_slope(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    float *v = NULL;
    long n = read_float_list(env, argv[0], &v);
    if (n < 0) return err(env, "bad_series");
    float r = uos_km_linear_slope(v, n);
    enif_free(v);
    /* A slope is legitimately negative, so -1.0 alone cannot mean rejection
       here. n < 2 is the only rejection this wrapper can distinguish, and it is
       checked before the call. */
    if (n < 2) return err(env, "series_too_short");
    return enif_make_double(env, (double)r);
}

static ERL_NIF_TERM nif_trend_residual(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    (void)argc;
    float *v = NULL;
    long n = read_float_list(env, argv[0], &v);
    if (n < 0) return err(env, "bad_series");
    if (n < 2) { enif_free(v); return err(env, "series_too_short"); }
    float r = uos_km_trend_residual(v, n);
    enif_free(v);
    if (r < 0.0f) return err(env, "rejected_by_kernel");
    return enif_make_double(env, (double)r);
}

static ErlNifFunc nif_funcs[] = {
    {"ewma",                 2, nif_ewma,                 0},
    {"linear_slope",         1, nif_linear_slope,         0},
    {"trend_residual",       1, nif_trend_residual,       0},
    {"cosine_similarity",    2, nif_cosine_similarity,    0},
    {"abi_version",          0, nif_abi_version,          0},
    {"conformance_score",    2, nif_conformance_score,    0},
    {"shannon_entropy_bits", 1, nif_shannon_entropy_bits, 0},
    {"drift_distance",       2, nif_drift_distance,       0},
    {"fmea_band",            3, nif_fmea_band,            0},
    {"column_means",         1, nif_column_means,         0}
};

ERL_NIF_INIT(uos_km_nif, nif_funcs, NULL, NULL, NULL, NULL)
