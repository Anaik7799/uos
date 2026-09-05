//! zigvm E0.2: the **CLI core** — a pure, testable composition that loads a
//! `.beam` module and runs one exported function to a printed value.
//!
//! This module introduces NO new VM semantics. It is a homomorphism onto the
//! existing algebras: `beam_loader` (parse → translate → entryOf) supplies the
//! program and its export table, `dispatch` engine #3 (predecode + runThreaded)
//! executes it, `term_algebra.FinalTerms` builds the argument terms and denotes
//! the result, and `diag.formatValue` observes that denotation as Erlang-ish
//! text. `run` is the whole CLI; `main` is one line of argv/file/stdout glue.
//!
//! Observation: the single output is the DENOTATION of `m.result` (the value in
//! x0 when the function returns), formatted exactly as the crash-dump formatter
//! prints terms — so the CLI observes the same spec.Value the law suite pins.
//!
//! Term-arg convention (E5.1): entry arguments are TERM LITERALS, not just
//! integers. `parseArg` is a pure, total grammar (`ArgLit`) over three literal
//! kinds distinguished by the first byte — integer (`-?[0-9]+`), atom
//! (`[a-z][A-Za-z0-9_@]*` or single-quoted `'...'`), and string (`"..."` → an
//! Erlang string, i.e. a proper list of the byte codepoints). `argToTerm` maps
//! a literal onto the SAME `spec.Value` the law suite pins, so no new term
//! semantics enter — the CLI just gains a wider argument surface. This
//! discharges DIVERGENCE 49 blocker (1): a generic runner's `main(Module)` can
//! now receive its target module ATOM from argv (the eunit path). Anything that
//! is not a literal (an uppercase-leading variable, an unterminated quote) is a
//! NAMED rejection (`ArgParseError`), never a panic.
//!
//! Bounds (E5.1): execution is fuel-bounded — a program that does not terminate
//! within the guard is a FAILED law (`error.RunDidNotTerminate`), never a hang.
//! The two-step arity rule resolves the entry: an exact-arity export takes the
//! args in x0..x(n-1); otherwise an arity-1 export takes all args as one proper
//! list in x0 (uniformly covering list-taking `sum`/`len`/`rev` and int-taking
//! `seq`). Pids/ports/refs are NOT a CLI-typeable literal (they name live
//! identities); their printed/wire parity is the E3.5 term-kind laws pinned
//! below, which E5.1 credits unchanged (external multi-node pid terms — a real
//! second node's `{node,creation}` — land with the E5 distribution slice).
//!
//! E18.2 (cross-node term transport & total order): two more pure observers live
//! here — `etfReencode` (`encode ∘ decode` over hex ETF bytes) and `termCompare`
//! (`FinalTerms.compare`/`compareExact` over two decoded ETF terms). They add NO
//! VM semantics (the codec is `etf`, the order is `term_algebra`); they exist so
//! the `--run-dist-term` harness can cross-check zigvm's wire round-trip and
//! total order against a live pinned OTP-30 peer. See the E18.2 section below.

const std = @import("std");
const ta = @import("term_algebra.zig");
const ia = @import("instr_algebra.zig");
const gc = @import("gc.zig"); // gap-perf-bench-realism: real copying collector in the mixed bench
const loader = @import("beam_loader.zig");
const proc = @import("proc.zig");
const app_controller = @import("app_controller.zig"); // e48-appctl-handoff
const boot_script = @import("boot_script.zig");
const ea = @import("ets_algebra.zig");
const timer_wheel = @import("timer_wheel.zig");
const apoptosis = @import("apoptosis.zig");
const dispatch = @import("dispatch.zig");
const jit_codegen = @import("jit_codegen.zig"); // jit-bench-realprog: native_supported host gate
const diag = @import("diag.zig");
const ets_bifs = @import("bifs/ets.zig"); // gap-ets-scale-unit: the shared-store contention workload
const erl_expr = @import("erl_expr.zig");
const io_format = @import("bifs/io_format.zig");
const agent_codegen = @import("agent_codegen.zig"); // verify-agent-codegen: agent-eval CLI probe dispatch
const a2ui = @import("a2ui.zig");
const event_log = @import("event_log.zig");
const dist_tailscale = @import("dist_tailscale.zig");
const dist = @import("dist.zig");
const event_wal = @import("event_wal.zig");
const etf = @import("etf.zig");

const AtomTable = ta.AtomTable;
const FinalTerms = ta.FinalTerms;

/// Fuel per dispatch slice — one reduction budget handed to the threaded
/// engine per loop turn (matches the dispatch differential recipe's 7).
const slice_budget: u64 = 7;
/// Loop guard: the maximum number of budgeted slices before a run is declared
/// non-terminating. A hang is a failed law, so it surfaces as an error.
const max_slices: usize = 50_000_000;

/// E5.1: a CLI entry-argument literal — the term-arg grammar that replaces E0's
/// integer-only convention. `atom`/`string` BORROW their bytes from argv (alive
/// for the whole run); `argToTerm` interns/copies into the process heap.
pub const ArgLit = union(enum) {
    /// A decimal integer literal (`-?[0-9]+`).
    int: i64,
    /// An atom NAME — the bytes between the quotes for a quoted atom, or the
    /// bareword itself. Denotes `spec.atom`.
    atom: []const u8,
    /// The raw bytes of a `"..."` literal; denotes an Erlang string (a proper
    /// list of the byte codepoints).
    string: []const u8,
};

/// Total classification of a rejected argument (never a panic; the parser is a
/// total function into `ArgLit ∪ ArgParseError`).
pub const ArgParseError = error{
    /// The argument was the empty string.
    EmptyArg,
    /// A bareword/quoted atom is malformed (uppercase-leading variable, an
    /// unterminated `'`, or a bareword byte outside `[A-Za-z0-9_@]`).
    BadAtom,
    /// A `"`-opened string is not `"`-terminated.
    BadString,
    /// A `-`/digit-opened token is not a valid `i64`.
    BadInt,
};

