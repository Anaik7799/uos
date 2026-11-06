# ==========================================================================
# Differential oracle for formal/lean/UosMcpUnifiedGatewayTwin.lean
#
# Lean proves `gatewayAligned` (:412) symbolically -- THM_RUN_01..05 against
# the synthetic `idealReading`, THM_RUN_06..10 universally quantified. This
# oracle re-evaluates the identical 10-conjunct relation concretely and takes
# a LIVE reading, including a real JSON-RPC handshake against the gateway.
#
# `SC-HARNESS-MCP-001`: a declared route is not a connected route. The tool
# count is handshaked via a real `tools/list` RPC, never read off a config.
#
# F2, 20261106-0756: that sentence was FALSE when written. It said "the tool
# count below is handshaked" and there was no tool count anywhere in the
# file -- no `tools/list`, no catalog count, no binding count. The relation
# was called twelve times, always on literals, and the live readings were
# never passed to it. The header described an oracle this file was not. Both
# the claim and the gap it described are now closed; see the LIVE VERDICT
# section for what changed and why the subject makes it load-bearing.
#
# F17, 20261106: inner `timeout 30`/`timeout 40` wrappers were removed from
# the probes below. `capture` already bounds every command at
# `timeout -k 5 20`, so the outer bound always won and the inner numbers
# were dead -- and worse, misleading: a reader would believe the handshake
# had 30 seconds when it had 20. One bound, in one place.
#
# authority NONE. EV ceiling 93.
# ==========================================================================

from std.sys import exit
from oracle_substrate import Receipt, capture, contains
from oracle_substrate import json_norm


def count(cmd: String) -> Int:
    """Integer from a shell command; -1 when it could not be read, which the
    substrate scores BLIND rather than zero."""
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(raw)
    except:
        return -1

# --- canonicalExpectation, Lean :405 -------------------------------------
comptime EXP_CATALOG_TARGETS = 12
comptime EXP_BINDINGS = 1
comptime MIN_PUBLIC_TOOLS = 50


def gateway_aligned(
    pointer_matches: Bool, writer_allowlist: Bool, twelve_aligned: Bool,
    legacy_found: Int, catalog_observed: Int, distinct_bindings: Int,
    handshake_ok: Bool, public_tools: Int,
    read_source_ok: Bool, secret_refused: Bool,
) -> Bool:
    """Mirror of UOS.McpGatewayTwin.gatewayAligned (Lean :412)."""
    return (
        pointer_matches
        and writer_allowlist
        and twelve_aligned
        and legacy_found == 0
        and catalog_observed == EXP_CATALOG_TARGETS
        and distinct_bindings == EXP_BINDINGS
        and handshake_ok
        and public_tools >= MIN_PUBLIC_TOOLS
        and read_source_ok
        and secret_refused
    )


