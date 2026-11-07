from std.sys import argv, exit
from std.ffi import external_call, c_int

def main() raises:
    var args = argv()
    if len(args) == 2 and args[1] == "selection-table":
        for a in range(1, 6):
            for b in range(1, 6):
                for ready in range(2):
                    for failed in range(2):
                        var answer = 1
                        if ready == 0:
                            answer = -1
                        elif a * (1 + failed) >= b:
                            answer = 0
                        print(a, b, ready, failed, answer)
        return
    var own_path = String(args[0])
    if not own_path.endswith("evolution_cycles.mojo"):
        exit(2)
    var directory = own_path.replace("evolution_cycles.mojo", "")
    var ocaml = String("/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml")
    var flag_i = String("-I")
    var backend = directory + "evolution_cycles.ml"
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