/// E5.1: the term-arg grammar — a PURE, TOTAL parse of one argv token into an
/// `ArgLit`. The first byte selects the kind:
///   `"`        → string  (`"..."`, inner bytes verbatim; must be `"`-closed)
///   `'`        → atom    (`'...'`, inner bytes as the name; must be `'`-closed)
///   `-`/digit  → int     (a decimal `i64`)
///   `[a-z]`    → atom    (bareword; every byte must be `[A-Za-z0-9_@]`)
///   otherwise  → BadAtom (uppercase = a variable, punctuation, … — not a literal)
pub fn parseArg(text: []const u8) ArgParseError!ArgLit {
    if (text.len == 0) return error.EmptyArg;
    const c0 = text[0];
    if (c0 == '"') {
        if (text.len < 2 or text[text.len - 1] != '"') return error.BadString;
        return .{ .string = text[1 .. text.len - 1] };
    }
    if (c0 == '\'') {
        if (text.len < 2 or text[text.len - 1] != '\'') return error.BadAtom;
        return .{ .atom = text[1 .. text.len - 1] };
    }
    if (c0 == '-' or (c0 >= '0' and c0 <= '9')) {
        const v = std.fmt.parseInt(i64, text, 10) catch return error.BadInt;
        return .{ .int = v };
    }
    if (c0 >= 'a' and c0 <= 'z') {
        for (text) |ch| {
            const ok = (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or
                (ch >= '0' and ch <= '9') or ch == '_' or ch == '@';
            if (!ok) return error.BadAtom;
        }
        return .{ .atom = text };
    }
    return error.BadAtom;
}

/// E5.1: map an `ArgLit` onto the `spec.Value` it denotes, allocating into
/// `ctx` (a string becomes a right-folded proper list of its byte codepoints;
/// an atom is interned into the shared table). No new term semantics — every
/// arm reuses an existing `FinalTerms` constructor.
fn argToTerm(ctx: *FinalTerms.Ctx, a: ArgLit) !FinalTerms.Term {
    return switch (a) {
        .int => |v| FinalTerms.int(ctx, v),
        .atom => |name| FinalTerms.atom(ctx, try ctx.atoms.intern(name)),
        .string => |bytes| blk: {
            var list = FinalTerms.nil(ctx);
            var i = bytes.len;
            while (i > 0) {
                i -= 1;
                list = try FinalTerms.cons(ctx, FinalTerms.int(ctx, bytes[i]), list);
            }
            break :blk list;
        },
    };
}

pub const RunError = error{
    /// No export matches `fn_name` under either the exact arity or arity 1.
    FunctionNotExported,
    /// Execution exceeded the fuel guard without halting — a failed law.
    RunDidNotTerminate,
    /// E3.12b: a module's `on_load` function returned a non-`ok` value (or
    /// crashed / did not terminate): its load is refused, as in real BEAM.
    OnLoadFailed,
};

pub const RunOptions = struct {
    experimental_apoptosis_rate: usize = 0,
    experimental_zenoh_crdt: bool = false,
    experimental_wasm_slm: bool = false,
    experimental_tailscale: bool = false,
    experimental_gossip: bool = false,
    experimental_event_log: bool = false,
    experimental_a2ui: bool = false,
    experimental_otlp: bool = false,
    experimental_event_wal: bool = false,
    experimental_apoptosis_immunity: bool = false,
    experimental_epmd_bridge: bool = false,
    /// gap-e46-resident-cli: run as a RESIDENT node — a supervised tree STAYS UP
    /// (driveResident) instead of the one-shot drive that treats an idle-but-alive
    /// tree as a deadlock. Default off = byte-identical one-shot behaviour.
    resident: bool = false,
    /// gap-fs-autoloader: the OPTIONAL filesystem autoload seam — a `dispatchMFA`
    /// miss loads `Module.beam` off `code_path` (under `root`) and retries.
    /// Default `null` = no autoloading; dispatch is byte-identical.
    autoload: ?proc.Vm.AutoloadCfg = null,
    /// e49-wire-real-file-io: the OPTIONAL real-file seam — file:read_file/1
    /// and file:write_file/2 route to the proven prim_file fd seam under
    /// `root`. Default `null` = closed-world file BIFs.
    fs: ?proc.Vm.FsCfg = null,
    /// gap-erl-cli-args (DIVERGENCE 598): the parsed init argv (flags + `-extra`
    /// plain args) so `init:get_plain_arguments/0` + `init:get_argument/1` answer
    /// from a compiled beam. `null` (default) = no CLI args (get_plain_arguments →
    /// [], get_argument → error). Slices borrow argv bytes (alive for the run).
    init_args: ?proc.Vm.InitArgsView = null,
    /// e48-appctl-handoff: boot an APPLICATION through the AppController
    /// BEFORE the entry runs — the controller takes the linked entry process
    /// as its code-bearing TEMPLATE and dispatches `mod:start(normal, [])`
    /// into the REAL loaded code (the a6b machinery over a real linked node).
    /// `app`/`mod` are atom names. Default `null` = byte-identical runs.
    app_boot: ?struct { app: []const u8, mod: []const u8 } = null,
    /// gap-erl-cli-exec: OTP-30 `-s`/`-run` boot-application ARITY semantics.
    /// When set, the entry is resolved and its arguments placed exactly as
    /// init.erl's `start_it` does: with N≥1 argument tokens `Func` is ALWAYS
    /// applied as `Func/1` on the single list `[A1,…,AN]` (never `Func/N`); with
    /// 0 tokens `Func/0` is applied with no arguments. Default `false` = the
    /// natural two-step arity rule the positional `run <beam> <fn> <args>` uses.
    boot_list_args: bool = false,
    /// gap-hof-stdlib (DIVERGENCE 661): PRELOAD the HOF-bearing stock stdlib
    /// (real OTP-30 `lists` + `maps`) into the link closure, so a compiled
    /// `call_ext_code {lists,map,2}` / `{maps,fold,3}` / … resolves to the real
    /// implementation — exactly as a real `erl` node has the stdlib ambient.
    /// The fun-taking higher-order functions (map/filter/foldl/foldr/all/any/
    /// foreach, maps:map/fold/filter) are Erlang code in OTP, not BIFs; zigvm
    /// wires only the pure/data `lists:` set as native BIFs, so without this the
    /// HOFs are `undef`. Native BIFs (lists:member/reverse) still WIN — they bake
    /// to `call_ext_bif` at the caller's load time, never reaching the linked
    /// `lists` exports. Entry stays `beams[0]` (the stdlib is appended). Default
    /// `false` = byte-identical to a bare closure (every existing runMulti test
    /// is unaffected); the `run` CLI subcommand sets it `true`.
    preload_stdlib: bool = false,
};

/// gap-hof-stdlib: the stock stdlib closure `preload_stdlib` appends — the REAL
/// erlc-compiled OTP-30 pure-data stdlib (from third_party/otp/lib/stdlib/ebin,
/// the same source the P-APP supervision closure vendored). Using OTP's own code
/// makes the semantics byte-EQ by construction (not a hand-written re-impl).
///   - lists/maps: the higher-order (fun-taking) functions — map/filter/foldl/…
///   - proplists: the property-list accessors (get_value/get_all_values/…)
///   - string + unicode + unicode_util: the string module and its TRANSITIVE
///     dependency closure — `string:uppercase/split/trim/length/…` delegate to
///     `unicode:characters_to_list/…` and the generated `unicode_util` grapheme/
///     whitespace tables, so ALL THREE must be present or `string:*` undefs on
///     the first `unicode_util:gc/whitespace` call (DIVERGENCE 662).
///   - sets + gb_trees: the collection modules — `sets` is maps-backed (needs no
///     new closure member beyond the already-present `maps`), `gb_trees` is
///     self-contained (DIVERGENCE 663).
///   - ordsets + queue: the ordered-set (sorted-list-backed) and double-ended
///     queue modules — both self-contained over `lists`/erlang guards
///     (DIVERGENCE 665).
///   - dict + orddict: the hash-dict and ordered-assoc-list dictionaries — both
///     self-contained over `lists`/erlang guards (DIVERGENCE 666).
///   - array: the extensible functional array (self-contained over erlang
///     guards). re: the regexp module's ERLANG WRAPPER (re.erl) — `re:replace/
///     split/…` are Erlang code that call the NATIVE `re:run`/`re:compile` BIFs
///     (already `.implemented`, src/re_engine.zig); the wrappers were `undef`
///     without re.beam even though the native BIFs existed (DIVERGENCE 667).
///   - gb_sets: the general-balanced-tree set (self-contained, like gb_trees).
///     digraph: the directed-graph module — ETS-BACKED and STATEFUL (digraph:new
///     mints ETS tables via the native ets BIFs); its graph handle embeds ETS
///     Tids (zigvm's are ints, OTP's #Refs — repr-coupled, so never exposed), but
///     every graph-query result (vertices/get_path/neighbours) is byte-EQ
///     (DIVERGENCE 668). NOTE: a caller must NOT also `--pa` a preloaded module —
///     a duplicate module name in the closure breaks entry resolution.
///   - calendar: the date/time math module — the DETERMINISTIC functions
///     (day_of_the_week/valid_date/gregorian_days/leap-year/…) are byte-EQ; the
///     TZ/host-dependent ones (local_time/universal_time) are not exercised.
///     timer: the PURE helpers (sleep/hms/hours/minutes/seconds) resolve; the
///     SERVER-based ones (apply_after/send_after) need a running timer_server
///     gen_server (a separate gap) and stay undef (DIVERGENCE 669).
///   - base64: the base64 codec (self-contained). uri_string: URI parse/quote/
///     compose — self-contained over the already-present unicode; `recompose/1`
///     stays undef (an internal dep gap) but parse/quote/unquote/compose_query/
///     dissect_query all resolve (DIVERGENCE 670).
///   - rand: the PRNG — self-contained; a SEEDED sequence (rand:seed_s + the
///     _s/2 variants) is deterministic and byte-EQ (the exsss algorithm matches
///     the oracle); the unseeded rand:uniform/0 draws host entropy (not EQ).
///     math: ALREADY fully native (every math fn is an `.implemented` BIF, so a
///     compiled `math:sqrt` bakes to call_ext_bif and wins) — math.beam is
///     preloaded for CLOSURE COMPLETENESS only and its exports are never reached
///     (dropping it is EQUIVALENT, see MUTATION_LOG) (DIVERGENCE 671).
///   - erl_anno: the parser-annotation module (self-contained). NOTE: `zip` is
///     deliberately NOT preloaded — it needs the native `zlib` stream BIFs
///     (zlib:open/deflate/inflate/close) which zigvm does not implement, so
///     zip.beam alone would undef on the first `zlib:open/0`; the zlib engine is
///     a separate substantial slice (DIVERGENCE 672).
///   - erl_scan + erl_parse + erl_features + epp + eval_bits: the Erlang
///     TOKENIZER + PARSER closure — `erl_scan:string`, `erl_parse:parse_exprs/
///     parse_form/normalise/abstract`. erl_scan:scan_atom needs erl_features
///     (feature keywords) which needs `init:get_arguments/0` (wired native in
///     this slice); erl_parse:normalise/abstract of binary literals needs eval_bits + erl_bits;
///     erl_parse:abstract needs epp:default_encoding. All six + the init BIF
///     make full source tokenize+parse+normalise byte-EQ (DIVERGENCE 673).
/// Order is irrelevant — the linker resolves every export after linking all
/// units (first-linked-wins only affects duplicate module names, of which there
/// are none here); the entry module stays `beams[0]`.
pub const hof_stdlib_beams = [_][]const u8{
    @embedFile("otp_lists.beam"),
    @embedFile("otp_maps.beam"),
    @embedFile("otp_proplists.beam"),
    @embedFile("otp_string.beam"),
    @embedFile("otp_unicode.beam"),
    @embedFile("otp_unicode_util.beam"),
    @embedFile("otp_sets.beam"),
    @embedFile("otp_gb_trees.beam"),
    @embedFile("otp_ordsets.beam"),
    @embedFile("otp_queue.beam"),
    @embedFile("otp_dict.beam"),
    @embedFile("otp_orddict.beam"),
    @embedFile("otp_array.beam"),
    @embedFile("otp_re.beam"),
    @embedFile("otp_gb_sets.beam"),
    @embedFile("otp_digraph.beam"),
    @embedFile("otp_calendar.beam"),
    @embedFile("otp_timer.beam"),
    @embedFile("otp_base64.beam"),
    @embedFile("otp_uri_string.beam"),
    @embedFile("otp_rand.beam"),
    @embedFile("otp_math.beam"),
    @embedFile("otp_erl_anno.beam"),
    @embedFile("otp_erl_scan.beam"),
    @embedFile("otp_erl_parse.beam"),
    @embedFile("otp_erl_features.beam"),
    @embedFile("otp_epp.beam"),
    @embedFile("otp_eval_bits.beam"),
    @embedFile("otp_erl_bits.beam"),
    // gap-hof-batch (DIVERGENCE 674): 14 pure/self-contained stdlib modules,
    // parallel-verified LOADABLE_EQ vs the pinned OTP-30 oracle (a 6-agent sweep
    // of the whole remaining stdlib surface). Each is self-contained (deps=[])
    // and byte-EQ; the OTP-30-only ones (graph/erl_id_trans/erl_stdlib_errors/
    // erl_abstract_code) are verified via the hof_probe LAW, not the OTP-28
    // ecosystem oracle.
    @embedFile("otp_binary.beam"),
    @embedFile("otp_sofs.beam"),
    @embedFile("otp_graph.beam"),
    @embedFile("otp_erl_internal.beam"),
    @embedFile("otp_erl_stdlib_errors.beam"),
    @embedFile("otp_otp_internal.beam"),
    @embedFile("otp_io_lib_fread.beam"),
    @embedFile("otp_erl_id_trans.beam"),
    @embedFile("otp_erl_expand_records.beam"),
    @embedFile("otp_erl_abstract_code.beam"),
    @embedFile("otp_random.beam"),
    @embedFile("otp_proc_lib.beam"),
    @embedFile("otp_edlin_key.beam"),
    @embedFile("otp_edlin_type_suggestion.beam"),
};

// ── gap-erl-cli-exec: the `-s`/`-run` boot-application EXECUTION semantics ────
// The parsed init FLAGS (`parseInitArgs` below) are only half the `erl` drop-in
// contract; the other half is EXECUTING the boot instructions. `-s`/`-run` name
// an entry `Mod:Func(Args)` that init.erl applies at boot (init.erl `start_it`,
// PINNED). SCOPE: this slice wires the `-s`/`-run` EXECUTION path (the highest-
// value flags every release script uses); `-eval` (needs an Erlang-expression
// evaluator), `-config`/`-boot`, `-extra`→`init:get_plain_arguments/0` (needs
// that BIF) and `-name`/`-sname`→`node()` (a net_kernel `setnode/2` identity)
// stay honestly UNWIRED — they PARSE (parseInitArgs) but need an absent seam.

/// How a boot flag interprets each argument token, per init.erl:
///   `-s`   → each token is an ATOM   (`Mod:Func([atom, …])`)
///   `-run` → each token is a STRING  (`Mod:Func([string, …])`)
pub const BootArgKind = enum { atoms, strings };

/// One resolved `-s`/`-run` boot instruction. `module` is informational under
/// the current CLI (the linker's `entryOf` resolves `func` by name across every
/// linked module, entry module first); `func` defaults to `start`; `argv` are
/// the value tokens after the module and function names (borrowed from the
/// process argv — alive for the whole run).
pub const BootCall = struct {
    module: []const u8,
    func: []const u8,
    argv: []const []const u8,
    kind: BootArgKind,
};

/// gap-erl-cli-exec: extract the FIRST `-s`/`-run` boot instruction from parsed
/// init flags, per OTP-30 init.erl `do_boot`/`start_it`. PURE + TOTAL: returns
/// `null` when no `-s`/`-run` flag carries a module (the caller then falls back
/// to the positional entry). Semantics:
///   `-s M`         → `M:start()`          (`func="start"`, no arg tokens)
///   `-s M F`       → `M:F()`              (`func=F`,       no arg tokens)
///   `-s M F A …`   → `M:F([A, …])`        (`func=F`, arg tokens A…, ATOMS)
///   `-run …`       → the same, but arg tokens are STRINGS.
/// A `-s`/`-run` with no values (`init` ignores it) is skipped. Multiple
/// `-s`/`-run` flags are each a boot call in init.erl; the one-shot CLI executes
/// the FIRST (its single-entry surface) — chaining is an honest non-goal.
pub fn resolveBoot(ia_args: InitArgs) ?BootCall {
    for (ia_args.flags) |fl| {
        const kind: BootArgKind =
            if (std.mem.eql(u8, fl.name, "s")) BootArgKind.atoms else if (std.mem.eql(u8, fl.name, "run")) BootArgKind.strings else continue;
        if (fl.values.len == 0) continue; // a `-s`/`-run` naming no module: init ignores it.
        return .{
            .module = fl.values[0],
            .func = if (fl.values.len >= 2) fl.values[1] else "start",
            .argv = if (fl.values.len >= 2) fl.values[2..] else fl.values[0..0],
            .kind = kind,
        };
    }
    return null;
}

/// gap-erl-cli-exec: map one boot-argument token onto the `ArgLit` it denotes —
/// the boot-kind HOMOMORPHISM. `-s` tokens become atom literals; `-run` tokens
/// become string literals (a proper list of the byte codepoints, via
/// `argToTerm`). PURE + TOTAL (borrows the token bytes).
pub fn bootArgLit(kind: BootArgKind, token: []const u8) ArgLit {
    return switch (kind) {
        .atoms => .{ .atom = token },
        .strings => .{ .string = token },
    };
}

/// gap-erl-cli-exec: is `t` one of the OTP `erl` init flags this build's `run`
/// subcommand recognizes (so the tokens from it onward are parsed as an init
/// argv rather than swallowed as positional entry arguments)? PURE + TOTAL.
pub fn isErlInitFlag(t: []const u8) bool {
    const known = [_][]const u8{ "-s", "-run", "-noshell", "-noinput", "-name", "-sname", "-extra", "-eval" };
    for (known) |k| if (std.mem.eql(u8, t, k)) return true;
    return false;
}

// ── gap-erl-cli-surface: the `erl`/`init` argument-parsing grammar ───────────
// The drop-in-`erl` contract every build tool / release script depends on
// (rebar3, mix, escript): how the post-emulator argv is split into init FLAGS
// and PLAIN arguments, matching `init:get_arguments/0` + `init:get_plain_
// arguments/0` (init.erl, PINNED across OTP). SCOPE: this is the INIT-flag
// grammar (a pure, total, property-tested algebra); the `+X` EMULATOR flags are
// stripped by erlexec BEFORE init and are a separate concern. EQUIV: modelled to
// the documented/pinned init.erl contract (an exhaustive live-erl differential
// is impractical in this sandbox — erl boot is slow); the grammar is the value.
pub const InitFlag = struct { name: []const u8, values: []const []const u8 };
pub const InitArgs = struct { flags: []const InitFlag, plain: []const []const u8 };

/// Parse `argv` (the tokens `init` sees) per the init.erl contract:
///   - a `-flag` starts a group; its VALUES are the following tokens up to (but
///     excluding) the next token beginning with `-` (the next flag).
///   - `-extra` is the TERMINATOR: everything after it is a plain argument,
///     VERBATIM, with no further flag parsing — the pass-through build tools use.
///   - bare tokens before any flag are plain arguments.
/// TOTAL: any argv parses; never a panic. Output is `arena`-owned.
pub fn parseInitArgs(arena: std.mem.Allocator, argv: []const []const u8) !InitArgs {
    var flags: std.ArrayList(InitFlag) = .empty;
    var plain: std.ArrayList([]const u8) = .empty;
    const isFlag = struct {
        fn f(t: []const u8) bool {
            return t.len > 0 and t[0] == '-';
        }
    }.f;
    var i: usize = 0;
    // leading bare tokens (before any flag) are plain arguments.
    while (i < argv.len and !isFlag(argv[i])) : (i += 1) try plain.append(arena, argv[i]);
    while (i < argv.len) {
        if (std.mem.eql(u8, argv[i], "-extra")) {
            i += 1; // the terminator: the rest are plain, verbatim (flags inert here).
            while (i < argv.len) : (i += 1) try plain.append(arena, argv[i]);
            break;
        }
        const name = argv[i][1..]; // drop the leading '-'
        var vals: std.ArrayList([]const u8) = .empty;
        i += 1;
        while (i < argv.len and !isFlag(argv[i]) and !std.mem.eql(u8, argv[i], "-extra")) : (i += 1)
            try vals.append(arena, argv[i]);
        try flags.append(arena, .{ .name = name, .values = try vals.toOwnedSlice(arena) });
    }
    return .{ .flags = try flags.toOwnedSlice(arena), .plain = try plain.toOwnedSlice(arena) };
}

/// gap-e46-resident-cli: idle ticks before a quiescent closed-world resident node
/// reports `.idle` (bounded, never a max_slices spin).
const resident_idle_budget: usize = 8;

/// Run `fn_name` from a `.beam` image on integer arguments and format the
/// denotation of its result into `out`. Returns the process exit status
/// (0 on a clean halt). A single-module run is the ONE-element case of the
/// multi-module linker (E3.12b) — no behaviour shifts (offset 0, no relocation).
pub fn run(
    gpa: std.mem.Allocator,
    beam_bytes: []const u8,
    fn_name: []const u8,
    args: []const ArgLit,
    out: *std.ArrayList(u8),
    opts: RunOptions,
) !u8 {
    return runMulti(gpa, &.{beam_bytes}, fn_name, args, out, opts);
}

/// E3.12b: run `fn_name` (resolved in `beams[0]`, the ENTRY module) after LINKING
/// every module in `beams` into one flat code space with a shared export index,
/// so a `call_ext` in the entry module dispatches ACROSS separately-compiled real
/// erlc `.beam` files. `beams[1..]` are the `--pa` dependencies. This is pure
/// composition over `beam_loader.link` (the loading homomorphism) + the E3.12
/// `call_ext_code`/`Machine.exports` dispatch mechanism + the E3.7 scheduler —
/// no new VM semantics. Every linked module's `on_load` function (if any) is run
/// and its `ok` result gated BEFORE the entry runs (load-gating); a non-`ok`
/// on_load fails the whole run with `OnLoadFailed`.
pub fn runMulti(
    gpa: std.mem.Allocator,
    beams_in: []const []const u8,
    fn_name: []const u8,
    args: []const ArgLit,
    out: *std.ArrayList(u8),
    opts: RunOptions,
) !u8 {
    std.debug.assert(beams_in.len >= 1);
    // gap-hof-stdlib (DIVERGENCE 661): with `preload_stdlib`, APPEND the stock
    // stdlib closure so the HOF `lists:`/`maps:` functions resolve. The entry
    // stays `beams[0]` (stdlib appended at the END → `entryOf` still finds the
    // entry module's export first). The combined slice-of-slices is freed here;
    // its ELEMENTS are borrowed (caller-owned entry/deps + static @embedFile
    // stdlib) and are NOT freed by this block.
    var combined: ?[][]const u8 = null;
    defer if (combined) |c| gpa.free(c);
    const beams: []const []const u8 = if (opts.preload_stdlib) blk: {
        const c = try gpa.alloc([]const u8, beams_in.len + hof_stdlib_beams.len);
        @memcpy(c[0..beams_in.len], beams_in);
        @memcpy(c[beams_in.len..], &hof_stdlib_beams);
        combined = c;
        break :blk c;
    } else beams_in;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    // --- parse + translate every module against the SHARED atom table ---
    // Cleanup discipline: `mods` deinit ALWAYS (they stay alive through the run —
    // entry-name slices, literal bytes, Attr bytes are read from their arenas);
    // the TRANSIENT `translated`-window errdefer frees the not-yet-linked
    // Translateds and is DISABLED once `link` consumes them (`translated = 0`).
    const mods = try gpa.alloc(loader.Module, beams.len);
    defer gpa.free(mods);
    var parsed: usize = 0;
    defer {
        var j: usize = parsed;
        while (j > 0) {
            j -= 1;
            mods[j].deinit();
        }
    }
    const units = try gpa.alloc(loader.LinkUnit, beams.len);
    defer gpa.free(units);
    var translated: usize = 0;
    errdefer {
        var i: usize = translated;
        while (i > 0) {
            i -= 1;
            loader.freeProg(gpa, units[i].t.prog);
            gpa.free(units[i].t.label_pc);
            gpa.free(units[i].t.entries);
            gpa.free(units[i].t.locs);
        }
    }
    for (beams, 0..) |bytes, i| {
        mods[i] = try loader.parse(gpa, bytes);
        parsed += 1;
        const t = try loader.translate(gpa, &mods[i], &atoms, null);
        units[i] = .{ .mod = &mods[i], .t = t };
        translated += 1;
    }

    // --- link: concatenate + relocate into one program + export index ---
    var linked = try loader.link(gpa, &atoms, units[0..translated]);
    translated = 0; // link consumed the Translateds; disable the transient errdefer
    defer linked.deinit(gpa);

    // --- two-step arity rule over the ENTRY module (beams[0]) ---
    // entryOf scans linked.entries (all modules, entry module first) — a same-
    // named export in a dep never shadows the entry module's, which sorts first.
    const Placement = enum { exact, list };
    const linked_t = loader.Translated{ .prog = linked.prog, .label_pc = &.{}, .entries = linked.entries, .locs = linked.locs };
    // gap-erl-cli-exec: `-s`/`-run` boot arity is FORCED, not the natural two-step
    // rule — init.erl always applies `Func/1` on the single arg LIST when there is
    // ≥1 token, and `Func/0` with no tokens (`-s M F A` = `M:F([A])`, NOT `M:F(A)`).
    const entry: u32, const placement: Placement = if (opts.boot_list_args)
        if (args.len == 0)
            .{ loader.entryOf(&linked_t, fn_name, 0) orelse return RunError.FunctionNotExported, .exact }
        else
            .{ loader.entryOf(&linked_t, fn_name, 1) orelse return RunError.FunctionNotExported, .list }
    else if (loader.entryOf(&linked_t, fn_name, @intCast(args.len))) |pc|
        .{ pc, .exact }
    else if (loader.entryOf(&linked_t, fn_name, 1)) |pc|
        .{ pc, .list }
    else
        return RunError.FunctionNotExported;

    // --- on_load load-gating: run each module's on_load fn, gate on `ok` ---
    for (0..beams.len) |k| {
        if (try onLoadOk(gpa, &atoms, &linked, mods, k)) |ok| {
            if (!ok) return RunError.OnLoadFailed;
        }
    }

    // --- drive the entry on process 0 (E3.7 scheduler), bounded ---
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    // gap-fs-autoloader: install the autoload seam BEFORE any spawn — every
    // process (entry + children) inherits `autoload_enabled` at spawn time.
    vm.autoload = opts.autoload;
    vm.fs = opts.fs; // e49-wire-real-file-io
    vm.init_args = opts.init_args; // gap-erl-cli-args: init:get_plain_arguments/get_argument
    a2ui.experimental_a2ui = opts.experimental_a2ui;
    var log = try event_log.EventLog.init(gpa, 1024);
    defer log.deinit();
    var wal = try event_wal.EventWAL.init();
    defer wal.deinit();
    defer wal.flushLog(&log) catch {};
    try a2ui.startServer(gpa, &log, 8080);
    apoptosis.experimental_apoptosis_rate_ms = if (opts.experimental_apoptosis_rate > 0) opts.experimental_apoptosis_rate else null;
    try apoptosis.schedule_next(&vm);
    const p0 = try vm.spawn(linked.prog, @intCast(entry), null);
    // E4.6 (Task 6): install the `standard_io` group-leader fixture and route the
    // entry process's io through it, so `group_leader() =/= self()` (matching the
    // OTP shell GL) and `io:put_chars`/protocol output lands in the captured sink.
    const gl = try vm.installGroupLeader(linked.prog);
    vm.procs.items[p0].machine.group_leader = gl;
    const m = &vm.procs.items[p0].machine;
    m.experimental_apoptosis_rate = opts.experimental_apoptosis_rate;
    m.experimental_zenoh_crdt = opts.experimental_zenoh_crdt;
    m.experimental_wasm_slm = opts.experimental_wasm_slm;
    m.experimental_tailscale = opts.experimental_tailscale;
    m.experimental_gossip = opts.experimental_gossip;
    m.experimental_event_log = opts.experimental_event_log;
    m.experimental_a2ui = opts.experimental_a2ui;
    m.experimental_otlp = opts.experimental_otlp;
    m.experimental_event_wal = opts.experimental_event_wal;
    m.experimental_apoptosis_immunity = opts.experimental_apoptosis_immunity;
    m.experimental_epmd_bridge = opts.experimental_epmd_bridge;
    dist_tailscale.experimental_tailscale = opts.experimental_tailscale;
    m.locs = linked.locs; // E3.11: cooked stacktraces (mfa + file + line)
    m.exports = linked.exports; // E3.12: cross-module call_ext_code resolution
    m.code_base = linked.prog.len; // e5-dispatch-codeidx: the split between the
    // static linked image and any RUNTIME-loaded (prepare/finish) module code.
    // E4.2: retained per-module metadata for get_module_info/1,2. Borrows the
    // Attr/CInf bytes out of each module's arena (alive through the run) and the
    // module atom the linker interned into the shared table.
    const meta = try gpa.alloc(ia.ModMeta, mods.len);
    defer gpa.free(meta);
    for (mods, 0..) |*mod, k| meta[k] = .{
        .module = linked.module_atom[k],
        .attr_bytes = mod.attr_bytes,
        .compile_bytes = mod.compile_bytes,
        .md5 = mod.mod_md5,
        .has_md5 = mod.has_md5,
    };
    m.mod_meta = meta;
    // E5.2b (Task 2 CONTINUATION, DIVERGENCE 61): register every linked module
    // into the runtime code table so the code-server QUERY BIFs
    // (`check_old_code/1`, `delete_module/1`) observe/mutate the SAME module
    // world the oracle does. The stored program is the linked image (presence is
    // all these ops read; execution stays on `linked.prog` directly, so a
    // runtime `delete_module` of the running module never disturbs the entry
    // process — the M10 continuation-stays law). Skips a name already present
    // (a dep can never be double-registered under the linker's first-wins rule).
    for (mods, 0..) |_, k| {
        const mod_name = atoms.nameOf(linked.module_atom[k]);
        if (m.code_index.slots.get(mod_name) == null)
            try m.code_index.load(mod_name, linked.prog);
    }
    m.literals = try materializeAll(gpa, &m.ctx, mods); // W-17 combined pool
    m.heap_lit_end = m.ctx.words.items.len; // e48-gc-literal-area: the GC water line
    defer gpa.free(m.literals);

    switch (placement) {
        .exact => for (args, 0..) |a, i| {
            m.regs[i] = try argToTerm(&m.ctx, a);
        },
        .list => {
            var list = FinalTerms.nil(&m.ctx);
            var i = args.len;
            while (i > 0) {
                i -= 1;
                list = try FinalTerms.cons(&m.ctx, try argToTerm(&m.ctx, args[i]), list);
            }
            m.regs[0] = list;
        },
    }

    // e48-appctl-handoff: boot the requested application through the
    // AppController with p0 (the linked entry) as the code-bearing template —
    // ensure_all_started dispatches mod:start(normal, []) into the REAL
    // loaded code; the spawned tree is scheduled alongside the entry (the
    // entry can observe/poll it — a real boot ordering, not a barrier).
    var app_specs: [1]boot_script.AppSpec = undefined;
    var ac_store: ?app_controller.AppController = null;
    defer if (ac_store) |*ac| ac.deinit();
    if (opts.app_boot) |ab| {
        const app_atom = try atoms.intern(ab.app);
        const mod_atom = try atoms.intern(ab.mod);
        app_specs[0] = .{
            .name = app_atom,
            .mod = .{ .m = mod_atom, .args = FinalTerms.nil(&m.ctx) },
            .applications = &.{},
        };
        ac_store = app_controller.AppController.init(gpa, &vm, &app_specs);
        ac_store.?.template = p0;
        try ac_store.?.ensureAllStarted(app_atom);
    }

    var sched: proc.Scheduler = .round_robin;
    if (opts.resident) {
        // gap-e46-resident-cli: run as a RESIDENT node. `.idle` = a supervised tree
        // booted and is ALIVE + stable (a running node, not a deadlock); `.done` =
        // every process halted → fall through to the entry's result. This is a SAFE
        // SUPERSET of the one-shot run: a halting program takes the `.done` path and
        // produces the identical result.
        const outcome = try sched.driveResident(&vm, slice_budget, max_slices, resident_idle_budget);
        try out.appendSlice(gpa, vm.io_output.items); // flush any logged output
        if (outcome == .idle) {
            try out.print(gpa, "resident: idle ({d} alive)\n", .{vm.residentAliveCount()});
            return 0;
        }
        // .done → fall through to the entry result path (io already flushed).
    } else {
        try sched.drive(&vm, slice_budget, max_slices);
        // e50-halt: erlang:halt(N) sets the node exit code — flush captured
        // stdout, then return N (the driver's exit).
        if (vm.halt_code) |code| {
            try out.appendSlice(gpa, vm.io_output.items);
            // gap-halt-argcheck: a `halt(String)` crashdump slogan goes to STDERR
            // (matching erts — the oracle prints the slogan on stderr + erl_crash.dump,
            // leaving STDOUT byte-identical), NOT stdout. Best-effort raw write; the
            // slogan stays captured in `vm.halt_slogan` for inspection.
            if (vm.halt_slogan.items.len > 0) {
                _ = std.os.linux.write(2, vm.halt_slogan.items.ptr, vm.halt_slogan.items.len);
                _ = std.os.linux.write(2, "\n", 1);
            }
            return code;
        }
        if (m.status == .running or m.status == .suspended) {
            std.debug.print("DEADLOCK: ", .{});
            for (vm.procs.items, 0..) |p, k| {
                if (p.alive) {
                    const pc = p.machine.pc;
                    std.debug.print("pid={} status={s} pc={} mbox={} ", .{ k, @tagName(p.machine.status), pc, p.machine.mbox.len() });
                    if (pc < p.prog.len) {
                        std.debug.print("opcode={s} ", .{@tagName(p.prog[pc])});
                    }
                }
            }
            std.debug.print("\n", .{});
            return RunError.RunDidNotTerminate;
        }
        // E4.6 (Task 6): flush any captured stdout (io:put_chars / the group-leader
        // protocol) AHEAD of the result line — the printed-output evidence path.
        try out.appendSlice(gpa, vm.io_output.items);
    }

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const v = try FinalTerms.denote(&m.ctx, arena.allocator(), m.result);
    try diag.formatValue(gpa, v, out);
    try out.append(gpa, '\n');
    // gap-root-crash-exit (DIVERGENCE 743): a crashed ROOT process is an ERROR exit,
    // not silent success — `exit 0` on a crash is an EVIDENCE-INTEGRITY hazard (a
    // failing run reads as passing to any `$?`-checking harness). erts exits 1 and
    // prints `Runtime terminating during boot (<reason>)` on STDERR. The exit code
    // (1) and the reason SHAPE are byte-EQ; the boot-frame stacktrace is EQUIV —
    // zigvm's `run` path has no `init:do_boot` frames (a disclosed bound).
    if (m.status == .crashed) {
        var banner: std.ArrayList(u8) = .empty;
        defer banner.deinit(gpa);
        try banner.appendSlice(gpa, "Runtime terminating during boot (");
        try diag.formatValue(gpa, v, &banner);
        try banner.appendSlice(gpa, ")\n");
        _ = std.os.linux.write(2, banner.items.ptr, banner.items.len);
        return 1;
    }
    return 0;
}

/// E3.12b: materialize the LitT literals of EVERY module into `ctx`, concatenated
/// in module order — the combined literal pool `.literal i` indexes after the
/// linker's index relocation (module k's slot j lands at `lit_offset[k] + j`).
/// Owned by the caller (one `gpa.free`). Empty when no module carries literals.
fn materializeAll(gpa: std.mem.Allocator, ctx: *FinalTerms.Ctx, mods: []loader.Module) ![]FinalTerms.Term {
    var total: usize = 0;
    for (mods) |mod| total += mod.literals.len;
    const outp = try gpa.alloc(FinalTerms.Term, total);
    errdefer gpa.free(outp);
    var i: usize = 0;
    for (mods) |*mod| {
        const part = try loader.materializeLiterals(gpa, ctx, mod);
        defer gpa.free(part);
        @memcpy(outp[i .. i + part.len], part);
        i += part.len;
    }
    return outp;
}

/// E3.12b: run module `mods[k]`'s `on_load` function (if it declares one) on a
/// throwaway process linked against the whole program, returning whether it
/// returned the atom `ok` (`true`), returned something else / crashed / did not
/// terminate (`false`), or has no on_load (`null` — no gate). Never a panic: an
/// unresolvable on_load target is treated as `false` (a load that names a missing
/// function must fail, not silently pass).
fn onLoadOk(gpa: std.mem.Allocator, atoms: *AtomTable, linked: *loader.Linked, mods: []loader.Module, k: usize) !?bool {
    var probe = try proc.Vm.init(gpa, atoms);
    defer probe.deinit();
    // A ctx is needed to decode the Attr proplist; use process 0's heap.
    const p0 = try probe.spawn(linked.prog, 0, null);
    const m = &probe.procs.items[p0].machine;
    const ol = (try loader.onLoadFun(gpa, &m.ctx, &mods[k])) orelse return null;
    const entry = loader.resolveLocal(linked.prog, linked.locs, linked.module_atom[k], ol.f, ol.arity) orelse return false;
    m.pc = entry;
    m.locs = linked.locs;
    m.exports = linked.exports;
    m.literals = try materializeAll(gpa, &m.ctx, mods);
    m.heap_lit_end = m.ctx.words.items.len; // e48-gc-literal-area: the GC water line
    defer gpa.free(m.literals);
    var sched: proc.Scheduler = .round_robin;
    try sched.drive(&probe, slice_budget, max_slices);
    if (m.status == .running or m.status == .suspended) return false;
    if (m.status == .crashed) return false;
    return FinalTerms.kindOf(&m.ctx, m.result) == .atom and
        std.mem.eql(u8, m.ctx.atoms.nameOf(FinalTerms.atomIdxOf(m.result)), "ok");
}

/// E1.2: `checkLoad` — the loader-acceptance mode's whole behavior. Composes
/// `loader.parse` + `loader.translate` and discards the result (no execution,
/// no dispatch): this is a PURE observation of "does the loader accept this
/// `.beam`", the exact question `--load-otp-corpus` asks of every curated OTP
/// module. On success the translate allocations are freed identically to
/// `run` (mirrors cli.zig's own recipe at the `run` composition above) so the
/// zero-leak law holds under `std.testing.allocator`.
///
/// OWNERSHIP (E1.2 fix): on `error.UnsupportedOp` the offending op's name —
/// which `translate` fills as a slice — may point INTO `mod.arena` (the
/// `gc_bif2` unsupported-BIF site fills it with `mod.atomName(...)`). Since
/// `checkLoad` frees that arena via `defer mod.deinit()` before it returns,
/// the raw slice would dangle. So we DUPE the name into `gpa`-owned memory
/// while the arena is still alive and hand that copy to the caller. **The
/// caller OWNS `.unsupported.name` and MUST free it with the SAME `gpa`.**
/// This makes ownership uniform across all three `translate` rejection sites
/// (two `opName()`-based, one arena-based) — the caller never has to reason
/// about which site fired.
pub const CheckLoadResult = union(enum) {
    ok,
    unsupported: loader.UnsupportedOpInfo,
};

pub fn checkLoad(gpa: std.mem.Allocator, beam_bytes: []const u8) !CheckLoadResult {
    var mod = try loader.parse(gpa, beam_bytes);
    defer mod.deinit();
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var unsupported: loader.UnsupportedOpInfo = undefined;
    const t = loader.translate(gpa, &mod, &atoms, &unsupported) catch |err| {
        if (err == error.UnsupportedOp) {
            // Dupe the name while mod.arena is still alive (the `defer
            // mod.deinit()` above fires only after this return completes), so
            // the caller receives gpa-owned memory it can safely read + free.
            const name_copy = try gpa.dupe(u8, unsupported.name);
            return .{ .unsupported = .{ .name = name_copy, .arity = unsupported.arity } };
        }
        // E5.2 (DIVERGENCE 46 discharged): the x-register file now spans the full
        // decodable range, so an x-register index no longer overflows the bank —
        // `xReg` is total and the former `x-register-index-over-15` load-reject is
        // unreachable. Any remaining translate error is a genuine one.
        return err;
    };
    defer {
        loader.freeProg(gpa, t.prog); // frees put_tuple2.elems too
        gpa.free(t.label_pc);
        gpa.free(t.entries);
        gpa.free(t.locs);
    }
    return .ok;
}

/// E0.5: print the VM's capability ledger — one machine-readable line per
/// implemented capability — into `out`. This is a pure OBSERVATION of the two
/// single-source tables the loader/executor actually consult:
///   `op <name> <arity>`            for each entry of loader.supported_ops
///   `bif <module>:<name>/<arity>`  for each entry of ia.supported_bifs
/// Both tables are declared pre-sorted (ops by name then arity; bifs by
/// module/name/arity), so the output is deterministic. No VM semantics here —
/// dumpCaps cannot claim a capability the tables (hence the loader) do not have,
/// which is exactly what the Zig round-trip law and the harness cross-law pin.
/// gap-erl-cli-eval: evaluate a `-eval`-style Erlang expression string and write
/// its OBSERVABLE output. The bounded value grammar + `erlang:display/1` are read
/// by `erl_expr` (a bare expression is evaluated and DISCARDED, no output — byte-
/// EQ with erl); a `.display` term is rendered with the SAME `%T` writer
/// (`diag.formatTermT`) `erlang:display/1` uses, plus the trailing newline. This
/// is the `-eval` flag's execution, exposed as the `zigvm eval` subcommand.
pub fn evalExpr(gpa: std.mem.Allocator, src: []const u8, out: *std.ArrayList(u8)) !void {
    // A standalone Machine supplies the ctx for BOTH parsing and rendering, so
    // io:format's formatTerm (which needs `m`) and the parsed fmt/args terms
    // share one heap. Machine.init has no side effects (no spawn/servers).
    var atoms = ta.AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    switch (try erl_expr.read(arena.allocator(), &m.ctx, src)) {
        .silent => {},
        .display => |t| {
            try diag.formatTermT(gpa, &m.ctx, t, out);
            try out.append(gpa, '\n');
        },
        .format => |f| {
            // io:format renders via the SAME io_format machinery the io:format
            // BIF uses; the resulting charlist is flattened to raw output bytes.
            const chars = io_format.formatTerm(&m, f.fmt, f.args) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.EvalFormat, // a bad format/arg → clean error
            };
            try flattenCharlist(&m.ctx, chars, gpa, out);
        },
    }
}

