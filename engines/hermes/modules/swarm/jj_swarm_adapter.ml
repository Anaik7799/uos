(* Compatibility quarantine only. Direct Swarm-to-Jujutsu adaptation is
   forbidden; Run_swarm_bridge is the sole future execution boundary. *)

type unavailable = {
  code : string;
  lifecycle : string;
}

let status () =
  { code = "jj.direct-swarm-adapter-quarantined";
    lifecycle = "Unavailable_observed" }
