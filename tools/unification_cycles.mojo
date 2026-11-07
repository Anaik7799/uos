from std.sys import argv, exit
from std.ffi import external_call, c_int

def selection(a: Int, b: Int, ready: Bool, failed: Bool) -> Int:
    if not ready:
        return -1
    var urgency = a
    if failed:
        urgency *= 2
    if urgency >= b:
        return 0
    return 1

def main() raises:
    var args = argv()
    if len(args) == 2 and args[1] == "selection-table":
        for a in range(1, 6):
            for b in range(1, 6):
                for ready in range(2):
                    for failed in range(2):
                        print(a, b, ready, failed, selection(a, b, ready == 1, failed == 1))
        return
    var own_path = String(args[0])
    if not own_path.endswith("unification_cycles.mojo"):
        print("Expected source script path")
        exit(2)
    var directory = own_path.replace("unification_cycles.mojo", "")
    var ocaml = String("/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml")
    var flag_i = String("-I")
    var backend = directory + "unification_cycles.ml"
    var a1 = String(args[1]) if len(args) > 1 else String("")
    var a2 = String(args[2]) if len(args) > 2 else String("")
    var a3 = String(args[3]) if len(args) > 3 else String("")
    var ocaml_c = ocaml.as_c_string_slice()
    var flag_i_c = flag_i.as_c_string_slice()
    var dir_c = directory.as_c_string_slice()
    var backend_c = backend.as_c_string_slice()
    var a1_c = a1.as_c_string_slice()
    var a2_c = a2.as_c_string_slice()
    var a3_c = a3.as_c_string_slice()
    if len(args) == 4:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml_c.unsafe_ptr(), ocaml_c.unsafe_ptr(),
            flag_i_c.unsafe_ptr(), dir_c.unsafe_ptr(), backend_c.unsafe_ptr(),
            a1_c.unsafe_ptr(), a2_c.unsafe_ptr(), a3_c.unsafe_ptr(), Int(0))
    elif len(args) == 3:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml_c.unsafe_ptr(), ocaml_c.unsafe_ptr(),
            flag_i_c.unsafe_ptr(), dir_c.unsafe_ptr(), backend_c.unsafe_ptr(),
            a1_c.unsafe_ptr(), a2_c.unsafe_ptr(), Int(0))
    elif len(args) == 2:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml_c.unsafe_ptr(), ocaml_c.unsafe_ptr(),
            flag_i_c.unsafe_ptr(), dir_c.unsafe_ptr(), backend_c.unsafe_ptr(),
            a1_c.unsafe_ptr(), Int(0))
    else:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml_c.unsafe_ptr(), ocaml_c.unsafe_ptr(),
            flag_i_c.unsafe_ptr(), dir_c.unsafe_ptr(), backend_c.unsafe_ptr(), Int(0))
    exit(125)
