/* Independent oracle for native/nifs/mojo/uos_km_kernel.mojo (SC-PROVENANCE-001).
   Every expected value is computed here from first principles in C, never by
   calling the kernel twice. Exit 0 = all laws hold. */
#include <stdio.h>
#include <math.h>
#include <stdint.h>

extern float uos_km_conformance_score(const float *f, const float *w, long n);
extern int32_t uos_km_matrix_column_means(const float *m, long rows, long cols, float *dest);
extern float uos_km_shannon_entropy_bits(const float *c, long n);
extern int32_t uos_km_fmea_band(int32_t s, int32_t o, int32_t d);
extern float uos_km_drift_distance(const float *o, const float *nom, long n);
extern int32_t uos_km_kernel_abi_version(void);
extern float uos_km_cosine_similarity(const float *a, const float *b, long n);
extern float uos_km_ewma(const float *s, long n, float alpha);
extern float uos_km_linear_slope(const float *s, long n);
extern float uos_km_trend_residual(const float *s, long n);

static int fails = 0, checks = 0;
static void near(const char *name, double got, double want) {
    checks++;
    if (fabs(got - want) > 1e-4) { printf("FAIL %-38s got %.6f want %.6f\n", name, got, want); fails++; }
    else printf("ok   %-38s %.6f\n", name, got);
}
static void eq(const char *name, long got, long want) {
    checks++;
    if (got != want) { printf("FAIL %-38s got %ld want %ld\n", name, got, want); fails++; }
    else printf("ok   %-38s %ld\n", name, got);
}

