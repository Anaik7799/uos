//! zigvm E0.2: the executable entry point — argv/file/stdout plumbing ONLY.
//!
//! All behavior lives in `cli.run` (a pure composition over the existing
//! algebras). `main` parses argv, reads the `.beam` file (absolute or cwd),
//! calls `cli.run`, writes its formatted output to stdout, and exits with the
//! returned status. Subcommands: `run <path.beam> <fn> [args…]` (E5.1: args are
//! term literals — int / atom / "string" — via `cli.parseArg`),
//! `check-load <path.beam>` (E1.2: loader-acceptance — parse+translate only,
//! no execution; prints `load-ok`/`load-reject <op>/<arity>`), `bench`,
//! `scale` (E6.9: the SMP scaling workload, prints `throughput`), `dump-caps`,
//! `dist-digest` (E18.1: the handshake challenge digest), `etf-reencode`/
//! `term-compare` (E18.2: the cross-node term-transport & total-order surface
//! the `--run-dist-term` harness cross-checks against the pinned OTP-30 peer),
//! and `version`. Anything else prints usage to stderr and exits 2.

const std = @import("std");
const cli = @import("cli.zig");
const apoptosis = @import("apoptosis.zig");
const max_fabric = @import("max_fabric.zig");

const version_string = "zigvm 0.1.0";
const usage_string =
    \\usage:
    \\  zigvm run <path.beam> [--pa <dep.beam>]* [--code-path <dir>]* [--resident] <fn> [args...]
    \\                                         run an exported function
    \\                                         (--pa links dependency modules;
    \\                                          --code-path DIR autoloads <Module>.beam
    \\                                          on demand from DIR (a real app's dep tree);
    \\                                          --resident boots an always-on node that
    \\                                          STAYS UP serving a supervised tree;
    \\                                          args are term literals: 42, an_atom,
    \\                                          'Quoted Atom', or "a string")
    \\  zigvm check-load <path.beam>           loader-acceptance: parse+translate, no exec
    \\  zigvm dist-digest <cookie> <challenge> OTP-30 handshake challenge digest (lower-hex)
    \\  zigvm dist-connect <peer@host> <cookie> <me@host> [hold_iters] [epmd_port]
    \\                                         live v6 handshake to a booted OTP-30 peer
    \\  zigvm dist-reverse <peer@host> <cookie> <me@host> [hold_iters] [epmd_port]
    \\                                         live v6 handshake; a running VM's OWN
    \\                                         nodes/0 reflects the connected peer
    \\  zigvm dist-accept <me@host> <cookie> [hold_iters] [epmd_port]
    \\                                         register with epmd + listen; ACCEPT an
    \\                                         inbound v6 dial-in (a peer net_adm:pings us)
    \\  zigvm dist-recv <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
    \\                                         live signals carrier; decode an inbound
    \\                                         DOP REG_SEND into a VM mailbox, print hex
    \\  zigvm dist-send <peer@host> <cookie> <me@host> <regname> <hexterm> [epmd_port]
    \\                                         live signals carrier; send a DOP REG_SEND
    \\                                         of the term to a registered peer process
    \\  zigvm dist-monitor <peer@host> <cookie> <me@host> <targetname> [iters] [epmd_port]
    \\                                         live signals carrier; MONITOR_P a peer proc,
    \\                                         deliver the 'DOWN' (wire reason, or
    \\                                         noconnection on teardown) to a VM mailbox
    \\  zigvm dist-link <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
    \\                                         live signals carrier; LINK a peer pid received
    \\                                         over REG_SEND, deliver {'EXIT',Pid,Reason} on
    \\                                         the peer proc's death to a VM mailbox
    \\  zigvm dist-exit2 <peer@host> <cookie> <me@host> <regname> <reason> [iters] [epmd_port]
    \\                                         live signals carrier; EXIT2 a peer pid received
    \\                                         over REG_SEND, killing it with <reason>
    \\  zigvm dist-demonitor <peer@host> <cookie> <me@host> <targetname> [iters] [epmd_port]
    \\                                         live signals carrier; MONITOR_P then DEMONITOR_P
    \\                                         a peer proc — the retract fires no 'DOWN'
    \\  zigvm dist-unlink <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
    \\                                         live signals carrier; LINK a peer pid received over
    \\                                         REG_SEND, then UNLINK_ID it — the peer ACKs (op 36)
    \\  zigvm dist-inexit2 <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
    \\                                         live signals carrier; send a local victim pid to a
    \\                                         peer proc which exit/2's it — zigvm kills the victim
    \\  zigvm dist-exit1 <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
    \\                                         live signals carrier; LINK a peer pid received over
    \\                                         REG_SEND that exit/1(normal)s — deliver {'EXIT',Pid,normal}
    \\  zigvm dist-global <peer@host> <cookie> <me@host> [iters] [epmd_port]
    \\                                         live signals carrier; register global_name_server,
    \\                                         observe the peer global's init_connect cast
    \\  zigvm dist-pg <peer@host> <cookie> <me@host> [iters] [epmd_port]
    \\                                         live signals carrier; register pg scope, observe
    \\                                         the peer pg scope's discover broadcast
    \\  zigvm dist-pg-join <peer@host> <cookie> <me@host> <group> [iters] [epmd_port]
    \\                                         live signals carrier; register pg scope + a member,
    \\                                         answer the peer's discover with local_data so the
    \\                                         peer's pg:get_members converges to include our member
    \\  zigvm global-register <peer@host> <cookie> <me@host> <name> [iters] [epmd_port]
    \\                                         E21 live 2-phase global register: $gen_call set_lock →
    \\                                         register(name,pid) → del_lock over dist so the name is
    \\                                         visible from the peer's global:whereis_name (single-owner)
    \\  zigvm dist-mesh <cookie> <me@host> <iters> <peerA@host> <peerB@host> [epmd_port]
    \\                                         E20 multi-node: hold TWO live carriers at once; zigvm's
    \\                                         own nodes/0 lists BOTH peers (transitive triad), then
    \\                                         teardown empties it
    \\  zigvm dist-pg-mesh <cookie> <me@host> <group> <iters> <peerA@host> <peerB@host> [epmd_port]
    \\                                         E20 multi-node: register pg scope + a member, cast
    \\                                         local_data to BOTH peers so a member on zigvm's node is
    \\                                         visible from all three
    \\  zigvm dist-pg-heal <cookie> <me@host> <group> <phase_iters> <peerA@host> <peerB@host> [epmd_port]
    \\                                         E20 multi-node: cast to A+B, PARTITION (drop B) so B
    \\                                         retracts the member, then HEAL (reconnect B + recast) so
    \\                                         B reconverges; A witnesses continuity
    \\  zigvm etf-reencode <hex>               decode ETF bytes and re-encode (lower-hex)
    \\  zigvm term-compare <hexA> <hexB> [exact]  print lt/eq/gt for two ETF terms
    \\  zigvm bench <unit> <iters>             run a microbench, print ops_per_s
    \\  zigvm scale <unit> <n_sched>           run the SMP scaling workload, print throughput
    \\  zigvm reds <workload> <N>              run a matched halting workload, print reds + result
    \\  zigvm eval "<Expr>"                    evaluate an Erlang -eval expression (erlang:display output)
    \\  zigvm dump-caps                        print the capability ledger
    \\  zigvm max-status                       print bare-metal MAX inference fabric status
    \\  zigvm max-selftest                     run bare-metal MAX/Mojo selftest supervised by ZigVM
    \\  zigvm max-gemma4                       run bare-metal Gemma 4 local AI selftest supervised by ZigVM
    \\  zigvm max-infer "<prompt>"             execute local inference on bare-metal MAX computational fabric
    \\  zigvm version                          print the version
    \\
;

/// Read up to 64 MiB of a `.beam` file — generous for BEAM modules.
const beam_read_limit: std.Io.Limit = .limited(64 << 20);

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;

    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    // argv[0] is the program name; the subcommand is argv[1].
    if (argv.len < 2) return usage(io);

    const cmd = argv[1];

    if (std.mem.eql(u8, cmd, "version")) {
        try writeStdout(io, version_string ++ "\n");
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dump-caps")) {
        // Machine-readable capability ledger, one line per implemented op/BIF.
        // Same out-param composition as `run`: cli.dumpCaps builds the text, we
        // flush it to stdout and exit 0.
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        cli.dumpCaps(gpa, &out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: dump-caps failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "max-status")) {
        var fabric = max_fabric.MaxFabric.init(gpa);
        defer fabric.deinit();
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        fabric.statusJson(&out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: max-status failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "max-selftest")) {
        var fabric = max_fabric.MaxFabric.init(gpa);
        defer fabric.deinit();
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const ok = fabric.runSelftest(&out) catch false;
        try writeStdout(io, out.items);
        return if (ok) 0 else 1;
    }

    if (std.mem.eql(u8, cmd, "max-gemma4")) {
        var fabric = max_fabric.MaxFabric.init(gpa);
        defer fabric.deinit();
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const ok = fabric.runGemma4Selftest(&out) catch false;
        try writeStdout(io, out.items);
        return if (ok) 0 else 1;
    }

    if (std.mem.eql(u8, cmd, "max-infer")) {
        if (argv.len < 3) {
            try writeStderr(io, "usage: zigvm max-infer \"<prompt>\"\n");
            return 2;
        }
        const prompt = argv[2];
        var fabric = max_fabric.MaxFabric.init(gpa);
        defer fabric.deinit();
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        fabric.infer(prompt, 64, &out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: max-infer failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "bench")) {
        // bench <unit> <iters> — print a single `ops_per_s <float>` line.
        if (argv.len < 4) return usage(io);
        const unit = argv[2];
        const iters = std.fmt.parseInt(u64, argv[3], 10) catch {
            try writeStderr(io, "zigvm: bench iters must be a non-negative integer\n");
            return 2;
        };
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const status = cli.bench(gpa, io, unit, iters, &out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: bench failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 2;
        };
        try writeStdout(io, out.items);
        return status;
    }

    if (std.mem.eql(u8, cmd, "scale")) {
        // scale <unit> <n_sched> — print a single `throughput <float>` line
        // (grants/sec) for the SMP scaling workload at n_sched schedulers.
        if (argv.len < 4) return usage(io);
        const unit = argv[2];
        const n_sched = std.fmt.parseInt(u32, argv[3], 10) catch {
            try writeStderr(io, "zigvm: scale n_sched must be a positive integer\n");
            return 2;
        };
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const status = cli.scale(gpa, io, unit, n_sched, &out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: scale failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 2;
        };
        try writeStdout(io, out.items);
        return status;
    }

    if (std.mem.eql(u8, cmd, "reds")) {
        // reds <workload> <N> — run a matched HALTING workload to completion and
        // print `reds <count>` + `result <value>`. The harness --reduction-oracle
        // mode compares this per-instruction reduction total against the pinned
        // OTP-30 per-call total (the {R} reduction-granularity gap). MEASUREMENT.
        if (argv.len < 4) return usage(io);
        const workload = argv[2];
        const n = std.fmt.parseInt(u64, argv[3], 10) catch {
            try writeStderr(io, "zigvm: reds N must be a non-negative integer\n");
            return 2;
        };
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const status = cli.reds(gpa, workload, n, &out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: reds failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 2;
        };
        try writeStdout(io, out.items);
        return status;
    }

    if (std.mem.eql(u8, cmd, "eval")) {
        // eval "<Expr>" — the `-eval` flag's execution (gap-erl-cli-eval): read a
        // bounded Erlang expression and write its observable output (erlang:display
        // + bare-expr = silent). Byte-EQ vs `erl -noshell -eval "<Expr>" -s init stop`.
        if (argv.len < 3) return usage(io);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        cli.evalExpr(gpa, argv[2], &out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: eval failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 2;
        };
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "agent-eval")) {
        // agent-eval <fn> <arg…> — run an AGENT-AUTHORED, contract-verified unit
        // (src/agent_codegen.zig) on integer args, printing its single integer
        // result. The seam the harness --verify-agent-codegen firewall rides to
        // run the REAL impl on seeded/boundary inputs and check its Aeon contract.
        if (argv.len < 3) return usage(io);
        const fn_name = argv[2];
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const status = cli.agentEval(gpa, fn_name, argv[3..], &out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: agent-eval failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 2;
        };
        try writeStdout(io, out.items);
        return status;
    }

    if (std.mem.eql(u8, cmd, "latency")) {
        // latency <W> <F> <rounds> — run W CPU-bound tail hogs through the LIVE
        // round-robin scheduler with a LatencyHistogram attached, printing the
        // per-grant scheduling-latency distribution. The harness --latency-oracle
        // mode compares this against pinned OTP-30's scheduling signal (the {R}
        // real-time axis). MEASUREMENT.
        if (argv.len < 5) return usage(io);
        const w = std.fmt.parseInt(u64, argv[2], 10) catch {
            try writeStderr(io, "zigvm: latency W must be a positive integer\n");
            return 2;
        };
        const f = std.fmt.parseInt(u64, argv[3], 10) catch {
            try writeStderr(io, "zigvm: latency F must be a positive integer\n");
            return 2;
        };
        const rounds = std.fmt.parseInt(u64, argv[4], 10) catch {
            try writeStderr(io, "zigvm: latency rounds must be a positive integer\n");
            return 2;
        };
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const status = cli.latency(gpa, w, f, rounds, &out) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: latency failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 2;
        };
        try writeStdout(io, out.items);
        return status;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        const proc = @import("proc.zig"); // gap-erl-cli-args: proc.Vm.InitArg view
        // run <path.beam> [--pa <dep.beam>]* <fn> [ints...]
        // `--pa <dep.beam>` flags (E3.12b) may appear anywhere after the
        // subcommand; they name dependency modules linked into one code space so
        // a call_ext in the entry module dispatches ACROSS separately-compiled
        // .beam files. The positional args (entry path, fn, ints) keep their
        // order — the no-flag `run <beam> <fn> <ints>` form is unchanged.
        var dep_paths: std.ArrayList([]const u8) = .empty;
        var code_paths: std.ArrayList([]const u8) = .empty;
        defer code_paths.deinit(gpa);
        defer dep_paths.deinit(gpa);
        var positional: std.ArrayList([]const u8) = .empty;
        defer positional.deinit(gpa);
        var run_opts: cli.RunOptions = .{};
        var i: usize = 2;
        while (i < argv.len) : (i += 1) {
            if (std.mem.startsWith(u8, argv[i], "--experimental-apoptosis-rate=")) {
                const rate_str = argv[i]["--experimental-apoptosis-rate=".len..];
                var rate: usize = 0;
                if (std.mem.endsWith(u8, rate_str, "ms")) {
                    rate = std.fmt.parseInt(usize, rate_str[0 .. rate_str.len - 2], 10) catch {
                        try writeStderr(io, "zigvm: --experimental-apoptosis-rate requires a valid integer before 'ms'\n");
                        return 2;
                    };
                } else {
                    rate = std.fmt.parseInt(usize, rate_str, 10) catch {
                        try writeStderr(io, "zigvm: --experimental-apoptosis-rate requires a valid integer\n");
                        return 2;
                    };
                }
                run_opts.experimental_apoptosis_rate = rate;
            } else if (std.mem.eql(u8, argv[i], "--experimental-zenoh-crdt")) {
                run_opts.experimental_zenoh_crdt = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-wasm-slm")) {
                run_opts.experimental_wasm_slm = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-tailscale")) {
                run_opts.experimental_tailscale = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-gossip")) {
                run_opts.experimental_gossip = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-event-log")) {
                run_opts.experimental_event_log = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-a2ui")) {
                run_opts.experimental_a2ui = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-otlp")) {
                run_opts.experimental_otlp = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-event-wal")) {
                run_opts.experimental_event_wal = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-apoptosis-immunity")) {
                run_opts.experimental_apoptosis_immunity = true;
            } else if (std.mem.eql(u8, argv[i], "--experimental-epmd-bridge")) {
                run_opts.experimental_epmd_bridge = true;
            } else if (std.mem.eql(u8, argv[i], "--resident")) {
                // gap-resident-node: run as a RESIDENT (always-on) node — the
                // supervised tree STAYS UP (driveResident) instead of the one-shot
                // drive that reports an idle-but-alive tree as a deadlock. A halting
                // program is a SAFE SUPERSET (identical result); a stable tree prints
                // `resident: idle (<n> alive)`. This is the first-class CLI node path.
                run_opts.resident = true;
            } else if (std.mem.eql(u8, argv[i], "--pa")) {
                if (i + 1 >= argv.len) {
                    try writeStderr(io, "zigvm: --pa requires a <dep.beam> path\n");
                    return 2;
                }
                i += 1;
                try dep_paths.append(gpa, argv[i]);
            } else if (std.mem.eql(u8, argv[i], "--code-path")) {
                // gap-fs-autoloader: `--code-path <dir>` enables filesystem
                // AUTOLOADING — a dispatchMFA miss loads `<dir>/<Module>.beam`
                // (dirs searched in order, erts code-path semantics) and retries.
                // A real app (its whole transitive stdlib/dep tree) boots by
                // auto-loading from its ebin dir(s) instead of an explicit `--pa`
                // per beam. Dirs are sub-paths under the cwd root.
                if (i + 1 >= argv.len) {
                    try writeStderr(io, "zigvm: --code-path requires a <dir> path\n");
                    return 2;
                }
                i += 1;
                try code_paths.append(gpa, argv[i]);
            } else {
                try positional.append(gpa, argv[i]);
            }
        }
        if (code_paths.items.len > 0) {
            run_opts.autoload = .{ .io = io, .root = std.Io.Dir.cwd(), .code_path = code_paths.items };
        }
        // gap-file-handle-io: wire the real-file-io seam so compiled file:open/pread/
        // pwrite/close/read_file/... resolve real fds under the CWD (the same Io+Dir
        // the autoloader uses). Without this vm.fs is null → file: ops → {error,enoent}.
        run_opts.fs = .{ .io = io, .root = std.Io.Dir.cwd() };
        // gap-hof-stdlib (DIVERGENCE 661): a real `erl` node has the stdlib ambient,
        // so `zigvm run` preloads the HOF-bearing stock `lists`/`maps` — otherwise a
        // compiled `lists:map/2`/`lists:foldl/3`/`maps:fold/3` (Erlang code in OTP,
        // not BIFs) is `undef`. Native `lists:` BIFs (member/reverse) still win.
        run_opts.preload_stdlib = true;
        if (positional.items.len < 1) return usage(io);
        const path = positional.items[0];

        // gap-erl-cli-exec: EXECUTE the OTP `erl` boot flags. When the tokens
        // after the beam carry an init flag (`-s`/`-run`/`-noshell`/`-extra`/…),
        // parse them as an init argv (init.erl grammar) and resolve the entry
        // from the FIRST `-s`/`-run` — `Mod:Func([A,…])` at boot — instead of the
        // positional `<fn> [args]` form. Absent any init flag, the positional
        // form is byte-identical to before.
        var init_arena = std.heap.ArenaAllocator.init(gpa);
        defer init_arena.deinit();
        var has_init_flag = false;
        for (positional.items[1..]) |t| {
            if (cli.isErlInitFlag(t)) {
                has_init_flag = true;
                break;
            }
        }

        var fn_name: []const u8 = undefined;
        var args: std.ArrayList(cli.ArgLit) = .empty;
        defer args.deinit(gpa);
        var run_opts_boot = run_opts;

        if (has_init_flag) {
            const parsed = cli.parseInitArgs(init_arena.allocator(), positional.items[1..]) catch {
                try writeStderr(io, "zigvm: could not parse init flags\n");
                return 2;
            };
            const call = cli.resolveBoot(parsed) orelse {
                // Init flags present, but none of them is an executable boot
                // instruction (`-s`/`-run`). `-eval`/`-config`/`-boot`/`-extra`/
                // `-name` PARSE but need an absent seam — honest rejection.
                try writeStderr(io, "zigvm: no executable boot instruction — only -s/-run are wired (given -eval/-noshell/-name parse but are not yet executed)\n");
                return 2;
            };
            fn_name = call.func;
            for (call.argv) |tok| try args.append(gpa, cli.bootArgLit(call.kind, tok));
            run_opts_boot.boot_list_args = true; // init.erl forces Func/1 on the arg list
            // gap-erl-cli-args (DIVERGENCE 598): expose the parsed init argv to the
            // runtime so init:get_plain_arguments/0 + init:get_argument/1 answer from
            // a compiled beam. Convert cli.InitArgs → the proc-native view (both
            // borrow the init_arena bytes, alive for the whole run).
            const view_flags = try init_arena.allocator().alloc(proc.Vm.InitArg, parsed.flags.len);
            for (parsed.flags, 0..) |fl, fi| view_flags[fi] = .{ .name = fl.name, .values = fl.values };
            run_opts_boot.init_args = .{ .flags = view_flags, .plain = parsed.plain };
        } else {
            if (positional.items.len < 2) return usage(io);
            fn_name = positional.items[1];
            // E5.1: parse each entry argument as a TERM LITERAL (int, atom, or
            // "string") per the documented grammar — a non-literal is a named
            // rejection, never a panic. This carries the module ATOM a generic
            // runner's `main(Module)` needs (DIVERGENCE 49 blocker (1)).
            for (positional.items[2..]) |raw| {
                const a = cli.parseArg(raw) catch {
                    try writeStderr(io, "zigvm: each argument must be a term literal: an integer, an atom (bareword or 'quoted'), or a \"string\"\n");
                    return 2;
                };
                try args.append(gpa, a);
            }
        }

        // Read the entry beam then each dependency; `beams[0]` is the entry.
        var beams: std.ArrayList([]const u8) = .empty;
        defer {
            for (beams.items) |b| gpa.free(b);
            beams.deinit(gpa);
        }
        const readBeam = struct {
            fn f(io_: std.Io, gpa_: std.mem.Allocator, p: []const u8) ![]const u8 {
                return std.Io.Dir.cwd().readFileAlloc(io_, p, gpa_, beam_read_limit);
            }
        }.f;
        {
            const entry_bytes = readBeam(io, gpa, path) catch |err| {
                var buf: [512]u8 = undefined;
                var ew = std.Io.File.stderr().writer(io, &buf);
                ew.interface.print("zigvm: cannot read '{s}': {t}\n", .{ path, err }) catch {};
                ew.interface.flush() catch {};
                return 2;
            };
            try beams.append(gpa, entry_bytes);
        }
        for (dep_paths.items) |dp| {
            const dep_bytes = readBeam(io, gpa, dp) catch |err| {
                var buf: [512]u8 = undefined;
                var ew = std.Io.File.stderr().writer(io, &buf);
                ew.interface.print("zigvm: cannot read '{s}': {t}\n", .{ dp, err }) catch {};
                ew.interface.flush() catch {};
                return 2;
            };
            try beams.append(gpa, dep_bytes);
        }

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const status = cli.runMulti(gpa, beams.items, fn_name, args.items, &out, run_opts_boot) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: run failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        try writeStdout(io, out.items);
        return status;
    }

    if (std.mem.eql(u8, cmd, "check-load")) {
        // check-load <path.beam> — loader-acceptance mode (E1.2): parse+
        // translate ONLY, no execution. Prints `load-ok` (exit 0) or
        // `load-reject <op>/<arity>` naming the first unsupported op (exit 1).
        if (argv.len < 3) return usage(io);
        const path = argv[2];

        const beam_bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, beam_read_limit) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: cannot read '{s}': {t}\n", .{ path, err }) catch {};
            ew.interface.flush() catch {};
            return 2;
        };
        defer gpa.free(beam_bytes);

        const result = cli.checkLoad(gpa, beam_bytes) catch |err| {
            var buf: [512]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: check-load failed: {t}\n", .{err}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        switch (result) {
            .ok => {
                try writeStdout(io, "load-ok\n");
                return 0;
            },
            .unsupported => |u| {
                // `u.name` is gpa-owned (checkLoad duped it); we own and free it.
                defer gpa.free(u.name);
                var line: std.ArrayList(u8) = .empty;
                defer line.deinit(gpa);
                try line.print(gpa, "load-reject {s}/{d}\n", .{ u.name, u.arity });
                try writeStdout(io, line.items);
                return 1;
            },
        }
    }

    if (std.mem.eql(u8, cmd, "dist-digest")) {
        // dist-digest <cookie> <challenge> — print the OTP-30 distribution
        // handshake challenge digest (dist.genDigest) as lower-hex. E18.1:
        // the harness `--run-dist-handshake` mode cross-checks this against a
        // live pinned OTP-30 peer's `erlang:md5([Cookie|itoa(Challenge)])`.
        if (argv.len < 4) return usage(io);
        const cookie = argv[2];
        const challenge = std.fmt.parseInt(u32, argv[3], 10) catch {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("zigvm: dist-digest: bad u32 challenge '{s}'\n", .{argv[3]}) catch {};
            ew.interface.flush() catch {};
            return 2;
        };
        const dist = @import("dist.zig");
        const hex = dist.digestHex(dist.genDigest(cookie, challenge));
        var line: [33]u8 = undefined;
        @memcpy(line[0..32], &hex);
        line[32] = '\n';
        try writeStdout(io, &line);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-connect")) {
        // dist-connect <peer@host> <cookie> <me@host> [hold_iters] [epmd_port]
        // E18.2 (DIVERGENCE 210 residual): the full live v6 distribution
        // carrier. Queries epmd for the peer's dist port, then drives
        // send_name -> recv_status -> recv_challenge -> challenge_reply ->
        // challenge_ack against a booted pinned OTP-30 peer, holding the socket
        // so the peer's nodes(connected) observes zigvm. The harness
        // `--run-dist-handshake` live-carrier driver records the parity verdict.
        if (argv.len < 5) return usage(io);
        const dist = @import("dist.zig");
        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
        };
        if (argv.len >= 6) cfg.hold_iters = std.fmt.parseInt(u32, argv[5], 10) catch cfg.hold_iters;
        if (argv.len >= 7) cfg.epmd_port = std.fmt.parseInt(u16, argv[6], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);
        const out = dist.liveConnect(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        var buf: [256]u8 = undefined;
        var w = std.Io.File.stdout().writer(io, &buf);
        w.interface.print(
            "connected peer={s} port={d} our_challenge={d} peer_challenge={d}\n",
            .{ cfg.peer_node, out.peer_port, out.our_challenge, out.peer_challenge },
        ) catch {};
        w.interface.flush() catch {};
        return 0;
    }

    if (std.mem.eql(u8, cmd, "etf-reencode")) {
        // etf-reencode <hex> — decode a versioned external term (e.g. a pinned
        // OTP-30 peer's `term_to_binary(T)` bytes) and re-encode, printing the
        // result as lower-hex. E18.2: the harness `--run-dist-term` mode
        // cross-checks byte-identity against the peer (wire round-trip fidelity)
        // and confirms the peer's `binary_to_term` accepts our bytes. A term the
        // codec cannot express prints `etf-error:<Name>` (exit 1) — an honest
        // UNTESTED row, never a panic.
        if (argv.len < 3) return usage(io);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        cli.etfReencode(gpa, argv[2], &out) catch |err| {
            var line: std.ArrayList(u8) = .empty;
            defer line.deinit(gpa);
            try line.print(gpa, "etf-error:{s}\n", .{@errorName(err)});
            try writeStdout(io, line.items);
            return 1;
        };
        try out.append(gpa, '\n');
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "term-compare")) {
        // term-compare <hexA> <hexB> [exact] — decode two ETF terms and print
        // their Erlang total-order relation (lt/eq/gt). Default is arithmetic
        // order (matches the peer's `<`/`>`); the optional `exact` selects the
        // `=:=`-refined order. E18.2: the harness checks `zig_cmp == oracle_cmp`
        // per twin-seeded vector against the live peer. Malformed input prints
        // `cmp-error:<Name>` (exit 1), never a panic.
        if (argv.len < 4) return usage(io);
        const exact = argv.len >= 5 and std.mem.eql(u8, argv[4], "exact");
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        cli.termCompare(gpa, argv[2], argv[3], exact, &out) catch |err| {
            var line: std.ArrayList(u8) = .empty;
            defer line.deinit(gpa);
            try line.print(gpa, "cmp-error:{s}\n", .{@errorName(err)});
            try writeStdout(io, line.items);
            return 1;
        };
        try out.append(gpa, '\n');
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-reverse")) {
        // dist-reverse <peer@host> <cookie> <me@host> [hold_iters] [epmd_port]
        // E18.3 (DIVERGENCE 211 residual, REVERSE direction): a RUNNING zigvm VM
        // completes the live v6 handshake to a booted pinned OTP-30 peer, registers
        // the peer in its OWN node table, and prints its own nodes(connected) — then
        // answers ticks (keepalive) and tears the connection down, printing the now-
        // empty node list. The harness `--run-dist-handshake` reverse driver records
        // the parity verdict: zigvm's own nodes/0 reflects the live carrier.
        if (argv.len < 5) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
        };
        if (argv.len >= 6) cfg.hold_iters = std.fmt.parseInt(u32, argv[5], 10) catch cfg.hold_iters;
        if (argv.len >= 7) cfg.epmd_port = std.fmt.parseInt(u16, argv[6], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        // The running VM whose OWN nodes/0 must reflect the peer.
        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const self_pid = try vm.spawn(idle, 0, null);
        const m = &vm.procs.items[self_pid].machine;

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();

        // Bridge the authenticated live carrier into THIS VM's node table.
        const peer_atom = try atoms.intern(cfg.peer_node);
        _ = try vm.registerLiveDistPeer(peer_atom, lc.outcome.peer_creation, @bitCast(lc.outcome.peer_flags));

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try out.appendSlice(gpa, "connected peer=");
        try out.appendSlice(gpa, cfg.peer_node);
        try out.appendSlice(gpa, "\nnodes-connected");
        try appendConnectedNodes(gpa, m, try vm.distLiveNodesTerm(m), &out);
        try out.append(gpa, '\n');

        // Keepalive: answer ticks over the held carrier (bounded).
        lc.holdTicks(gpa, cfg.hold_iters);

        // Teardown: drop the peer; the VM's own nodes/0 must go empty.
        _ = try vm.removeLiveDistPeer(peer_atom);
        try out.appendSlice(gpa, "nodes-after-teardown");
        try appendConnectedNodes(gpa, m, try vm.distLiveNodesTerm(m), &out);
        try out.append(gpa, '\n');

        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-accept")) {
        // dist-accept <me@host> <cookie> [hold_iters] [epmd_port]
        // E21 Task 5 (DIVERGENCE 440 discharge, INBOUND acceptor): a RUNNING zigvm
        // VM registers a distribution port with epmd (ALIVE2_REQ) and LISTENS, so a
        // real pinned OTP-30 peer can `net_adm:ping('zigvm@host')` — DIAL IN — and
        // zigvm ACCEPTS the v6 handshake (the mirror of dist-reverse's initiator).
        // On a verified handshake zigvm registers the peer in its OWN node table,
        // prints its nodes/0, holds ticks (so the peer's nodes/0 keeps showing
        // zigvm), then tears down. Bounded accept: an absent dialer → nonzero exit.
        if (argv.len < 4) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");

        var cfg = dist.AcceptConfig{
            .our_node = argv[2],
            .cookie = argv[3],
        };
        if (argv.len >= 5) cfg.hold_iters = std.fmt.parseInt(u32, argv[4], 10) catch cfg.hold_iters;
        if (argv.len >= 6) cfg.epmd_port = std.fmt.parseInt(u16, argv[5], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const self_pid = try vm.spawn(idle, 0, null);
        const m = &vm.procs.items[self_pid].machine;

        var listener: dist.AcceptListener = undefined;
        var peer_name: std.ArrayList(u8) = .empty;
        defer peer_name.deinit(gpa);
        var lc = dist.liveAcceptOpen(gpa, cfg, prng.random(), &listener, &peer_name) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        defer listener.close();

        // Bridge the ACCEPTED peer into THIS VM's node table.
        const peer_atom = try atoms.intern(peer_name.items);
        _ = try vm.registerLiveDistPeer(peer_atom, lc.outcome.peer_creation, @bitCast(lc.outcome.peer_flags));

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try out.print(gpa, "listening port={d}\n", .{listener.port});
        try out.appendSlice(gpa, "accepted peer=");
        try out.appendSlice(gpa, peer_name.items);
        try out.appendSlice(gpa, "\nnodes-connected");
        try appendConnectedNodes(gpa, m, try vm.distLiveNodesTerm(m), &out);
        try out.append(gpa, '\n');

        // Keepalive: answer the peer's ticks over the accepted carrier (bounded)
        // so the peer's nodes/0 keeps observing zigvm during its read window.
        lc.holdTicks(gpa, cfg.hold_iters);

        // Teardown: drop the peer; the VM's own nodes/0 must go empty.
        _ = try vm.removeLiveDistPeer(peer_atom);
        try out.appendSlice(gpa, "nodes-after-teardown");
        try appendConnectedNodes(gpa, m, try vm.distLiveNodesTerm(m), &out);
        try out.append(gpa, '\n');

        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-recv")) {
        // dist-recv <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
        // E18 Task 3 (DIVERGENCE 212, INBOUND): a RUNNING zigvm VM completes the
        // live v6 handshake (signals flags: no atom cache / fragments), registers
        // a local process under <regname>, then reads inbound DOP control messages
        // off the live packet-4 carrier. When the peer sends `{regname, me} ! T`
        // (a DOP REG_SEND), zigvm decodes it, DELIVERS T into the registered
        // process's mailbox as a real `Vm.signal(.message)`, then re-encodes the
        // DELIVERED mailbox term to lower-hex and prints `delivered <hex>`. The
        // harness compares that hex to the peer's `term_to_binary(T)` — a genuine
        // end-to-end inbound-signal EQ (the message traversed the real socket AND
        // the mailbox). Bounded reads: a silent peer prints `no-message` (exit 0).
        if (argv.len < 6) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");
        const etf = @import("etf.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const regname = argv[5];
        var iters: u32 = 40;
        if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
        if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const rx_pid = try vm.spawn(idle, 0, null);
        const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
        const reg_idx = try atoms.intern(regname);
        try vm.registry.register(reg_idx, rx_pid, true);

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);

        // Read inbound control messages; deliver the first REG_SEND to <regname>.
        var delivered = false;
        var scanned: u32 = 0;
        while (scanned < iters and !delivered) : (scanned += 1) {
            const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| {
                try out.print(gpa, "decode-error {s}\n", .{@errorName(err)});
                break;
            } orelse continue;
            if (ic.op == dist.DOP_REG_SEND) {
                const to = dist.regSendName(rx_ctx, ic.ctrl) orelse continue;
                if (!std.mem.eql(u8, atoms.nameOf(to), regname)) continue;
                const target = vm.registry.whereis(to) orelse continue;
                const payload = ic.msg orelse continue;
                // REAL signal path: deliver into the registered process's mailbox.
                try vm.signal(0xFFFF, target, .{ .message = payload });
                try vm.drainSignalsPub(target);
                // Pull the DELIVERED term back OUT of the mailbox and re-encode it.
                const rp = vm.procs.items[target];
                var qbuf: [64]@import("mailbox_algebra.zig").Msg(ta.FinalTerms) = undefined;
                const q = rp.machine.mbox.toSeq(&qbuf);
                if (q.len == 0) continue;
                const got = q[q.len - 1].payload;
                var enc = try etf.encode(gpa, &rp.machine.ctx, got);
                defer enc.deinit(gpa);
                try out.appendSlice(gpa, "delivered ");
                try cli.appendHexLower(gpa, &out, enc.items);
                try out.append(gpa, '\n');
                delivered = true;
            }
        }
        if (!delivered) try out.appendSlice(gpa, "no-message\n");
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-send")) {
        // dist-send <peer@host> <cookie> <me@host> <regname> <hexterm> [epmd_port]
        // E18 Task 3 (DIVERGENCE 212, OUTBOUND): a running zigvm VM completes the
        // live v6 signals handshake, then sends a DOP REG_SEND of the ETF term
        // <hexterm> to the peer's registered process <regname> over the real
        // socket. The harness registers a collector under <regname> on the peer;
        // it receives the term and prints its `term_to_binary`, which the harness
        // compares to <hexterm> — a genuine outbound-signal EQ observed by the
        // real pinned peer. Prints `sent <regname>` on success.
        if (argv.len < 7) return usage(io);
        const dist = @import("dist.zig");
        const ta = @import("term_algebra.zig");
        const etf = @import("etf.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const regname = argv[5];
        if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var ctx = ta.FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();

        const bytes = cli.hexDecode(gpa, argv[6]) catch |err| {
            var buf: [128]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("bad-hex: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer gpa.free(bytes);
        const msg = etf.decode(gpa, &ctx, bytes) catch |err| {
            var buf: [128]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("etf-error: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();

        const our_node_idx = try atoms.intern(cfg.our_node);
        lc.sendRegSend(gpa, &ctx, our_node_idx, cfg.creation, regname, msg) catch |err| {
            var buf: [128]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("send-error: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        // Hold briefly so the peer's net_kernel reads/dispatches the frame before
        // we tear the socket down (a close-before-flush would drop the message).
        lc.holdTicks(gpa, 6);

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try out.print(gpa, "sent {s}\n", .{regname});
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-monitor")) {
        // dist-monitor <peer@host> <cookie> <me@host> <targetname> [iters] [epmd_port]
        // E18 Task 3b (DIVERGENCE 260 residual, monitor+DOWN+noconnection): a
        // RUNNING zigvm VM completes the live v6 signals handshake, then sends a
        // real DOP MONITOR_P for the peer's registered name <targetname>, using a
        // fresh reference on our node. It then reads inbound DOP control messages:
        //   - a MONITOR_P_EXIT for OUR ref  -> the peer's WIRE reason (e.g. noproc)
        //   - carrier teardown (peer node down / socket EOF) -> `noconnection`
        // Either way it builds `{'DOWN', Ref, process, {TargetName, PeerNode},
        // Reason}` and DELIVERS it into the watcher's mailbox as a real
        // `Vm.signal(.message)`, then prints `down <hex>` of the DELIVERED
        // {process, Object, Reason} triple (the ref is opaque/fresh — verified
        // structurally by matchMonitorExit, not byte-compared). The harness
        // compares that hex to the oracle's `term_to_binary({process, {Name,
        // Peer}, Reason})` — a genuine end-to-end monitor→DOWN EQ over the real
        // socket. Bounded reads: a silent, still-connected peer prints `no-down`.
        if (argv.len < 6) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");
        const etf = @import("etf.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const target_name = argv[5];
        var iters: u32 = 60;
        if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
        if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const rx_pid = try vm.spawn(idle, 0, null);
        const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
        const our_node_idx = try atoms.intern(cfg.our_node);

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

        // OUTBOUND: MONITOR_P the peer's registered name with a fresh ref.
        const ref = lc.sendMonitorP(gpa, rx_ctx, our_node_idx, cfg.creation, target_name, prng.random().int(u32)) catch |err| {
            var buf: [128]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("monitor-error: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);

        // INBOUND: read control messages; deliver exactly one 'DOWN'.
        var reason: ?ta.FinalTerms.Term = null;
        var scanned: u32 = 0;
        while (scanned < iters and reason == null) : (scanned += 1) {
            const maybe = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                // Carrier teardown (peer node down / socket EOF): flush the
                // outstanding monitor with `noconnection` — never a silent loss.
                error.TcpClosed => {
                    reason = ta.FinalTerms.atom(rx_ctx, try atoms.intern("noconnection"));
                    break;
                },
                else => {
                    try out.print(gpa, "decode-error {s}\n", .{@errorName(err)});
                    break;
                },
            };
            const ic = maybe orelse continue;
            // A MONITOR_P_EXIT for OUR exact ref → the peer's wire reason.
            if (dist.matchMonitorExit(rx_ctx, ic, ref)) |wire_reason| {
                reason = wire_reason;
            }
        }

        if (reason) |r| {
            // REAL signal path: build the DOWN and deliver into the mailbox.
            const down = try dist.downMessage(rx_ctx, ref, target_name, cfg.peer_node, r);
            try vm.signal(0xFFFF, rx_pid, .{ .message = down });
            try vm.drainSignalsPub(rx_pid);
            // Pull the DELIVERED DOWN back out and re-encode its deterministic
            // {process, Object, Reason} triple (elems 2,3,4) for the oracle EQ.
            const rp = vm.procs.items[rx_pid];
            var qbuf: [64]@import("mailbox_algebra.zig").Msg(ta.FinalTerms) = undefined;
            const q = rp.machine.mbox.toSeq(&qbuf);
            if (q.len == 0) {
                try out.appendSlice(gpa, "no-down\n");
            } else {
                const got = q[q.len - 1].payload;
                const triple = try ta.FinalTerms.tuple(rx_ctx, &.{
                    ta.FinalTerms.tupleElem(rx_ctx, got, 2),
                    ta.FinalTerms.tupleElem(rx_ctx, got, 3),
                    ta.FinalTerms.tupleElem(rx_ctx, got, 4),
                });
                var enc = try etf.encode(gpa, rx_ctx, triple);
                defer enc.deinit(gpa);
                try out.appendSlice(gpa, "down ");
                try cli.appendHexLower(gpa, &out, enc.items);
                try out.append(gpa, '\n');
            }
        } else {
            try out.appendSlice(gpa, "no-down\n");
        }
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-link")) {
        // dist-link <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
        // E18 Task 3c (DIVERGENCE 261 residual, remote LINK + inbound EXIT prop):
        // a RUNNING zigvm completes the live v6 signals handshake and registers a
        // VM process under <regname>. The peer sends its OWN pid to <regname> over
        // a DOP REG_SEND; zigvm decodes that peer pid off the live carrier, then
        // sends a real DOP LINK for it. When the linked peer proc dies with a
        // known reason the peer sends PAYLOAD_EXIT (or classic EXIT) addressed to
        // our exact linked pid; zigvm decodes it (`matchLinkExit`, right-target
        // identity) and delivers `{'EXIT', PeerPid, Reason}` into the watcher's
        // mailbox as a real `Vm.signal(.message)`, then prints `exit <hex>` of the
        // DELIVERED {'EXIT',Pid,Reason} (the PeerPid bytes are the exact pid the
        // peer sent — an ETF foreign-pid round-trip). The harness compares that to
        // the peer's own `term_to_binary({'EXIT', self(), Reason})` — a genuine
        // end-to-end link→exit EQ over the real socket. Bounded reads: a still-
        // connected peer that never dies prints `no-exit`.
        if (argv.len < 6) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");
        const etf = @import("etf.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const regname = argv[5];
        var iters: u32 = 60;
        if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
        if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const rx_pid = try vm.spawn(idle, 0, null);
        const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
        const reg_idx = try atoms.intern(regname);
        try vm.registry.register(reg_idx, rx_pid, true);
        const our_node_idx = try atoms.intern(cfg.our_node);

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);

        // Phase 1: receive the peer's own pid over a REG_SEND to <regname>.
        var peer_pid: ?ta.FinalTerms.Term = null;
        var our_pid_term: ?ta.FinalTerms.Term = null;
        var scanned: u32 = 0;
        while (scanned < iters and peer_pid == null) : (scanned += 1) {
            const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                error.TcpClosed => break,
                else => {
                    try out.print(gpa, "decode-error {s}\n", .{@errorName(err)});
                    break;
                },
            } orelse continue;
            if (ic.op == dist.DOP_REG_SEND) {
                const to = dist.regSendName(rx_ctx, ic.ctrl) orelse continue;
                if (!std.mem.eql(u8, atoms.nameOf(to), regname)) continue;
                const payload = ic.msg orelse continue;
                if (!ta.FinalTerms.repIsPid(rx_ctx, payload)) continue;
                peer_pid = payload;
                // Phase 2: LINK that exact peer pid over the real socket.
                our_pid_term = lc.sendLink(gpa, rx_ctx, our_node_idx, cfg.creation, payload) catch |err| {
                    try out.print(gpa, "link-error {s}\n", .{@errorName(err)});
                    break;
                };
            }
        }

        // Phase 3: read the EXIT the peer sends when the linked proc dies.
        var exit_reason: ?ta.FinalTerms.Term = null;
        var exit_from: ?ta.FinalTerms.Term = null;
        if (our_pid_term) |our_pid| {
            while (scanned < iters and exit_reason == null) : (scanned += 1) {
                const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                    // Node death before the linked-exit reason: the cross-node link
                    // resolves to `noconnection` (never a silent loss).
                    error.TcpClosed => {
                        exit_reason = ta.FinalTerms.atom(rx_ctx, try atoms.intern("noconnection"));
                        exit_from = peer_pid;
                        break;
                    },
                    else => break,
                } orelse continue;
                if (dist.matchLinkExit(rx_ctx, ic, our_pid)) |le| {
                    exit_from = le.from;
                    exit_reason = le.reason;
                }
            }
        }

        if (exit_reason) |r| {
            const from = exit_from orelse peer_pid.?;
            // REAL signal path: build {'EXIT',From,Reason}, deliver into the mailbox.
            const exit_msg = try dist.exitMessage(rx_ctx, from, r);
            try vm.signal(0xFFFF, rx_pid, .{ .message = exit_msg });
            try vm.drainSignalsPub(rx_pid);
            const rp = vm.procs.items[rx_pid];
            var qbuf: [64]@import("mailbox_algebra.zig").Msg(ta.FinalTerms) = undefined;
            const q = rp.machine.mbox.toSeq(&qbuf);
            if (q.len == 0) {
                try out.appendSlice(gpa, "no-exit\n");
            } else {
                const got = q[q.len - 1].payload;
                var enc = try etf.encode(gpa, rx_ctx, got);
                defer enc.deinit(gpa);
                try out.appendSlice(gpa, "exit ");
                try cli.appendHexLower(gpa, &out, enc.items);
                try out.append(gpa, '\n');
            }
        } else {
            try out.appendSlice(gpa, "no-exit\n");
        }
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-exit2")) {
        // dist-exit2 <peer@host> <cookie> <me@host> <regname> <reason> [iters] [epmd_port]
        // E18 Task 3c (DIVERGENCE 261 residual, remote EXIT2 outbound): a RUNNING
        // zigvm completes the live handshake and registers <regname>. The peer
        // sends its OWN pid to <regname> (REG_SEND); zigvm decodes it and sends a
        // real DOP PAYLOAD_EXIT2 killing that pid with the atom <reason>. The peer
        // (trapping exit, linked to that proc) observes the death carrying exactly
        // <reason> and reports it — the EQ is observed BY the pinned peer. zigvm
        // prints `sent <reason>` on success. Bounded: a peer whose pid never
        // arrives prints `no-pid` (exit 0).
        if (argv.len < 7) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const regname = argv[5];
        const reason_name = argv[6];
        var iters: u32 = 60;
        if (argv.len >= 8) iters = std.fmt.parseInt(u32, argv[7], 10) catch iters;
        if (argv.len >= 9) cfg.epmd_port = std.fmt.parseInt(u16, argv[8], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const rx_pid = try vm.spawn(idle, 0, null);
        const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
        const reg_idx = try atoms.intern(regname);
        try vm.registry.register(reg_idx, rx_pid, true);
        const our_node_idx = try atoms.intern(cfg.our_node);

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);

        var sent = false;
        var scanned: u32 = 0;
        while (scanned < iters and !sent) : (scanned += 1) {
            const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                error.TcpClosed => break,
                else => break,
            } orelse continue;
            if (ic.op == dist.DOP_REG_SEND) {
                const to = dist.regSendName(rx_ctx, ic.ctrl) orelse continue;
                if (!std.mem.eql(u8, atoms.nameOf(to), regname)) continue;
                const payload = ic.msg orelse continue;
                if (!ta.FinalTerms.repIsPid(rx_ctx, payload)) continue;
                const reason = ta.FinalTerms.atom(rx_ctx, try atoms.intern(reason_name));
                lc.sendExit2(gpa, rx_ctx, our_node_idx, cfg.creation, payload, reason) catch |err| {
                    try out.print(gpa, "exit2-error {s}\n", .{@errorName(err)});
                    break;
                };
                sent = true;
            }
        }
        // Hold briefly so the peer's dist reads/dispatches the EXIT2 before teardown.
        if (sent) lc.holdTicks(gpa, 6);
        if (sent) {
            try out.print(gpa, "sent {s}\n", .{reason_name});
        } else {
            try out.appendSlice(gpa, "no-pid\n");
        }
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-demonitor")) {
        // dist-demonitor <peer@host> <cookie> <me@host> <targetname> [iters] [epmd_port]
        // E18 Task 3c (DIVERGENCE 261 residual, DEMONITOR retract): a RUNNING zigvm
        // completes the live handshake, sends a real DOP MONITOR_P for the peer's
        // LIVE registered <targetname> with a fresh ref, then IMMEDIATELY sends a
        // DOP DEMONITOR_P retracting that exact ref. The peer honors the retract:
        // when <targetname> later dies it fires NO MONITOR_P_EXIT for our ref.
        // zigvm reads bounded and observes the ABSENCE of a 'DOWN', printing
        // `no-down`. The harness EQ is `no-down` (demonitor semantics), a genuine
        // live negative observation over the real socket. If a 'DOWN' for our ref
        // DOES arrive (retract lost) zigvm prints `down <hex>` → DIVERGENT.
        if (argv.len < 6) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");
        const etf = @import("etf.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const target_name = argv[5];
        var iters: u32 = 40;
        if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
        if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const rx_pid = try vm.spawn(idle, 0, null);
        const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
        const our_node_idx = try atoms.intern(cfg.our_node);

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

        // MONITOR_P then IMMEDIATELY DEMONITOR_P the same ref over the real socket.
        const ref = lc.sendMonitorP(gpa, rx_ctx, our_node_idx, cfg.creation, target_name, prng.random().int(u32)) catch |err| {
            var buf: [128]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("monitor-error: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        lc.sendDemonitorP(gpa, rx_ctx, our_node_idx, cfg.creation, target_name, ref) catch |err| {
            var buf: [128]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("demonitor-error: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);

        // Read bounded: a demonitored ref must NEVER match a monitor exit. Node
        // teardown (peer down) is NOT a 'DOWN' here — we retracted the monitor.
        var down: ?ta.FinalTerms.Term = null;
        var scanned: u32 = 0;
        while (scanned < iters and down == null) : (scanned += 1) {
            const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                error.TcpClosed => break,
                else => break,
            } orelse continue;
            if (dist.matchMonitorExit(rx_ctx, ic, ref)) |wire_reason| {
                // Retract lost — a 'DOWN' fired for our demonitored ref (DIVERGENT).
                down = try dist.downTriple(rx_ctx, target_name, cfg.peer_node, wire_reason);
            }
        }

        if (down) |triple| {
            var enc = try etf.encode(gpa, rx_ctx, triple);
            defer enc.deinit(gpa);
            try out.appendSlice(gpa, "down ");
            try cli.appendHexLower(gpa, &out, enc.items);
            try out.append(gpa, '\n');
        } else {
            try out.appendSlice(gpa, "no-down\n");
        }
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-unlink")) {
        // dist-unlink <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
        // E20 Task 1 (DIVERGENCE 262 residual, remote unlink two-frame protocol):
        // a RUNNING zigvm completes the live v6 signals handshake and registers a
        // VM process under <regname>. The peer sends its OWN pid to <regname> over
        // a DOP REG_SEND; zigvm LINKs that exact pid, then sends a real DOP
        // UNLINK_ID {35, Id, OurPid, PeerPid} with a fresh non-zero id. The peer's
        // ERTS honours the retract and replies UNLINK_ID_ACK {36, Id, PeerPid,
        // OurPid} echoing our EXACT id — the two-frame handshake that closes the
        // unlink/exit race. zigvm decodes the ack (`matchUnlinkIdAck`, right-id +
        // right-target identity) off the live carrier and prints `unlink-ack <id>`.
        // Bounded reads: a peer that never acks prints `no-ack`.
        if (argv.len < 6) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const regname = argv[5];
        var iters: u32 = 60;
        if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
        if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const rx_pid = try vm.spawn(idle, 0, null);
        const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
        const reg_idx = try atoms.intern(regname);
        try vm.registry.register(reg_idx, rx_pid, true);
        const our_node_idx = try atoms.intern(cfg.our_node);

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);

        // Phase 1: receive the peer's own pid over a REG_SEND to <regname>, LINK it,
        // then UNLINK_ID it with a fresh non-zero id.
        const unlink_id_val: u32 = (prng.random().int(u32) | 1);
        const id_term = ta.FinalTerms.int(rx_ctx, @intCast(unlink_id_val));
        var our_pid_term: ?ta.FinalTerms.Term = null;
        var scanned: u32 = 0;
        while (scanned < iters and our_pid_term == null) : (scanned += 1) {
            const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                error.TcpClosed => break,
                else => break,
            } orelse continue;
            if (ic.op == dist.DOP_REG_SEND) {
                const to = dist.regSendName(rx_ctx, ic.ctrl) orelse continue;
                if (!std.mem.eql(u8, atoms.nameOf(to), regname)) continue;
                const payload = ic.msg orelse continue;
                if (!ta.FinalTerms.repIsPid(rx_ctx, payload)) continue;
                _ = lc.sendLink(gpa, rx_ctx, our_node_idx, cfg.creation, payload) catch |err| {
                    try out.print(gpa, "link-error {s}\n", .{@errorName(err)});
                    break;
                };
                our_pid_term = lc.sendUnlinkId(gpa, rx_ctx, our_node_idx, cfg.creation, id_term, payload) catch |err| {
                    try out.print(gpa, "unlink-error {s}\n", .{@errorName(err)});
                    break;
                };
            }
        }

        // Phase 2: read the UNLINK_ID_ACK the peer sends for our exact id.
        var acked = false;
        if (our_pid_term) |our_pid| {
            while (scanned < iters and !acked) : (scanned += 1) {
                const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                    error.TcpClosed => break,
                    else => break,
                } orelse continue;
                if (dist.matchUnlinkIdAck(rx_ctx, ic, our_pid, id_term)) acked = true;
            }
        }

        if (acked) {
            try out.print(gpa, "unlink-ack {d}\n", .{unlink_id_val});
        } else {
            try out.appendSlice(gpa, "no-ack\n");
        }
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-inexit2")) {
        // dist-inexit2 <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
        // E20 Task 1 (DIVERGENCE 262 residual, INBOUND exit2 — the mirror of the
        // outbound dist-exit2): a RUNNING zigvm completes the live handshake, spawns
        // a local VICTIM proc, mints its foreign pid, and sends THAT pid to the
        // peer's registered <regname> over a DOP REG_SEND. The peer's process calls
        // `exit(VictimPid, killzig)`, so its ERTS sends PAYLOAD_EXIT2 addressed to
        // our exact victim pid. zigvm decodes it (`matchLinkExit`, right-target
        // identity), drives a REAL `exit_sig` into the local victim, which
        // TERMINATES with exactly the wire reason. zigvm prints `killed <hex>` of
        // the reason the dead victim carries (machine.result). Bounded: a peer that
        // never kills prints `no-kill`.
        if (argv.len < 6) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");
        const etf = @import("etf.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const regname = argv[5];
        var iters: u32 = 60;
        if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
        if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const victim_pid = try vm.spawn(idle, 0, null);
        const vctx = &vm.procs.items[victim_pid].machine.ctx;
        const our_node_idx = try atoms.intern(cfg.our_node);
        // The victim's FOREIGN pid identity we hand to the peer (number 2 to
        // distinguish it from the reg-send `from` pid, which is number 1).
        const victim_ext = try ta.FinalTerms.pidExt(vctx, 2, 0, our_node_idx, cfg.creation);

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);

        // Phase 1: send the victim's foreign pid to the peer's <regname>.
        lc.sendRegSend(gpa, vctx, our_node_idx, cfg.creation, regname, victim_ext) catch |err| {
            var buf: [128]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("regsend-error: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };

        // Phase 2: read the inbound EXIT2 the peer sends to kill our victim pid.
        var kill_reason: ?ta.FinalTerms.Term = null;
        var scanned: u32 = 0;
        while (scanned < iters and kill_reason == null) : (scanned += 1) {
            const ic = lc.recvControl(gpa, vctx, 1) catch |err| switch (err) {
                error.TcpClosed => break,
                else => break,
            } orelse continue;
            if (dist.matchLinkExit(vctx, ic, victim_ext)) |le| {
                kill_reason = le.reason;
            }
        }

        if (kill_reason) |r| {
            // REAL kill path: drive an exit_sig into the local victim proc.
            try vm.signal(0xFFFF, victim_pid, .{ .exit_sig = .{ .rfrag = try vm.reasonFrag(vctx, r) } });
            try vm.drainSignalsPub(victim_pid);
            if (vm.procs.items[victim_pid].alive) {
                try out.appendSlice(gpa, "no-kill\n"); // survived (e.g. trapped) — not expected
            } else {
                const got = vm.procs.items[victim_pid].machine.result;
                var enc = try etf.encode(gpa, vctx, got);
                defer enc.deinit(gpa);
                try out.appendSlice(gpa, "killed ");
                try cli.appendHexLower(gpa, &out, enc.items);
                try out.append(gpa, '\n');
            }
        } else {
            try out.appendSlice(gpa, "no-kill\n");
        }
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-exit1")) {
        // dist-exit1 <peer@host> <cookie> <me@host> <regname> [iters] [epmd_port]
        // E20 Task 1 (DIVERGENCE 262 residual, remote exit/1 self-exit — the
        // NORMAL-reason link edge distinct from e18-t3c's abnormal `linkboom`): a
        // RUNNING zigvm completes the live handshake, registers a TRAPPING VM proc
        // under <regname>. The peer sends its OWN pid to <regname>; zigvm LINKs it.
        // The peer proc then calls `exit(normal)` (exit/1 self-exit). Over the link
        // erts STILL transmits the normal-reason exit (which a local link would
        // silently drop); zigvm decodes PAYLOAD_EXIT/EXIT for our exact pid
        // (`matchLinkExit`) and — because the watcher traps — delivers {'EXIT',
        // PeerPid, normal} to its mailbox, printing `exit <hex>`. The harness
        // compares that byte-for-byte to the peer's term_to_binary({'EXIT', self(),
        // normal}). Bounded: a peer that never exits prints `no-exit`.
        if (argv.len < 6) return usage(io);
        const dist = @import("dist.zig");
        const proc = @import("proc.zig");
        const ta = @import("term_algebra.zig");
        const ia = @import("instr_algebra.zig");
        const etf = @import("etf.zig");

        var cfg = dist.ConnectConfig{
            .peer_node = argv[2],
            .cookie = argv[3],
            .our_node = argv[4],
            .flags_override = dist.signalsFlags(),
        };
        const regname = argv[5];
        var iters: u32 = 60;
        if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
        if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
        var seed: u64 = undefined;
        _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
        var prng = std.Random.DefaultPrng.init(seed);

        var atoms = ta.AtomTable.init(gpa);
        defer atoms.deinit();
        var vm = try proc.Vm.init(gpa, &atoms);
        defer vm.deinit();
        const idle: ia.Program = &.{
            .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
            .{ .jump = .{ .to = 0 } },
        };
        const rx_pid = try vm.spawn(idle, 0, null);
        // Trap exit so the NORMAL-reason link exit is delivered (not dropped).
        vm.procs.items[rx_pid].machine.trap_exit = true;
        const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
        const reg_idx = try atoms.intern(regname);
        try vm.registry.register(reg_idx, rx_pid, true);
        const our_node_idx = try atoms.intern(cfg.our_node);

        var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
            var buf: [256]u8 = undefined;
            var ew = std.Io.File.stderr().writer(io, &buf);
            ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
            ew.interface.flush() catch {};
            return 1;
        };
        defer lc.close();
        dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);

        // Phase 1: receive the peer's pid over REG_SEND, LINK it.
        var peer_pid: ?ta.FinalTerms.Term = null;
        var our_pid_term: ?ta.FinalTerms.Term = null;
        var scanned: u32 = 0;
        while (scanned < iters and peer_pid == null) : (scanned += 1) {
            const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                error.TcpClosed => break,
                else => break,
            } orelse continue;
            if (ic.op == dist.DOP_REG_SEND) {
                const to = dist.regSendName(rx_ctx, ic.ctrl) orelse continue;
                if (!std.mem.eql(u8, atoms.nameOf(to), regname)) continue;
                const payload = ic.msg orelse continue;
                if (!ta.FinalTerms.repIsPid(rx_ctx, payload)) continue;
                peer_pid = payload;
                our_pid_term = lc.sendLink(gpa, rx_ctx, our_node_idx, cfg.creation, payload) catch |err| {
                    try out.print(gpa, "link-error {s}\n", .{@errorName(err)});
                    break;
                };
            }
        }

        // Phase 2: read the normal-reason EXIT the peer sends on exit/1(normal).
        var exit_reason: ?ta.FinalTerms.Term = null;
        var exit_from: ?ta.FinalTerms.Term = null;
        if (our_pid_term) |our_pid| {
            while (scanned < iters and exit_reason == null) : (scanned += 1) {
                const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
                    error.TcpClosed => break,
                    else => break,
                } orelse continue;
                if (dist.matchLinkExit(rx_ctx, ic, our_pid)) |le| {
                    exit_from = le.from;
                    exit_reason = le.reason;
                }
            }
        }

        if (exit_reason) |r| {
            const from = exit_from orelse peer_pid.?;
            const exit_msg = try dist.exitMessage(rx_ctx, from, r);
            try vm.signal(0xFFFF, rx_pid, .{ .message = exit_msg });
            try vm.drainSignalsPub(rx_pid);
            const rp = vm.procs.items[rx_pid];
            var qbuf: [64]@import("mailbox_algebra.zig").Msg(ta.FinalTerms) = undefined;
            const q = rp.machine.mbox.toSeq(&qbuf);
            if (q.len == 0) {
                try out.appendSlice(gpa, "no-exit\n");
            } else {
                const got = q[q.len - 1].payload;
                var enc = try etf.encode(gpa, rx_ctx, got);
                defer enc.deinit(gpa);
                try out.appendSlice(gpa, "exit ");
                try cli.appendHexLower(gpa, &out, enc.items);
                try out.append(gpa, '\n');
            }
        } else {
            try out.appendSlice(gpa, "no-exit\n");
        }
        try writeStdout(io, out.items);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "dist-global")) {
        // dist-global <peer@host> <cookie> <me@host> [iters] [epmd_port]
        // E18 Task 4 (DIVERGENCE 320, GLOBAL name-exchange initiation): a RUNNING
        // zigvm completes the live v6 signals handshake and registers a local
        // process under the fixed name `global_name_server`. On the nodeup the
        // peer's OWN global_name_server casts an `init_connect` to
        // `{global_name_server, me}` — the first step of the global name-table
        // sync that enforces the single-owner consistency law. zigvm decodes that
        // DOP REG_SEND off the live carrier, extracts the initiating peer node
        // (globalInitConnectNode), and prints `init-connect <peernode>`. The
        // harness compares <peernode> to the real peer's node name — a genuine
        // live proof the peer's global admitted zigvm into the consistency
        // protocol. Bounded reads: a silent peer prints `no-init-connect` (exit 0).
        // RESIDUAL (DIVERGENCE 320): completing lock/exchange/resolved so a global
        // NAME is visible from BOTH nodes needs zigvm's global locker — deferred.
        if (argv.len < 5) return usage(io);
        return cmdDistCoord(gpa, io, argv, .global);
    }

    if (std.mem.eql(u8, cmd, "dist-pg")) {
        // dist-pg <peer@host> <cookie> <me@host> [iters] [epmd_port]
        // E18 Task 4 (DIVERGENCE 321, PG membership discovery): a RUNNING zigvm
        // completes the live v6 signals handshake and registers a local process
        // under the fixed default scope name `pg`. On the nodeup the peer's pg
        // scope broadcasts a `{discover, ScopePid, Ref}` to `{pg, me}` — the
        // membership handshake that precedes group sync. zigvm decodes that DOP
        // REG_SEND off the live carrier, extracts the peer's scope pid
        // (pgDiscoverPid), and prints `discover <peernode>` (the pid's node). The
        // harness compares <peernode> to the real peer's node — a genuine live
        // proof the peer's pg admitted zigvm into the membership protocol.
        // Bounded: a silent peer prints `no-discover` (exit 0). RESIDUAL
        // (DIVERGENCE 321): completing join/sync so a GROUP membership is visible
        // from BOTH nodes needs zigvm's pg-scope state machine — deferred.
        if (argv.len < 5) return usage(io);
        return cmdDistCoord(gpa, io, argv, .pg);
    }

    if (std.mem.eql(u8, cmd, "dist-pg-join")) {
        // dist-pg-join <peer@host> <cookie> <me@host> <group> [iters] [epmd_port]
        // E20 Task 2 (DIVERGENCE 321, PG MEMBERSHIP CONVERGENCE — live): a RUNNING
        // zigvm completes the live v6 signals handshake, registers a local `pg`
        // scope process and a local MEMBER pid it "joins" to <group>. On the
        // nodeup the peer's pg scope broadcasts `{discover, PeerScopePid, 1}`;
        // zigvm answers it by casting its `local_data`
        // (`{'$gen_cast', {local_data, OurScopePid, 1, #{group => [Member]}}}`)
        // BACK to the peer's scope pid over the live carrier, plus a symmetric
        // `discover`. The peer's `data_publisher` merges our member into its global
        // view, so the pinned peer's own `pg:get_members(group)` CONVERGES to
        // include our member — the membership-convergence law OBSERVED on the real
        // peer (not a mock). Prints `joined <ournode> <group>`; a silent peer
        // prints `no-discover` (exit 0). Bounded socket reads throughout.
        if (argv.len < 6) return usage(io);
        return cmdDistPgJoin(gpa, io, argv);
    }

    if (std.mem.eql(u8, cmd, "dist-mesh")) {
        // dist-mesh <cookie> <me@host> <iters> <peerA@host> <peerB@host> [epmd_port]
        // E20 Task 3 (DIVERGENCE 322, TRANSITIVE-NODES-VISIBILITY): a RUNNING zigvm
        // completes the live v6 handshake to TWO booted pinned OTP-30 peers, holds
        // BOTH carriers simultaneously (answering each peer's ticks), and prints its
        // OWN nodes/0 — which lists BOTH peers, the local vertex of the 3-node triad.
        // Teardown drops both and the node list goes empty.
        if (argv.len < 6) return usage(io);
        return cmdDistMesh(gpa, io, argv);
    }

    if (std.mem.eql(u8, cmd, "dist-pg-mesh")) {
        // dist-pg-mesh <cookie> <me@host> <group> <iters> <peerA@host> <peerB@host> [epmd_port]
        // E20 Task 3 (DIVERGENCE 322, 3-NODE-PG-CONVERGENCE): zigvm registers a pg
        // scope + a local member and, on EACH peer's discover, casts its local_data
        // back over that peer's live carrier — so a member on zigvm's node CONVERGES
        // into BOTH pinned peers' own pg:get_members (visible from all three).
        if (argv.len < 7) return usage(io);
        return cmdDistPgMesh(gpa, io, argv);
    }

    if (std.mem.eql(u8, cmd, "dist-pg-heal")) {
        // dist-pg-heal <cookie> <me@host> <group> <phase_iters> <peerA@host> <peerB@host> [epmd_port]
        // E20 Task 3 (DIVERGENCE 322, PARTITION-HEAL-RECONVERGENCE): zigvm casts its
        // member to A and B (both converge), then PARTITIONS by dropping B's carrier
        // (B's pg observes nodedown and RETRACTS the member) while A stays connected
        // (continuity witness), then HEALS by reconnecting B and re-casting local_data
        // (B's pg reconverges). Bounded phase windows throughout.
        if (argv.len < 7) return usage(io);
        return cmdDistPgHeal(gpa, io, argv);
    }

    if (std.mem.eql(u8, cmd, "global-register")) {
        // global-register <peer@host> <cookie> <me@host> <name> [iters] [epmd_port]
        // E21 Task 4 (DIVERGENCE 320 → LIVE): drive the 2-phase global register
        // transaction against the pinned peer for the UNCONTENDED single name.
        // $gen_call set_lock → register(name, pid) → del_lock, awaiting each
        // peer reply over the alias, then hold the carrier so the peer's
        // global:whereis_name(name) resolves the owner on OUR node while connected.
        if (argv.len < 5) return usage(io);
        return cmdDistGlobalRegister(gpa, io, argv);
    }

    return usage(io);
}

/// E20 Task 3: shared connect+register step for a mesh carrier. Completes the v6
/// handshake to `peer` and registers it live in `vm`'s node table. Returns the
/// open LiveCarrier (caller holds/closes it). `null` epmd_port uses the default.
fn meshConnectPeer(
    gpa: std.mem.Allocator,
    io: std.Io,
    vm: anytype,
    atoms: anytype,
    peer: []const u8,
    cookie: []const u8,
    our_node: []const u8,
    epmd_port: ?u16,
    flags_override: ?u64,
    rng: std.Random,
) !@import("dist.zig").LiveCarrier {
    const dist = @import("dist.zig");
    var cfg = dist.ConnectConfig{ .peer_node = peer, .cookie = cookie, .our_node = our_node, .flags_override = flags_override };
    if (epmd_port) |p| cfg.epmd_port = p;
    const lc = dist.liveConnectOpen(gpa, cfg, rng) catch |err| {
        var buf: [256]u8 = undefined;
        var ew = std.Io.File.stderr().writer(io, &buf);
        ew.interface.print("rejected {s}: {s}\n", .{ peer, @errorName(err) }) catch {};
        ew.interface.flush() catch {};
        return err;
    };
    const peer_atom = try atoms.intern(peer);
    _ = try vm.registerLiveDistPeer(peer_atom, lc.outcome.peer_creation, @as(i64, @bitCast(lc.outcome.peer_flags)));
    return lc;
}

/// E20 Task 3 dist-mesh: hold two live carriers and reflect both in nodes/0.
fn cmdDistMesh(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) !u8 {
    const dist = @import("dist.zig");
    const proc = @import("proc.zig");
    const ta = @import("term_algebra.zig");
    const ia = @import("instr_algebra.zig");

    const cookie = argv[2];
    const our_node = argv[3];
    var iters: u32 = 30;
    iters = std.fmt.parseInt(u32, argv[4], 10) catch iters;
    const peer_a = argv[5];
    const peer_b = argv[6];
    var epmd_port: ?u16 = null;
    if (argv.len >= 8) epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch null;
    var seed: u64 = undefined;
    _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
    var prng = std.Random.DefaultPrng.init(seed);

    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    const idle: ia.Program = &.{
        .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    const self_pid = try vm.spawn(idle, 0, null);
    const m = &vm.procs.items[self_pid].machine;

    var lc_a = try meshConnectPeer(gpa, io, &vm, &atoms, peer_a, cookie, our_node, epmd_port, null, prng.random());
    defer lc_a.close();
    var lc_b = try meshConnectPeer(gpa, io, &vm, &atoms, peer_b, cookie, our_node, epmd_port, null, prng.random());
    defer lc_b.close();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, "connected\nnodes-connected");
    try appendConnectedNodes(gpa, m, try vm.distLiveNodesTerm(m), &out);
    try out.append(gpa, '\n');

    const carriers = [_]dist.TcpStreamCarrier{ lc_a.carrier, lc_b.carrier };
    dist.holdCarriersTicks(gpa, &carriers, iters);

    _ = try vm.removeLiveDistPeer(try atoms.intern(peer_a));
    _ = try vm.removeLiveDistPeer(try atoms.intern(peer_b));
    try out.appendSlice(gpa, "nodes-after-teardown");
    try appendConnectedNodes(gpa, m, try vm.distLiveNodesTerm(m), &out);
    try out.append(gpa, '\n');
    try writeStdout(io, out.items);
    return 0;
}

/// E20 Task 3: connect to `peer` with pg signals flags and, on its discover,
/// cast our local_data + a symmetric discover back to the peer scope pid so the
/// peer merges our member. Returns the open carrier and whether the cast fired.
/// Bounded socket reads (a silent peer yields joined=false, never a hang).
fn pgConnectCast(
    gpa: std.mem.Allocator,
    io: std.Io,
    vm: anytype,
    rx_pid: anytype,
    rx_ctx: anytype,
    atoms: anytype,
    our_scope_pid: anytype,
    our_member_pid: anytype,
    group: []const u8,
    peer: []const u8,
    cookie: []const u8,
    our_node: []const u8,
    epmd_port: ?u16,
    scan_iters: u32,
    rng: std.Random,
) !struct { lc: @import("dist.zig").LiveCarrier, joined: bool } {
    const dist = @import("dist.zig");
    var lc = try meshConnectPeer(gpa, io, vm, atoms, peer, cookie, our_node, epmd_port, dist.signalsFlags(), rng);
    dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};
    var joined = false;
    var scanned: u32 = 0;
    while (scanned < scan_iters) : (scanned += 1) {
        const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
            error.TcpClosed => break,
            else => break,
        } orelse continue;
        if (ic.op != dist.DOP_REG_SEND) continue;
        const to = dist.regSendName(rx_ctx, ic.ctrl) orelse continue;
        if (!std.mem.eql(u8, atoms.nameOf(to), "pg")) continue;
        const payload = ic.msg orelse continue;
        const peer_scope = dist.pgDiscoverPid(rx_ctx, payload) orelse continue;
        try vm.signal(0xFFFF, rx_pid, .{ .message = payload });
        try vm.drainSignalsPub(rx_pid);
        const ld = try dist.pgLocalDataCast(rx_ctx, our_scope_pid, group, our_member_pid);
        try lc.sendToPid(gpa, rx_ctx, peer_scope, ld);
        const disc = try dist.pgDiscoverMsg(rx_ctx, our_scope_pid);
        try lc.sendToPid(gpa, rx_ctx, peer_scope, disc);
        joined = true;
        break;
    }
    return .{ .lc = lc, .joined = joined };
}

/// E20 Task 3 dist-pg-mesh: cast our member to BOTH peers, hold both.
fn cmdDistPgMesh(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) !u8 {
    const dist = @import("dist.zig");
    const proc = @import("proc.zig");
    const ta = @import("term_algebra.zig");
    const ia = @import("instr_algebra.zig");

    const cookie = argv[2];
    const our_node = argv[3];
    const group = argv[4];
    var iters: u32 = 30;
    iters = std.fmt.parseInt(u32, argv[5], 10) catch iters;
    const peer_a = argv[6];
    const peer_b = argv[7];
    var epmd_port: ?u16 = null;
    if (argv.len >= 9) epmd_port = std.fmt.parseInt(u16, argv[8], 10) catch null;
    var seed: u64 = undefined;
    _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
    var prng = std.Random.DefaultPrng.init(seed);

    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    const idle: ia.Program = &.{
        .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    const rx_pid = try vm.spawn(idle, 0, null);
    const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
    const pg_idx = try atoms.intern("pg");
    try vm.registry.register(pg_idx, rx_pid, true);
    const our_node_idx = try atoms.intern(our_node);
    const our_scope_pid = try ta.FinalTerms.pidExt(rx_ctx, @intCast(rx_pid + 1), 0, our_node_idx, 1);
    const our_member_pid = try ta.FinalTerms.pidExt(rx_ctx, 1000, 0, our_node_idx, 1);

    var ra = try pgConnectCast(gpa, io, &vm, rx_pid, rx_ctx, &atoms, our_scope_pid, our_member_pid, group, peer_a, cookie, our_node, epmd_port, 40, prng.random());
    defer ra.lc.close();
    var rb = try pgConnectCast(gpa, io, &vm, rx_pid, rx_ctx, &atoms, our_scope_pid, our_member_pid, group, peer_b, cookie, our_node, epmd_port, 40, prng.random());
    defer rb.lc.close();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "joined-a {s} joined-b {s} group {s} node {s}\n", .{
        if (ra.joined) "yes" else "no",
        if (rb.joined) "yes" else "no",
        group,
        our_node,
    });

    const carriers = [_]dist.TcpStreamCarrier{ ra.lc.carrier, rb.lc.carrier };
    dist.holdCarriersTicks(gpa, &carriers, iters);
    try out.appendSlice(gpa, "held\n");
    try writeStdout(io, out.items);
    return 0;
}

/// E20 Task 3 dist-pg-heal: cast to A+B, partition B, heal B, holding A throughout.
fn cmdDistPgHeal(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) !u8 {
    const dist = @import("dist.zig");
    const proc = @import("proc.zig");
    const ta = @import("term_algebra.zig");
    const ia = @import("instr_algebra.zig");

    const cookie = argv[2];
    const our_node = argv[3];
    const group = argv[4];
    var phase: u32 = 15;
    phase = std.fmt.parseInt(u32, argv[5], 10) catch phase;
    const peer_a = argv[6];
    const peer_b = argv[7];
    var epmd_port: ?u16 = null;
    if (argv.len >= 9) epmd_port = std.fmt.parseInt(u16, argv[8], 10) catch null;
    var seed: u64 = undefined;
    _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
    var prng = std.Random.DefaultPrng.init(seed);

    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    const idle: ia.Program = &.{
        .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    const rx_pid = try vm.spawn(idle, 0, null);
    const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
    const pg_idx = try atoms.intern("pg");
    try vm.registry.register(pg_idx, rx_pid, true);
    const our_node_idx = try atoms.intern(our_node);
    const our_scope_pid = try ta.FinalTerms.pidExt(rx_ctx, @intCast(rx_pid + 1), 0, our_node_idx, 1);
    const our_member_pid = try ta.FinalTerms.pidExt(rx_ctx, 1000, 0, our_node_idx, 1);
    const peer_b_atom = try atoms.intern(peer_b);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    // Phase 1: connect A (stable) + B, cast to both, hold both — all converged.
    var ra = try pgConnectCast(gpa, io, &vm, rx_pid, rx_ctx, &atoms, our_scope_pid, our_member_pid, group, peer_a, cookie, our_node, epmd_port, 40, prng.random());
    defer ra.lc.close();
    var rb = try pgConnectCast(gpa, io, &vm, rx_pid, rx_ctx, &atoms, our_scope_pid, our_member_pid, group, peer_b, cookie, our_node, epmd_port, 40, prng.random());
    try out.print(gpa, "phase1 joinedA {s} joinedB {s}\n", .{ if (ra.joined) "yes" else "no", if (rb.joined) "yes" else "no" });
    {
        const carriers = [_]dist.TcpStreamCarrier{ ra.lc.carrier, rb.lc.carrier };
        dist.holdCarriersTicks(gpa, &carriers, phase);
    }

    // Phase 2: PARTITION — drop B's carrier; B observes nodedown and retracts our
    // member. A stays up (continuity). Hold only A through the partition window.
    rb.lc.close();
    _ = try vm.removeLiveDistPeer(peer_b_atom);
    try out.appendSlice(gpa, "partitioned B\n");
    {
        const carriers = [_]dist.TcpStreamCarrier{ra.lc.carrier};
        dist.holdCarriersTicks(gpa, &carriers, phase);
    }

    // Phase 3: HEAL — reconnect B and re-cast local_data; B's pg reconverges.
    var rb2 = try pgConnectCast(gpa, io, &vm, rx_pid, rx_ctx, &atoms, our_scope_pid, our_member_pid, group, peer_b, cookie, our_node, epmd_port, 40, prng.random());
    defer rb2.lc.close();
    try out.print(gpa, "healed joinedB {s}\n", .{if (rb2.joined) "yes" else "no"});
    {
        const carriers = [_]dist.TcpStreamCarrier{ ra.lc.carrier, rb2.lc.carrier };
        dist.holdCarriersTicks(gpa, &carriers, phase);
    }
    try writeStdout(io, out.items);
    return 0;
}

/// E20 Task 2: drive the live pg membership-convergence handshake. Connects,
/// registers a `pg` scope + a member pid, and on the peer's `discover` casts our
/// `local_data` back so the peer's `pg:get_members` includes our member. Holds
/// the carrier so the peer can read the converged membership before teardown.
fn cmdDistPgJoin(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) !u8 {
    const dist = @import("dist.zig");
    const proc = @import("proc.zig");
    const ta = @import("term_algebra.zig");
    const ia = @import("instr_algebra.zig");

    const group = argv[5];
    var cfg = dist.ConnectConfig{
        .peer_node = argv[2],
        .cookie = argv[3],
        .our_node = argv[4],
        .flags_override = dist.signalsFlags(),
    };
    var iters: u32 = 60;
    if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
    if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
    var seed: u64 = undefined;
    _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
    var prng = std.Random.DefaultPrng.init(seed);

    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    const idle: ia.Program = &.{
        .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    const rx_pid = try vm.spawn(idle, 0, null);
    const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
    const pg_idx = try atoms.intern("pg");
    try vm.registry.register(pg_idx, rx_pid, true);

    // Our scope pid and member pid — distinct pids on OUR node (creation matches
    // the value advertised in send_name so the peer accepts them as ours).
    const our_node_idx = try atoms.intern(cfg.our_node);
    const our_scope_pid = try ta.FinalTerms.pidExt(rx_ctx, @intCast(rx_pid + 1), 0, our_node_idx, cfg.creation);
    const our_member_pid = try ta.FinalTerms.pidExt(rx_ctx, 1000, 0, our_node_idx, cfg.creation);

    var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
        var buf: [256]u8 = undefined;
        var ew = std.Io.File.stderr().writer(io, &buf);
        ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
        ew.interface.flush() catch {};
        return 1;
    };
    defer lc.close();
    dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    // Read inbound control; on the peer's `discover` cast our local_data back so
    // the peer merges our member, then hold the carrier for the remaining slices.
    var joined = false;
    var scanned: u32 = 0;
    while (scanned < iters) : (scanned += 1) {
        const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
            error.TcpClosed => break,
            else => {
                try out.print(gpa, "decode-error {s}\n", .{@errorName(err)});
                break;
            },
        } orelse continue;
        if (joined) continue; // keep answering ticks via recvControl for the hold
        if (ic.op != dist.DOP_REG_SEND) continue;
        const to = dist.regSendName(rx_ctx, ic.ctrl) orelse continue;
        if (!std.mem.eql(u8, atoms.nameOf(to), "pg")) continue;
        const payload = ic.msg orelse continue;
        const peer_scope = dist.pgDiscoverPid(rx_ctx, payload) orelse continue;
        // Deliver the discover into the scope process's mailbox (real signal path).
        try vm.signal(0xFFFF, rx_pid, .{ .message = payload });
        try vm.drainSignalsPub(rx_pid);
        // Answer: cast local_data + a symmetric discover back to the peer scope.
        const ld = try dist.pgLocalDataCast(rx_ctx, our_scope_pid, group, our_member_pid);
        try lc.sendToPid(gpa, rx_ctx, peer_scope, ld);
        const disc = try dist.pgDiscoverMsg(rx_ctx, our_scope_pid);
        try lc.sendToPid(gpa, rx_ctx, peer_scope, disc);
        joined = true;
    }

    if (joined) {
        try out.appendSlice(gpa, "joined ");
        try out.appendSlice(gpa, cfg.our_node);
        try out.append(gpa, ' ');
        try out.appendSlice(gpa, group);
        try out.append(gpa, '\n');
    } else {
        try out.appendSlice(gpa, "no-discover\n");
    }
    try writeStdout(io, out.items);
    return 0;
}

const CoordKind = enum { global, pg };

/// Shared driver for the two coordination-observation commands (dist-global /
/// dist-pg). Completes the live signals handshake, registers a local process
/// under the service's fixed name, reads inbound DOP REG_SENDs off the live
/// carrier, and prints the OBSERVABLE peer identity the service's convergence
/// cast carries. Bounded reads; a silent peer prints `no-<x>` (exit 0).
fn cmdDistCoord(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8, kind: CoordKind) !u8 {
    const dist = @import("dist.zig");
    const proc = @import("proc.zig");
    const ta = @import("term_algebra.zig");
    const ia = @import("instr_algebra.zig");

    const reg = switch (kind) {
        .global => "global_name_server",
        .pg => "pg",
    };
    const found_prefix = switch (kind) {
        .global => "init-connect ",
        .pg => "discover ",
    };
    const none_line = switch (kind) {
        .global => "no-init-connect\n",
        .pg => "no-discover\n",
    };

    var cfg = dist.ConnectConfig{
        .peer_node = argv[2],
        .cookie = argv[3],
        .our_node = argv[4],
        .flags_override = dist.signalsFlags(),
    };
    var iters: u32 = 60;
    if (argv.len >= 6) iters = std.fmt.parseInt(u32, argv[5], 10) catch iters;
    if (argv.len >= 7) cfg.epmd_port = std.fmt.parseInt(u16, argv[6], 10) catch cfg.epmd_port;
    var seed: u64 = undefined;
    _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
    var prng = std.Random.DefaultPrng.init(seed);

    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    const idle: ia.Program = &.{
        .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    const rx_pid = try vm.spawn(idle, 0, null);
    const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
    const reg_idx = try atoms.intern(reg);
    try vm.registry.register(reg_idx, rx_pid, true);

    var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
        var buf: [256]u8 = undefined;
        var ew = std.Io.File.stderr().writer(io, &buf);
        ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
        ew.interface.flush() catch {};
        return 1;
    };
    defer lc.close();
    dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    // Read inbound control messages; observe the FIRST coordination cast whose
    // REG_SEND targets our service name and carries the expected convergence shape.
    var found: ?[]const u8 = null; // peer node name (owned by atoms via nameOf)
    var scanned: u32 = 0;
    while (scanned < iters and found == null) : (scanned += 1) {
        const ic = lc.recvControl(gpa, rx_ctx, 1) catch |err| switch (err) {
            error.TcpClosed => break,
            else => {
                try out.print(gpa, "decode-error {s}\n", .{@errorName(err)});
                break;
            },
        } orelse continue;
        if (ic.op != dist.DOP_REG_SEND) continue;
        const to = dist.regSendName(rx_ctx, ic.ctrl) orelse continue;
        if (!std.mem.eql(u8, atoms.nameOf(to), reg)) continue;
        const payload = ic.msg orelse continue;
        // REAL signal path: deliver the cast into the service process's mailbox.
        try vm.signal(0xFFFF, rx_pid, .{ .message = payload });
        try vm.drainSignalsPub(rx_pid);
        switch (kind) {
            .global => {
                if (dist.globalInitConnectNode(rx_ctx, payload)) |node|
                    found = atoms.nameOf(ta.FinalTerms.atomIdxOf(node));
            },
            .pg => {
                if (dist.pgDiscoverPid(rx_ctx, payload)) |pid|
                    found = ta.FinalTerms.pidNodeName(rx_ctx, pid);
            },
        }
    }

    if (found) |peernode| {
        try out.appendSlice(gpa, found_prefix);
        try out.appendSlice(gpa, peernode);
        try out.append(gpa, '\n');
    } else {
        try out.appendSlice(gpa, none_line);
    }
    try writeStdout(io, out.items);
    return 0;
}

/// E21 Task 4: scan the live carrier (bounded) for the `$gen_call` reply routed
/// to our `alias_ref`; return the `Reply` term or `null` if no matching reply
/// arrives within `iters` ~200ms slices. Non-matching control (the peer's
/// init_connect casts, ticks) is skipped — the acquire is admitted ONLY for the
/// reply to OUR exact alias (`matchAliasReply`). Bounded: never hangs.
fn awaitAliasReply(
    gpa: std.mem.Allocator,
    lc: *const @import("dist.zig").LiveCarrier,
    ctx: anytype,
    alias_ref: anytype,
    iters: u32,
) !?@TypeOf(alias_ref) {
    const dist = @import("dist.zig");
    var i: u32 = 0;
    while (i < iters) : (i += 1) {
        const ic_opt = lc.recvControl(gpa, ctx, 1) catch return null;
        const ic = ic_opt orelse continue;
        if (dist.matchAliasReply(ctx, ic, alias_ref)) |reply| return reply;
    }
    return null;
}

/// E21 Task 4 (DIVERGENCE 320 → LIVE): the 2-phase global REGISTER transaction
/// against the pinned peer for the UNCONTENDED single name. Completes the v6
/// signals handshake (ALTACT_SIG cleared so the peer replies via ALIAS_SEND),
/// registers a local `global_name_server`, then drives $gen_call set_lock →
/// register(name, owner_pid) → del_lock, awaiting each alias reply, and holds the
/// carrier so the peer's global:whereis_name(name) resolves the owner on OUR node
/// while connected. Bounded socket reads throughout (a silent peer never hangs).
fn cmdDistGlobalRegister(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) !u8 {
    const dist = @import("dist.zig");
    const proc = @import("proc.zig");
    const ta = @import("term_algebra.zig");
    const ia = @import("instr_algebra.zig");

    const name = argv[5];
    var cfg = dist.ConnectConfig{
        .peer_node = argv[2],
        .cookie = argv[3],
        .our_node = argv[4],
        .flags_override = dist.globalCallFlags(),
    };
    var iters: u32 = 40;
    if (argv.len >= 7) iters = std.fmt.parseInt(u32, argv[6], 10) catch iters;
    if (argv.len >= 8) cfg.epmd_port = std.fmt.parseInt(u16, argv[7], 10) catch cfg.epmd_port;
    var seed: u64 = undefined;
    _ = std.os.linux.getrandom(std.mem.asBytes(&seed), @sizeOf(u64), 0);
    var prng = std.Random.DefaultPrng.init(seed);

    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    const idle: ia.Program = &.{
        .{ .recv_any = .{ .dst = 0, .else_to = 0 } },
        .{ .jump = .{ .to = 0 } },
    };
    const rx_pid = try vm.spawn(idle, 0, null);
    const rx_ctx = &vm.procs.items[rx_pid].machine.ctx;
    const gns_idx = try atoms.intern("global_name_server");
    try vm.registry.register(gns_idx, rx_pid, true);

    const our_node_idx = try atoms.intern(cfg.our_node);
    // FromPid = the transaction requester on our node (the lock owner); owner_pid
    // = the pid the NAME will own — distinct, also on our node so node(P)==our_node
    // when the peer resolves whereis_name.
    const from_pid = try ta.FinalTerms.pidExt(rx_ctx, @intCast(rx_pid + 1), 0, our_node_idx, cfg.creation);
    const owner_pid = try ta.FinalTerms.pidExt(rx_ctx, 2000, 0, our_node_idx, cfg.creation);

    var lc = dist.liveConnectOpen(gpa, cfg, prng.random()) catch |err| {
        var buf: [256]u8 = undefined;
        var ew = std.Io.File.stderr().writer(io, &buf);
        ew.interface.print("rejected: {s}\n", .{@errorName(err)}) catch {};
        ew.interface.flush() catch {};
        return 1;
    };
    defer lc.close();
    dist.setRecvTimeoutPub(lc.carrier.fd, 200) catch {};

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    // Phase 1: set_lock — bounded retry on a transient `false` (contention with the
    // peer's own nodeup locker), mirroring set_lock_known's retry loop.
    var lock_ok = false;
    var attempt: u32 = 0;
    while (attempt < 5 and !lock_ok) : (attempt += 1) {
        const alias = try ta.FinalTerms.refExt(rx_ctx, .{ @as(u32, 0xA11A0) + attempt, 0, 0 }, our_node_idx, cfg.creation);
        const req = try dist.globalSetLockReq(rx_ctx, from_pid);
        try lc.sendGenCall(gpa, rx_ctx, from_pid, alias, "global_name_server", req);
        if (try awaitAliasReply(gpa, &lc, rx_ctx, alias, 25)) |reply| {
            if (dist.replyIsAtom(rx_ctx, reply, "true")) lock_ok = true;
        }
    }
    if (!lock_ok) {
        try out.appendSlice(gpa, "no-lock\n");
        try writeStdout(io, out.items);
        return 0;
    }
    try out.appendSlice(gpa, "lock true\n");

    // Phase 2: register(Name, owner_pid) — the peer inserts Name→owner_pid and
    // replies `yes`, making the name visible via the peer's whereis_name.
    const alias2 = try ta.FinalTerms.refExt(rx_ctx, .{ 0xA11A5, 0, 0 }, our_node_idx, cfg.creation);
    const reg = try dist.globalRegisterReq(rx_ctx, name, owner_pid);
    try lc.sendGenCall(gpa, rx_ctx, from_pid, alias2, "global_name_server", reg);
    var registered = false;
    if (try awaitAliasReply(gpa, &lc, rx_ctx, alias2, 25)) |reply| {
        if (dist.replyIsAtom(rx_ctx, reply, "yes")) registered = true;
    }
    if (registered) {
        try out.print(gpa, "registered {s}\n", .{name});
    } else {
        try out.appendSlice(gpa, "no-register\n");
    }

    // Phase 3: del_lock — release (best-effort; the peer also auto-releases on
    // our nodedown, so a missed reply never leaves a stuck lock).
    const alias3 = try ta.FinalTerms.refExt(rx_ctx, .{ 0xA11A6, 0, 0 }, our_node_idx, cfg.creation);
    const del = try dist.globalDelLockReq(rx_ctx, from_pid);
    try lc.sendGenCall(gpa, rx_ctx, from_pid, alias3, "global_name_server", del);
    if (try awaitAliasReply(gpa, &lc, rx_ctx, alias3, 25)) |reply| {
        if (dist.replyIsAtom(rx_ctx, reply, "true")) try out.appendSlice(gpa, "unlocked\n");
    }

    // Hold the carrier (bounded tick keepalive) so the peer's whereis_name resolves
    // the owner on our node WHILE we are still connected (the name is monitored on
    // the peer and would be retracted on nodedown).
    lc.holdTicks(gpa, iters);

    try writeStdout(io, out.items);
    return 0;
}

/// E18.3: append " <name>" for every atom in a nodes(connected) cons list.
fn appendConnectedNodes(gpa: std.mem.Allocator, m: anytype, term: anytype, out: *std.ArrayList(u8)) !void {
    const ta = @import("term_algebra.zig");
    const FinalTerms = ta.FinalTerms;
    var cur = term;
    while (FinalTerms.kindOf(&m.ctx, cur) == .cons) {
        const head = FinalTerms.listHead(&m.ctx, cur);
        try out.append(gpa, ' ');
        try out.appendSlice(gpa, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(head)));
        cur = FinalTerms.listTail(&m.ctx, cur);
    }
}

fn usage(io: std.Io) !u8 {
    try writeStderr(io, usage_string);
    return 2;
}

fn writeStdout(io: std.Io, bytes: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var w = std.Io.File.stdout().writer(io, &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}

fn writeStderr(io: std.Io, bytes: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var w = std.Io.File.stderr().writer(io, &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}
