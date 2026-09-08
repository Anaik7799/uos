from std.sys import argv, exit
from std.python import Python

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
    var command: List[String] = ["/home/an/dev/ver/zigvm/_opam/bin/ocaml", "-I", directory, directory + "evolution_cycles.ml"]
    for i in range(1, len(args)):
        command.append(String(args[i]))
    var builtins = Python.import_module("builtins")
    var os = Python.import_module("os")
    var forwarded = builtins.list()
    for arg in command:
        forwarded.append(arg)
    os.execv(command[0], forwarded)
    exit(125)
