
(** Bounded DEVELOPMENT-only interpreter. No production owner, issuer, signer,
    general SQL callback or raw SQLite handle is exported. Both operations
    restrict locators to private /tmp/uos-control-private-* fixtures. Expected
    hashes/identities and cryptographic configuration remain caller DATA.
    Public production Store/port/owner defaults remain unchanged and HOLD.
    Fresh exclusive process, fixed trusted callee and cooperative namespace
    premises of reviewed writable VFS42 apply. History may rebuild SHM cache;
    no task/receipt append occurs in historical interpretation. *)
type observation = { reply:string; diagnostics:Yojson.Safe.t }
(** Prepare ONLY the exact additional receipt namespaces on a populated,
    existing v7 synthetic Store. Owned transaction, fixed-plan bounded snapshot
    projection conservation, exact schema/readback. Ambiguous commit/cleanup
    returns UNKNOWN; no whole-v7-database conservation or migration authority. *)
val prepare_private_existing_v7 : database:string -> (string,string) result
(** One bounded commit or history request on one retained main/WAL/SHM session.
    All temporary checker/resource handles close before bound open; no native
    callback/clock parameter is accepted. Unknown cleanup requires worker exit,
    and cannot authorize retry. Replies have authority NONE and admitted=false. *)
val handle_private_data : locator:string -> request:string -> (observation,string) result