/// Flatten a charlist / binary / iolist term to raw bytes (the io output shape),
/// bounded against a cyclic/huge structure.
fn flattenCharlist(ctx: *ta.FinalTerms.Ctx, w: ta.FinalTerms.Term, gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    var budget: usize = 1 << 20;
    try flattenRec(ctx, w, gpa, out, &budget);
}

fn flattenRec(ctx: *ta.FinalTerms.Ctx, w: ta.FinalTerms.Term, gpa: std.mem.Allocator, out: *std.ArrayList(u8), budget: *usize) !void {
    const FT = ta.FinalTerms;
    if (budget.* == 0) return error.EvalFormat;
    budget.* -= 1;
    switch (FT.kindOf(ctx, w)) {
        .nil => {},
        .number => {
            const v = FT.smallValOf(w);
            if (v < 0 or v > 255) return error.EvalFormat;
            try out.append(gpa, @intCast(v));
        },
        .binary => try out.appendSlice(gpa, FT.binBytes(ctx, w)),
        .cons => {
            var cur = w;
            while (FT.kindOf(ctx, cur) == .cons) {
                try flattenRec(ctx, FT.listHead(ctx, cur), gpa, out, budget);
                cur = FT.listTail(ctx, cur);
            }
            if (FT.kindOf(ctx, cur) != .nil) try flattenRec(ctx, cur, gpa, out, budget); // improper tail
        },
        else => return error.EvalFormat,
    }
}

pub fn dumpCaps(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    for (loader.supported_ops) |c| {
        try out.print(gpa, "op {s} {d}\n", .{ c.name, c.arity });
    }
    for (ia.supported_bifs) |b| {
        try out.print(gpa, "bif {s}:{s}/{d}\n", .{ b.module, b.name, b.arity });
    }
}

// ============================================================================
// E18.2: cross-node term transport & total-order CLI surface
// ============================================================================
//
// These two subcommands expose the ALREADY-LAW-GOVERNED `etf` codec and
// `term_algebra` total order across a process boundary, so the OCaml harness
// (`--run-dist-term`) can cross-check them against a live pinned OTP-30 peer
// (`term_to_binary`/`binary_to_term`/`erlang:'<'`). They introduce NO new VM
// semantics — `etfReencode` is `encode ∘ decode` and `termCompare` is
// `FinalTerms.compare`/`compareExact`; the peer is the oracle, the CLI is the
// homomorphic image. All I/O is hex over stdout so no term-literal grammar is
// needed on either side (the ETF bytes are the shared representation both
// runtimes speak). Errors are NAMED tokens, never panics: a term the codec
// cannot express (`ForeignNode`, `UnsupportedRefLen`, `UnknownTag`, …) prints
// `etf-error:<Name>` / `cmp-error:<Name>` and exits nonzero, which the harness
// records as an honest UNTESTED-with-reason row.

pub const HexError = error{ OddHexLength, BadHexDigit };

/// Decode an ASCII hex string (even length, no `0x` prefix, either case) into a
/// freshly gpa-allocated byte buffer the caller owns. Total: any malformed
/// input is a NAMED `HexError`, never a panic.
pub fn hexDecode(gpa: std.mem.Allocator, hex: []const u8) (HexError || std.mem.Allocator.Error)![]u8 {
    if (hex.len % 2 != 0) return error.OddHexLength;
    const out = try gpa.alloc(u8, hex.len / 2);
    errdefer gpa.free(out);
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        const hi = std.fmt.charToDigit(hex[2 * i], 16) catch return error.BadHexDigit;
        const lo = std.fmt.charToDigit(hex[2 * i + 1], 16) catch return error.BadHexDigit;
        out[i] = (@as(u8, hi) << 4) | @as(u8, lo);
    }
    return out;
}

/// E18.2 `etf-reencode <hex>`: decode the ETF bytes (a versioned external term,
/// e.g. the peer's `term_to_binary(T)` output) and re-encode them, writing the
/// result as lower-hex into `out`. For every term the codec supports this is a
/// WIRE ROUND-TRIP FIDELITY observation: byte-identity with the peer's bytes is
/// the NODE-ENCODE law extended across the process boundary. A term the codec
/// cannot represent surfaces as its named `etf.DecodeError`/`etf.EncodeError`,
/// which the caller renders as `etf-error:<Name>` (an honest UNTESTED row).
pub fn etfReencode(gpa: std.mem.Allocator, hex_in: []const u8, out: *std.ArrayList(u8)) !void {
    const bytes = try hexDecode(gpa, hex_in);
    defer gpa.free(bytes);
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const t = try etf.decode(gpa, &ctx, bytes);
    var re = try etf.encode(gpa, &ctx, t);
    defer re.deinit(gpa);
    try appendHexLower(gpa, out, re.items);
}

/// Append `bytes` as lower-hex (two chars per byte) into `out`. Manual LUT (the
/// same idiom as `dist.digestHex`) — format-string hex specifiers vary across
/// Zig versions; this is unambiguous and matches what the harness parses.
pub fn appendHexLower(gpa: std.mem.Allocator, out: *std.ArrayList(u8), bytes: []const u8) !void {
    const lut = "0123456789abcdef";
    for (bytes) |b| {
        try out.append(gpa, lut[b >> 4]);
        try out.append(gpa, lut[b & 0x0f]);
    }
}

/// E18.2 `term-compare <hexA> <hexB> [exact]`: decode two ETF terms and print
/// their Erlang total-order relation — `lt`/`eq`/`gt` — into `out`. Default is
/// the ARITHMETIC order (`FinalTerms.compare`, matching the peer's `<`/`>`,
/// where a numerically-equal int and float tie as `eq`); the `exact` mode uses
/// `compareExact` (the `=:=`-refined order: int < float on a numeric tie). This
/// is the total-order HOMOMORPHISM's observable image: `zig_cmp == oracle_cmp`
/// is checked by the harness against the peer per twin-seeded vector.
pub fn termCompare(gpa: std.mem.Allocator, hex_a: []const u8, hex_b: []const u8, exact: bool, out: *std.ArrayList(u8)) !void {
    const ba = try hexDecode(gpa, hex_a);
    defer gpa.free(ba);
    const bb = try hexDecode(gpa, hex_b);
    defer gpa.free(bb);
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const ta_ = try etf.decode(gpa, &ctx, ba);
    const tb = try etf.decode(gpa, &ctx, bb);
    const ord = if (exact) FinalTerms.compareExact(&ctx, ta_, tb) else FinalTerms.compare(&ctx, ta_, tb);
    const token = switch (ord) {
        .lt => "lt",
        .eq => "eq",
        .gt => "gt",
    };
    try out.appendSlice(gpa, token);
}

// ============================================================================
// E0.7: the term-compare microbench (performance protocol v0)
// ============================================================================

/// Errors from the bench subcommand.
pub const BenchError = error{
    /// The requested bench unit is not one this build knows how to run.
    UnknownBenchUnit,
};

/// The **term-compare** microbench WORKLOAD — pure, deterministic, timing-free.
///
/// Builds a fixed 3-term ring ONCE (two 8-int lists differing only in the head
/// cell, and an 8-int tuple — a different term rank, so the ring exercises both
/// same-kind and cross-kind comparison), then performs `iters` comparisons over
/// successive ring pairs, folding each `Order` into a running checksum
/// (lt = -1, eq = 0, gt = +1). The checksum is a DENOTATION of the work: it
/// depends only on `iters` and the fixed ring, never on the clock — so a law
/// can pin it. `bench` wraps this in a timer; separating work from measurement
/// is exactly what keeps the workload law-testable (the timing is not).
///
/// Scaling law (pinned by the test): the ring has period 3, so
///   work(3 * n) == n * work(3)   for every n,
/// which simultaneously proves determinism AND that the loop ran `iters` times
/// (a workload the optimizer folded away could satisfy neither).
pub fn benchTermCompareWork(gpa: std.mem.Allocator, iters: u64) !i64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // ring[0], ring[1]: 8-int lists differing only in the head cell (value 1 vs
    // 99); ring[2]: an 8-int tuple. Built once, outside the timed loop.
    var list_a = FinalTerms.nil(&ctx);
    var list_b = FinalTerms.nil(&ctx);
    var elems: [8]FinalTerms.Term = undefined;
    var i: i64 = 8;
    while (i > 0) : (i -= 1) {
        list_a = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, i), list_a);
        list_b = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, if (i == 1) 99 else i), list_b);
        elems[@intCast(i - 1)] = FinalTerms.int(&ctx, i);
    }
    const tup = try FinalTerms.tuple(&ctx, &elems);
    const ring = [_]FinalTerms.Term{ list_a, list_b, tup };

    var checksum: i64 = 0;
    var n: u64 = 0;
    while (n < iters) : (n += 1) {
        const a = ring[@intCast(n % 3)];
        const b = ring[@intCast((n + 1) % 3)];
        checksum += switch (FinalTerms.compare(&ctx, a, b)) {
            .lt => @as(i64, -1),
            .eq => 0,
            .gt => 1,
        };
    }
    return checksum;
}

/// The **dist_send** microbench WORKLOAD (E18.7) — the SEND side of the live
/// distribution carrier, pure and timing-free. Builds a fixed remote-send triple
/// ONCE (an external `from` pid on our node, a registered-name target atom, and a
/// small fixed message tuple), then encodes `iters` DOP `REG_SEND` frames via
/// `dist.encodeRegSend` — the EXACT final wire encoding `LiveCarrier.sendRegSend`
/// writes onto a real socket (`112, enc(ctrl), enc(msg)`). Each frame's length is
/// folded into a running checksum and the frame is freed (zero net allocation
/// growth — the bench measures encode throughput, not heap growth).
///
/// The checksum is a DENOTATION of the work: with a fixed input every frame has
/// the SAME length L, so `work(iters) == iters * L`. That scaling law (pinned by
/// the test) simultaneously proves determinism AND that the encode loop ran
/// `iters` times — a workload the optimizer folded away could satisfy neither.
pub fn benchDistSendWork(gpa: std.mem.Allocator, iters: u64) !u64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    // The remote-send triple, built once outside the encode loop.
    const our_node = try atoms.intern("zigvmbench@127.0.0.1");
    const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
    const to_atom = FinalTerms.atom(&ctx, try atoms.intern("collector"));
    const msg = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.int(&ctx, 1),
        FinalTerms.int(&ctx, 2),
        FinalTerms.int(&ctx, 3),
    });

    var checksum: u64 = 0;
    var n: u64 = 0;
    while (n < iters) : (n += 1) {
        const frame = try dist.encodeRegSend(gpa, &ctx, from_pid, to_atom, msg);
        checksum +%= frame.len;
        gpa.free(frame);
    }
    return checksum;
}

/// The **term_hash** microbench WORKLOAD (perf-scale-corpus) — the hash-throughput
/// sibling of `term_compare`, a distinct perf pillar unit exercising the S7 term
/// hash rather than the S1 total order. Builds the SAME fixed 3-term ring ONCE
/// (two 8-int lists differing only in the head cell, and an 8-int tuple), then
/// folds `iters` term HASHES (`FinalTerms.hashTerm` over successive ring elements)
/// into a running checksum. The checksum is a DENOTATION of the work — it depends
/// only on `iters` and the fixed ring, never on the clock — and is NEVER compared
/// across VMs (only the timing ratio is; the Zig and OTP hash algorithms differ).
/// Period-3 ring ⇒ work(3 * n) == n * work(3), the scaling law the test pins
/// (proving determinism AND that the loop ran `iters` times).
pub fn benchTermHashWork(gpa: std.mem.Allocator, iters: u64) !u64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    var list_a = FinalTerms.nil(&ctx);
    var list_b = FinalTerms.nil(&ctx);
    var elems: [8]FinalTerms.Term = undefined;
    var i: i64 = 8;
    while (i > 0) : (i -= 1) {
        list_a = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, i), list_a);
        list_b = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, if (i == 1) 99 else i), list_b);
        elems[@intCast(i - 1)] = FinalTerms.int(&ctx, i);
    }
    const tup = try FinalTerms.tuple(&ctx, &elems);
    const ring = [_]FinalTerms.Term{ list_a, list_b, tup };

    var checksum: u64 = 0;
    var n: u64 = 0;
    while (n < iters) : (n += 1) {
        checksum +%= FinalTerms.hashTerm(&ctx, ring[@intCast(n % 3)]);
    }
    return checksum;
}

/// The **dispatch** microbench WORKLOAD (E44-T1, `gap-perf-bench-realism`) — the
/// FIRST bench that measures INTERPRETER DISPATCH, not a native kernel. Unlike
/// `term_compare`/`term_hash` (pure-Zig loops over `FinalTerms.compare`/`hashTerm`,
/// which measure a native routine and structurally HIDE the interpreter-vs-JIT gap),
/// this runs REAL BEAM bytecode through `ia.run` → `execInstr` for `iters`
/// reductions: a bounded arithmetic loop (`add`/`is_lt`/`jump`), so `iters`
/// reductions ≈ `iters` fetch-decode-dispatch cycles. The oracle twin
/// (`fixtures/erl/zigvm_bench.erl` `dispatch_loop`) is a compiled Erlang loop that
/// OTP-30 runs under BeamAsm — so the zigvm/oracle ratio measures the dispatch tax
/// (switch-interpreter vs native JIT) the perf pillar previously could not see.
///
/// The accumulator is kept BOUNDED in [0, 4096] by a modular reset, so no bignum
/// promotion perturbs the timing and the checksum (the final `x0`) is a small-int
/// DENOTATION of the reduction count mod the loop period — deterministic, and a
/// workload the optimizer folded away could not produce.
pub fn benchDispatchWork(gpa: std.mem.Allocator, iters: u64) !i64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    // run EXACTLY `iters` reductions of real bytecode (bounded loop → never halts).
    try ia.run(&m, dispatch_bench_prog, iters);
    return FinalTerms.smallValOf(m.regs[0]);
}

/// The dispatch-bench WORKLOAD program, shared by `benchDispatchWork` (via the
/// reference interpreter `ia.run`) AND `benchDispatchEngineWork` (via engines #3
/// and #4). A bounded arithmetic counted loop — every op (`move`/`add`/`is_lt`/
/// `jump`) is one the block-JIT covers natively (`jit_codegen.emitBlock`), so the
/// whole loop body runs as machine code under engine #4 and as fetch-decode-
/// dispatch under engine #3: exactly the dispatch tax the JIT removes.
/// 0: x0=0 (init, once) · 1: x0++ · 2: if x0<4096 fall to (3) else jump (5) reset ·
/// 3: jump 1 (loop) · 4: (unused) · 5: x0=0 · 6: jump 1.
const dispatch_bench_prog: ia.Program = &.{
    .{ .move = .{ .src = .{ .imm = 0 }, .dst = 0 } }, //                     0
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } }, //      1: x0++
    .{ .is_lt = .{ .a = .{ .x = 0 }, .b = .{ .imm = 4096 }, .else_to = 4 } }, // 2
    .{ .jump = .{ .to = 1 } }, //                                           3: loop back
    .{ .move = .{ .src = .{ .imm = 0 }, .dst = 0 } }, //                     4: reset x0
    .{ .jump = .{ .to = 1 } }, //                                           5: loop back
};

/// jit-bench-ratchet (JIT epoch slice #6): the SAME `dispatch_bench_prog` driven
/// under a chosen engine so the harness can MEASURE the native-vs-threaded
/// speedup on a workload the native backend actually covers. `native=false` runs
/// engine #3 (threaded: `predecode` + `runThreaded`); `native=true` runs engine #4
/// (block-JIT: `compileNativeBlock` + `runNativeBlock`, which stays in machine code
/// across the backward branch). Both run EXACTLY `iters` reductions from the SAME
/// init (x0=0), so — composing with the L2 differential (`runNativeBlock ≡
/// runThreaded` at every slice boundary) — the returned checksum (final x0) is
/// IDENTICAL across engines: a faster-but-wrong engine is not a speedup. The
/// harness times each engine separately; only the wall-time (never the checksum)
/// differs, and only the ratio is compared. On a non-x86_64-linux host
/// `runNativeBlock` transparently falls back to threaded, so the ratio degrades to
/// ~1.0 — honest (no native path, no fabricated gain), never a failure.
pub fn benchDispatchEngineWork(gpa: std.mem.Allocator, iters: u64, native: bool) !i64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    m.regs[0] = FinalTerms.int(&m.ctx, 0);
    if (native) {
        var n = try dispatch.compileNativeBlock(gpa, dispatch_bench_prog);
        defer n.deinit(gpa);
        try dispatch.runNativeBlock(&m, &n, iters);
    } else {
        var d = try dispatch.predecode(gpa, dispatch_bench_prog);
        defer d.deinit(gpa);
        try dispatch.runThreaded(&m, &d, iters);
    }
    return FinalTerms.smallValOf(m.regs[0]);
}