int main(void) {
    eq("abi_version", uos_km_kernel_abi_version(), 3);

    /* 1. conformance: 13 lanes exercises the SIMD body (8) plus the tail (5). */
    float f[13], w[13];
    double num = 0.0, den = 0.0;
    for (int i = 0; i < 13; i++) {
        f[i] = (i % 3 == 0) ? 1.0f : 0.0f;
        w[i] = (float)(i + 1);
        num += (double)f[i] * (double)w[i];
        den += (double)w[i];
    }
    near("conformance_score 13 lanes", uos_km_conformance_score(f, w, 13), num / den);

    float allf[8], allw[8];
    for (int i = 0; i < 8; i++) { allf[i] = 1.0f; allw[i] = 2.0f; }
    near("conformance_score all-conformant", uos_km_conformance_score(allf, allw, 8), 1.0);
    for (int i = 0; i < 8; i++) allf[i] = 0.0f;
    near("conformance_score none-conformant", uos_km_conformance_score(allf, allw, 8), 0.0);
    near("conformance_score rejects n=0", uos_km_conformance_score(f, w, 0), -1.0);
    near("conformance_score rejects n<0", uos_km_conformance_score(f, w, -3), -1.0);

    /* 2. column means of a 3x4 row-major matrix. */
    float m[12] = { 1,2,3,4,  5,6,7,8,  9,10,11,12 };
    float dest[4] = {0};
    eq("column_means returns cols", uos_km_matrix_column_means(m, 3, 4, dest), 4);
    for (int c = 0; c < 4; c++) {
        double want = (m[c] + m[4 + c] + m[8 + c]) / 3.0;
        char nm[64]; snprintf(nm, sizeof nm, "column_mean[%d]", c);
        near(nm, dest[c], want);
    }
    eq("column_means rejects rows=0", uos_km_matrix_column_means(m, 0, 4, dest), -1);

    /* 3. Shannon entropy. Uniform over k has entropy log2(k) exactly. */
    float u8[8]; for (int i = 0; i < 8; i++) u8[i] = 5.0f;
    near("entropy uniform k=8", uos_km_shannon_entropy_bits(u8, 8), 3.0);
    float u4[4]; for (int i = 0; i < 4; i++) u4[i] = 1.0f;
    near("entropy uniform k=4", uos_km_shannon_entropy_bits(u4, 4), 2.0);
    float deg[4] = { 7.0f, 0.0f, 0.0f, 0.0f };
    near("entropy degenerate", uos_km_shannon_entropy_bits(deg, 4), 0.0);
    float skew[3] = { 1.0f, 1.0f, 2.0f };   /* -2*(.25*log2 .25) - .5*log2 .5 = 1.5 */
    near("entropy skewed", uos_km_shannon_entropy_bits(skew, 3), 1.5);
    float zero[3] = { 0.0f, 0.0f, 0.0f };
    near("entropy rejects all-zero", uos_km_shannon_entropy_bits(zero, 3), -1.0);
    float negv[3] = { 1.0f, -1.0f, 1.0f };
    near("entropy rejects negative", uos_km_shannon_entropy_bits(negv, 3), -1.0);

    /* 4. FMEA bands against the policy maxima [5,15,35,70,125]. */
    eq("fmea 1,1,1 -> band1", uos_km_fmea_band(1, 1, 1), 1);
    eq("fmea 1,1,5 -> band1", uos_km_fmea_band(1, 1, 5), 1);
    eq("fmea 2,2,3 -> band2", uos_km_fmea_band(2, 2, 3), 2);
    eq("fmea 3,3,3 -> band3", uos_km_fmea_band(3, 3, 3), 3);
    eq("fmea 4,3,3 -> band4", uos_km_fmea_band(4, 3, 3), 4);
    eq("fmea 5,5,5 -> band5", uos_km_fmea_band(5, 5, 5), 5);
    eq("fmea rejects s=0", uos_km_fmea_band(0, 1, 1), -1);
    eq("fmea rejects d=6", uos_km_fmea_band(1, 1, 6), -1);

    /* 5. drift distance: 3-4-5 triangle padded past the SIMD width. */
    float o[10], nom[10];
    for (int i = 0; i < 10; i++) { o[i] = 1.0f; nom[i] = 1.0f; }
    o[0] = 4.0f; o[9] = 5.0f;            /* deltas 3 and 4 -> sqrt(9+16) = 5 */
    near("drift_distance 3-4-5", uos_km_drift_distance(o, nom, 10), 5.0);
    for (int i = 0; i < 10; i++) o[i] = nom[i];
    near("drift_distance zero", uos_km_drift_distance(o, nom, 10), 0.0);
    near("drift_distance rejects n=0", uos_km_drift_distance(o, nom, 0), -1.0);

    /* 6. cosine similarity: identical, orthogonal, opposed, and a hand-computed case. */
    float ca[10], cb[10];
    for (int i = 0; i < 10; i++) { ca[i] = (float)(i + 1); cb[i] = (float)(i + 1); }
    near("cosine identical vectors", uos_km_cosine_similarity(ca, cb, 10), 1.0);
    for (int i = 0; i < 10; i++) { ca[i] = 0.0f; cb[i] = 0.0f; }
    ca[0] = 1.0f; cb[1] = 1.0f;
    near("cosine orthogonal", uos_km_cosine_similarity(ca, cb, 10), 0.0);
    ca[0] = 1.0f; ca[1] = 0.0f; cb[0] = -1.0f; cb[1] = 0.0f;
    near("cosine opposed", uos_km_cosine_similarity(ca, cb, 10), -1.0);
    {   /* a=(1,2,3), b=(3,2,1): dot 10, |a|=|b|=sqrt(14) -> 10/14 */
        float x[3] = {1,2,3}, y[3] = {3,2,1};
        near("cosine hand-computed 10/14", uos_km_cosine_similarity(x, y, 3), 10.0 / 14.0);
    }
    {   /* a zero vector has no direction: reject rather than answer 0 */
        float z[3] = {0,0,0}, w[3] = {1,1,1};
        near("cosine rejects zero magnitude", uos_km_cosine_similarity(z, w, 3), -1.0);
    }
    near("cosine rejects n=0", uos_km_cosine_similarity(ca, cb, 0), -1.0);

    /* 7. forecasting primitives, each against a hand-computed expectation. */
    {   /* alpha=1 keeps only the last observation */
        float s1[4] = {1, 2, 3, 4};
        near("ewma alpha=1 is last value", uos_km_ewma(s1, 4, 1.0f), 4.0);
        /* a constant series has that constant as its level for any alpha */
        float s2[5] = {7, 7, 7, 7, 7};
        near("ewma constant series", uos_km_ewma(s2, 5, 0.3f), 7.0);
        /* hand-computed: alpha .5 over 1,2,3 -> .5*3 + .5*(.5*2 + .5*1) = 2.25 */
        float s3[3] = {1, 2, 3};
        near("ewma hand-computed", uos_km_ewma(s3, 3, 0.5f), 2.25);
        near("ewma rejects alpha=0", uos_km_ewma(s3, 3, 0.0f), -1.0);
        near("ewma rejects alpha>1", uos_km_ewma(s3, 3, 1.5f), -1.0);
    }
    {   /* a perfect line has exactly its slope and zero residual */
        float lin[5];
        for (int i = 0; i < 5; i++) lin[i] = 3.0f + 2.0f * (float)i;
        near("slope of exact line", uos_km_linear_slope(lin, 5), 2.0);
        near("residual of exact line", uos_km_trend_residual(lin, 5), 0.0);
        /* a flat series has zero slope */
        float flat[4] = {5, 5, 5, 5};
        near("slope of flat series", uos_km_linear_slope(flat, 4), 0.0);
        /* a descending line has negative slope */
        float down[4] = {10, 8, 6, 4};
        near("slope of descending line", uos_km_linear_slope(down, 4), -2.0);
        /* noise around a flat line: slope ~0 but residual must be non-zero,
           which is the whole point of reporting the residual */
        float noisy[4] = {0, 4, 0, 4};
        near("slope of alternating series", uos_km_linear_slope(noisy, 4), 0.8);
        if (uos_km_trend_residual(noisy, 4) <= 0.5f) {
            printf("FAIL residual of noisy series should be large\n"); fails++;
        } else { printf("ok   residual of noisy series is large\n"); }
        checks++;
        near("slope rejects n=1", uos_km_linear_slope(lin, 1), -1.0);
        near("residual rejects n=1", uos_km_trend_residual(lin, 1), -1.0);
    }

    printf("\n%d checks, %d failures\n", checks, fails);
    return fails == 0 ? 0 : 1;
}
