#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>

typedef int CUresult;
typedef uint64_t CUdeviceptr;
typedef void* CUstream;

static void* get_wsl_libcuda(void) {
    static void* h = NULL;
    if (!h) {
        h = dlopen("/usr/lib/wsl/lib/libcuda.so.1.1", RTLD_LAZY | RTLD_GLOBAL);
        if (!h) h = dlopen("/usr/lib/wsl/lib/libcuda.so.1", RTLD_LAZY | RTLD_GLOBAL);
    }
    return h;
}

static CUresult stub_cuFuncGetParamInfo(void* func, size_t paramIndex, size_t* paramOffset, size_t* paramSize) {
    if (paramOffset) *paramOffset = paramIndex * 8;
    if (paramSize) *paramSize = 8;
    return 800; /* CUDA_ERROR_NOT_SUPPORTED */
}

/* Real stream-ordered batch copy loop over cuMemcpyAsync for Turing sm_75 under WSL2 CUDA 12.x */
static CUresult stub_cuMemcpyBatchAsync(
    CUdeviceptr* dsts,
    const CUdeviceptr* srcs,
    const size_t* sizes,
    size_t count,
    void* attrs,
    void* attrIdxs,
    size_t numAttrs,
    size_t* failIdx,
    CUstream hStream
) {
    (void)attrs;
    (void)attrIdxs;
    (void)numAttrs;
    static CUresult (*real_cuMemcpyAsync)(CUdeviceptr, CUdeviceptr, size_t, CUstream) = NULL;
    if (!real_cuMemcpyAsync) {
        void* h = get_wsl_libcuda();
        if (h) {
            real_cuMemcpyAsync = dlvsym(h, "cuMemcpyAsync", "libcuda.so.1");
            if (!real_cuMemcpyAsync) real_cuMemcpyAsync = dlsym(h, "cuMemcpyAsync");
        }
    }
    if (!real_cuMemcpyAsync) {
        if (failIdx) *failIdx = 0;
        return 800;
    }
    if (!dsts || !srcs || !sizes) {
        if (failIdx) *failIdx = 0;
        return 1; /* CUDA_ERROR_INVALID_VALUE */
    }
    for (size_t i = 0; i < count; ++i) {
        CUresult rc = real_cuMemcpyAsync(dsts[i], srcs[i], sizes[i], hStream);
        if (rc != 0) {
            if (failIdx) *failIdx = i;
            return rc;
        }
    }
    return 0;
}

static CUresult stub_cuMemcpyBatch(
    CUdeviceptr* dsts,
    const CUdeviceptr* srcs,
    const size_t* sizes,
    size_t count,
    void* attrs,
    void* attrIdxs,
    size_t numAttrs,
    size_t* failIdx,
    CUstream hStream
) {
    return stub_cuMemcpyBatchAsync(dsts, srcs, sizes, count, attrs, attrIdxs, numAttrs, failIdx, hStream);
}

static CUresult stub_cuMemset(uint64_t dstDevice, unsigned char uc, size_t N) {
    static CUresult (*real_cuMemsetD8)(uint64_t, unsigned char, size_t) = NULL;
    if (!real_cuMemsetD8) {
        void* h = get_wsl_libcuda();
        if (h) real_cuMemsetD8 = dlvsym(h, "cuMemsetD8_v2", "libcuda.so.1");
        if (!real_cuMemsetD8 && h) real_cuMemsetD8 = dlsym(h, "cuMemsetD8_v2");
    }
    if (real_cuMemsetD8) return real_cuMemsetD8(dstDevice, uc, N);
    return 800;
}

static CUresult stub_cuDriverGetVersion(int* driverVersion) {
    if (driverVersion) *driverVersion = 13000; /* Spoof CUDA 13.0 driver for Modular MAX 26.8.0 */
    return 0;
}

void* dlsym(void* handle, const char* symbol) {
    static void* (*real_dlsym)(void*, const char*) = NULL;
    if (!real_dlsym) {
        real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
        if (!real_dlsym) real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    }
    if (symbol && symbol[0] == 'c' && symbol[1] == 'u') {
        if (strcmp(symbol, "cuFuncGetParamInfo") == 0) return (void*)stub_cuFuncGetParamInfo;
        if (strcmp(symbol, "cuMemcpyBatchAsync") == 0) return (void*)stub_cuMemcpyBatchAsync;
        if (strcmp(symbol, "cuMemcpyBatch") == 0) return (void*)stub_cuMemcpyBatch;
        if (strcmp(symbol, "cuMemset") == 0) return (void*)stub_cuMemset;
        if (strcmp(symbol, "cuDriverGetVersion") == 0) return (void*)stub_cuDriverGetVersion;
    }
    return real_dlsym(handle, symbol);
}