// ============================================================================
// gap-jit-beamasm-bench: matched-workload closed form (zigvm JIT vs OTP-30 BeamAsm)
// ============================================================================
//
// SEMANTIC DOMAIN: an *increment* is one full pass of the counted loop body of
// `dispatch_bench_prog` (add x0+=1 → is_lt x0<4096 → jump), which is the
// engine-neutral unit of work the harness `--bench-beamasm` mode compares across
// the zigvm JIT native engine (#4) and OTP-30's BeamAsm. Two closed forms pin the
// exact correspondence between a *reduction* budget (what `bench dispatch_native`
// consumes) and *increments* (what the Erlang `zigvm_jit_probe:count/2` counts):
//
//   • `dispatchBenchItersForIncrs(a)` — the exact reduction budget that runs `a`
//     increments TO COMPLETION. Accounting: the program starts at pc0 with a
//     one-off `move x0=0` (1 reduction). Each increment then costs 3 reductions
//     (add + is_lt-fallthrough + jump) EXCEPT every 4096th increment, which hits
//     the reset arm (add x0=4096 + is_lt-jump-to-reset + move x0=0 + jump = 4
//     reductions). So budget = 1 + 3*a + floor(a/4096). The `floor(a/4096)` term
//     is the ~0.02% reset accounting the harness discloses (a/12288 ≈ 0.0081%).
//
//   • `dispatchBenchFinalForIncrs(a)` — the final x0 after `a` completed
//     increments = `a % 4096`. (At an increment boundary x0 ∈ [0,4095]: the
//     4096th increment's transient 4096 is reset to 0 within the SAME increment,
//     so x0 lands on `a % 4096`, matching the Erlang whose X cycles 0..4095.)
//
// These are the RESULT-IDENTITY anchor: `benchDispatchEngineWork(iters,*) ==
// dispatchBenchFinalForIncrs(a)` for `iters = dispatchBenchItersForIncrs(a)`,
// proven for BOTH engines below — so a faster-but-wrong engine (or a mismatched
// work unit) reddens the law before the harness can record a fabricated ratio.

/// The exact reduction budget running EXACTLY `incrs` completed increments of
/// `dispatch_bench_prog` (see the block comment above for the accounting).
pub fn dispatchBenchItersForIncrs(incrs: u64) u64 {
    return 1 + 3 * incrs + incrs / 4096;
}

/// The final x0 after `incrs` completed increments — the checksum both engines
/// (and the matched Erlang `count/2`) must agree on: `incrs % 4096`.
pub fn dispatchBenchFinalForIncrs(incrs: u64) i64 {
    return @intCast(incrs % 4096);
}

/// gap-perf-bench-call (DIVERGENCE 637): the FUNCTION-CALL / RETURN dispatch
/// bench — the one realism dimension `dispatch`/`mixed`/`list_sum` all HIDE.
/// Every existing unit is call-free (the flat arithmetic loop) or tail-call-only
/// (the Erlang twins compile to loops), so none exercises the non-tail CALL/RETURN
/// machinery — `call_ext_code` export resolution + the CP (return-address) push,
/// the callee `ret` + CP pop — which is a DOMINANT real-BEAM cost (every `M:F(..)`).
/// This runs EXACTLY `iters` leaf calls through `ia.run` → `execInstr`: a bounded
/// counted loop whose body CALLS a trivial leaf export (`bench:leaf/0` → 1) and
/// accumulates its RETURN, then HALTS. Unlike `dispatch` (iters = reductions),
/// here `iters` = the CALL COUNT on BOTH VMs, so the checksum is a clean cross-VM
/// identity `== iters` (the OTP twin `call_loop/2` does the same `iters` calls),
/// and the timing ratio measures the call-dispatch tax the switch-interpreter pays
/// vs OTP-30 BeamAsm's native CALL. The program is built at RUNTIME so `iters`
/// bakes into the loop bound (a self-halting workload, no reduction-budget skew).
pub fn benchCallReturnWork(gpa: std.mem.Allocator, iters: u64) !i64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    const modb = try atoms.intern("bench");
    const leaf = try atoms.intern("leaf");
    const bound: i64 = @intCast(iters);
    // 0 counter:=0 · 1 acc:=0 · 2 if counter<iters fall→3 else→7(halt) ·
    // 3 call bench:leaf/0 (push CP=4) · 4 acc+=x0 · 5 counter+=1 · 6 jump 2 ·
    // 7 halt acc · 8 leaf: x0:=1 · 9 ret (pop CP→4).
    const prog = [_]ia.CInstr{
        .{ .move = .{ .src = .{ .imm = 0 }, .dst = 1 } }, //                    0
        .{ .move = .{ .src = .{ .imm = 0 }, .dst = 2 } }, //                    1
        .{ .is_lt = .{ .a = .{ .x = 1 }, .b = .{ .imm = bound }, .else_to = 7 } }, // 2
        .{ .call_ext_code = .{ .module = modb, .func = leaf, .arity = 0, .push_ret = true } }, // 3
        .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 0 }, .dst = 2 } }, //       4: acc += ret
        .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .imm = 1 }, .dst = 1 } }, //     5: counter++
        .{ .jump = .{ .to = 2 } }, //                                          6
        .{ .halt = .{ .src = .{ .x = 2 } } }, //                               7
        .{ .move = .{ .src = .{ .imm = 1 }, .dst = 0 } }, //                    8: leaf body
        .ret, //                                                               9
    };
    const exports = [_]ia.Export{.{ .module = modb, .func = leaf, .arity = 0, .pc = 8 }};
    m.exports = &exports;
    // Ample budget so the self-halting loop always reaches `halt` (≈7 reductions
    // per call + the leaf's 2); a run that hit the budget instead of halt would
    // return a WRONG (short) checksum and redden the result-identity law.
    try ia.run(&m, &prog, iters * 8 + 64);
    return FinalTerms.smallValOf(m.regs[2]);
}

/// jit-bench-realprog: a REAL list-traversal program — `mylists:sum/2`-shaped —
/// that folds a fixed cons list, accumulating into x1. Unlike the synthetic
/// `dispatch_bench_prog` (a bare counted loop), this walks a real heap cons SPINE
/// (`is_cons`/`get_list`) doing real arithmetic (`add`), exactly the shape of a
/// BEAM list fold. It runs CONTINUOUSLY: when the list is exhausted the else-arm
/// resets L to the original list (x4) AND resets the accumulator to 0 (so the sum
/// stays small ⇒ `add` never overflows into a bignum fallback), then loops. The
/// list is built ONCE up front, so there is ZERO allocation in the measured hot
/// loop — this is the TRAVERSAL-bound regime the widened native tier now covers
/// end to end (is_cons/get_list/add/move/jump are ALL native), as opposed to the
/// allocation-bound regime (`mixed`, put_list/test_heap) that still falls back.
///   x0 = L (working)   x1 = Acc   x2 = H   x3 = T   x4 = original list (const)
///   0 is_cons x0 else 5 · 1 get_list x0→x2,x3 · 2 add x1+=x2 · 3 move x0<-x3 ·
///   4 jump 0 · 5 move x0<-x4 (reset L) · 6 move x1<-0 (reset Acc) · 7 jump 0
const list_sum_prog: ia.Program = &.{
    .{ .is_cons = .{ .src = .{ .x = 0 }, .else_to = 5 } }, //                 0
    .{ .get_list = .{ .src = .{ .x = 0 }, .hd = .{ .x = 2 }, .tl = .{ .x = 3 } } }, // 1
    .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 2 }, .dst = 1 } }, //         2: Acc += H
    .{ .move = .{ .src = .{ .x = 3 }, .dst = 0 } }, //                        3: L := T
    .{ .jump = .{ .to = 0 } }, //                                            4
    .{ .move = .{ .src = .{ .x = 4 }, .dst = 0 } }, //                        5: reset L
    .{ .move = .{ .src = .{ .imm = 0 }, .dst = 1 } }, //                      6: reset Acc
    .{ .jump = .{ .to = 0 } }, //                                            7
};

/// Seed the list-sum machine: build the fixed list [1,2,3,4,5,6,7,8] on the heap
/// (once), pin it in BOTH x0 (working) and x4 (the const reset source), and zero
/// the accumulator x1. The list is small so the running sum never leaves the
/// small-int range (no bignum ⇒ `add` stays native).
fn seedListSum(m: *ia.Machine) !void {
    var lst = FinalTerms.nil(&m.ctx);
    var v: i64 = 8;
    while (v >= 1) : (v -= 1) lst = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, v), lst);
    m.regs[0] = lst; // working list
    m.regs[4] = lst; // const reset source (structurally shared — read-only)
    m.regs[1] = FinalTerms.int(&m.ctx, 0); // accumulator
}

/// jit-bench-realprog: run the REAL list-sum program for exactly `iters`
/// reductions under engine #3 (`native=false`: predecode + runThreaded) or engine
/// #4 (`native=true`: compileNativeBlock + runNativeBlock). Both start from the
/// SAME seeded state and run the SAME reduction count, so — composing with the L2
/// differential — the returned checksum (final Acc, x1) is IDENTICAL across
/// engines (LAW `jit-bench-realprog RESULT-IDENTITY`): a faster-but-wrong engine
/// is not a speedup. Only wall-time differs; the harness times each separately.
pub fn benchListSumEngineWork(gpa: std.mem.Allocator, iters: u64, native: bool) !i64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    try seedListSum(&m);
    if (native) {
        var n = try dispatch.compileNativeBlock(gpa, list_sum_prog);
        defer n.deinit(gpa);
        try dispatch.runNativeBlock(&m, &n, iters);
    } else {
        var d = try dispatch.predecode(gpa, list_sum_prog);
        defer d.deinit(gpa);
        try dispatch.runThreaded(&m, &d, iters);
    }
    return FinalTerms.smallValOf(m.regs[1]);
}

/// jit-bench-realprog: the executed-op NATIVE COVERAGE of the real list-sum
/// program over `iters` reductions — the honest fraction of the program's work
/// that ran as machine code (1.0 = fully native/traversal-bound; <1.0 = some ops
/// fell back). On a non-x86-64-linux host this is honestly 0.0 (no native path).
pub fn benchListSumNativeCoverage(gpa: std.mem.Allocator, iters: u64) !f64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    try seedListSum(&m);
    var n = try dispatch.compileNativeBlock(gpa, list_sum_prog);
    defer n.deinit(gpa);
    const split = try dispatch.runNativeBlockCounted(&m, &n, iters);
    return split.coverage();
}

/// gap-perf-bench-realism: the MIXED microbench WORKLOAD — the first bench that
/// exercises ALLOC + GC + DISPATCH together, a workload shaped like a real BEAM
/// program. Each *pass* runs real bytecode through `ia.run`→`execInstr`: it builds
/// a fresh 8-cell list on the process heap (`put_list` → the real arena allocator),
/// walks it summing heads (`get_hd`/`add`/`get_tl` → real dispatch), and drops the
/// previous list as garbage (`move nil`). Every `mixed_gc_period` passes the REAL
/// copying collector runs (`gc.collectMachineRoots`), reclaiming that garbage so the
/// heap stays bounded. `term_compare`/`term_hash`/`dispatch` each isolate ONE cost;
/// this unit measures the COMBINED alloc+GC+dispatch tax vs OTP-30 (BeamAsm + the
/// generational collector). DENOTATION (GC preserves meaning): after `iters` passes
/// the bounded counter x0 == iters%4096 and the per-pass accumulator x2 == 8*x0, so
/// `benchMixedWork(iters) == 8*(iters%4096)` — bounded, deterministic, and
/// unreproducible by a folded loop.
const mixed_gc_period: u64 = 16; // collect every N passes (alloc↔GC dial; timing-only)
const mixed_pass_budget: u64 = 128; // > max reductions/pass; the pass halts at fall-off first

// one pass, then halts (falls off the end). x0 counter PERSISTS across passes
// (runMixed resets pc, not x0). x1=list, x2=accumulator, x3=scratch head.
const mixed_prog: ia.Program = &.{
    .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } }, //          0: x0++
    .{ .is_lt = .{ .a = .{ .x = 0 }, .b = .{ .imm = 4096 }, .else_to = 3 } }, // 1: x0<4096 ? →2 : →3
    .{ .jump = .{ .to = 4 } }, //                                               2: skip reset
    .{ .move = .{ .src = .{ .imm = 0 }, .dst = 0 } }, //                         3: reset x0 (else_to)
    .{ .move = .{ .src = .{ .imm = 0 }, .dst = 2 } }, //                         4: x2 := 0 (per-pass)
    .{ .move = .{ .src = .nil, .dst = 1 } }, //                                  5: x1 := [] (old list → garbage)
    .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } }, //       6..13: cons x0 ×8
    .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } },
    .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } },
    .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } },
    .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } },
    .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } },
    .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } },
    .{ .put_list = .{ .h = .{ .x = 0 }, .t = .{ .x = 1 }, .dst = 1 } }, //       13: x1 = 8-cell list
    // walk 8 cells: (get_hd; add; get_tl) ×8 → pc 14..37; final get_tl leaves x1=nil.
    .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } },
    .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } },
    .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } },
    .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } },
    .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } },
    .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } },
    .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } },
    .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } },
    .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } },
    .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } },
    .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } },
    .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } },
    .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } },
    .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } },
    .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } },
    .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } },
    .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } },
    .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } },
    .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } },
    .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } },
    .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } },
    .{ .get_hd = .{ .src = .{ .x = 1 }, .dst = .{ .x = 3 } } },
    .{ .add = .{ .a = .{ .x = 2 }, .b = .{ .x = 3 }, .dst = 2 } },
    .{ .get_tl = .{ .src = .{ .x = 1 }, .dst = .{ .x = 1 } } }, //               37: x1=nil → pc 38==len → halt, x2=8*x0
};

/// Drive `iters` passes; collect every `mixed_gc_period` passes so the copying
/// collector is in the measured hot path. `pub` so the LAW can inspect the heap.
pub fn runMixed(m: *ia.Machine, iters: u64) !void {
    m.regs[0] = FinalTerms.int(&m.ctx, 0); // x0 counter := 0 (persists across passes)
    var p: u64 = 0;
    while (p < iters) : (p += 1) {
        m.pc = 0;
        m.status = .running;
        try ia.run(m, mixed_prog, mixed_pass_budget); // one pass; halts at fall-off
        if (p % mixed_gc_period == 0) try gc.collectMachineRoots(m); // REAL copying collect
    }
    try gc.collectMachineRoots(m); // leave a bounded, quiescent heap
}

pub fn benchMixedWork(gpa: std.mem.Allocator, iters: u64) !i64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    try runMixed(&m, iters);
    return FinalTerms.smallValOf(m.regs[2]);
}

/// Run one microbench `unit` for `iters` iterations and print a single
/// `ops_per_s <float>` line into `out`. The workload is `benchTermCompareWork`
/// (`term_compare`) or `benchDistSendWork` (`dist_send`, the live-carrier
/// remote-send throughput probe); this wrapper adds ONLY the monotonic-clock
/// measurement (via the `.awake` clock — monotonic, excludes suspend) and a
/// guard against the optimizer eliding the work. The harness parses `ops_per_s`
/// from stdout and computes the zigvm/oracle ratio — no VM semantics or
/// statistics live here (the median/MAD/ratio algebra is the OCaml `Bench`
/// module).
///
/// An unknown `unit` is rejected by name BEFORE the clock is touched, so the
/// error path never reads `io` (which is what lets the rejection law pass a
/// placeholder io).
pub fn bench(
    gpa: std.mem.Allocator,
    io: std.Io,
    unit: []const u8,
    iters: u64,
    out: *std.ArrayList(u8),
) !u8 {
    const is_term_compare = std.mem.eql(u8, unit, "term_compare");
    const is_dist_send = std.mem.eql(u8, unit, "dist_send");
    const is_term_hash = std.mem.eql(u8, unit, "term_hash");
    const is_dispatch = std.mem.eql(u8, unit, "dispatch");
    const is_mixed = std.mem.eql(u8, unit, "mixed");
    // jit-bench-ratchet: the SAME dispatch loop under engine #3 vs engine #4, so
    // the harness can time native-vs-threaded on a native-covered workload.
    const is_disp_threaded = std.mem.eql(u8, unit, "dispatch_threaded");
    const is_disp_native = std.mem.eql(u8, unit, "dispatch_native");
    // jit-bench-realprog: the REAL list-sum program (mylists:sum-shaped) under
    // engine #3 vs #4, plus a coverage probe that prints the native-coverage %.
    const is_lsum_threaded = std.mem.eql(u8, unit, "list_sum_threaded");
    const is_lsum_native = std.mem.eql(u8, unit, "list_sum_native");
    const is_lsum_cov = std.mem.eql(u8, unit, "list_sum_cov");
    const is_call = std.mem.eql(u8, unit, "call"); // gap-perf-bench-call: call/return dispatch
    if (!is_term_compare and !is_dist_send and !is_term_hash and !is_dispatch and
        !is_mixed and !is_disp_threaded and !is_disp_native and
        !is_lsum_threaded and !is_lsum_native and !is_lsum_cov and !is_call)
        return BenchError.UnknownBenchUnit;
    // The coverage probe is a static property, not a timing: print it and return
    // before touching the clock (it prints `native_coverage <frac>`, not ops/s).
    if (is_lsum_cov) {
        const cov = try benchListSumNativeCoverage(gpa, iters);
        try out.print(gpa, "native_coverage {d}\n", .{cov});
        return 0;
    }
    const t0 = std.Io.Timestamp.now(io, .awake);
    const checksum: u64 = if (is_dist_send)
        try benchDistSendWork(gpa, iters)
    else if (is_term_hash)
        try benchTermHashWork(gpa, iters)
    else if (is_dispatch)
        @bitCast(try benchDispatchWork(gpa, iters))
    else if (is_disp_threaded)
        @bitCast(try benchDispatchEngineWork(gpa, iters, false))
    else if (is_disp_native)
        @bitCast(try benchDispatchEngineWork(gpa, iters, true))
    else if (is_lsum_threaded)
        @bitCast(try benchListSumEngineWork(gpa, iters, false))
    else if (is_lsum_native)
        @bitCast(try benchListSumEngineWork(gpa, iters, true))
    else if (is_mixed)
        @bitCast(try benchMixedWork(gpa, iters))
    else if (is_call)
        @bitCast(try benchCallReturnWork(gpa, iters))
    else
        @bitCast(try benchTermCompareWork(gpa, iters));
    const t1 = std.Io.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(checksum);
    // gap-jit-beamasm-bench: the dispatch engine units ALSO print the final x0
    // checksum so the harness can byte-assert zigvm's result-identity against the
    // matched Erlang FINAL (RESULT-IDENTITY end-to-end). Printed as a signed i64;
    // an extra line never disturbs the `ops_per_s` timing parse (parse_metric
    // finds the line by key). Other units keep their single-line output.
    if (is_disp_native or is_disp_threaded) {
        try out.print(gpa, "final {d}\n", .{@as(i64, @bitCast(checksum))});
    }
    const ns = t0.durationTo(t1).nanoseconds;
    const secs = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
    const ops_per_s: f64 = if (secs > 0.0)
        @as(f64, @floatFromInt(iters)) / secs
    else
        0.0;
    try out.print(gpa, "ops_per_s {d}\n", .{ops_per_s});
    return 0;
}

// ============================================================================
// gap-reduction-oracle: measured reduction cost vs OTP-30 (the {R} granularity gap)
// ============================================================================
//
// SEMANTIC DOMAIN: for a FIXED, HALTING computation the observable is
// total-reductions-consumed — `m.reductions` after `ia.run` drives the workload
// program to `.halted`. R2b (gap-reduction-cost-model): zigvm now charges reductions
// the OTP-30 PER-CALL way — ~1 reduction per function CALL / tail-call, 0 for
// straight-line ops (`instr_algebra.reductionCost`). Each probe loop's back-edge is
// a TAIL call (`.tail = true`), so a loop of N iterations charges EXACTLY N
// reductions — the same per-call count OTP reports. The cross-VM ratio
// `zig_reds / otp_reds` therefore → ~1.0 (was 3-5x under the old per-instruction
// model). The RESULT (the computed value) is UNCHANGED: only the reduction
// accounting moved. The harness `--reduction-oracle` mode measures both sides and
// asserts the ratio is within a band of 1.0; this CLI is the zigvm probe: run a
// matched program to completion, print the per-call reduction count and the result
// checksum. MEASUREMENT ONLY.

/// The zigvm probe result: per-call reductions actually consumed, and the computed
/// value (a small-int denotation the matched Erlang must equal).
pub const RedsResult = struct { reds: u64, result: i64 };

/// countdown_sum: `csum(0,A)->A; csum(N,A)->csum(N-1,A+N)` — a tail-recursive
/// integer sum. Result = N*(N+1)/2. The back-edge (pc5→1) is the TAIL call that
/// re-enters csum, so each iteration charges EXACTLY 1 reduction — matching OTP's
/// per-call count. The intermediate add/is_lt/sub are straight-line ⇒ 0 reductions.
///  0: A := 0 · 1: N<1 ? →2(done) : →3(body) · 2: halt A ·
///  3: A += N · 4: N -= 1 · 5: tail-jump 1.
const countdown_sum_prog: ia.Program = &.{
    .{ .move = .{ .src = .{ .imm = 0 }, .dst = 1 } }, //                       0
    .{ .is_lt = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .else_to = 3 } }, //  1
    .{ .halt = .{ .src = .{ .x = 1 } } }, //                                   2
    .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 0 }, .dst = 1 } }, //          3: A += N
    .{ .sub = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } }, //        4: N -= 1
    .{ .jump = .{ .to = 1, .tail = true } }, //                               5: TAIL call csum
};