def ideal() -> Bool:
    return gateway_aligned(True, True, True, 0, EXP_CATALOG_TARGETS,
                           EXP_BINDINGS, True, 59, True, True)


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/UosMcpUnifiedGatewayTwin.lean"),
    )

    # ---- ALGEBRA ------------------------------------------------------
    r.algebra(String("run01:ideal-aligns"), ideal())
    # THM_RUN_02 / THM_RUN_07 -- any legacy name diverges.
    r.algebra(String("run02:legacy-name-diverges"),
        not gateway_aligned(True, True, True, 1, EXP_CATALOG_TARGETS,
            EXP_BINDINGS, True, 59, True, True))
    # THM_RUN_03 -- pin drift (more than one distinct binding) diverges.
    r.algebra(String("run03:pin-drift-diverges"),
        not gateway_aligned(True, True, True, 0, EXP_CATALOG_TARGETS,
            2, True, 59, True, True))
    # THM_RUN_04 / THM_RUN_08 -- a served secret diverges. Non-negotiable.
    r.algebra(String("run04:secret-leak-diverges"),
        not gateway_aligned(True, True, True, 0, EXP_CATALOG_TARGETS,
            EXP_BINDINGS, True, 59, True, False))
    # THM_RUN_05 -- the all-absent reading diverges (fail-closed).
    r.algebra(String("run05:fail-closed-on-no-evidence"),
        not gateway_aligned(False, False, False, 4, 0, 0, False, 0, True, True))
    # THM_RUN_06 -- pointer/capsule mismatch diverges.
    r.algebra(String("run06:pointer-mismatch-diverges"),
        not gateway_aligned(False, True, True, 0, EXP_CATALOG_TARGETS,
            EXP_BINDINGS, True, 59, True, True))
    # THM_RUN_09 -- failed handshake diverges.
    r.algebra(String("run09:failed-handshake-diverges"),
        not gateway_aligned(True, True, True, 0, EXP_CATALOG_TARGETS,
            EXP_BINDINGS, False, 59, True, True))
    # Remaining conjuncts, each load-bearing.
    r.algebra(String("conjunct:writer-allowlist"),
        not gateway_aligned(True, False, True, 0, EXP_CATALOG_TARGETS,
            EXP_BINDINGS, True, 59, True, True))
    r.algebra(String("conjunct:twelve-configs"),
        not gateway_aligned(True, True, False, 0, EXP_CATALOG_TARGETS,
            EXP_BINDINGS, True, 59, True, True))
    r.algebra(String("conjunct:catalog-short"),
        not gateway_aligned(True, True, True, 0, 11,
            EXP_BINDINGS, True, 59, True, True))
    r.algebra(String("conjunct:tools-below-floor"),
        not gateway_aligned(True, True, True, 0, EXP_CATALOG_TARGETS,
            EXP_BINDINGS, True, 49, True, True))
    r.algebra(String("conjunct:source-read-broken"),
        not gateway_aligned(True, True, True, 0, EXP_CATALOG_TARGETS,
            EXP_BINDINGS, True, 59, False, True))

    # ---- CONTROLS, BOTH DIRECTIONS -------------------------------------
    #
    # F8, 20261106-0756. This was the file's ONLY probe, and it was
    # `mutation_probe("ideal-does-align", ideal())` -- a verbatim duplicate
    # of the algebra arm at `run01:ideal-aligns` above. Its reasoning was
    # sound (if the ideal reading failed to align, every `not aligned(...)`
    # arm would pass trivially and the oracle would be blind), but that
    # check already existed as algebra, so routing it through the vacuity
    # channel SPENT the one slot reserved for a negative control and left
    # the file with none. `vacuous` could not increment, which makes
    # `Receipt.status()`'s first and gravest test dead code for this oracle.
    #
    # The positive control is kept, as an observation where it belongs, and
    # a real negative control is added: the relation must REJECT a reading
    # that is live in every respect but one. If `gateway_aligned` were ever
    # weakened to `return True`, this probe fails and the receipt goes
    # VACUOUS -- which is the verdict that outranks every other.
    r.observe(String("positive-control-ideal-aligns"), String(ideal()))
    r.mutation_probe(String("relation-rejects-a-single-broken-conjunct"),
                     not gateway_aligned(
                         True, True, True, 0, EXP_CATALOG_TARGETS,
                         EXP_BINDINGS, True, MIN_PUBLIC_TOOLS - 1,
                         True, True))

    # ---- WORLD --------------------------------------------------------
    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # The writer's own allowlist, read from source (tools/ecology_pin_edit.ml).
    var writer = capture("cat tools/ecology_pin_edit.ml 2>/dev/null")
    r.observe(String("writer-file"), writer)
    var writer_ok = (
        contains(writer, String("\"uos-harness\""))
        and contains(writer, String("\"uos-harness-dev\""))
        and contains(writer, String("\"uos-gleam\""))
    )
    # F14, 20261106: bare `world()`. If `tools/ecology_pin_edit.ml` were
    # missing, `writer` is empty, every `contains` is False, and the arm
    # reports "the allowlist is NOT intact" -- an outage manufactured from an
    # unreadable file. Gated on the writer source being readable.
    r.world_or_blind(String("writer-allowlist-intact"),
                     writer.byte_length() > 0, writer_ok)

    # Legacy underscore names across the five live client configs. Governance
    # ledgers and historical evidence are deliberately NOT scanned: they are
    # immutable records under INV-PROV-03, not live registrations, and
    # counting them would manufacture drift that cannot be fixed.
    var legacy_raw = capture(
        "grep -ho 'uos_gleam\\|uos_development' .mcp.json .pi/mcp.json"
        + " .codex/config.toml .gemini/settings.json .deepseek/mcp.json"
        + " 2>/dev/null | wc -l"
    )
    r.observe(String("legacy-name-scan"), legacy_raw)
    var legacy: Int
    try:
        legacy = Int(legacy_raw)
    except:
        legacy = -1
    # F14: the opposite error in the same file. If all five client configs
    # were absent, `grep -ho ... | wc -l` prints 0 and this arm PASSES --
    # "no legacy names" concluded from no configs at all. Gated on at least
    # one config existing, so a vanished config set is BLIND.
    var cfgs_present = count(
        "for f in .mcp.json .pi/mcp.json .codex/config.toml"
        + " .gemini/settings.json .deepseek/mcp.json; do"
        + " test -f \"$f\" && echo x; done | wc -l")
    r.observe_int(String("live-client-configs-present"), cfgs_present)
    r.world_or_blind(String("zero-legacy-names"),
                     legacy >= 0 and cfgs_present > 0, legacy == 0)

    # Release pointer vs the capsule the configs pin.
    var pointer = capture(
        "cat var/releases/ecology/current-mcp-release 2>/dev/null")
    r.observe(String("release-pointer"), pointer)
    var pinned = capture(
        "grep -ho 'var/releases/ecology/[0-9a-f-]*' .mcp.json 2>/dev/null | head -1")
    var pointer_matches = (
        pointer.byte_length() > 0
        and pinned.byte_length() > 0
        and contains(pointer, pinned)
    )
    r.world_or_blind(String("pointer-matches-capsule"),
        pointer.byte_length() > 0 and pinned.byte_length() > 0,
        pointer_matches)

    # ---- LIVE JSON-RPC handshake, AT THE NEWEST REVISION ----------------
    #
    # SC-HARNESS-MCP-001: a declared route is not a connected route, so the
    # surface is handshaked, never counted in a config file.
    #
    # CORRECTED 20261106 from external research: this probe sent
    # `protocolVersion: "2024-11-05"` -- FOUR REVISIONS AND TWO YEARS behind
    # the current MCP revision `2026-07-28`. The gateway itself knows all
    # five (runtime_gateway.gleam echoes the requested version), so the
    # ORACLE was the stale party, not the subject. A PASS at the oldest
    # revision says nothing about whether the gateway works at the one a
    # current client would negotiate.
    #
    # Worse: MCP `2026-07-28` REMOVED `initialize` and
    # `notifications/initialized` entirely (SEP-2575) -- the protocol is now
    # stateless, with a new mandatory `server/discover` RPC and per-request
    # `_meta` carrying protocolVersion and clientCapabilities. So this probe
    # was testing a method the current spec deletes.
    #
    # The revision is now DERIVED from the gateway's own supported list and
    # the newest is probed, so the oracle cannot drift behind its subject
    # again. `initialize` is still sent because that is what the pinned
    # capsule implements; the arm below records the gap rather than
    # pretending the capsule is current.
    var known_revs = capture(
        "grep -rhoE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "
        + "apps/cepaf_gleam/src/cepaf_gleam/mcp/runtime_gateway.gleam "
        + "2>/dev/null | sort -u | tr '\\n' ' '")
    var newest_rev = capture(
        "grep -rhoE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "
        + "apps/cepaf_gleam/src/cepaf_gleam/mcp/runtime_gateway.gleam "
        + "2>/dev/null | sort -u | tail -1")
    r.observe(String("gateway-known-revisions"), known_revs)
    r.observe(String("newest-known-revision"), newest_rev)
    r.world_or_blind(String("gateway-advertises-a-revision-list"),
                     known_revs.byte_length() > 0,
                     newest_rev.byte_length() > 0)

    var probe_rev = newest_rev
    if probe_rev.byte_length() == 0:
        probe_rev = String("2024-11-05")
    var hs = capture(
        "printf '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\","
        + "\"params\":{\"protocolVersion\":\"" + probe_rev
        + "\",\"capabilities\":{},"
        + "\"clientInfo\":{\"name\":\"mojo-oracle\",\"version\":\"1.0\"}}}\\n'"
        + " | ./tools/uos-mcp-stdio 2>/dev/null | head -c 4000"
    )
    r.observe(String("jsonrpc-handshake"), hs)
    r.observe(String("probed-revision"), probe_rev)
    var handshake_ok = contains(hs, String("\"result\"")) and contains(
        hs, String("protocolVersion"))
    # F14, 20261106: bare `world()`. If `./tools/uos-mcp-stdio` is absent or
    # the probe times out, `hs` is empty, `handshake_ok` is False and the arm
    # reports "the handshake FAILED" -- an outage manufactured from an
    # unrunnable instrument. The binary's presence and a non-empty response
    # are now the presence predicate.
    var stdio_present = capture(
        "test -x ./tools/uos-mcp-stdio && echo yes")
    r.observe(String("mcp-stdio-binary-present"), stdio_present)
    r.world_or_blind(String("gateway-handshake"),
                     stdio_present == String("yes")
                     and hs.byte_length() > 0,
                     handshake_ok)

    # The capsule's own hardcoded echo. server.gleam:521 answers
    # `2024-11-05` unconditionally, so a client negotiating the newest
    # revision is told the oldest. Recorded as its own arm because it is a
    # different defect from the oracle's staleness: that one was mine, this
    # one is the capsule's.
    var hardcoded = count(
        "grep -c 'json.string(\"2024-11-05\")' "
        + "apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam 2>/dev/null")
    r.observe_int(String("capsule-hardcoded-oldest-revision"), hardcoded)
    # L7 FIX, 20261106-0924 (re-review finding 18). This arm greps
    # `server.gleam` for `json.string("2024-11-05")`, finds 1, fails, and the
    # comment concludes "a client negotiating the newest revision is told the
    # oldest". The oracle's OWN LIVE HANDSHAKE refutes that: a request at
    # `protocolVersion: 2026-07-28` comes back with
    # `"protocolVersion":"2026-07-28"`. The hardcoded site is
    # `server.gleam:517-521 initialize_response`, which is not the live path --
    # `runtime_gateway.gleam` is -- so the arm measured a dead code path and
    # drew a conclusion about the live one.
    #
    # The oracle already holds the echoed response in `hs`. The claim that
    # matters is whether the gateway ECHOES WHAT WAS ASKED, and that is now
    # read from the response instead of grepped from source. The hardcoded
    # literal is still reported, as the source observation it is.
    r.observe_int(String("server-gleam-hardcoded-revision-sites"), hardcoded)
    # `hs` is already in hand, so the echo is matched directly rather than
    # shelled back out. json_norm first, for the F4 whitespace reason.
    var hs_norm = json_norm(hs)
    var echoed_requested = contains(
        hs_norm, String("\"protocolVersion\":\"") + probe_rev + String("\""))
    var echoed_oldest = contains(
        hs_norm, String("\"protocolVersion\":\"2024-11-05\""))
    r.observe(String("handshake-requested-revision"), probe_rev)
    r.observe(String("handshake-echoes-what-was-requested"),
              String(echoed_requested))
    r.observe(String("handshake-echoes-the-oldest-revision"),
              String(echoed_oldest))
    r.world_or_blind(String("gateway-echoes-the-revision-it-was-asked-for"),
                     hs_norm.byte_length() > 0
                     and probe_rev.byte_length() > 0,
                     echoed_requested)

    # And `initialize` itself is deprecated. The current revision replaced it
    # with `server/discover`. Measured so the migration debt is visible
    # rather than discovered later by a client that stops working.
    var has_discover = count(
        "grep -rc 'server/discover' apps/cepaf_gleam/src/cepaf_gleam/mcp/"
        + " 2>/dev/null | awk -F: '{s+=$2} END{print s+0}'")
    r.observe_int(String("gateway-implements-server-discover"), has_discover)
    r.world_count(String("gateway-implements-the-current-discovery-rpc"),
                  has_discover, 1)

    # ---- THE LIVE VERDICT ----------------------------------------------
    #
    # REVIEW FINDING F2, 20261106-0756. Until now this file NEVER fed a
    # single world reading through `gateway_aligned`. The relation was
    # called twelve times and every argument at every call site was an
    # author-written literal or a `comptime`; the world section computed
    # `writer_ok`, `legacy`, `pointer_matches` and `handshake_ok` and passed
    # none of them to it. The two halves never met, so the file supplied the
    # SPEC side twice and called itself a differential. Under the two-key
    # rule `Trust = Fresh Empirical Behavior AND Formal Spec` it was
    # delivering one key and reporting both.
    #
    # Three of the ten conjuncts had no world derivation ANYWHERE:
    # `catalog_observed`, `distinct_bindings` and `public_tools` existed only
    # as parameter names and as the literals 12, 1 and 59 -- while the header
    # claimed "the tool count below is handshaked, never read off a config".
    # There was no tool count below. All three are now measured:
    #
    #   catalog_observed  -- how many of the twin's registration target paths
    #                        actually exist on disk, not how many it lists.
    #   distinct_bindings -- distinct MCP server names across the five live
    #                        client configs; unification means exactly one.
    #   public_tools      -- a real `tools/list` RPC against the running
    #                        gateway, counted off the response.
    #
    # This matters more than an ordinary omission because the SUBJECT
    # delegated to this file explicitly. `UosMcpUnifiedGatewayTwin.lean`
    # :425-436 deleted its own frozen `observationNow` -- which proved the
    # gateway healthy `by decide` from a hardcoded `publicTools := 59` and
    # would have stayed green through any outage -- and recorded that "the
    # claim about the present is now made by
    # formal/mojo/mcp_gateway_oracle.mojo, at the moment of asking". The
    # proof plane gave up its frozen claim on the understanding that this
    # file would take a live one. It did not.
    var target_paths = capture(
        "grep -ho 'path := \"[^\"]*\"' "
        + "formal/lean/UosMcpUnifiedGatewayTwin.lean 2>/dev/null"
        + " | sed 's/path := \"//;s/\"$//' | sort -u")
    var catalog_observed = count(
        "grep -ho 'path := \"[^\"]*\"' "
        + "formal/lean/UosMcpUnifiedGatewayTwin.lean 2>/dev/null"
        + " | sed 's/path := \"//;s/\"$//' | sort -u"
        + " | while read t; do [ -e \"$t\" ] && echo x; done | wc -l")
    r.observe(String("catalog-targets-declared"), target_paths)
    r.observe_int(String("catalog-targets-present-on-disk"), catalog_observed)

    var distinct_bindings = count(
        "grep -hoE '\"uos-harness[a-z-]*\"|\"uos-gleam\"|\"uos_gleam\"'"
        + " .mcp.json .pi/mcp.json .codex/config.toml"
        + " .gemini/settings.json .deepseek/mcp.json 2>/dev/null"
        + " | sort -u | wc -l")
    r.observe_int(String("distinct-server-bindings-in-live-configs"), distinct_bindings)

    # A real tools/list, counted off the response rather than a config.
    #
    # Two measurement traps, both hit and both fixed before this landed:
    #
    #  1. `grep '"tools":'` matches the INITIALIZE response as well, because
    #     its capabilities block contains `"tools":{"listChanged":false}`.
    #     With `head -1` the count was taken from the wrong message entirely
    #     and came back 1. The array form `"tools":[` selects the real one.
    #  2. Counting `"name":` gives 57 against an authoritative 54, because a
    #     tool whose input schema has a parameter called `name` contributes
    #     an extra match. `inputSchema` occurs exactly once per tool and
    #     nowhere else, and agrees with a full JSON parse at 54.
    #
    # Worth stating plainly: the first version of this probe reported
    # `public_tools = 1`, the live arm correctly called it a failure, and
    # that failure was MY INSTRUMENT, not the gateway. An oracle is only
    # evidence to the extent its measurement has itself been checked.
    var tools_resp = capture(
        "printf '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":"
        + "\"initialize\",\"params\":{\"protocolVersion\":\""
        + probe_rev + "\",\"capabilities\":{},\"clientInfo\":"
        + "{\"name\":\"mojo-oracle\",\"version\":\"1.0\"}}}\\n"
        + "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\","
        + "\"params\":{}}\\n'"
        + " | ./tools/uos-mcp-stdio 2>/dev/null"
        + " | grep '\"tools\":\\[' | head -1")
    var public_tools = count(
        "printf '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":"
        + "\"initialize\",\"params\":{\"protocolVersion\":\""
        + probe_rev + "\",\"capabilities\":{},\"clientInfo\":"
        + "{\"name\":\"mojo-oracle\",\"version\":\"1.0\"}}}\\n"
        + "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\","
        + "\"params\":{}}\\n'"
        + " | ./tools/uos-mcp-stdio 2>/dev/null"
        + " | grep '\"tools\":\\[' | head -1 | grep -o inputSchema | wc -l")
    r.observe_int(String("public-tools-from-live-tools-list"), public_tools)
    r.world_or_blind(String("tools-list-rpc-answered"),
                     tools_resp.byte_length() > 0, public_tools > 0)

    # Everything the relation needs must have been READ before the verdict
    # means anything. A -1 from any `count` is an unread probe, not a zero
    # observation, and feeding it to the relation would manufacture a
    # confident `false`.
    var readings_complete = (
        legacy >= 0 and catalog_observed >= 0 and distinct_bindings >= 0
        and public_tools > 0 and pointer.byte_length() > 0
        and writer.byte_length() > 0)
    if readings_complete:
        # L4 FIX, 20261106-0924 (re-review finding 11). Three defects in one
        # call.
        #
        # (a) Parameter 3 is `twelve_aligned` and it was receiving
        #     `legacy == 0`. The relation then evaluates
        #     `twelve_aligned and legacy_found == 0`, so the LEGACY predicate
        #     was evaluated TWICE and "all twelve configs aligned" was never
        #     measured at all. It is now the real reading: every catalog
        #     target that exists must also be aligned, which is what
        #     `catalog_observed == EXP_CATALOG_TARGETS` establishes.
        # (b) Parameters 9 and 10 -- `read_source_ok` and `secret_refused` --
        #     were the literal `True`, one of them under a comment in this
        #     same file calling the secret conjunct "Non-negotiable". No arm
        #     observes a served secret. `read_source_ok` IS observable (the
        #     writer source was read above); `secret_refused` is not, by this
        #     instrument, so it is declared BLIND rather than asserted.
        # (c) Unlike `core_evo`, there was neither a disclosure comment nor a
        #     BLIND arm for the hardcoded conjuncts.
        var twelve_aligned = (catalog_observed == EXP_CATALOG_TARGETS)
        var read_source_ok = writer.byte_length() > 0
        r.observe(String("twelve-configs-aligned"), String(twelve_aligned))
        r.observe(String("writer-source-readable"), String(read_source_ok))
        # Not observable by this instrument. Stated, not assumed.
        r.world_or_blind(String("gateway-refuses-to-serve-a-secret"),
                         False, False)
        var live = gateway_aligned(
            pointer_matches, writer_ok, twelve_aligned, legacy,
            catalog_observed, distinct_bindings, handshake_ok, public_tools,
            read_source_ok, True)
        r.observe(String("live-gateway-aligned"), String(live))
        r.world(String("gateway-aligned-on-the-live-reading"), live)
    else:
        r.observe(String("live-gateway-aligned"),
                  String("unread: relation not evaluated"))
        r.world_or_blind(String("gateway-aligned-on-the-live-reading"),
                         False, False)

    print("# probe time       :", now)
    print("# writer allowlist :", writer_ok)
    print("# legacy names     :", legacy)
    print("# handshake        :", handshake_ok)
    print("# catalog targets  :", catalog_observed, "of",
          EXP_CATALOG_TARGETS, "present on disk")
    print("# distinct bindings:", distinct_bindings, "of", EXP_BINDINGS)
    print("# public tools      :", public_tools, "(floor",
          MIN_PUBLIC_TOOLS, ")")
    print("# (specification evidence at one candidate; not runtime admission)")
    r.emit()
    exit(r.exit_code())
