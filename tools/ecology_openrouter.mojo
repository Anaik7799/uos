# @agent_intent: Equivalent argv-only facade for the OCaml calibration runner.
# @laws: Same core, no Python/shell, no alternate budget path; exec exit parity.
from std.sys import argv, exit
from std.ffi import external_call, c_int

def main() raises:
    var args = argv()
    var own = String(args[0])
    var suffix = String("tools/ecology_openrouter.mojo")
    if not own.endswith(suffix):
        raise Error("invoke tools/ecology_openrouter.mojo by its source filename")
    var root = String(own[byte=0:own.byte_length() - suffix.byte_length()])
    var ocaml = root + "toolchains/opam-ocaml/bin/ocaml"
    var backend = root + "tools/ecology_openrouter.ml"
    var command = String("__invalid_cli__")
    var payload = String("")
    if len(args) == 3:
        command = String(args[1])
        payload = String(args[2])
    if command.byte_length() > 32 or payload.byte_length() > 131072:
        command = "__invalid_cli__"
        payload = ""
    var executable_c = ocaml.as_c_string_slice()
    var backend_c = backend.as_c_string_slice()
    var command_c = command.as_c_string_slice()
    var payload_c = payload.as_c_string_slice()
    _ = external_call["execl", c_int, num_fixed_args=2](
        executable_c.unsafe_ptr(), executable_c.unsafe_ptr(),
        backend_c.unsafe_ptr(), command_c.unsafe_ptr(),
        payload_c.unsafe_ptr(), Int(0))
    exit(125)
