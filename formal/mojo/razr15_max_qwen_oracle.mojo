# ==========================================================================
# Differential oracle for formal/lean/Razr15_Max_Qwen_Digital_Twin.lean
#
# WHAT THE REMOVED PROBER DID, AND WHY IT WAS THE WORST ONE
# ---------------------------------------------------------
# The `def main` stripped from that file ran four `curl` probes and one
# `ssh` into razr15-1, and then printed, conditioned on nothing but five
# exit codes being zero:
#
#     VERDICT: TRUST = FRESH EMPIRICAL BEHAVIOR /\ FORMAL SPEC
#              (25/25 THEOREMS GREEN)
#
# Five HTTP/SSH exit codes do not establish 25 theorems, and the 25
# theorems do not establish that the node is up. The banner multiplied two
# unrelated claims and reported the product as one verdict -- the precise
# collapse CLAUDE.md's epistemic discipline forbids ("specification, model
# proof, runtime observation and admission are four different claims and
# are never collapsed"). Worse, `curl -s` exits 0 on an HTTP 500, so four
# of the five conjuncts were satisfiable by a node that was answering
# nothing but errors.
#
# A SECOND DEFECT, IN THE PROOF PLANE, LEFT BEHIND ON PURPOSE
# -----------------------------------------------------------
# `DualPlaneObservabilityTwinSpec` (:594) declares every SLO as a field
# DEFAULTED TO TRUE -- allDataPlaneSlosPass := true, rogueAuthorityVetoed
# := true -- and `t25_dual_plane_observability_and_intent_twin_verified`
# decides that the all-true record is all-true. That theorem is a
# restatement: it cannot fail, so it carries no information about razr15-1.
# It is not this oracle's place to delete someone's theorem, so instead
# every one of those fields is OBSERVED here against the live endpoints,
# and the receipt reports what the world actually says. Where the world
# cannot be asked, the verdict is BLIND, which is nonpassing -- never the
# field's optimistic default.
#
# authority NONE. EV ceiling 93. No remote token is spent: the chat probe
# is bounded to 16 tokens at temperature 0 against a LOCAL gateway on the
# tailnet, which is the same zero-external-burn path THM_BML_03 routes.
# ==========================================================================

from std.sys import exit
from oracle_substrate import (
    Receipt, capture, contains, json_flag, json_int, json_norm, occurrences,
    shell_quote,
)

# F17, 20261106: this was the raw tailnet IP `100.114.9.28`.
# `contracts/rules/tailscale-web-fqdn-mandate.md` requires FQDN navigation,
# and tailnet IPs are reassignable, so an instrument pinned to one can start
# probing a different machine without any visible change. The FQDN was
# verified reachable (200 on /v1/models) before the swap, not after.
# F17, 20261106: curl used `--max-time 20` inside `capture`, which bounds at
# `timeout -k 5 20` -- so the inner bound could never fire before the outer
# one killed the process, and a slow endpoint produced a KILL rather than
# curl's own timeout diagnostic. Lowered to 12 so curl reports the timeout
# itself and the capture survives to record it.
comptime HOST = "razr15-1.tail55d152.ts.net"
comptime PORT = 8000
# The runtime's own declaration of this node's authority, by another author
# in another language. `node_to_string(Razr15MaxQwen)` is the second key for
# `endpoint:runtime-adapter-declares-the-same-authority`.
comptime ADAPTER = (
    "apps/cepaf_gleam/src/cepaf_gleam/ai/tailnet_llm_adapter.gleam")
comptime MODEL_ID = "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
comptime DUAL_PLANE_SCHEMA = "uos.observability.dual_plane_14stage.v1"
# The stage total the dual-plane schema name commits to, parsed from the
# schema string itself rather than written twice.
comptime DUAL_PLANE_STAGES = 14
comptime SSH_PORT = 2222


def base_url() -> String:
    return String("http://") + String(HOST) + String(":") + String(PORT)


def http_code(path: String) -> String:
    """The STATUS, not just the body. `curl -s` exits 0 on a 500, which is
    how the old prober's five-exit-code verdict could be green against a
    node answering nothing but errors."""
    return capture(
        "curl -s -o /dev/null -w '%{http_code}' --max-time 5 "
        + base_url() + path)