/// count_loop: `cloop(0)->0; cloop(N)->cloop(N-1)` — a bare countdown. Result 0.
/// The back-edge (pc3→0) is the TAIL call ⇒ 1 reduction per iteration.
///  0: N<1 ? →1(halt) : →2(body) · 1: halt N · 2: N -= 1 · 3: tail-jump 0.
const count_loop_prog: ia.Program = &.{
    .{ .is_lt = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .else_to = 2 } }, //  0
    .{ .halt = .{ .src = .{ .x = 0 } } }, //                                   1
    .{ .sub = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } }, //        2
    .{ .jump = .{ .to = 0, .tail = true } }, //                               3: TAIL call cloop
};

/// list_fold: fold a pre-built cons list [1..L], summing heads, then HALT (unlike
/// `list_sum_prog`, which resets and loops forever). Result = L*(L+1)/2. Walks a
/// real heap spine (is_cons/get_list) — the BEAM list-fold shape. The back-edge
/// (pc4→0) is the TAIL call ⇒ 1 reduction per element folded.
///  0: cons? →1(body) : →5(done) · 1: <H,T> := x0 · 2: A += H · 3: x0 := T ·
///  4: tail-jump 0 · 5: halt A.
const list_fold_prog: ia.Program = &.{
    .{ .is_cons = .{ .src = .{ .x = 0 }, .else_to = 5 } }, //                  0
    .{ .get_list = .{ .src = .{ .x = 0 }, .hd = .{ .x = 2 }, .tl = .{ .x = 3 } } }, // 1
    .{ .add = .{ .a = .{ .x = 1 }, .b = .{ .x = 2 }, .dst = 1 } }, //          2: A += H
    .{ .move = .{ .src = .{ .x = 3 }, .dst = 0 } }, //                         3: x0 := T
    .{ .jump = .{ .to = 0, .tail = true } }, //                               4: TAIL call lfold
    .{ .halt = .{ .src = .{ .x = 1 } } }, //                                   5
};

/// The exact PER-CALL reduction counts (R2b) each matched program consumes running
/// to completion — the closed forms the RESULT-IDENTITY law pins. Each is simply
/// the number of tail-call iterations: N (countdown/count) or L (list_fold). The
/// terminal iteration falls through to `halt` (a straight-line op, 0 reductions),
/// so there is no `+2` tail term anymore — exactly the OTP per-call count.
// ============================================================================
// verify-agent-codegen: the CLI probe for agent-authored, contract-verified units
// ============================================================================
//
// `zigvm agent-eval <fn> <arg…>` runs an AGENT-AUTHORED function (src/agent_codegen.zig)
// on positional integer args and prints its single integer result on one line.
// This is the seam the harness `--verify-agent-codegen` firewall rides to run the
// REAL Zig impl on seeded + boundary inputs and assert its Aeon contract predicate
// holds on every output. Introduces NO VM semantics — a pure dispatch onto the
// agent-codegen algebra. Domain errors are NAMED (never a panic): a non-integer
// arg, unknown fn, or wrong arity returns a status the harness reads as red.
pub const AgentEvalCliError = error{BadAgentEvalArg};

pub fn agentEval(
    gpa: std.mem.Allocator,
    fn_name: []const u8,
    args: []const []const u8,
    out: *std.ArrayList(u8),
) !u8 {
    var buf: [16]u64 = undefined;
    if (args.len > buf.len) return AgentEvalCliError.BadAgentEvalArg;
    for (args, 0..) |a, i| {
        buf[i] = std.fmt.parseInt(u64, a, 10) catch return AgentEvalCliError.BadAgentEvalArg;
    }
    const r = try agent_codegen.agentEvalU64(fn_name, buf[0..args.len]);
    try out.print(gpa, "{d}\n", .{r});
    return 0;
}

pub fn redsCountdownSum(n: u64) u64 {
    return n;
}
pub fn redsCountLoop(n: u64) u64 {
    return n;
}
pub fn redsListFold(l: u64) u64 {
    return l;
}

/// The per-INSTRUCTION retirement count of each probe (the `run` budget currency,
/// which bounds preemption on `m.instrs`). A safe run budget derives from these
/// (strictly greater), independent of the per-call reduction count returned.
fn instrsCountdownSum(n: u64) u64 {
    return 1 + 4 * n + 2;
}
fn instrsCountLoop(n: u64) u64 {
    return 3 * n + 2;
}
fn instrsListFold(l: u64) u64 {
    return 5 * l + 2;
}

/// Run a matched HALTING workload to completion and return the reductions
/// consumed (`m.reductions`, one per retired instruction) plus the computed
/// result. The budget is set strictly above the closed-form so the program
/// halts on its OWN terms (never fuel-starved); a machine left `.running` is an
/// error (the caller's N was too large for the budget — never a silent
/// wrong-count). Zero leaks: arena/atoms freed on every path.
pub fn redsWork(gpa: std.mem.Allocator, workload: []const u8, n: u64) !RedsResult {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();

    var prog: ia.Program = undefined;
    var budget: u64 = undefined;
    // R2b: the `run` budget is an INSTRUCTION budget (preemption rides `m.instrs`),
    // so it derives from the per-instruction count (strictly greater), NOT the
    // per-call reduction count returned to the oracle.
    if (std.mem.eql(u8, workload, "countdown_sum")) {
        m.regs[0] = FinalTerms.int(&m.ctx, @intCast(n)); // N
        prog = countdown_sum_prog;
        budget = instrsCountdownSum(n) + 16;
    } else if (std.mem.eql(u8, workload, "count_loop")) {
        m.regs[0] = FinalTerms.int(&m.ctx, @intCast(n)); // N
        prog = count_loop_prog;
        budget = instrsCountLoop(n) + 16;
    } else if (std.mem.eql(u8, workload, "list_fold")) {
        // Build [1,2,..,L] on the heap ONCE (outside any measured window — the
        // reductions counted are the FOLD only, matching the Erlang probe which
        // snapshots reductions AFTER lists:seq/2 built the list).
        var lst = FinalTerms.nil(&m.ctx);
        var v: i64 = @intCast(n);
        while (v >= 1) : (v -= 1) lst = try FinalTerms.cons(&m.ctx, FinalTerms.int(&m.ctx, v), lst);
        m.regs[0] = lst; // working list
        m.regs[1] = FinalTerms.int(&m.ctx, 0); // accumulator
        prog = list_fold_prog;
        budget = instrsListFold(n) + 16;
    } else {
        return BenchError.UnknownBenchUnit;
    }

    try ia.run(&m, prog, budget);
    if (m.status != .halted) return error.WorkloadDidNotHalt;
    return .{ .reds = m.reductions, .result = FinalTerms.smallValOf(m.result) };
}

/// The `zigvm reds <workload> <N>` subcommand body: run the matched workload and
/// print `reds <count>` + `result <value>` for the harness `--reduction-oracle`
/// to parse against the pinned-OTP side. Two lines; a parser keys on the field.
pub fn reds(
    gpa: std.mem.Allocator,
    workload: []const u8,
    n: u64,
    out: *std.ArrayList(u8),
) !u8 {
    const r = try redsWork(gpa, workload, n);
    try out.print(gpa, "reds {d}\n", .{r.reds});
    try out.print(gpa, "result {d}\n", .{r.result});
    return 0;
}

// ============================================================================
// gap-reduction-cost-model R4: the LIVE scheduling-latency probe (the {R} axis)
// ============================================================================
//
// The zigvm side of `--latency-oracle`: run W CPU-bound tail-recursive hogs
// through the REAL round-robin `Scheduler.drive` with a `LatencyHistogram`
// ATTACHED to the Vm, and print the per-grant scheduling-latency distribution
// (measured in reductions consumed by OTHER processes between a proc's grants).
// This is the SAME instrumentation the `LAW e50-t4 LIVE-LATENCY` exercises —
// exposed as a CLI probe so the harness can compare zigvm's grant-latency
// distribution against pinned OTP-30's scheduling signal. MEASUREMENT ONLY.

/// The `zigvm latency <W> <F> <rounds>` probe: W tail hogs, fuel F, driven
/// round-robin for W*rounds grants with a histogram attached. Prints the sample
/// count, key percentiles (p50/p90/p100, in reductions), and the non-empty
/// bucket lower bounds — a machine-parsable grant-latency distribution. The
/// steady-state per-grant latency is (W-1)*F (a proc waits behind its W-1 peers,
/// each burning F reductions), which the harness reports against OTP-30's signal.
pub fn latency(
    gpa: std.mem.Allocator,
    w: u64,
    f: u64,
    rounds: u64,
    out: *std.ArrayList(u8),
) !u8 {
    if (w == 0 or f == 0 or rounds == 0) return BenchError.UnknownBenchUnit;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var vm = try proc.Vm.init(gpa, &atoms);
    defer vm.deinit();
    // A pure tail self-call hog — each iteration charges 1 per-call reduction
    // (== 1 instr), so a grant of F consumes F reductions and the latency
    // staircase is measured in the OTP per-call currency (R2b).
    const hog: ia.Program = &.{.{ .jump = .{ .to = 0, .tail = true } }};
    var i: u64 = 0;
    while (i < w) : (i += 1) _ = try vm.spawn(hog, 0, null);

    var h = proc.LatencyHistogram.init(f);
    vm.latency_histogram = &h;
    const sched: proc.Scheduler = .round_robin;
    try sched.drive(&vm, f, @intCast(w * rounds));
    vm.latency_histogram = null;

    // Two header lines + one line per non-empty bucket. The harness keys on the
    // field names (`samples`, `p50`, `p90`, `p99`, `p100`, `steady`, `bucket`).
    // gap-reduction-latency-percentiles (DIVERGENCE 605): the FULL tail vector — p99
    // is the soft-real-time SLO signal (the tail a scheduler must bound), added here.
    const s = h.summary();
    try out.print(gpa, "samples {d}\n", .{s.n});
    try out.print(gpa, "p50 {d}\n", .{s.p50});
    try out.print(gpa, "p90 {d}\n", .{s.p90});
    try out.print(gpa, "p99 {d}\n", .{s.p99});
    try out.print(gpa, "p100 {d}\n", .{s.p100});
    // The MODELLED steady-state per-grant latency: (W-1)*F.
    try out.print(gpa, "steady {d}\n", .{(w - 1) * f});
    for (h.buckets, 0..) |c, b| {
        if (c != 0) try out.print(gpa, "bucket {d} count {d}\n", .{ @as(u64, @intCast(b)) * h.width, c });
    }
    return 0;
}

// ============================================================================
// E6.9: the scalability throughput probe (scalability protocol, §2.3)
// ============================================================================

/// Errors from the scale subcommand.
pub const ScaleError = error{
    /// The requested scale unit is not one this build knows how to run.
    UnknownScaleUnit,
    /// The scheduler count is outside the SMP engine's supported range.
    SchedulerCountOutOfRange,
    /// gap-ets-scale-unit: the contention workload lost an update, so the
    /// threads ran a cheaper workload than the one being priced. There is no
    /// honest throughput for that run — refusing to report one is the point.
    EtsLostUpdate,
};

/// Workers per storm round and rounds per measurement. Sized so one `scale` run
/// does enough conserved work (`scale_workers * scale_rounds` self-terminating
/// storms) that its wall-time is stable under the harness's median/MAD gate,
/// while staying bounded (a fixed, terminating amount of work).
const scale_workers: u32 = 96;
const scale_rounds: u32 = 240;
const scale_max_steps: usize = 20_000;

/// Rounds per `dist_fanout` measurement (E18.7). Each round fans one REG_SEND out
/// to every one of the `n_peers` targets, so a measurement encodes
/// `n_peers * dist_fanout_rounds` frames — conserved work per peer, sized to stay
/// sub-second while dominating process-startup noise under the median/MAD gate.
const dist_fanout_rounds: u32 = 8_000;

/// gap-ets-scale-unit: rounds x iters per thread. Sized so a single n-point is
/// ~0.1s of real contended work — long enough that thread spawn is not what is
/// being measured, short enough that the three n-points fit a gate budget.
const ets_scale_rounds: u32 = 6;
const ets_scale_iters: usize = 4_000;

/// gap-ets-scale-unit: the scale-unit REGISTRY, as a value.
///
/// The unit names used to be an `and`-chain of `mem.eql` inside `scale`, which
/// meant the only way to check that a unit is REACHABLE was to run it — and
/// running it needs a real clock, so no in-process law could. Dropping a unit
/// from that chain would have been invisible to the suite: the FM-DISPATCH-DEAD
/// shape, in its measurement-surface form. As a value it is checkable purely.
pub const scale_units = [_][]const u8{ "spawn_storm", "dist_fanout", "spawn_storm_real", "ets_contention" };

pub fn scaleUnitKnown(unit: []const u8) bool {
    for (scale_units) |u| {
        if (std.mem.eql(u8, unit, u)) return true;
    }
    return false;
}

/// The **dist_fanout** scalability WORKLOAD (E18.7) — 2-node fan-out over the
/// live carrier's send path, pure and timing-free. Models one node broadcasting a
/// registered-send to `n_peers` remote targets: builds the `from` pid, the
/// `n_peers` distinct target atoms, and a fixed message ONCE, then for each of
/// `rounds` rounds encodes one `dist.encodeRegSend` frame per peer (freeing each),
/// folding total frames encoded into the return. The result is a DENOTATION of
/// the work: `work(n_peers, rounds) == n_peers * rounds` frames — a scaling law
/// (pinned by the test) proving the fan-out loop ran exactly and the optimizer
/// did not elide it. The harness times this to a per-peer throughput curve and
/// bands the normalized shape against the OTP-30 oracle (δ ≤ 0.25 at E18).
pub fn scaleDistFanoutWork(gpa: std.mem.Allocator, n_peers: u32, rounds: u32) !u64 {
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();

    const our_node = try atoms.intern("zigvmfanout@127.0.0.1");
    const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
    const msg = try FinalTerms.tuple(&ctx, &.{
        FinalTerms.int(&ctx, 1),
        FinalTerms.int(&ctx, 2),
    });
    // n_peers distinct registered-name targets ("peer0".."peer<n-1>"), interned
    // once so the fan-out loop only pays encode cost, not atom-intern cost.
    var targets = try gpa.alloc(FinalTerms.Term, n_peers);
    defer gpa.free(targets);
    var name_buf: [32]u8 = undefined;
    var p: u32 = 0;
    while (p < n_peers) : (p += 1) {
        const name = try std.fmt.bufPrint(&name_buf, "peer{d}", .{p});
        targets[p] = FinalTerms.atom(&ctx, try atoms.intern(name));
    }

    var frames: u64 = 0;
    var round: u32 = 0;
    while (round < rounds) : (round += 1) {
        for (targets) |to_atom| {
            const frame = try dist.encodeRegSend(gpa, &ctx, from_pid, to_atom, msg);
            frames +%= 1;
            gpa.free(frame);
        }
    }
    return frames;
}

/// Run the `spawn_storm` scalability workload at `n_sched` schedulers and print a

/// gap-ets-scale-unit — the ETS shared-store contention workload.
///
/// `gap-ets-concurrency` has sat in the ranked queue labelled "measurement-bound:
/// cannot be measured on this contended host". Checking that turned up something
/// else: there were THREE scale units (`spawn_storm`, `dist_fanout`,
/// `spawn_storm_real`) and **none of them touched ETS**. The row was not blocked
/// on an untrustworthy number — it had no number at all. A measurement that does
/// not exist cannot be untrustworthy, and it also cannot improve.
///
/// The workload is the one `LAW gap-b-inc0` already proves correct: N real
/// threads, each doing M `ets:update_counter/3` on ONE shared public table, so
/// the only thing serializing them is the ETS reentrant spinlock — the exact
/// cell any future coordinator narrowing would move.
///
/// THE MEASUREMENT VALIDATES ITSELF, which the other three units do not. A
/// throughput number is only emitted if the final counter equals N×M exactly. A
/// run that lost an update ran a DIFFERENT, cheaper workload, and reporting its
/// ops/sec would reward the corruption with a better score — the benchmark would
/// be fastest precisely when it was most broken.
fn scaleWorkEts(
    gpa: std.mem.Allocator,
    atoms: *ta.AtomTable,
    nthreads: u32,
    iters: usize,
) !u64 {
    var vm = try proc.Vm.init(gpa, atoms);
    defer vm.deinit();

    const halt_prog: ia.Program = &.{.{ .move = .{ .src = .{ .imm = 0 }, .dst = 0 } }};

    // One shared PUBLIC named table holding {k, 0}. Public because each worker
    // writes from its OWN machine; `protected` would reject the peers.
    const setup = try vm.spawn(halt_prog, 0, null);
    const sm = &vm.procs.items[setup].machine;
    const tname = try atoms.intern("scale_ctr_tab");
    const opts = try ta.FinalTerms.cons(
        &sm.ctx,
        ta.FinalTerms.atom(&sm.ctx, try atoms.intern("named_table")),
        try ta.FinalTerms.cons(
            &sm.ctx,
            ta.FinalTerms.atom(&sm.ctx, try atoms.intern("public")),
            ta.FinalTerms.nil(&sm.ctx),
        ),
    );
    _ = try ets_bifs.new_2(sm, &.{ ta.FinalTerms.atom(&sm.ctx, tname), opts });
    const key0 = ta.FinalTerms.atom(&sm.ctx, try atoms.intern("k"));
    _ = try ets_bifs.insert_2(sm, &.{
        ta.FinalTerms.atom(&sm.ctx, tname),
        try ta.FinalTerms.tuple(&sm.ctx, &.{ key0, ta.FinalTerms.int(&sm.ctx, 0) }),
    });

    const Worker = struct {
        fn run(m: *ia.Machine, tab: ta.FinalTerms.Term, key: ta.FinalTerms.Term, incr: ta.FinalTerms.Term, n: usize) void {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                _ = ets_bifs.update_counter_3(m, &.{ tab, key, incr }) catch return;
            }
        }
    };

    var machines: [proc.SmpEngine.MAX_SCHED]*ia.Machine = undefined;
    for (0..nthreads) |w| {
        const wp = try vm.spawn(halt_prog, 0, null);
        machines[w] = &vm.procs.items[wp].machine;
    }
    var threads: [proc.SmpEngine.MAX_SCHED]std.Thread = undefined;
    for (0..nthreads) |w| {
        const m = machines[w];
        const tab = ta.FinalTerms.atom(&m.ctx, tname); // atoms are shared immediates
        const key = ta.FinalTerms.atom(&m.ctx, try atoms.intern("k"));
        const incr = ta.FinalTerms.int(&m.ctx, 1);
        threads[w] = try std.Thread.spawn(.{}, Worker.run, .{ m, tab, key, incr, iters });
    }
    for (0..nthreads) |w| threads[w].join();

    // SELF-VALIDATION. A lost update means the threads ran a cheaper workload
    // than the one being priced, so there is no honest throughput to report.
    const got = try ets_bifs.lookup_2(sm, &.{ ta.FinalTerms.atom(&sm.ctx, tname), key0 });
    const row = ta.FinalTerms.listHead(&sm.ctx, got);
    const final = ta.FinalTerms.smallValOf(ta.FinalTerms.tupleElem(&sm.ctx, row, 1));
    const expect: i64 = @intCast(@as(usize, nthreads) * iters);
    if (final != expect) return ScaleError.EtsLostUpdate;
    return @intCast(expect);
}
/// single `throughput <float>` line (grants per second). The WORKLOAD is
/// `proc.scaleWork` — a deterministic spawn-storm whose completed-work count is
/// invariant of `n_sched`; this wrapper adds ONLY the monotonic-clock
/// measurement (the `.awake` clock) and the round loop, so the throughput number
/// is `total_grants / wall_seconds`. The harness records the point, normalizes
/// the curve s(n)=throughput(n)/throughput(1), and bands it (δ ≤ 0.40 at E6). No
/// statistics live here (the median/MAD/band algebra is the OCaml `Bench`
/// module); no VM semantics enter (the work is the SMP engine's).
///
/// An unknown `unit` / out-of-range scheduler count is rejected by name BEFORE
/// the clock is touched (the error path never reads `io`).
pub fn scale(
    gpa: std.mem.Allocator,
    io: std.Io,
    unit: []const u8,
    n_sched: u32,
    out: *std.ArrayList(u8),
) !u8 {
    const is_dist_fanout = std.mem.eql(u8, unit, "dist_fanout");
    // e48-smp-s5: the REAL-thread scaling unit — driveThreads (the S3/S4
    // concurrent engine) instead of the deterministic model. The FIRST honest
    // CPU-throughput surface for the scalability pillar.
    const is_spawn_storm_real = std.mem.eql(u8, unit, "spawn_storm_real");
    // gap-ets-scale-unit: the FOURTH unit, and the first that touches ETS.
    const is_ets = std.mem.eql(u8, unit, "ets_contention");
    if (!scaleUnitKnown(unit)) return ScaleError.UnknownScaleUnit;
    // `n_sched` names the scaling axis: scheduler count (spawn_storm) or fan-out
    // degree (dist_fanout). Both are bounded 1..MAX_SCHED so a stray huge n never
    // allocates unboundedly (the charter n-points are {1,2,4}).
    if (n_sched < 1 or n_sched > proc.SmpEngine.MAX_SCHED)
        return ScaleError.SchedulerCountOutOfRange;

    if (is_ets) {
        var ets_atoms = AtomTable.init(gpa);
        defer ets_atoms.deinit();
        const t0 = std.Io.Timestamp.now(io, .awake);
        var ops: u64 = 0;
        var r: u32 = 0;
        while (r < ets_scale_rounds) : (r += 1)
            ops += try scaleWorkEts(gpa, &ets_atoms, n_sched, ets_scale_iters);
        const t1 = std.Io.Timestamp.now(io, .awake);
        const ns = t0.durationTo(t1).nanoseconds;
        const secs = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
        const throughput: f64 = if (secs > 0.0) @as(f64, @floatFromInt(ops)) / secs else 0.0;
        try out.print(gpa, "ops_per_s {d}\n", .{throughput});
        return 0;
    }

    if (is_dist_fanout) {
        const t0 = std.Io.Timestamp.now(io, .awake);
        const frames = try scaleDistFanoutWork(gpa, n_sched, dist_fanout_rounds);
        const t1 = std.Io.Timestamp.now(io, .awake);
        std.mem.doNotOptimizeAway(frames);
        const ns = t0.durationTo(t1).nanoseconds;
        const secs = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
        const throughput: f64 = if (secs > 0.0)
            @as(f64, @floatFromInt(frames)) / secs
        else
            0.0;
        try out.print(gpa, "ops_per_s {d}\n", .{throughput});
        return 0;
    }

    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();

    const t0 = std.Io.Timestamp.now(io, .awake);
    var total_grants: u64 = 0;
    var round: u32 = 0;
    // e48-smp-s5: the REAL unit runs FEWER, heavier rounds (each storm is
    // ~4M reductions of unlocked machine run; 240 model-sized rounds would
    // measure thread-spawn overhead, not execution).
    const rounds: u32 = if (is_spawn_storm_real) 3 else scale_rounds;
    while (round < rounds) : (round += 1) {
        const storm = if (is_spawn_storm_real)
            try proc.scaleWorkReal(gpa, &atoms, n_sched, scale_workers)
        else
            try proc.scaleWork(gpa, &atoms, n_sched, scale_workers, scale_max_steps);
        // A storm that did not complete within the step bound is a FAILED law —
        // surface it as an error (a truncated storm would bias the throughput).
        if (!storm.completed) return error.ScaleStormDidNotComplete;
        total_grants += storm.grants;
    }
    const t1 = std.Io.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(total_grants);

    const ns = t0.durationTo(t1).nanoseconds;
    const secs = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
    const throughput: f64 = if (secs > 0.0)
        @as(f64, @floatFromInt(total_grants)) / secs
    else
        0.0;
    try out.print(gpa, "ops_per_s {d}\n", .{throughput});
    return 0;
}

