# SC-PROVENANCE-001 — Mojo kernel + C NIF facade build.
#
# Produces two artifacts:
#   libuos_km_kernel.so  the Mojo kernel, C ABI
#   uos_km_nif.so        the Erlang NIF facade, linked against the kernel
#
# ERTS headers are located from the running erl, so the NIF matches the OTP that
# will load it. A missing toolchain fails the build rather than emitting a stub.

REPO       := $(shell cd ../../.. && pwd)
MOJO       := $(REPO)/tools/mojo
PRIV       := $(REPO)/apps/cepaf_gleam/priv
ERTS_DIR   := $(shell erl -noshell -eval 'io:format("~s",[code:root_dir()]),halt().')
ERTS_INC   := $(shell erl -noshell -eval 'io:format("~s/erts-~s/include",[code:root_dir(),erlang:system_info(version)]),halt().')

KERNEL_SO  := $(PRIV)/libuos_km_kernel.so
NIF_SO     := $(PRIV)/uos_km_nif.so

CFLAGS     := -O2 -fPIC -Wall -Wextra -std=c11
LDFLAGS    := -shared

.PHONY: all clean test otp29

all: $(NIF_SO)

$(PRIV):
	mkdir -p $(PRIV)

$(KERNEL_SO): uos_km_kernel.mojo | $(PRIV)
	$(MOJO) build --emit shared-lib uos_km_kernel.mojo -o $(KERNEL_SO)

$(NIF_SO): uos_km_nif.c $(KERNEL_SO)
	$(CC) $(CFLAGS) -I$(ERTS_INC) $(LDFLAGS) -o $(NIF_SO) uos_km_nif.c \
	  -L$(PRIV) -l:libuos_km_kernel.so -Wl,-rpath,'$$ORIGIN'

# Independent C oracle: expected values are computed in C, never by the kernel.
test: $(KERNEL_SO)
	$(CC) -O2 -o /tmp/uos_km_oracle test_uos_km_kernel.c $(KERNEL_SO) -lm \
	  -Wl,-rpath,$(PRIV)
	/tmp/uos_km_oracle

clean:
	rm -f $(KERNEL_SO) $(NIF_SO)

# The running indrajaal-web release is OTP 29 (erts 17) from nix, while the
# system erl is OTP 27. A NIF must match the OTP that loads it, so build a
# second object against the OTP 29 headers when that toolchain is present.
OTP29_ROOT := /nix/store/qq9f90d5giydnhpdxlqq83n21c22jq0b-erlang-29.0.6
OTP29_INC  := $(OTP29_ROOT)/lib/erlang/erts-17.0.6/include
NIF_SO_29  := $(PRIV)/uos_km_nif_otp29.so

otp29: $(KERNEL_SO)
	@test -d "$(OTP29_INC)" || { echo "OTP 29 headers absent at $(OTP29_INC)"; exit 2; }
	$(CC) $(CFLAGS) -I$(OTP29_INC) $(LDFLAGS) -o $(NIF_SO_29) uos_km_nif.c \
	  -L$(PRIV) -l:libuos_km_kernel.so -Wl,-rpath,'$$ORIGIN'