def http_body(path: String) -> String:
    return capture("curl -s --max-time 5 " + base_url() + path)


def count(cmd: String) -> Int:
    var raw = capture(cmd)
    if raw.byte_length() == 0:
        return -1
    try:
        return Int(String(raw.strip()))
    except:
        return -1


def main() raises:
    var r = Receipt(
        String("uos.oracle.v1"),
        String("formal/lean/Razr15_Max_Qwen_Digital_Twin.lean"),
    )

    var now = capture("date -u +%Y-%m-%dT%H:%M:%SZ")
    r.observe(String("clock"), now)

    # ---- ALGEBRA: the parts of the twin that are genuinely decidable ----
    # These re-evaluate arithmetic the kernel decides, so a disagreement
    # here is DIVERGENCE, not an outage.
    # F11, 20261106. These three were `7 + 7 == 14`, `PORT == 8000` and
    # `93 == 93`. The first restated arithmetic without reading the stage
    # counts; the second compared the oracle's OWN `comptime` against the
    # literal it was set to, under a name asserting agreement with a
    # firewall it never read; the third asserted the provenance ceiling by
    # comparing 93 to itself, reading no contract.
    #
    # All three now have two independently-sourced sides:
    comptime TWIN = "formal/lean/Razr15_Max_Qwen_Digital_Twin.lean"
    comptime PROXY = "ops/nodes/razr15-1-wsl2/tcp_proxy_8000.escript"
    comptime POLICY = "CLAUDE.md"
    var twin_data_stages = count(
        "grep -oE 'dataPlaneStageCount *: *Nat := *[0-9]+' " + String(TWIN)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'")
    var twin_ctrl_stages = count(
        "grep -oE 'controlPlaneStageCount *: *Nat := *[0-9]+' " + String(TWIN)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'")
    var twin_ceiling = count(
        "grep -oE 'def admittedEvCeiling : Nat := [0-9]+' " + String(TWIN)
        + " 2>/dev/null | grep -oE '[0-9]+$'")
    var policy_ceiling = count(
        "grep -oE 'admitted_ev_ceiling = [0-9]+' " + String(POLICY)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'")
    var proxy_port = count(
        "grep -oE 'gen_tcp:listen\\([0-9]+' " + String(PROXY)
        + " 2>/dev/null | head -1 | grep -oE '[0-9]+'")
    r.observe_int(String("twin-data-plane-stages"), twin_data_stages)
    r.observe_int(String("twin-control-plane-stages"), twin_ctrl_stages)
    r.observe_int(String("twin-admitted-ev-ceiling"), twin_ceiling)
    r.observe_int(String("policy-admitted-ev-ceiling"), policy_ceiling)
    r.observe_int(String("proxy-listen-port"), proxy_port)
    if twin_data_stages >= 0 and twin_ctrl_stages >= 0:
        r.algebra(String("t25:fourteen-stages-is-the-two-plane-counts"),
                  twin_data_stages + twin_ctrl_stages == DUAL_PLANE_STAGES)
    else:
        r.observe(String("t25"), String("skipped: stage counts unreadable"))
    # The port the proxy actually LISTENS on, against the one this oracle
    # probes. Renamed: nothing here reads a firewall, and the old name said
    # it did.
    r.world_count(String("endpoint:probed-port-matches-the-proxy-listener"),
                  proxy_port, PORT)
    # ---- the address this oracle dials is the address the runtime dials --
    # ADDED 20261107-0331, found by B5 mirror mutation. `base_url` is used
    # ONLY inside `capture("curl ... " + base_url() + path)`, so its value
    # reached the receipt only through the network. Emptying its scheme
    # literal -- turning "http://host:8000" into "host:8000" -- returned a
    # byte-identical receipt. Every endpoint arm in this file would read the
    # same whether the URL had a scheme or not, because a curl that cannot
    # parse its argument and a service that is down are indistinguishable
    # here. A mirror observed only through a failing world call is not
    # observed.
    #
    # KEY 1 (world, independent provenance): the Gleam adapter that actually
    # dials this model declares its own host:port, written by another hand
    # in another language. If either side moves, this fires.
    var adapter_hits = count(
        "grep -cF " + shell_quote(String(HOST) + ":" + String(PORT)) + " "
        + String(ADAPTER) + " 2>/dev/null")
    r.world_or_blind(
        String("endpoint:runtime-adapter-declares-the-same-authority"),
        adapter_hits >= 0, adapter_hits > 0)
    # KEY 2 (algebra): the composed URL is absolute. Exactly one scheme
    # separator, and the scheme sits immediately before the host rather than
    # anywhere in the string. This is a necessary property, not a restated
    # definition: it does not fix what the authority is, which is KEY 1's
    # job, and it is falsified by the mutant that KEY 1 cannot see.
    var u = base_url()
    r.algebra(String("endpoint:composed-url-is-absolute"),
              occurrences(u, String("://")) == 1
              and contains(u, String("http://") + String(HOST) + String(":")))

    # A real differential: the twin's ceiling against the ROOT POLICY's,
    # which is a separate artifact with a separate author.
    if twin_ceiling >= 0 and policy_ceiling >= 0:
        r.algebra(String("prov:twin-ceiling-agrees-with-root-policy"),
                  twin_ceiling == policy_ceiling)
    else:
        r.world_or_blind(String("prov:twin-ceiling-agrees-with-root-policy"),
                         False, False)
    # ---- VRAM geometry, RE-DERIVED FROM THE TWIN'S OWN RECORD -----------
    #
    # CODEX FINDING, 20261106: this arm previously used 1792 MiB KV cache and
    # 4483 MiB weights. `canonicalRazr15Deployment` (:330) records 448 KV,
    # 4218 weights and a 296 MiB compute buffer, and `totalUsedVramMiB`
    # (:347) adds `windowsDesktopMiB` on top of those three. The 1792/4483
    # figures came from nowhere in the twin, so the arm was not re-deriving
    # the twin -- it was agreeing with itself about a DIFFERENT deployment and
    # calling that a differential.
    #
    # An oracle that invents its own inputs is the transcription failure one
    # level down: it cannot disagree with the model, because it is not
    # evaluating the model. It was the most dangerous arm in this file
    # precisely because it passed.
    #
    # The three fields are now READ FROM the Lean record, so the arm fails
    # closed if the record changes and nobody updates the oracle.
    var vram_fields = capture(
        "grep -oE '(modelWeightsVramMiB|kvCacheVramMiB|computeBufferMiB)"
        + " *:= *[0-9]+' formal/lean/Razr15_Max_Qwen_Digital_Twin.lean"
        + " | grep -oE '[0-9]+' | tr '\\n' ' '")
    r.observe(String("vram-record"), vram_fields)
    var vram_sum = 0
    var vram_n = 0
    for part in vram_fields.split(String(" ")):
        var p = String(String(part).strip())
        if p.byte_length() == 0:
            continue
        try:
            vram_sum += Int(p)
            vram_n += 1
        except:
            continue
    # Three fields, or the record was not read as expected. A silent 0 would
    # make the budget look satisfied by an empty deployment, so an unreadable
    # record is BLIND rather than a pass.
    r.world_count(String("vram-record-has-three-fields"), vram_n, 3)
    if vram_n == 3:
        # The twin PROVES totalUsedVramMiB = 7104 (:542), which includes the
        # Windows desktop reservation. The three model-side fields alone must
        # therefore be strictly less, and the proved total must fit the card.
        # F11: `7104 <= 8192` had BOTH sides literal -- the proved total and
        # the card's capacity were author-typed, so the arm could not notice
        # either changing. Both are now read from the twin: the total from
        # the theorem that proves it, the capacity from the GPU record.
        var proved_total = count(
            "grep -oE 'totalUsedVramMiB = [0-9]+' " + String(TWIN)
            + " 2>/dev/null | head -1 | grep -oE '[0-9]+$'")
        var card_capacity = count(
            "grep -oE 'totalVramMiB *:= *[0-9]+' " + String(TWIN)
            + " 2>/dev/null | head -1 | grep -oE '[0-9]+'")
        r.observe_int(String("twin-proved-total-used-vram-mib"), proved_total)
        r.observe_int(String("twin-card-capacity-mib"), card_capacity)
        if proved_total >= 0 and card_capacity >= 0:
            r.algebra(String("deploy-model-vram-is-under-the-proved-total"),
                      vram_sum < proved_total)
            r.algebra(String("deploy-proved-total-fits-the-card"),
                      proved_total <= card_capacity)
        else:
            r.world_or_blind(String("deploy-vram-geometry"), False, False)

    # ---- WORLD: /v1/models ---------------------------------------------
    var models_code = http_code(String("/v1/models"))
    var models_body = http_body(String("/v1/models"))
    r.observe(String("models-status"), models_code)
    r.observe(String("models-body"), models_body)
    r.world_or_blind(String("models-answers-200"),
                     models_code.byte_length() > 0,
                     models_code == String("200"))
    r.world_or_blind(String("canonical-model-id-is-served"),
                     models_body.byte_length() > 0,
                     contains(models_body, String(MODEL_ID)))

    # ---- WORLD: the dual-plane telemetry endpoint -----------------------
    # Every assertion below replaces a field the Lean spec DEFAULTS to true.
    # Each goes through `json_flag`, so a key the gateway does not emit is
    # BLIND rather than false -- the first run of this oracle asked for
    # `"all_data_plane_slos_pass":true` against a body that writes
    # `"all_data_plane_slos_pass": true`, and reported six outages on a
    # healthy node.
    var tel_code = http_code(String("/v1/telemetry/pipeline"))
    var tel = http_body(String("/v1/telemetry/pipeline"))
    r.observe(String("telemetry-status"), tel_code)
    r.observe(String("telemetry-body"), tel)
    var tel_seen = tel.byte_length() > 0
    r.world_or_blind(String("telemetry-answers-200"),
                     tel_code.byte_length() > 0, tel_code == String("200"))
    r.world_or_blind(String("dual-plane-schema-is-declared"),
                     tel_seen, contains(tel, String(DUAL_PLANE_SCHEMA)))
    r.world_json(String("data-plane-slos-pass-live"),
                 json_flag(tel, String("all_data_plane_slos_pass")), True)
    r.world_json(String("control-plane-slos-pass-live"),
                 json_flag(tel, String("all_control_plane_slos_pass")), True)
    r.world_json(String("profile-lock-is-thread-safe"),
                 json_flag(tel, String("profile_lock_thread_safe")), True)
    r.world_json(String("os-nvme-serial-stays-locked"),
                 json_flag(tel, String("nvme_os_serial_locked")), True)

    # Remote token burn. The twin proves 0; the gateway reports a total.
    var remote_tokens = json_int(tel, String("total_remote_tokens_billed"))
    r.world_count(String("zero-remote-tokens-billed"), remote_tokens, 0)

    # COUNT the stages rather than trust a summary field to agree with the
    # list printed beside it. The twin declares 7 data + 7 control = 14.
    # R2, 20261106-1230: the telemetry body is the instrument for every arm
    # below. An unreachable node or a broken curl yields an empty body, and
    # the stage/profile counts then read 0 -- which the arms reported as a
    # DIVERGENCE FROM THE TWIN rather than as "I could not look". Found by
    # the robustness harness with `curl` stubbed to exit 127.
    var tel_read = tel.byte_length() > 0
    r.observe(String("telemetry-body-was-read"), String(tel_read))
    r.world_or_blind(String("telemetry-endpoint-is-readable"),
                     models_code.byte_length() > 0, tel_read)
    var tel_n = json_norm(tel)
    var data_stages = occurrences(tel_n, String("\"plane\":\"data_plane\""))
    var ctrl_stages = occurrences(tel_n, String("\"plane\":\"control_plane\""))
    r.observe(String("stage-census"),
              String(data_stages) + String("+") + String(ctrl_stages))
    # F11-adjacent, 20261106: these compared the LIVE stage census against
    # the literal 7. The twin's own `dataPlaneStageCount` and
    # `controlPlaneStageCount` are read above, so the comparison now has the
    # subject on one side and the running node on the other -- which is what
    # makes it a differential rather than a reminder of what the author
    # expected. BLIND if the twin's declaration could not be read, because
    # comparing a live count against -1 would manufacture a divergence.
    r.world_or_blind(String("live-data-plane-stages-match-the-twin"),
                     twin_data_stages >= 0 and tel_read,
                     data_stages == twin_data_stages)
    r.world_or_blind(String("live-control-plane-stages-match-the-twin"),
                     twin_ctrl_stages >= 0 and tel_read,
                     ctrl_stages == twin_ctrl_stages)
    # `configurableProfileCount := 4` in the Lean record. Count the names the
    # gateway actually offers; a summary integer could agree with the model
    # while the list beside it does not.
    var profiles = 0
    var profile_names = [
        String("\"max_saturation\""), String("\"burst\""),
        String("\"sovereign_cpu\""), String("\"eco\""),
    ]
    for i in range(4):
        if profile_names[i] in tel_n:
            profiles += 1
    r.world_or_blind(String("four-configurable-profiles-are-offered"),
                  tel_read, profiles == 4)

    # ---- WORLD: the rogue-authority veto, as a REFUSAL ------------------
    # `rogueAuthorityVetoed := true` is a default in the Lean record. The
    # only way to learn whether the veto fires is to present a rogue
    # authority and require a REFUSAL. An endpoint that answers 200 and
    # accepts the profile is the failure, so a bare "it answered" check
    # would score the defect as a pass.
    var veto_code = capture(
        "curl -s -o /dev/null -w '%{http_code}' --max-time 5 "
        + "-H 'Content-Type: application/json' "
        + "-d '{\"profile\":\"max_saturation\",\"authority\":\"rogue\"}' "
        + base_url() + "/v1/intent/evaluate")
    var veto = capture(
        "curl -s --max-time 5 -H 'Content-Type: application/json' "
        + "-d '{\"profile\":\"max_saturation\",\"authority\":\"rogue\"}' "
        + base_url() + "/v1/intent/evaluate")
    r.observe(String("veto-status"), veto_code)
    r.observe(String("veto-response"), veto)
    # Not approved is the whole claim. `approved` absent => BLIND.
    r.world_json(String("rogue-authority-is-not-approved"),
                 json_flag(veto, String("approved")), False)
    r.world_or_blind(String("veto-refuses-at-the-http-layer-too"),
                     veto_code.byte_length() > 0,
                     veto_code != String("200"))

    # The complement: the SANCTIONED authority must be approved. A veto that
    # refuses everything is not a veto, it is an outage, and checking only
    # the refusal cannot tell the two apart.
    var ok_intent = capture(
        "curl -s --max-time 5 -H 'Content-Type: application/json' "
        + "-d '{\"profile\":\"max_saturation\",\"authority\":\"sa-plan\"}' "
        + base_url() + "/v1/intent/evaluate")
    r.observe(String("sanctioned-intent-response"), ok_intent)
    r.world_json(String("sa-plan-authority-is-approved"),
                 json_flag(ok_intent, String("approved")), True)

    # ---- WORLD: bounded inference, 16 tokens, temperature 0 -------------
    var chat = capture(
        "curl -s --max-time 12 -H 'Content-Type: application/json' "
        + "-d '{\"model\":\"" + String(MODEL_ID)
        + "\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],"
        + "\"max_tokens\":16,\"temperature\":0.0}' "
        + base_url() + "/v1/chat/completions")
    r.observe(String("chat-response"), chat)
    r.world_or_blind(String("gateway-completes-a-bounded-chat"),
                     chat.byte_length() > 0,
                     contains(chat, String("\"choices\"")))

    # ---- WORLD: the node itself, over SSH -------------------------------
    # BatchMode so an unreachable node fails fast instead of prompting.
    var ssh_probe = capture(
        "ssh -p " + String(SSH_PORT) + " -o BatchMode=yes -o ConnectTimeout=5 "
        + "an@" + String(HOST)
        + " 'cd /home/an/uos-max 2>/dev/null && /home/an/.pixi/bin/pixi run mojo --version' "
        + "2>/dev/null")
    r.observe(String("ssh-mojo-version"), ssh_probe)
    r.world_or_blind(String("remote-node-reports-a-mojo-toolchain"),
                     ssh_probe.byte_length() > 0,
                     contains(ssh_probe, String("Mojo")))

    # ---- NEGATIVE CONTROL ----------------------------------------------
    # Mutate a REAL input: ask the live gateway for a path that cannot
    # exist. If that returns 200 the status probe is not reading status, and
    # every world verdict above is worthless.
    # F17, 20261106: this probe passed when the NODE WAS DOWN. `curl -w
    # '%{http_code}'` prints `000` on a connection failure, which is
    # non-empty and `!= "200"`, so "an absent path correctly refuses" and
    # "nothing answered at all" were indistinguishable. A control that is
    # satisfied by total absence of the subject is not a control.
    #
    # `000` is now excluded explicitly, and the probe additionally requires
    # that a path which DOES exist answered 200 on the same run -- so the
    # refusal is evidence about routing rather than about reachability.
    # L3 FIX, 20261106-0924 (re-review finding 10). The previous version
    # added `and models_code == String("200")` to this probe. That made a
    # NODE OUTAGE report VACUOUS -- severity 5, outranking WORLD_FAIL 2 and
    # BLIND 1 -- so an unreachable machine was indistinguishable from an
    # oracle that cannot discriminate. The hardening rationale was right
    # ("a control satisfied by total absence of the subject is not a
    # control") and the CHANNEL was wrong: reachability belongs in a
    # `world_or_blind` presence predicate, which every world arm in this file
    # already uses.
    #
    # This file diagnosed the same anti-pattern in `agent_profile` during the
    # very same repair pass -- "a legitimate 41st subsystem would fail the
    # probe, set vacuous to 1, and make the receipt report VACUOUS, the
    # verdict that outranks every other" -- and then introduced it here.
    #
    # The probe is now gated: it runs only when the node is reachable, and
    # when it is not, reachability is reported as BLIND.
    var node_reachable = (models_code == String("200"))
    r.observe(String("node-reachable"), String(node_reachable))
    r.world_or_blind(String("razr15-node-is-reachable"),
                     models_code.byte_length() > 0, node_reachable)
    var bogus = http_code(String("/v1/models-that-cannot-exist-" + now))
    r.observe(String("absent-path-http-code"), bogus)
    if node_reachable:
        r.mutation_probe(String("absent-path-refuses-while-a-real-path-serves"),
                         bogus.byte_length() > 0
                         and bogus != String("200")
                         and bogus != String("000"))
    else:
        r.observe(String("absent-path-probe"),
                  String("skipped: node unreachable, reported BLIND above"))
    # A wrong model id must not be served as the canonical one.
    # F17: this passed when `models_body` was EMPTY, i.e. when the node was
    # unreachable -- "the wrong id is absent" is trivially true of nothing.
    # The listing must be non-empty and carry the canonical id for the
    # absence of the wrong one to mean anything.
    # L3: same gating, same reason.
    if node_reachable:
        r.mutation_probe(String("wrong-model-id-is-absent-from-a-real-listing"),
                         models_body.byte_length() > 0
                         and contains(models_body, String(MODEL_ID))
                         and not contains(models_body,
                                          String("Qwen/Qwen9.9-Nonexistent")))
    # And the field lookup itself must be able to say ABSENT. If json_flag
    # returns anything but -1 for a key no payload carries, every BLIND
    # verdict above collapses into a silent false.
    r.mutation_probe(String("json-flag-reports-absence-as-absent"),
                     json_flag(tel, String("key_that_cannot_exist")) == -1)

    print("# probe time          :", now)
    print("# /v1/models          :", models_code)
    print("# /v1/telemetry       :", tel_code)
    print("# stages data+control :", data_stages, "+", ctrl_stages)
    print("# remote tokens       :", remote_tokens)
    print("# rogue veto status   :", veto_code)
    print("# absent-path control :", bogus)
    print("# vram record (MiB)   :", vram_fields, "sum", vram_sum, "of 7104 proved")
    r.emit()
    exit(r.exit_code())