// ============================================================================
// Tests (failing-first law: written before `run` exists)
// ============================================================================

test "check-load accepts mylists.beam" {
    const beam = @embedFile("mylists.beam");
    const result = try checkLoad(std.testing.allocator, beam);
    try std.testing.expect(result == .ok);
}

test "LAW gap-erl-cli-surface init-args grammar: -flag groups values-until-next-flag; -extra terminates flag parsing (rest is plain, verbatim); leading bare tokens are plain; TOTAL over any argv (init:get_arguments/get_plain_arguments contract)" {
    var arena_i = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_i.deinit();
    const a = arena_i.allocator();

    // (1) a typical build-tool invocation: flags with 0/1/2 values, no -extra.
    {
        const argv = [_][]const u8{ "-noshell", "-pa", "d1", "d2", "-s", "init", "stop" };
        const r = try parseInitArgs(a, &argv);
        try std.testing.expectEqual(@as(usize, 3), r.flags.len);
        try std.testing.expectEqualStrings("noshell", r.flags[0].name);
        try std.testing.expectEqual(@as(usize, 0), r.flags[0].values.len);
        try std.testing.expectEqualStrings("pa", r.flags[1].name);
        try std.testing.expectEqual(@as(usize, 2), r.flags[1].values.len);
        try std.testing.expectEqualStrings("d2", r.flags[1].values[1]);
        try std.testing.expectEqualStrings("s", r.flags[2].name);
        try std.testing.expectEqual(@as(usize, 2), r.flags[2].values.len); // init, stop
        try std.testing.expectEqual(@as(usize, 0), r.plain.len);
    }
    // (2) THE -extra CONTRACT: everything after -extra is a PLAIN argument,
    //     verbatim — even tokens that LOOK like flags (-x). This is the
    //     pass-through build tools rely on (m1 target: not terminating at -extra
    //     would wrongly parse -x as a flag).
    {
        const argv = [_][]const u8{ "-pa", "d", "-extra", "-x", "y", "z" };
        const r = try parseInitArgs(a, &argv);
        try std.testing.expectEqual(@as(usize, 1), r.flags.len);
        try std.testing.expectEqualStrings("pa", r.flags[0].name);
        try std.testing.expectEqual(@as(usize, 3), r.plain.len);
        try std.testing.expectEqualStrings("-x", r.plain[0]); // a dash-token, kept PLAIN
        try std.testing.expectEqualStrings("z", r.plain[2]);
    }
    // (3) leading bare tokens (before any flag) are plain.
    {
        const argv = [_][]const u8{ "foo", "-run", "m", "f" };
        const r = try parseInitArgs(a, &argv);
        try std.testing.expectEqual(@as(usize, 1), r.plain.len);
        try std.testing.expectEqualStrings("foo", r.plain[0]);
        try std.testing.expectEqual(@as(usize, 1), r.flags.len);
        try std.testing.expectEqual(@as(usize, 2), r.flags[0].values.len);
    }
    // (4) empty argv → empty parse (totality edge).
    {
        const r = try parseInitArgs(a, &[_][]const u8{});
        try std.testing.expectEqual(@as(usize, 0), r.flags.len);
        try std.testing.expectEqual(@as(usize, 0), r.plain.len);
    }

    // PROPERTY (seeded, totality + two invariants over generated argv): parse
    // NEVER panics, and — outside the -extra tail — NO flag's value begins with
    // '-' (values-until-next-flag holds: m2 target). Also every token is
    // accounted for exactly once (conservation).
    var prng = std.Random.DefaultPrng.init(0xE51C11);
    const rnd = prng.random();
    const pool = [_][]const u8{ "-a", "-bb", "x", "yy", "-extra", "z", "-c", "w" };
    var iter: usize = 0;
    while (iter < 200) : (iter += 1) {
        var arena_j = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena_j.deinit();
        const aj = arena_j.allocator();
        const n = rnd.uintLessThan(usize, 8);
        const argv = try aj.alloc([]const u8, n);
        for (argv) |*t| t.* = pool[rnd.uintLessThan(usize, pool.len)];
        const r = try parseInitArgs(aj, argv); // TOTAL: no panic
        // invariant: a flag value never begins with '-' (it would be the next flag)
        for (r.flags) |fl| for (fl.values) |v| try std.testing.expect(!(v.len > 0 and v[0] == '-'));
        // conservation: |flags| + Σ|values| + |plain| + (extra-terminators consumed) == n.
        var accounted: usize = 0;
        for (r.flags) |fl| accounted += 1 + fl.values.len;
        accounted += r.plain.len;
        // if an -extra was present it consumed one token as the terminator itself.
        var had_extra = false;
        for (argv) |t| if (std.mem.eql(u8, t, "-extra")) {
            had_extra = true;
        };
        if (had_extra) accounted += 1;
        try std.testing.expectEqual(n, accounted); // EXACT partition: every token is a flag-name, a value, a plain arg, or the one -extra terminator
    }
}

test "LAW gap-erl-cli-exec resolve-boot: -s/-run resolve the FIRST boot instruction per init.erl start_it (module, func default `start`, arg tokens, kind); no -s/-run → null; TOTAL over any argv" {
    var arena_i = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_i.deinit();
    const a = arena_i.allocator();

    // `-s M F A B` → M:F([A,B]) with ATOM args.
    {
        const r = try parseInitArgs(a, &[_][]const u8{ "-pa", "d", "-s", "mymod", "boot", "x", "y" });
        const call = resolveBoot(r).?;
        try std.testing.expectEqualStrings("mymod", call.module);
        try std.testing.expectEqualStrings("boot", call.func);
        try std.testing.expectEqual(BootArgKind.atoms, call.kind);
        try std.testing.expectEqual(@as(usize, 2), call.argv.len);
        try std.testing.expectEqualStrings("y", call.argv[1]);
    }
    // `-s M` → M:start() (func defaults to `start`, no arg tokens).
    {
        const r = try parseInitArgs(a, &[_][]const u8{ "-s", "onlymod" });
        const call = resolveBoot(r).?;
        try std.testing.expectEqualStrings("onlymod", call.module);
        try std.testing.expectEqualStrings("start", call.func);
        try std.testing.expectEqual(@as(usize, 0), call.argv.len);
    }
    // `-run` → STRING args, and the FIRST boot flag wins over a later `-s`.
    {
        const r = try parseInitArgs(a, &[_][]const u8{ "-run", "m", "f", "arg", "-s", "other", "g" });
        const call = resolveBoot(r).?;
        try std.testing.expectEqualStrings("m", call.module);
        try std.testing.expectEqualStrings("f", call.func);
        try std.testing.expectEqual(BootArgKind.strings, call.kind);
        try std.testing.expectEqual(@as(usize, 1), call.argv.len);
    }
    // a valueless `-s` names nothing → init ignores it → null.
    {
        const r = try parseInitArgs(a, &[_][]const u8{ "-s", "-noshell" });
        try std.testing.expect(resolveBoot(r) == null);
    }
    // no `-s`/`-run` at all → null (caller falls back to the positional entry).
    {
        const r = try parseInitArgs(a, &[_][]const u8{ "-noshell", "-pa", "d" });
        try std.testing.expect(resolveBoot(r) == null);
    }
    // TOTALITY (seeded): resolveBoot never panics over arbitrary init argvs, and
    // whenever it returns a call, that call's module is non-empty (init.erl never
    // boots a nameless module) and its func is non-empty (defaults to `start`).
    var prng = std.Random.DefaultPrng.init(0xE47EC);
    const rnd = prng.random();
    const pool = [_][]const u8{ "-s", "-run", "-noshell", "m", "f", "a", "b", "-pa" };
    var it: usize = 0;
    while (it < 300) : (it += 1) {
        var arena_j = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena_j.deinit();
        const aj = arena_j.allocator();
        const n = rnd.uintLessThan(usize, 7);
        const argv = try aj.alloc([]const u8, n);
        for (argv) |*t| t.* = pool[rnd.uintLessThan(usize, pool.len)];
        const r = try parseInitArgs(aj, argv);
        if (resolveBoot(r)) |call| {
            try std.testing.expect(call.module.len > 0);
            try std.testing.expect(call.func.len > 0);
        }
    }
}

test "LAW gap-erl-cli-exec boot-kind homomorphism: -s tokens denote ATOMS, -run tokens denote STRINGS — observable end-to-end via mylists:rev (rev([a,b])==[b,a]; rev([\"a\",\"b\"])==[\"b\",\"a\"])" {
    const beam = @embedFile("mylists.beam");
    // bootArgLit is the pure homomorphism: kind selects the ArgLit constructor.
    try std.testing.expect(bootArgLit(.atoms, "x") == .atom);
    try std.testing.expect(bootArgLit(.strings, "x") == .string);

    // `-s mylists rev a b` → mylists:rev([a,b]) == [b,a]  (a LIST of two ATOMS).
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(std.testing.allocator);
        const st = try runMulti(std.testing.allocator, &.{beam}, "rev", &[_]ArgLit{ bootArgLit(.atoms, "a"), bootArgLit(.atoms, "b") }, &out, .{ .boot_list_args = true });
        try std.testing.expectEqual(@as(u8, 0), st);
        try std.testing.expectEqualStrings("[b,a]\n", out.items);
    }
    // `-run mylists rev a b` → mylists:rev(["a","b"]) == ["b","a"]  (STRINGS —
    // each a proper list of codepoints; the printed shape differs from atoms).
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(std.testing.allocator);
        const st = try runMulti(std.testing.allocator, &.{beam}, "rev", &[_]ArgLit{ bootArgLit(.strings, "a"), bootArgLit(.strings, "b") }, &out, .{ .boot_list_args = true });
        try std.testing.expectEqual(@as(u8, 0), st);
        try std.testing.expectEqualStrings("[[98],[97]]\n", out.items);
    }
}

test "LAW gap-erl-cli-exec boot-arity: with N≥1 tokens Func is ALWAYS Func/1 on the single list [A,…] (never Func/N); mylists:len over 3 boot atoms prints 3" {
    const beam = @embedFile("mylists.beam");
    // `-s mylists len foo bar baz` → mylists:len([foo,bar,baz]) == 3. Note the
    // FORCED-list arity: three tokens do NOT resolve len/3 (absent), they build
    // ONE 3-element list handed to len/1 — the init.erl start_it contract.
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    const st = try runMulti(std.testing.allocator, &.{beam}, "len", &[_]ArgLit{ bootArgLit(.atoms, "foo"), bootArgLit(.atoms, "bar"), bootArgLit(.atoms, "baz") }, &out, .{ .boot_list_args = true });
    try std.testing.expectEqual(@as(u8, 0), st);
    try std.testing.expectEqualStrings("3\n", out.items);
    // CONTRAST: a single token is STILL a 1-element list — `-s mylists len x` →
    // len([x]) == 1, NOT len(x) (which the natural two-step rule would attempt).
    var out1: std.ArrayList(u8) = .empty;
    defer out1.deinit(std.testing.allocator);
    const st1 = try runMulti(std.testing.allocator, &.{beam}, "len", &[_]ArgLit{bootArgLit(.atoms, "x")}, &out1, .{ .boot_list_args = true });
    try std.testing.expectEqual(@as(u8, 0), st1);
    try std.testing.expectEqualStrings("1\n", out1.items);
}

test "LAW gap-hof-stdlib: preload_stdlib links the stock stdlib closure (lists/maps HOFs + string/unicode_util + proplists + sets/gb_trees/ordsets/queue/dict/orddict/array/re/gb_sets/digraph/calendar/timer/base64/uri_string/rand/math/erl_anno/erl_scan/erl_parse + a 14-module pure-stdlib batch) so every call resolves byte-EQ, while a native lists BIF (reverse/2) still wins; without the flag the same call is undef (DIVERGENCE 661-674)" {
    const probe = @embedFile("hof_probe.beam");
    // The 19-tuple denotation of hof_probe:go/0 on the pinned oracle. Elements:
    // lists:map/foldl/filter/all + reverse (native BIF) + maps:map/fold +
    // string:uppercase(<<"ab">>)=<<65,66>> (needs string+unicode+unicode_util) +
    // proplists:get_value=7 (DIVERGENCE 662) + sets:size=3 + gb_trees:get=b
    // (DIVERGENCE 663) + ordsets:to_list=[1,2,3] + queue:to_list=[1,2,3]
    // (DIVERGENCE 665) + dict:fetch=2 + orddict:to_list=[{a,1},{b,2},{c,3}]
    // (DIVERGENCE 666) + array:get=20 + re:replace("a-b","-","_")=<<"a_b">>
    // (DIVERGENCE 667) + gb_sets:to_list=[1,2,3] + digraph:get_path(a→b)=[a,b]
    // (DIVERGENCE 668) + calendar:day_of_the_week(2026,7,30)=4 + timer:hms(1,2,3)
    // =3723000 (DIVERGENCE 669) + base64:encode(<<"hi">>)=<<"aGk=">> +
    // uri_string:quote("a b")="a%20b" (DIVERGENCE 670) + rand:uniform_s(1000,
    // seed_s(exsss,{42,42,42}))=484 (SEEDED → deterministic) + math:sqrt(144)=12
    // (native BIF) (DIVERGENCE 671) + erl_anno:line(set_line(7,new(1)))=7
    // (DIVERGENCE 672) + the full tokenize+parse+normalise chain
    // ={tag,<<"hi">>,[1,2]} (DIVERGENCE 673) + a 12-module BATCH tuple
    // (binary/erl_internal/otp_internal/graph/io_lib_fread/sofs/erl_stdlib_errors/
    // random/erl_id_trans/edlin_key/edlin_type_suggestion/erl_expand_records —
    // parallel-verified byte-EQ vs OTP-30) (DIVERGENCE 674 adds the pure-stdlib batch).
    const expected = "{[1,4,9],10,[2,4],true,[3,2,1],#{a => 2},3,<<65,66>>,7,3,b,[1,2,3],[1,2,3],2,[{a,1},{b,2},{c,3}],20,<<97,95,98>>,[1,2,3],[a,b],4,3723000,<<97,71,107,61>>,[97,37,50,48,98],484,12,7,{tag,<<104,105>>,[1,2]},{<<70,70,48,48,49,48>>,true,no,1,{ok,[42],[]},[1,2,3],true,9,attribute,true,[none],true}}\n";

    // WITH preload_stdlib: the WHOLE stock closure is appended, so `lists:`/
    // `maps:` HOFs + `string:uppercase` (delegating through unicode_util) +
    // `proplists:get_value` all resolve, and `lists:reverse/2` (a native BIF,
    // baked call_ext_bif) still wins — byte-identical to the oracle.
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(std.testing.allocator);
        const st = try runMulti(std.testing.allocator, &.{probe}, "go", &.{}, &out, .{ .preload_stdlib = true });
        try std.testing.expectEqual(@as(u8, 0), st);
        try std.testing.expectEqualStrings(expected, out.items);
    }

    // WITHOUT the flag (a bare closure): `lists:map/2` is Erlang code with no
    // linked `lists` module and is NOT a native BIF → the entry crashes `undef`,
    // so the run does NOT produce the EQ tuple. This is the CONTRAST the mutants
    // trip (disable-preload; drop any closure member the probe reaches).
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(std.testing.allocator);
        const st = try runMulti(std.testing.allocator, &.{probe}, "go", &.{}, &out, .{});
        const eq = (st == 0) and std.mem.eql(u8, out.items, expected);
        try std.testing.expect(!eq); // without the stdlib the HOFs cannot resolve
        // gap-root-crash-exit (DIVERGENCE 743): the entry crashes (undef) → a
        // crashed ROOT process returns a NON-ZERO exit code (erts=1), NOT silent
        // success — the evidence-integrity fix (paired with the preload run above,
        // which returns 0). A `return 0` mutant on the crash path reds this.
        try std.testing.expectEqual(@as(u8, 1), st);
    }
}

test "LAW gap-erl-cli-exec boot-rejection: a boot flag naming an unexported Func is FunctionNotExported (named error, not a panic) — `-s mylists nosuch a`" {
    const beam = @embedFile("mylists.beam");
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    // mylists has no `nosuch/1` (nor /0): the boot resolution REJECTS cleanly.
    try std.testing.expectError(RunError.FunctionNotExported, runMulti(std.testing.allocator, &.{beam}, "nosuch", &[_]ArgLit{bootArgLit(.atoms, "a")}, &out, .{ .boot_list_args = true }));
    // The func-default `start` is likewise absent from mylists → `-s mylists`
    // (Func defaults to `start`, 0 tokens → start/0) is rejected, not a panic.
    try std.testing.expectError(RunError.FunctionNotExported, runMulti(std.testing.allocator, &.{beam}, "start", &[_]ArgLit{}, &out, .{ .boot_list_args = true }));
}

test "check-load ownership: unsupported-op name outlives checkLoad's internal arena and is gpa-owned" {
    // E1.2 REGRESSION GUARD for the use-after-free fix: `checkLoad` frees the
    // module arena (via `defer mod.deinit()`) before it returns, so the op name
    // it surfaces MUST be gpa-owned (duped), not a raw slice into that arena or
    // into any static table. This test builds a minimal `.beam` whose sole op is
    // NOT in `supported_ops`, drives it through `checkLoad`, then — AFTER the
    // call has returned (arena already freed inside) — reads AND frees the name.
    // If the dupe were ever removed and the raw slice returned, `gpa.free` here
    // would fault on non-gpa memory under `std.testing.allocator`, turning this
    // law red.
    const gpa = std.testing.allocator;

    // Build a one-instruction beam carrying `init/1`, a real generic op but
    // absent from `supported_ops`, so translate rejects it at the
    // capSupported guard. (is_integer served this role until E1.3, is_ge
    // until E1.4, is_tuple until E1.5, bs_get_binary2 until E3.3,
    // bs_create_bin until E3.4 — all became supported; `init/1` is
    // OBSOLETE — the `-init/1` genop.tab marker means the OTP 30-rc compiler
    // no longer emits it — so it stays permanently unsupported and never
    // needs repointing again.) Operands are throwaway (the guard fires on
    // the op NAME before any operand is inspected) but must still DECODE, so
    // we emit well-formed ones via the loader's own assembler.
    std.debug.assert(!loader.capSupported("init"));
    const init_op: u16 = blk: {
        for (loader.op_table, 0..) |maybe, oc| {
            if (maybe) |info| if (std.mem.eql(u8, info.name, "init")) break :blk @intCast(oc);
        }
        unreachable;
    };
    const code_ops = [_]loader.Op{
        .{ .opcode = init_op, .args = &.{
            .{ .x = 0 },
        } },
    };
    var code_payload = try loader.emit(gpa, &code_ops);
    defer code_payload.deinit(gpa);

    // Assemble the IFF container: FOR1 <size> BEAM  +  a single Code chunk whose
    // payload is the 20-byte sub-header (head_size=16, then version/maxop/labels/
    // funcs) followed by the assembled ops. Chunk bodies are 4-byte aligned.
    var beam: std.ArrayList(u8) = .empty;
    defer beam.deinit(gpa);
    var chunk: std.ArrayList(u8) = .empty;
    defer chunk.deinit(gpa);
    // Code sub-header
    try appendU32Be(&chunk, gpa, 16); // head_size (bytes after this field)
    try appendU32Be(&chunk, gpa, 0); // instruction-set version (ignored by parse)
    try appendU32Be(&chunk, gpa, 0); // max opcode (ignored by parse)
    try appendU32Be(&chunk, gpa, 0); // label count (0 → label_pc has 1 slot)
    try appendU32Be(&chunk, gpa, 0); // function count (ignored by parse)
    try chunk.appendSlice(gpa, code_payload.items);

    try beam.appendSlice(gpa, "FOR1");
    try appendU32Be(&beam, gpa, 0); // FOR1 size — parse ignores it
    try beam.appendSlice(gpa, "BEAM");
    try beam.appendSlice(gpa, "Code");
    try appendU32Be(&beam, gpa, @intCast(chunk.items.len));
    try beam.appendSlice(gpa, chunk.items);
    while (beam.items.len % 4 != 0) try beam.append(gpa, 0); // 4-byte align

    const result = try checkLoad(gpa, beam.items);
    try std.testing.expect(result == .unsupported);
    // The arena is already gone; reading the name here would be a UAF without
    // the dupe. Assert the value survived, then free it as the OWNER.
    try std.testing.expectEqualStrings("init", result.unsupported.name);
    try std.testing.expectEqual(@as(u32, 1), result.unsupported.arity);
    gpa.free(result.unsupported.name);
}

