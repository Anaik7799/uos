# Equivalent bounded command surface; one shared OCaml operational core.
# No credential is read or printed by this argv-only native facade.
from std.sys import argv, exit
from std.ffi import external_call, c_int

def main() raises:
    var args = argv()
    var own = String(args[0])
    var suffix = String("tools/ecology_credential.mojo")
    if not own.endswith(suffix):
        raise Error("invoke tools/ecology_credential.mojo by its source filename")
    var root = String(own[byte=0:own.byte_length() - suffix.byte_length()])
    var ocaml = root + "toolchains/opam-ocaml/bin/ocaml"
    var backend = root + "tools/ecology_credential.ml"
    var command = String("__invalid_cli__")
    if len(args) == 2:
        command = String(args[1])
    if command.byte_length() > 64:
        command = "__invalid_cli__"
    var executable_c = ocaml.as_c_string_slice()
    var backend_c = backend.as_c_string_slice()
    var command_c = command.as_c_string_slice()
    _ = external_call["execl", c_int, num_fixed_args=2](
        executable_c.unsafe_ptr(), executable_c.unsafe_ptr(),
        backend_c.unsafe_ptr(), command_c.unsafe_ptr(), Int(0))
    exit(125)
