# Same operational CLI as release_process.ml; all effects use its single native core.
# Only the finite prefix-state interpreter below is independent.
from std.sys import argv, exit
from std.ffi import external_call, c_int

def next_stage(current: Int, incoming: Int, valid: Bool) -> Int:
    if current < 0 or current >= 12 or incoming != current or not valid:
        return -1
    return current + 1

def main() raises:
    var args = argv()
    if len(args) == 2 and args[1] == "model-table":
        for current in range(13):
            for incoming in range(13):
                for valid in range(2):
                    print(current, incoming, valid, next_stage(current, incoming, valid == 1))
        return
    if len(args) == 2 and args[1] == "model-selftest":
        var checks = 0
        for current in range(13):
            for incoming in range(13):
                for valid in range(2):
                    var expected = -1
                    if current < 12 and current == incoming and valid == 1:
                        expected = current + 1
                    if next_stage(current, incoming, valid == 1) != expected:
                        raise Error("prefix semantics disagree")
                    checks += 1
        print('{"schema":"uos.release-check.v1","stage":"model-selftest","status":"PASS","authority":"NONE","checks":' + String(checks) + '}')
        return
    var own_path = String(args[0])
    if not own_path.endswith("release_process.mojo"):
        raise Error("invoke this Mojo script by its canonical source filename")
    var backend = own_path.replace("release_process.mojo", "release_process.ml")
    var ocaml = String("/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml")
    var a1 = String(args[1]) if len(args) > 1 else String("")
    var a2 = String(args[2]) if len(args) > 2 else String("")
    var a3 = String(args[3]) if len(args) > 3 else String("")
    var ocaml_c = ocaml.as_c_string_slice()
    var backend_c = backend.as_c_string_slice()
    var a1_c = a1.as_c_string_slice()
    var a2_c = a2.as_c_string_slice()
    var a3_c = a3.as_c_string_slice()
    # execl preserves argv, exit status, signals and the core's deadlines with zero Python.
    if len(args) == 4:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml_c.unsafe_ptr(), ocaml_c.unsafe_ptr(),
            backend_c.unsafe_ptr(), a1_c.unsafe_ptr(), a2_c.unsafe_ptr(), a3_c.unsafe_ptr(), Int(0))
    elif len(args) == 3:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml_c.unsafe_ptr(), ocaml_c.unsafe_ptr(),
            backend_c.unsafe_ptr(), a1_c.unsafe_ptr(), a2_c.unsafe_ptr(), Int(0))
    elif len(args) == 2:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml_c.unsafe_ptr(), ocaml_c.unsafe_ptr(),
            backend_c.unsafe_ptr(), a1_c.unsafe_ptr(), Int(0))
    else:
        _ = external_call["execl", c_int, num_fixed_args=2](
            ocaml_c.unsafe_ptr(), ocaml_c.unsafe_ptr(),
            backend_c.unsafe_ptr(), Int(0))
    exit(125)
