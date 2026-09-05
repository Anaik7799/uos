(* The static site: one index hub reaching every component, use case,
   operational surface, KPI, wiki/ZK note, and analytic. Pure — the build
   is a function of the read model and the doc tree; writing is the
   driver's job (serve_site / render_site). *)

type t = {
  model : Web_read_model.t;
  wiki : Hermes_wiki.model;
  pages : (string * string) list;  (* filename -> html, deterministic order *)
}

val build : root:string -> t
