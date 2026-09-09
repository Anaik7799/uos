# @agent_intent: Equivalent argv-only entrypoint to ecology_release.ml.
# @laws: The OCaml core owns validation, bounds and effects; exec preserves its
# exit status and signals. No Python, shell, package installation or PATH lookup.
# Run using the existing pinned MAX environment with --no-install --frozen.
from std.sys import argv, exit
from std.ffi import external_call, c_int

def main() raises:
    var args = argv()
    var own = String(args[0])
    var suffix = String("tools/ecology_release.mojo")
    if not own.endswith(suffix):
        raise Error("invoke tools/ecology_release.mojo by its source filename")
    var root = String(own[byte=0:own.byte_length() - suffix.byte_length()])
    var ocaml = root + "toolchains/opam-ocaml/bin/ocaml"
    var backend = root + "tools/ecology_release.ml"
    # The finite CLI accepts one command and at most one path. Invalid argc is
    # sent to the same core failure path without unbounded argv construction.
    var command = String("__invalid_cli__")
    if len(args) == 2 or len(args) == 3:
        command = String(args[1])
    var path = String("")
    if len(args) == 3:
        path = String(args[2])
    if command.byte_length() > 4096 or path.byte_length() > 4096:
        command = "__invalid_cli__"
        path = ""
    # execl has two fixed arguments. Int(0) is the null pointer sentinel on the
    # supported Linux x86_64 ABI; all preceding variadic arguments are C strings.
    if len(args) == 3:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml.as_c_string_slice().unsafe_ptr(),
            ocaml.as_c_string_slice().unsafe_ptr(),
            backend.as_c_string_slice().unsafe_ptr(),
            command.as_c_string_slice().unsafe_ptr(),
            path.as_c_string_slice().unsafe_ptr(), Int(0))
    else:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml.as_c_string_slice().unsafe_ptr(),
            ocaml.as_c_string_slice().unsafe_ptr(),
            backend.as_c_string_slice().unsafe_ptr(),
            command.as_c_string_slice().unsafe_ptr(), Int(0))
    exit(125)
