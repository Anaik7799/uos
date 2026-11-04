#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>

typedef int CUresult;

static CUresult stub_cuFuncGetParamInfo(void* func, size_t paramIndex, size_t* paramOffset, size_t* paramSize) {
    if (paramOffset) *paramOffset = paramIndex * 8;
    if (paramSize) *paramSize = 8;
    return 800; /* CUDA_ERROR_NOT_SUPPORTED */
}

static CUresult stub_cuMemcpyBatchAsync(void* dsts, void* srcs, void* sizes, size_t count, void* attrs, void* attrIdxs, size_t numAttrs, void* failIdx, void* hStream) {
    return 800;
}

static CUresult stub_cuMemcpyBatch(void* dsts, void* srcs, void* sizes, size_t count, void* attrs, void* attrIdxs, size_t numAttrs, void* failIdx, void* hStream) {
    return 800;
}

static CUresult stub_cuMemset(uint64_t dstDevice, unsigned char uc, size_t N) {
    static CUresult (*real_cuMemsetD8)(uint64_t, unsigned char, size_t) = NULL;
    if (!real_cuMemsetD8) {
        void* h = dlopen("/usr/lib/wsl/lib/libcuda.so.1.1", RTLD_LAZY | RTLD_GLOBAL);
        if (h) real_cuMemsetD8 = dlvsym(h, "cuMemsetD8_v2", "libcuda.so.1");
        if (!real_cuMemsetD8 && h) real_cuMemsetD8 = dlsym(h, "cuMemsetD8_v2");
    }
    if (real_cuMemsetD8) return real_cuMemsetD8(dstDevice, uc, N);
    return 800;
}

static CUresult stub_cuDriverGetVersion(int* driverVersion) {
    if (driverVersion) *driverVersion = 13000; /* Spoof CUDA 13.0 driver */
    return 0;
}

void* dlsym(void* handle, const char* symbol) {
    static void* (*real_dlsym)(void*, const char*) = NULL;
    if (!real_dlsym) {
        real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
        if (!real_dlsym) real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    }
    if (symbol) {
        if (strcmp(symbol, "cuFuncGetParamInfo") == 0) return (void*)stub_cuFuncGetParamInfo;
        if (strcmp(symbol, "cuMemcpyBatchAsync") == 0) return (void*)stub_cuMemcpyBatchAsync;
        if (strcmp(symbol, "cuMemcpyBatch") == 0) return (void*)stub_cuMemcpyBatch;
        if (strcmp(symbol, "cuMemset") == 0) return (void*)stub_cuMemset;
        if (strcmp(symbol, "cuDriverGetVersion") == 0) return (void*)stub_cuDriverGetVersion;
    }
    return real_dlsym(handle, symbol);
}
