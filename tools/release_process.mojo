# Same operational CLI as release_process.ml; all effects use its single native core.
# Only the finite prefix-state interpreter below is independent.
from std.sys import argv, exit
from std.python import Python

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
    var command: List[String] = ["/home/an/dev/ver/zigvm/_opam/bin/ocaml", backend]
    for index in range(1, len(args)):
        command.append(String(args[index]))
    # execv preserves argv, exit status, signals and the core's deadlines exactly.
    # Python standard library only; no package or Python installation is performed.
    var builtins = Python.import_module("builtins")
    var os = Python.import_module("os")
    var forwarded = builtins.list()
    for index in range(len(command)):
        forwarded.append(command[index])
    os.execv(command[0], forwarded)
    exit(125)
