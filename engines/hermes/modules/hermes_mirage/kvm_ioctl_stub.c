#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <sys/ioctl.h>
#include <linux/kvm.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>

CAMLprim value caml_kvm_get_api_version(value v_unit) {
    CAMLparam1(v_unit);
    int fd = open("/dev/kvm", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        CAMLreturn(Val_int(-1));
    }
    int ver = ioctl(fd, KVM_GET_API_VERSION, 0);
    close(fd);
    CAMLreturn(Val_int(ver));
}

CAMLprim value caml_monotonic_now_sec(value v_unit) {
    CAMLparam1(v_unit);
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double sec = (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
    CAMLreturn(caml_copy_double(sec));
}
