# @agent_intent: Equivalent argv/stdin facade for the OCaml budget ledger.
# @laws: No network, shell or Python; exec preserves exit status and signals.
# The same core validates every argument and performs the atomic reservation.
from std.sys import argv, exit
from std.ffi import external_call, c_int

def main() raises:
    var args = argv()
    var own = String(args[0])
    var suffix = String("tools/ecology_budget.mojo")
    if not own.endswith(suffix):
        raise Error("invoke tools/ecology_budget.mojo by its source filename")
    var root = String(own[byte=0:own.byte_length() - suffix.byte_length()])
    var ocaml = root + "toolchains/opam-ocaml/bin/ocaml"
    var backend = root + "tools/ecology_budget.ml"
    var command = String("__invalid_cli__")
    if len(args) == 2 or len(args) == 3:
        command = String(args[1])
    var path = String("")
    if len(args) == 3:
        path = String(args[2])
    if command.byte_length() > 4096 or path.byte_length() > 4096:
        command = "__invalid_cli__"
        path = ""
    var executable_c = ocaml.as_c_string_slice()
    var backend_c = backend.as_c_string_slice()
    var command_c = command.as_c_string_slice()
    var path_c = path.as_c_string_slice()
    if len(args) == 3:
        _ = external_call["execl", c_int, num_fixed_args=2](
            executable_c.unsafe_ptr(), executable_c.unsafe_ptr(),
            backend_c.unsafe_ptr(), command_c.unsafe_ptr(),
            path_c.unsafe_ptr(), Int(0))
    else:
        _ = external_call["execl", c_int, num_fixed_args=2](
            executable_c.unsafe_ptr(), executable_c.unsafe_ptr(),
            backend_c.unsafe_ptr(), command_c.unsafe_ptr(), Int(0))
    exit(125)