/// Test-local big-endian u32 appender (mirrors the loader's on-wire order).
fn appendU32Be(list: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, v, .big);
    try list.appendSlice(gpa, &b);
}

test "CLI run denotation: mylists:sum([1..5]) prints 15 (== fixtures/expected.txt line 1)" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const beam = @embedFile("mylists.beam");
    const status = try run(std.testing.allocator, beam, "sum", &[_]ArgLit{ .{ .int = 1 }, .{ .int = 2 }, .{ .int = 3 }, .{ .int = 4 }, .{ .int = 5 } }, &buf, .{});
    try std.testing.expectEqual(@as(u8, 0), status);
    try std.testing.expectEqualStrings("15\n", buf.items);
}

test "CLI run denotation: mylists:seq(5) prints [5,4,3,2,1] via the EXACT-arity path" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const beam = @embedFile("mylists.beam");
    const status = try run(std.testing.allocator, beam, "seq", &[_]ArgLit{.{ .int = 5 }}, &buf, .{});
    try std.testing.expectEqual(@as(u8, 0), status);
    try std.testing.expectEqualStrings("[5,4,3,2,1]\n", buf.items);
}

test "CLI run: unknown function name returns the named error" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const beam = @embedFile("mylists.beam");
    try std.testing.expectError(error.FunctionNotExported, run(std.testing.allocator, beam, "nope", &[_]ArgLit{.{ .int = 1 }}, &buf, .{}));
}

// ============================================================================
// E5.1: the CLI term-arg convention — grammar laws + pinned E3.5 pid parity
// ============================================================================

test "LAW E5.1 term-arg round-trip: parse∘denote∘print == identity for ints/atoms" {
    // For an int or a bareword atom, the printed denotation is the source text
    // verbatim (the round-trip identity). A quoted atom's denotation prints its
    // INNER name. Distinct atoms print distinctly — this is the law that kills
    // the "every arg maps to the same atom" mutant (MUTATION_LOG E5.1 m1).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const Case = struct { text: []const u8, want: []const u8 };
    const cases = [_]Case{
        .{ .text = "42", .want = "42" },
        .{ .text = "-7", .want = "-7" },
        .{ .text = "0", .want = "0" },
        .{ .text = "foo", .want = "foo" },
        .{ .text = "bar", .want = "bar" },
        .{ .text = "eunit_lists", .want = "eunit_lists" },
        .{ .text = "node@host", .want = "node@host" },
        .{ .text = "'Weird Atom'", .want = "Weird Atom" },
    };
    for (cases) |c| {
        const lit = try parseArg(c.text);
        const t = try argToTerm(&ctx, lit);
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const v = try FinalTerms.denote(&ctx, arena.allocator(), t);
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(gpa);
        try diag.formatValue(gpa, v, &buf);
        try std.testing.expectEqualStrings(c.want, buf.items);
    }
}

test "LAW E5.1 string-arg denotes an Erlang char list (proper list of codepoints)" {
    // A `\"...\"` literal denotes the proper list of its byte codepoints — the
    // Erlang string. Structural equality against a hand-built list pins it
    // (killing an off-by-one in the string fold — MUTATION_LOG E5.1 m2).
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const lit = try parseArg("\"ABC\"");
    const got = try argToTerm(&ctx, lit);
    // hand-built [65,66,67]
    var expect = FinalTerms.nil(&ctx);
    expect = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 67), expect);
    expect = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 66), expect);
    expect = try FinalTerms.cons(&ctx, FinalTerms.int(&ctx, 65), expect);
    try std.testing.expect(FinalTerms.compare(&ctx, got, expect) == .eq);
    // The empty string denotes nil.
    const empty = try argToTerm(&ctx, try parseArg("\"\""));
    try std.testing.expect(FinalTerms.compare(&ctx, empty, FinalTerms.nil(&ctx)) == .eq);
}

test "LAW E5.1 term-arg grammar rejection totality: non-literals get a NAMED error" {
    // Every non-literal is a named rejection, never a panic — a variable
    // (uppercase-leading), the empty arg, an unterminated quote, a bareword
    // with an illegal byte.
    try std.testing.expectError(error.EmptyArg, parseArg(""));
    try std.testing.expectError(error.BadAtom, parseArg("Module")); // a variable
    try std.testing.expectError(error.BadAtom, parseArg("_x")); //     a variable
    try std.testing.expectError(error.BadAtom, parseArg("fo o")); //   illegal byte
    try std.testing.expectError(error.BadAtom, parseArg("'unterminated"));
    try std.testing.expectError(error.BadString, parseArg("\"unterminated"));
    try std.testing.expectError(error.BadInt, parseArg("-"));
    try std.testing.expectError(error.BadInt, parseArg("12x"));
}

test "LAW E5.1 CLI run end-to-end: a string arg reaches the beam as a char list" {
    // `sum(\"ABC\")` folds the char list [65,66,67] → 198, exercising the whole
    // string-arg path (parse → argToTerm → placement → dispatch → denote).
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    const beam = @embedFile("mylists.beam");
    const status = try run(std.testing.allocator, beam, "sum", &[_]ArgLit{.{ .string = "ABC" }}, &buf, .{});
    try std.testing.expectEqual(@as(u8, 0), status);
    try std.testing.expectEqualStrings("198\n", buf.items); // 65+66+67
}

test "LAW E5.1 pid-print homomorphism (E3.5 parity pinned): live pids print <0.N.0>" {
    // The pid-REPRESENTATION parity Task 1 credits: a pid TERM built the way the
    // scheduler builds `self()`/spawn pids (number = proc index, serial 0)
    // prints EXACTLY the oracle's `<0.N.0>` shape over a deterministic sequence.
    // (A serial/number swap in the writer reddens this — the E3.5 writer is
    // pinned here at the E5.1 boundary; the residual for `processes/0` byte-EQ
    // is the boot-set pid-NUMBER allocation, not the print shape — DIVERGENCE 54.)
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const wants = [_][]const u8{ "<0.0.0>", "<0.1.0>", "<0.2.0>", "<0.3.0>" };
    for (wants, 0..) |want, n| {
        const p = try FinalTerms.pid(&ctx, n, 0);
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const v = try FinalTerms.denote(&ctx, arena.allocator(), p);
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(gpa);
        try diag.formatValue(gpa, v, &buf);
        try std.testing.expectEqualStrings(want, buf.items);
    }
}

test "bench term_compare workload is deterministic and period-3 scaled" {
    // Determinism: same iters ⇒ same checksum (the work is a pure denotation).
    const w3 = try benchTermCompareWork(std.testing.allocator, 3);
    const w3_again = try benchTermCompareWork(std.testing.allocator, 3);
    try std.testing.expectEqual(w3, w3_again);
    // The comparisons actually happened (a folded-away loop would give 0).
    try std.testing.expect(w3 != 0);
    // Scaling law: the ring has period 3, so work(3n) == n * work(3).
    const n: i64 = 7;
    const w21 = try benchTermCompareWork(std.testing.allocator, @intCast(3 * n));
    try std.testing.expectEqual(w3 * n, w21);
}

test "LAW perf-scale-corpus bench term_hash workload is deterministic and period-3 scaled" {
    // Determinism: same iters ⇒ same checksum (a pure denotation of the work).
    const w3 = try benchTermHashWork(std.testing.allocator, 3);
    const w3_again = try benchTermHashWork(std.testing.allocator, 3);
    try std.testing.expectEqual(w3, w3_again);
    // The hashes actually happened (a folded-away loop would give 0).
    try std.testing.expect(w3 != 0);
    // Scaling law: the ring has period 3, so work(3n) == n * work(3) — with the
    // wrapping u64 accumulator (`+%`), the multiply wraps too (`*%`).
    const n: u64 = 7;
    const w21 = try benchTermHashWork(std.testing.allocator, 3 * n);
    try std.testing.expectEqual(w3 *% n, w21);
}

test "LAW gap-e46-resident-cli: --resident is a SAFE SUPERSET — a halting program runs IDENTICALLY (resident .done == the one-shot run)" {
    const gpa = std.testing.allocator;
    const beam = @embedFile("mylists.beam");
    var one: std.ArrayList(u8) = .empty;
    defer one.deinit(gpa);
    var res: std.ArrayList(u8) = .empty;
    defer res.deinit(gpa);
    // sum([1..5]) == 15 HALTS → under --resident the node reaches `.done`
    // (aliveCount==0) and falls through to the identical result. The stays-up
    // (.idle) behaviour is proven by the driveResident + resident-node-smoke laws
    // (src/proc.zig); this pins that resident mode never CHANGES a terminating run.
    const args = [_]ArgLit{ .{ .int = 1 }, .{ .int = 2 }, .{ .int = 3 }, .{ .int = 4 }, .{ .int = 5 } };
    _ = try run(gpa, beam, "sum", &args, &one, .{});
    _ = try run(gpa, beam, "sum", &args, &res, .{ .resident = true });
    try std.testing.expectEqualStrings(one.items, res.items);
    try std.testing.expect(std.mem.indexOf(u8, res.items, "15") != null);
}

test "LAW E44-T1 gap-perf-bench-realism: dispatch workload runs REAL bytecode through execInstr, deterministic + bounded" {
    const gpa = std.testing.allocator;
    // Determinism: same iters ⇒ same checksum (a pure denotation of the run).
    try std.testing.expectEqual(try benchDispatchWork(gpa, 1000), try benchDispatchWork(gpa, 1000));
    // The bytecode ACTUALLY RAN through the interpreter: 4 reductions
    // (move·add·is_lt·jump) leave x0 == 1 — a folded-away loop could not.
    try std.testing.expectEqual(@as(i64, 1), try benchDispatchWork(gpa, 4));
    // The accumulator stays BOUNDED in [0, 4096] for ANY iters (the modular reset
    // holds), so no bignum promotion perturbs the dispatch-throughput measurement.
    for ([_]u64{ 1, 4, 100, 12289, 123457, 1_000_003 }) |it| {
        const w = try benchDispatchWork(gpa, it);
        try std.testing.expect(w >= 0 and w <= 4096);
    }
    // The loop ADVANCES with more reductions (not a constant): 7 reds reach a
    // different accumulator than 4 (mutant: a jump that never loops would freeze it).
    try std.testing.expect((try benchDispatchWork(gpa, 7)) != (try benchDispatchWork(gpa, 4)));
}

test "LAW gap-perf-bench-call RESULT-IDENTITY: the call/return bench runs EXACTLY iters leaf calls through call_ext_code+ret, checksum == iters (a clean cross-VM identity the OTP twin call_loop/2 also satisfies)" {
    const gpa = std.testing.allocator;
    // Each of `iters` leaf calls returns 1 and is accumulated → checksum == iters.
    // The call/return machinery (export resolution + CP push + ret + CP pop) is on
    // the measured path (unlike dispatch/mixed/list_sum, which are call-free or
    // tail-only). A run that hit the reduction budget instead of `halt` would
    // return a SHORT checksum ≠ iters and redden this law.
    for ([_]u64{ 0, 1, 4, 100, 4096, 100_000 }) |it| {
        try std.testing.expectEqual(@as(i64, @intCast(it)), try benchCallReturnWork(gpa, it));
    }
    // determinism.
    try std.testing.expectEqual(try benchCallReturnWork(gpa, 12345), try benchCallReturnWork(gpa, 12345));
}

test "LAW jit-bench-ratchet RESULT-IDENTITY: engine #4 (native) ≡ engine #3 (threaded) checksum on the bench workload (a faster-but-wrong engine is not a speedup)" {
    const gpa = std.testing.allocator;
    // The bench times native vs threaded and compares only the RATIO; that ratio
    // is a valid speedup ONLY if both engines compute the SAME work. This composes
    // with the L2 differential (`runNativeBlock ≡ runThreaded` at every slice
    // boundary, src/dispatch.zig): here we pin it at the exact reduction counts the
    // bench uses, so a native mutant that skips/miscomputes the loop reddens THIS
    // law before it can fabricate a speedup. On a non-native host both sides ARE
    // the threaded engine, so identity holds trivially (an honest ratio ≈ 1.0).
    for ([_]u64{ 1, 4, 7, 100, 4095, 4096, 4097, 12289, 1_000_003 }) |it| {
        const threaded = try benchDispatchEngineWork(gpa, it, false);
        const native = try benchDispatchEngineWork(gpa, it, true);
        try std.testing.expectEqual(threaded, native);
        // and both agree with the reference interpreter `ia.run` (engine #2 path):
        // native ≡ threaded ≡ interp — the full three-way refinement at bench scale.
        try std.testing.expectEqual(try benchDispatchWork(gpa, it), native);
    }
    // The engines actually RAN the loop (a folded-away or never-looping workload
    // would give a constant): more reductions reach a different accumulator.
    try std.testing.expect(
        (try benchDispatchEngineWork(gpa, 7, true)) != (try benchDispatchEngineWork(gpa, 4, true)),
    );
    // Bounded for ANY iters under BOTH engines (no bignum promotion perturbs timing).
    for ([_]u64{ 1, 100, 12289, 1_000_003 }) |it| {
        const w = try benchDispatchEngineWork(gpa, it, true);
        try std.testing.expect(w >= 0 and w <= 4096);
    }
}

test "LAW gap-jit-beamasm-bench RESULT-IDENTITY: dispatch_bench_prog final x0 for `iters` reductions == the closed-form `incrs % 4096` the matched Erlang count/2 computes (native ≡ threaded ≡ closed form)" {
    const gpa = std.testing.allocator;
    // The `--bench-beamasm` mode measures increments/sec on BOTH sides and would
    // report a garbage ratio if the two loops did DIFFERENT work. This law is the
    // correctness anchor: for the exact reduction budget the harness runs
    // (`dispatchBenchItersForIncrs(incrs)`), BOTH engines land on EXACTLY
    // `dispatchBenchFinalForIncrs(incrs) == incrs % 4096` — the same value the
    // matched Erlang `zigvm_jit_probe:count(Incrs,0)` returns. So a faster-but-
    // wrong engine, OR a mismatched work-unit accounting (the reset arm miscounted,
    // the pc0 init dropped), reddens HERE before a fabricated number can be
    // recorded. Spans a full period boundary (4095/4096/4097), several periods,
    // and the harness-scale count.
    for ([_]u64{ 0, 1, 2, 4095, 4096, 4097, 8192, 12345, 1_000_000 }) |incrs| {
        const iters = dispatchBenchItersForIncrs(incrs);
        const want = dispatchBenchFinalForIncrs(incrs);
        const threaded = try benchDispatchEngineWork(gpa, iters, false);
        const native = try benchDispatchEngineWork(gpa, iters, true);
        try std.testing.expectEqual(threaded, native); // L2 differential at bench scale
        try std.testing.expectEqual(want, native); // == the closed form the Erlang computes
        try std.testing.expectEqual(want, threaded);
        // the checksum is a genuine mod-4096 counter, never a folded constant
        try std.testing.expect(want >= 0 and want <= 4095);
    }
    // Sanity on the closed form itself: one increment costs 3 reductions after the
    // one-off pc0 init; the 4096th costs 4 (the reset arm) — so the budget grows by
    // exactly one extra reduction each 4096 increments.
    try std.testing.expectEqual(@as(u64, 1 + 3), dispatchBenchItersForIncrs(1));
    try std.testing.expectEqual(@as(u64, 1 + 3 * 4095), dispatchBenchItersForIncrs(4095));
    try std.testing.expectEqual(@as(u64, 1 + 3 * 4096 + 1), dispatchBenchItersForIncrs(4096));
    try std.testing.expectEqual(@as(i64, 0), dispatchBenchFinalForIncrs(4096));
    try std.testing.expectEqual(@as(i64, 1), dispatchBenchFinalForIncrs(4097));
}

test "LAW gap-reduction-oracle RESULT-IDENTITY: each matched zigvm workload computes EXACTLY the closed-form value the matched Erlang computes, and (R2b) charges EXACTLY the OTP per-call reduction count (~1/iteration)" {
    const gpa = std.testing.allocator;
    // The `--reduction-oracle` mode compares total-reductions-consumed on zigvm vs
    // pinned OTP-30 and records `zig/otp`. R2b migrated zigvm to the OTP PER-CALL
    // reduction model, so that ratio must now → ~1.0. This law is the correctness
    // anchor: the zigvm workload's RESULT equals the closed form the matched Erlang
    // returns —
    //   countdown_sum(N) == N*(N+1)/2   (== csum(N,0))
    //   count_loop(N)    == 0           (== cloop(N))
    //   list_fold(L)     == L*(L+1)/2   (== lfold(lists:seq(1,L),0))
    // — so a mismatched work-unit (wrong N wired, an off-by-one loop) reddens HERE
    // before the harness can record a fabricated ratio. It ALSO pins the exact
    // per-CALL reduction counts (the zig side of the ratio) to their closed forms
    // (N tail-calls), so a mis-accounted loop cannot masquerade as a granularity
    // change.
    for ([_]u64{ 0, 1, 2, 3, 10, 97, 1000, 10000 }) |n| {
        const cs = try redsWork(gpa, "countdown_sum", n);
        try std.testing.expectEqual(@as(i64, @intCast(n * (n + 1) / 2)), cs.result);
        try std.testing.expectEqual(redsCountdownSum(n), cs.reds);
        try std.testing.expectEqual(n, cs.reds); // R2b: EXACTLY N tail-calls

        const cl = try redsWork(gpa, "count_loop", n);
        try std.testing.expectEqual(@as(i64, 0), cl.result);
        try std.testing.expectEqual(redsCountLoop(n), cl.reds);
        try std.testing.expectEqual(n, cl.reds);

        const lf = try redsWork(gpa, "list_fold", n);
        try std.testing.expectEqual(@as(i64, @intCast(n * (n + 1) / 2)), lf.result);
        try std.testing.expectEqual(redsListFold(n), lf.reds);
        try std.testing.expectEqual(n, lf.reds);
    }
    // The workloads actually RAN (a folded-away computation gives a constant):
    // more iterations land on a strictly larger reduction count AND (for the sums)
    // a strictly larger value — the optimizer could not have precomputed these.
    try std.testing.expect(
        (try redsWork(gpa, "countdown_sum", 5)).reds < (try redsWork(gpa, "countdown_sum", 6)).reds,
    );
    try std.testing.expect(
        (try redsWork(gpa, "list_fold", 5)).result < (try redsWork(gpa, "list_fold", 6)).result,
    );
    // R2b: zigvm now charges the OTP per-CALL count — EXACTLY 1 reduction per loop
    // iteration for every workload (slope 1). A mutant that reverts to
    // per-instruction accounting would make this slope 3-5x and redden here (and
    // the harness `--reduction-oracle` band around 1.0).
    try std.testing.expectEqual(@as(u64, 1), redsCountdownSum(2) - redsCountdownSum(1));
    try std.testing.expectEqual(@as(u64, 1), redsCountLoop(2) - redsCountLoop(1));
    try std.testing.expectEqual(@as(u64, 1), redsListFold(2) - redsListFold(1));
}

test "LAW jit-bench-realprog RESULT-IDENTITY: engine #4 (native) ≡ engine #3 (threaded) checksum on the REAL list-sum program (mylists:sum-shaped traversal)" {
    const gpa = std.testing.allocator;
    // The jit-bench-realprog measurement times the REAL list-fold program under
    // engine #3 vs #4 and compares only the RATIO; that ratio is a valid speedup
    // ONLY if both engines compute the SAME fold. This pins `runNativeBlock ≡
    // runThreaded` (the L2 differential) at the exact reduction counts the bench
    // uses, over the list-SPINE ops (is_cons/get_list) + arith — a native mutant
    // that skips a cons step or miscomputes the sum reddens HERE before it can
    // fabricate a speedup. On a non-native host both sides ARE threaded, so
    // identity holds trivially (an honest ratio ≈ 1.0).
    for ([_]u64{ 1, 2, 5, 9, 40, 41, 100, 4096, 1_000_003 }) |it| {
        const threaded = try benchListSumEngineWork(gpa, it, false);
        const native = try benchListSumEngineWork(gpa, it, true);
        try std.testing.expectEqual(threaded, native);
    }
    // The engines actually RAN the fold (a folded-away workload gives a constant):
    // different reduction counts land on different partial accumulators.
    try std.testing.expect(
        (try benchListSumEngineWork(gpa, 2, true)) != (try benchListSumEngineWork(gpa, 3, true)),
    );
    // Deterministic + bounded: the accumulator never leaves the small-int range
    // (0..sum([1..8])==36), so `add` never promotes to a bignum (which would both
    // perturb timing AND fall back off the native path).
    for ([_]u64{ 1, 40, 4096, 1_000_003 }) |it| {
        const w = try benchListSumEngineWork(gpa, it, true);
        try std.testing.expectEqual(try benchListSumEngineWork(gpa, it, true), w); // deterministic
        try std.testing.expect(w >= 0 and w <= 36);
    }
}

