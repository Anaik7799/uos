#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <sys/ioctl.h>
#include <linux/kvm.h>
#include <unistd.h>
#include <fcntl.h>

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
