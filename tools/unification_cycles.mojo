from std.sys import argv, exit
from std.python import Python

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
    var command: List[String] = ["/home/an/dev/ver/zigvm/_opam/bin/ocaml", "-I", directory, directory + "unification_cycles.ml"]
    for i in range(1, len(args)):
        command.append(String(args[i]))
    var builtins = Python.import_module("builtins")
    var os = Python.import_module("os")
    var forwarded = builtins.list()
    for arg in command:
        forwarded.append(arg)
    os.execv(command[0], forwarded)
    exit(125)