test "LAW jit-bench-realprog NATIVE-COVERAGE: the REAL list-sum program runs 100% native on the supported host (traversal-bound, zero fallback); honest 0.0 otherwise" {
    const gpa = std.testing.allocator;
    // The executed-op native coverage is the honest number that says whether this
    // real program is native-bound. Every op in `list_sum_prog` (is_cons/get_list/
    // add/move/jump) is in the widened native tier, and the loop NEVER reaches an
    // uncovered pc (no halt is reachable), so on x86-64-linux the coverage is
    // EXACTLY 1.0 — the whole fold is machine code. On any other host there is no
    // native path and the probe honestly reports 0.0 (no fabricated coverage).
    for ([_]u64{ 40, 4096, 1_000_003 }) |it| {
        const cov = try benchListSumNativeCoverage(gpa, it);
        if (jit_codegen.native_supported) {
            try std.testing.expectEqual(@as(f64, 1.0), cov); // fully native: zero fallback reductions
        } else {
            try std.testing.expectEqual(@as(f64, 0.0), cov); // no native path: honest 0.0
        }
    }
    // Contrast — the coverage split is REAL, not hardcoded: a program with an
    // uncovered op (a trailing `halt`, which the codegen does NOT emit) charges a
    // fallback reduction, so its coverage is < 1.0. Prove the meter can read < 1.0.
    {
        const prog = [_]ia.CInstr{
            .{ .add = .{ .a = .{ .x = 0 }, .b = .{ .imm = 1 }, .dst = 0 } }, // native
            .{ .halt = .{ .src = .{ .x = 0 } } }, //                          fallback
        };
        var atoms = AtomTable.init(gpa);
        defer atoms.deinit();
        var m = try ia.Machine.init(gpa, &atoms);
        defer m.deinit();
        m.regs[0] = FinalTerms.int(&m.ctx, 0);
        var n = try dispatch.compileNativeBlock(gpa, prog[0..]);
        defer n.deinit(gpa);
        const split = try dispatch.runNativeBlockCounted(&m, &n, 100);
        if (jit_codegen.native_supported) {
            try std.testing.expect(split.fallback_reds >= 1); // the halt fell back
            try std.testing.expect(split.coverage() < 1.0);
        }
    }
}

test "LAW gap-perf-bench-realism: MIXED workload runs REAL bytecode (alloc+GC+dispatch), deterministic + bounded + GC-reclaimed" {
    const gpa = std.testing.allocator;
    // Determinism: same iters ⇒ same checksum (a pure, GC-independent denotation).
    try std.testing.expectEqual(try benchMixedWork(gpa, 1000), try benchMixedWork(gpa, 1000));
    // It ACTUALLY RAN alloc+walk: one pass ⇒ counter 1, an 8-cell list of 1s summed
    // = 8. A folded-away build/walk could not produce 8.
    try std.testing.expectEqual(@as(i64, 8), try benchMixedWork(gpa, 1));
    // Closed form + BOUNDEDNESS: result == 8*(iters % 4096) ∈ [0, 32760], never a bignum.
    for ([_]u64{ 1, 2, 4096, 4097, 12345, 1_000_003 }) |it| {
        const w = try benchMixedWork(gpa, it);
        try std.testing.expectEqual(@as(i64, 8) * @as(i64, @intCast(it % 4096)), w);
        try std.testing.expect(w >= 0 and w <= 8 * 4095);
    }
    // ADVANCES: different iters (mod 4096) ⇒ different result (kills a frozen counter).
    try std.testing.expect((try benchMixedWork(gpa, 7)) != (try benchMixedWork(gpa, 4)));

    // GC WITNESS (the mixed-specific law): the copying collector reclaims per-pass
    // garbage, so the process heap stays BOUNDED regardless of iters — without the
    // collect, 200k passes (≈8 cons cells each) would grow the heap ~unboundedly.
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var m = try ia.Machine.init(gpa, &atoms);
    defer m.deinit();
    try runMixed(&m, 200_000);
    try std.testing.expect(m.ctx.words.items.len < 4096); // reclaimed, not accumulated
}

test "LAW E18.7 dist_send workload is deterministic and linear in iters" {
    // Determinism: same iters ⇒ same checksum (encoding a fixed triple is a pure
    // denotation). Linearity: with a fixed input every REG_SEND frame has the same
    // length L, so work(iters) == iters * L — in particular work(k*iters) ==
    // k * work(iters). A folded-away encode loop could satisfy neither.
    const w1 = try benchDistSendWork(std.testing.allocator, 1);
    const w1_again = try benchDistSendWork(std.testing.allocator, 1);
    try std.testing.expectEqual(w1, w1_again);
    // The encode actually happened (a non-empty PASS_THROUGH+ctrl+msg frame).
    try std.testing.expect(w1 != 0);
    // work(0) == 0 (no frames encoded).
    try std.testing.expectEqual(@as(u64, 0), try benchDistSendWork(std.testing.allocator, 0));
    // Linearity: work(iters) == iters * L, where L == work(1).
    const iters: u64 = 9;
    const w9 = try benchDistSendWork(std.testing.allocator, iters);
    try std.testing.expectEqual(w1 * iters, w9);
}

test "LAW E18.7 dist_fanout workload frame-count is n_peers * rounds (conserved per peer)" {
    // The fan-out denotation is total frames encoded == n_peers * rounds: each
    // round emits exactly one REG_SEND per peer. This pins both that the fan-out
    // loop ran the full grid (no dropped peer, no dropped round) and that per-peer
    // work is conserved as the fan-out degree grows — the invariant the normalized
    // throughput curve is banded on.
    const rounds: u32 = 5;
    try std.testing.expectEqual(@as(u64, 1 * 5), try scaleDistFanoutWork(std.testing.allocator, 1, rounds));
    try std.testing.expectEqual(@as(u64, 2 * 5), try scaleDistFanoutWork(std.testing.allocator, 2, rounds));
    try std.testing.expectEqual(@as(u64, 4 * 5), try scaleDistFanoutWork(std.testing.allocator, 4, rounds));
    // work(0 rounds) == 0 frames regardless of fan-out degree.
    try std.testing.expectEqual(@as(u64, 0), try scaleDistFanoutWork(std.testing.allocator, 4, 0));
}

test "LAW E18.7 dist bench workload produces a REAL REG_SEND frame (live-carrier encoding, not a stub)" {
    // The dist_send workload exercises the live-carrier final encoding:
    // decodePassThrough recovers op=REG_SEND from a produced frame, so the bench
    // measures real remote-send work rather than a placeholder.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    var ctx = FinalTerms.Ctx.init(gpa, &atoms);
    defer ctx.deinit();
    const our_node = try atoms.intern("zigvmbench@127.0.0.1");
    const from_pid = try FinalTerms.pidExt(&ctx, 1, 0, our_node, 3);
    const to_atom = FinalTerms.atom(&ctx, try atoms.intern("collector"));
    const msg = try FinalTerms.tuple(&ctx, &.{ FinalTerms.int(&ctx, 1), FinalTerms.int(&ctx, 2), FinalTerms.int(&ctx, 3) });
    const frame = try dist.encodeRegSend(gpa, &ctx, from_pid, to_atom, msg);
    defer gpa.free(frame);
    const ic = try dist.decodePassThrough(gpa, &ctx, frame);
    try std.testing.expectEqual(dist.DOP_REG_SEND, ic.op);
}

test "bench rejects an unknown unit by name" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    // The unit check returns before the clock is read, so `io` is never used on
    // this path — an undefined placeholder is safe and keeps the law hermetic.
    const io: std.Io = undefined;
    try std.testing.expectError(error.UnknownBenchUnit, bench(std.testing.allocator, io, "no_such_bench", 10, &buf));
}

test "scale rejects an unknown unit / out-of-range scheduler count by name" {
    // Both rejections return BEFORE the clock is read, so `io` is never used on
    // these paths — an undefined placeholder keeps the laws hermetic.
    const io: std.Io = undefined;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnknownScaleUnit, scale(std.testing.allocator, io, "no_such_scale", 1, &buf));
    try std.testing.expectError(error.SchedulerCountOutOfRange, scale(std.testing.allocator, io, "spawn_storm", 0, &buf));
    try std.testing.expectError(error.SchedulerCountOutOfRange, scale(std.testing.allocator, io, "spawn_storm", proc.SmpEngine.MAX_SCHED + 1, &buf));
}

test "LAW E6.9 scalability zero-leak: scale spawn_storm does not leak memory" {
    var atoms = AtomTable.init(std.testing.allocator);
    defer atoms.deinit();
    // One round is enough to prove the allocators return everything.
    const storm = try proc.scaleWork(std.testing.allocator, &atoms, 1, 96, 20000);
    try std.testing.expect(storm.completed);
}

// ============================================================================
// E18.2 laws: the cross-node transport & total-order CLI surface
// ============================================================================

/// Map a total-order `Order` onto the token `term-compare` prints, so a law can
/// assert the CLI string equals the algebra's verdict.
fn orderToken(o: ta.Order) []const u8 {
    return switch (o) {
        .lt => "lt",
        .eq => "eq",
        .gt => "gt",
    };
}

test "LAW E18.2 etf-reencode is a byte-identity wire round-trip over twin-seeded wire terms" {
    // encode ∘ decode ∘ encode == encode: the codec is a deterministic encoder
    // and decode preserves the canonical frame, so re-encoding the peer's bytes
    // must reproduce them EXACTLY (the NODE-ENCODE law lifted to the CLI). This
    // is what makes the harness's transport verdict a genuine byte-for-byte
    // parity claim rather than a mere denotational one.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = ta.LawConfig{ .seed = 0xD157, .iterations = 128 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();
    for (0..cfg.iterations) |i| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        const t = try etf.genWireTerm(random, &ctx, 4);
        var bytes = try etf.encode(gpa, &ctx, t);
        defer bytes.deinit(gpa);
        var hex: std.ArrayList(u8) = .empty;
        defer hex.deinit(gpa);
        try appendHexLower(gpa, &hex, bytes.items);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try etfReencode(gpa, hex.items, &out);
        try ta.expectLaw(std.mem.eql(u8, out.items, hex.items), "etf-reencode: byte-identity wire round-trip", cfg, i);
    }
}

test "LAW E18.2 term-compare CLI agrees with the total order (arith & exact) over twin-seeded pairs" {
    // total-order HOMOMORPHISM at the transport boundary: for twin-seeded term
    // pairs, the token printed after decoding the ETF bytes equals the algebra's
    // verdict on the originals, in BOTH the arithmetic (`<`/`>`) and exact
    // (`=:=`-refined) orders. This is the local half of `zig_cmp == oracle_cmp`;
    // the harness closes the loop against the live peer.
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const cfg = ta.LawConfig{ .seed = 0xC0DE, .iterations = 128 };
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();
    for (0..cfg.iterations) |i| {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        const a = try etf.genWireTerm(random, &ctx, 3);
        const b = try etf.genWireTerm(random, &ctx, 3);
        var ba = try etf.encode(gpa, &ctx, a);
        defer ba.deinit(gpa);
        var bb = try etf.encode(gpa, &ctx, b);
        defer bb.deinit(gpa);
        var ha: std.ArrayList(u8) = .empty;
        defer ha.deinit(gpa);
        var hb: std.ArrayList(u8) = .empty;
        defer hb.deinit(gpa);
        try appendHexLower(gpa, &ha, ba.items);
        try appendHexLower(gpa, &hb, bb.items);

        var arith: std.ArrayList(u8) = .empty;
        defer arith.deinit(gpa);
        try termCompare(gpa, ha.items, hb.items, false, &arith);
        try ta.expectLaw(std.mem.eql(u8, arith.items, orderToken(FinalTerms.compare(&ctx, a, b))), "term-compare: arith order homomorphism", cfg, i);

        var exact: std.ArrayList(u8) = .empty;
        defer exact.deinit(gpa);
        try termCompare(gpa, ha.items, hb.items, true, &exact);
        try ta.expectLaw(std.mem.eql(u8, exact.items, orderToken(FinalTerms.compareExact(&ctx, a, b))), "term-compare: exact order homomorphism", cfg, i);
    }

    // Pinned int/float-tie vector: the ONLY place the arithmetic and exact
    // orders DISAGREE (1 == 1.0 arithmetically, but int < float exactly). The
    // random pairs above almost never land a numeric tie, so this deterministic
    // case is what actually distinguishes the two modes at the CLI boundary
    // (and kills the arith/exact-swap mutant).
    {
        var ctx = FinalTerms.Ctx.init(gpa, &atoms);
        defer ctx.deinit();
        const one_i = FinalTerms.int(&ctx, 1);
        const one_f = FinalTerms.float(&ctx, 1.0);
        var bi = try etf.encode(gpa, &ctx, one_i);
        defer bi.deinit(gpa);
        var bf = try etf.encode(gpa, &ctx, one_f);
        defer bf.deinit(gpa);
        var hi: std.ArrayList(u8) = .empty;
        defer hi.deinit(gpa);
        var hf: std.ArrayList(u8) = .empty;
        defer hf.deinit(gpa);
        try appendHexLower(gpa, &hi, bi.items);
        try appendHexLower(gpa, &hf, bf.items);
        var arith_tie: std.ArrayList(u8) = .empty;
        defer arith_tie.deinit(gpa);
        var exact_tie: std.ArrayList(u8) = .empty;
        defer exact_tie.deinit(gpa);
        try termCompare(gpa, hi.items, hf.items, false, &arith_tie);
        try termCompare(gpa, hi.items, hf.items, true, &exact_tie);
        try std.testing.expectEqualStrings("eq", arith_tie.items); // 1 == 1.0
        try std.testing.expectEqualStrings("lt", exact_tie.items); // int < float exactly
    }
}

test "LAW E18.2 hexDecode totality: malformed hex is a NAMED rejection, never a panic" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.OddHexLength, hexDecode(gpa, "abc"));
    try std.testing.expectError(error.BadHexDigit, hexDecode(gpa, "zz"));
    const ok = try hexDecode(gpa, "83610f");
    defer gpa.free(ok);
    try std.testing.expect(ok.len == 3 and ok[0] == 0x83 and ok[2] == 0x0f);
}

test "LAW e47-a6 P-APP REAL M:start: the STOCK pinned OTP-30 supervision closure boots a real tree ({ok,tree_up,pong} incl a live gen_server:call), and kill->one_for_one restart yields a NEW child pid under receive-after ({true,true,true})" {
    // The P-APP milestone over REAL code: supervisor.beam + gen_server.beam +
    // gen.beam + proc_lib.beam (+ sys/lists/maps/proplists) are the PINNED
    // OTP-30 artifacts, vendored byte-exact (fixtures/otp_*.beam). sup_probe's
    // callbacks are the only test code. `restart` is the e47-a4 livelock repro
    // made a PERMANENT law: kill the child, sit in `receive after 300`, expect
    // the supervisor to have restarted a NEW pid (a livelock would trip the
    // bounded driver; the pre-fix VM span here at 99% CPU forever).
    const gpa = std.testing.allocator;
    const closure = [_][]const u8{
        @embedFile("sup_probe.beam"),
        @embedFile("otp_supervisor.beam"),
        @embedFile("otp_gen_server.beam"),
        @embedFile("otp_gen.beam"),
        @embedFile("otp_proc_lib.beam"),
        @embedFile("otp_sys.beam"),
        @embedFile("otp_lists.beam"),
        @embedFile("otp_maps.beam"),
        @embedFile("otp_proplists.beam"),
    };
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const st = try runMulti(gpa, &closure, "boot", &.{}, &out, .{});
        try std.testing.expectEqual(@as(u8, 0), st);
        try std.testing.expectEqualStrings("{ok,tree_up,pong}\n", out.items);
    }
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const st = try runMulti(gpa, &closure, "restart", &.{}, &out, .{});
        try std.testing.expectEqual(@as(u8, 0), st);
        try std.testing.expectEqualStrings("{true,true,true}\n", out.items);
    }
}

test "LAW e48-appctl-handoff: ensure_all_started boots the STOCK-closure app through the AppController (p0 as the code-bearing template) — the entry process OBSERVES the controller-booted tree via a REAL gen_server:call; without the boot the same entry times out" {
    const gpa = std.testing.allocator;
    const closure = [_][]const u8{
        @embedFile("sup_probe.beam"),
        @embedFile("otp_supervisor.beam"),
        @embedFile("otp_gen_server.beam"),
        @embedFile("otp_gen.beam"),
        @embedFile("otp_proc_lib.beam"),
        @embedFile("otp_sys.beam"),
        @embedFile("otp_lists.beam"),
        @embedFile("otp_maps.beam"),
        @embedFile("otp_proplists.beam"),
    };
    {
        // WITH the controller boot: sup_probe:start(normal, []) is dispatched
        // into the REAL stock code by ensure_all_started; the entry (`ping`)
        // polls bounded, finds sp_app_child, and round-trips a call → app_ok.
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const st = try runMulti(gpa, &closure, "ping", &.{}, &out, .{ .app_boot = .{ .app = "sup_probe_app", .mod = "sup_probe" } });
        try std.testing.expectEqual(@as(u8, 0), st);
        try std.testing.expectEqualStrings("app_ok\n", out.items);
    }
    {
        // WITHOUT the boot: the tree exists ONLY when the controller made it —
        // the same entry exhausts its bounded poll (never a hang).
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        const st = try runMulti(gpa, &closure, "ping", &.{}, &out, .{});
        try std.testing.expectEqual(@as(u8, 0), st);
        try std.testing.expectEqualStrings("app_timeout\n", out.items);
    }
}

test "LAW gap-resident-node: the RESIDENT node lifecycle COMPOSES with P-APP ensure_all_started — a `--resident` boot keeps the supervised app tree UP (an always-on serving node reports `resident: idle (<n> alive)`), where the one-shot path serves `app_ok` and ABANDONS the tree" {
    // The UNTESTED→EQUIV witness for `resident_node`: the resident node is now a
    // first-class CLI node path. Both runs boot the application through the
    // AppController (ensure_all_started) and the entry round-trips a REAL
    // gen_server:call against the controller-booted supervision tree. The
    // DIFFERENCE is the node lifecycle:
    //   • one-shot  (`drive`): once `ping` halts, the idle-but-alive app tree is
    //     treated as done — the served result `app_ok` is returned, the tree gone.
    //   • resident (`driveResident`): the supervised gen_server tree is ALIVE, so
    //     the node STAYS UP and reports `resident: idle (<n> alive)` — an always-on
    //     serving node, exactly the semantics a real OTP release boot has.
    const gpa = std.testing.allocator;
    const closure = [_][]const u8{
        @embedFile("sup_probe.beam"),
        @embedFile("otp_supervisor.beam"),
        @embedFile("otp_gen_server.beam"),
        @embedFile("otp_gen.beam"),
        @embedFile("otp_proc_lib.beam"),
        @embedFile("otp_sys.beam"),
        @embedFile("otp_lists.beam"),
        @embedFile("otp_maps.beam"),
        @embedFile("otp_proplists.beam"),
    };
    // RESIDENT: the node boots the app tree and STAYS UP (the supervised tree is
    // alive) — an always-on serving node, not a one-shot that exits.
    var out_res: std.ArrayList(u8) = .empty;
    defer out_res.deinit(gpa);
    const st_res = try runMulti(gpa, &closure, "ping", &.{}, &out_res, .{
        .app_boot = .{ .app = "sup_probe_app", .mod = "sup_probe" },
        .resident = true,
    });
    try std.testing.expectEqual(@as(u8, 0), st_res);
    // stays up: reports the resident-idle verdict with a live process count.
    try std.testing.expect(std.mem.startsWith(u8, out_res.items, "resident: idle ("));
    // the app tree is genuinely resident: at least one alive process remains.
    try std.testing.expect(std.mem.indexOf(u8, out_res.items, "(0 alive)") == null);

    // ONE-SHOT: the SAME P-APP boot serves the gen_server:call — `app_ok` — then
    // the idle-but-alive tree is treated as done (the drive exits). This proves the
    // tree DID boot + serve; resident mode reclassifies its quiescence as "still up".
    var out_one: std.ArrayList(u8) = .empty;
    defer out_one.deinit(gpa);
    const st_one = try runMulti(gpa, &closure, "ping", &.{}, &out_one, .{ .app_boot = .{ .app = "sup_probe_app", .mod = "sup_probe" } });
    try std.testing.expectEqual(@as(u8, 0), st_one);
    try std.testing.expectEqualStrings("app_ok\n", out_one.items);
}

test "LAW gap-ets-scale-unit WORKLOAD: the contention workload prices EXACTLY N*M ops and scales its op count with the thread axis" {
    const gpa = std.testing.allocator;
    var atoms = AtomTable.init(gpa);
    defer atoms.deinit();
    const iters: usize = 200;
    // The op COUNT must be a function of the thread axis. A workload that
    // ignored `nthreads` would produce a perfectly flat curve and look like a
    // scaling RESULT — the most misleading possible outcome for a unit whose
    // whole job is to say whether ETS scales.
    var prev: u64 = 0;
    for ([_]u32{ 1, 2, 4 }) |n| {
        const ops = try scaleWorkEts(gpa, &atoms, n, iters);
        try std.testing.expectEqual(@as(u64, @intCast(@as(usize, n) * iters)), ops);
        try std.testing.expect(ops > prev);
        prev = ops;
    }
}

test "LAW gap-ets-scale-unit DISPATCH: the scale-unit REGISTRY is total — every declared unit is known, a non-declared one is not, and ets_contention is among them" {
    // REACHABILITY, checkable without a clock. A unit the CLI does not accept is
    // a unit nobody can run — the FM-DISPATCH-DEAD shape this repository has hit
    // ten times, here in its measurement-surface form.
    for (scale_units) |u| try std.testing.expect(scaleUnitKnown(u));
    try std.testing.expect(scaleUnitKnown("ets_contention"));
    // REJECTION counterweight — without it a registry that answered `true` for
    // everything would satisfy the acceptance arm above.
    try std.testing.expect(!scaleUnitKnown("ets_contentionn"));
    try std.testing.expect(!scaleUnitKnown(""));
    try std.testing.expect(!scaleUnitKnown("spawn"));
    // NON-VACUOUS: the registry is not empty, and it grew for this slice.
    try std.testing.expect(scale_units.len >= 4);
    // And the rejection still reaches the caller through `scale` itself — the
    // guard uses the registry rather than a parallel chain that could drift.
    const io: std.Io = undefined; // the reject path returns before the clock
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try std.testing.expectError(
        ScaleError.UnknownScaleUnit,
        scale(std.testing.allocator, io, "ets_contentionn", 1, &out),
    );
}
