(* Compatibility quarantine only. This module is intentionally absent from the
   production Dune denominator. Jujutsu execution remains unavailable until a
   closed typed activity is admitted through Run_swarm_bridge. *)

type unavailable = {
  code : string;
  lifecycle : string;
  reason : string;
}

let unavailable_observed =
  { code = "jj.bridge-activity-unavailable";
    lifecycle = "Unavailable_observed";
    reason =
      "No controlled typed OCaml Jujutsu activity is admitted by Run_swarm_bridge" }

let status () = unavailable_observed
