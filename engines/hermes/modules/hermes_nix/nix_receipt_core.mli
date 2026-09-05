(** Immutable cryptographic execution receipts for Nix and Devenv intents. *)

type verdict =
  | Success
  | Failed of Nix_error.t

type t = {
  receipt_id : Nix_id.Receipt_id.t;
  intent_id : Nix_id.Intent_id.t;
  timestamp : string;
  duration_ms : int;
  output_paths : Nix_id.Store_path.t list;
  closure_digest : Nix_id.Closure_digest.t option;
  summary : string;
  verdict : verdict;
}

val make :
  intent:Nix_intent.t ->
  duration_ms:int ->
  output_paths:Nix_id.Store_path.t list ->
  closure_digest:Nix_id.Closure_digest.t option ->
  summary:string ->
  verdict:verdict ->
  t

val is_success : t -> bool
val to_yojson : t -> Yojson.Safe.t
