# onnxruntime C API header, vendored

`onnxruntime_c_api.h` from **v1.28.0**, matching the
`libonnxruntime.so.1.28.0` that ships in the pip wheel at
`venv/lib/python3.13/site-packages/onnxruntime/capi/`.

Vendored because the wheel ships the shared library but **no headers**,
and without the header the `OrtApi` struct layout is guesswork. A wrong
offset there does not fail to compile — it calls the wrong function
pointer and segfaults inside the harness's own address space.

## The layout problem, and why it is smaller than it looks

`struct OrtApi` (line 1294) is **400 function pointers**. Reproducing
that in Ctypes field-by-field with correct signatures would be a large,
version-fragile transcription.

It is not necessary. **Every field is a function pointer, so every field
is the same width.** The struct can be treated as an array of
pointer-sized cells, indexed by ordinal, with only the handful actually
called coerced to their real signatures. `ortapi-field-order.txt` is the
ordered field list extracted from this header, so the ordinal of any
entry point is a fact rather than a count.

## The ordinals for a minimal detection path

    4   CreateEnv   (NOT 1 — see below)
    8   CreateSession
    10  Run
    30  SessionGetInputCount
    50  CreateTensorWithDataAsOrtValue
    52  GetTensorMutableData
    70  CreateCpuMemoryInfo

Reached via `OrtGetApiBase()` -> `GetApi(ORT_API_VERSION)`.

## Regenerating the field order

    awk 'NR>1294 && /^\};/{exit} NR>1294' onnxruntime_c_api.h \
      | grep -oE "ORT_API2_STATUS\(([A-Za-z0-9_]+)|ORT_API_T\(.*, ([A-Za-z0-9_]+)" \
      | sed -E 's/.*[(,] *//; s/ORT_API2_STATUS\(//' | nl -ba

**If the .so version ever changes, re-vendor the matching header and
regenerate this table.** Ordinals are not stable across ORT versions,
and a stale table is exactly the silent-segfault case this file exists
to prevent.

## Runtime note

The venv's Python needs `libz.so.1`, which is absent from the system
path. `LD_LIBRARY_PATH=/home/an/hello-world/.pixi/envs/default/lib`
resolves it; `apt install zlib1g` is the durable fix. Without it numpy
fails with a message about importing from its source directory, which is
misleading — the real cause is on the following line.

## The off-by-three, and how it was caught

The first extraction grepped only `ORT_API2_STATUS(...)` forms. The
struct's first three fields — `CreateStatus`, `GetErrorCode`,
`GetErrorMessage` — return values other than `OrtStatus*` and use a
different macro, so none of them matched. **Every ordinal in the first
table was three too low.**

Calling ordinal 1 as `CreateEnv` therefore invoked `CreateStatus`, which
happens to accept an int and a string and return a pointer — so it did
not crash, it returned a plausible-looking non-null "status" and the
probe reported a clean failure. A wrong ordinal that segfaults is easy;
one that *returns* is what makes this table worth pinning.

It surfaced because the safety gate runs the first call in a CHILD
process. In-process, a less compatible signature would have taken the
harness down with no record of why.

The regeneration command above now matches both macro forms. **Verify a
regenerated table by checking that `CreateStatus` is ordinal 1** — if it
is not, the extraction has missed a prefix again.
