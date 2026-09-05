(* Fractal diagnostics for the wiki plane — see wiki_diagnostics.mli.
   Every constructor below is Blocks_credit or No_effect, and no origin
   is Implementation: the R5 law, held by what this file can build. *)

open Fractal_diagnostic

type finding =
  | Dead_link of { source : string; target : string }
  | Ambiguous_ref of { source : string; target : string }
  | Dead_anchor of { source : string; target : string; anchor : string }
  | Schema_gap of { page : string; field : string }
  | Drifted_render of { page : string }
  | Stale_declaration of { row : string }
  | Grounded_anomaly of { claim : string }
  | Orphan of { page : string }
  | Unported_mirror of { module_ : string; row : string }
  | Ratchet_breach of { gauge : string; previous : int; current : int }
  | Journal_violation of { file : string; detail : string }
  | Term_gap of { page : string; term : string }
  | Index_violation of { page : string; target : string }
  | Corpus_defect of { detail : string }
  | Include_gap of { page : string; path : string; reason : string }
  | Toc_gap of { page : string; target : string }

let diagnose = function
  (* L2: a document's linking capability is broken. Specification origin:
     the document says something about the corpus that is not so. *)
  | Dead_link { source; target } ->
      make ~level:L2_capability ~origin:Specification ~impact:Blocks_credit
        ~node:"corpus/links" ~subject:source
        ~message:(Printf.sprintf "dead link: %s -> %s" source target)
        ~cause:"the referenced page does not exist under any resolver key"
        ~fix:"create the target, correct the reference, or record it as a deliberate example link"
        ()
  (* L2, beside Dead_link: the linking capability again, but the OPPOSITE
     failure — too many targets rather than none. The reader is shown one
     of several candidates with no signal (HW.3.7.2). *)
  | Ambiguous_ref { source; target } ->
      make ~level:L2_capability ~origin:Specification ~impact:Blocks_credit
        ~node:"corpus/links" ~subject:source
        ~message:(Printf.sprintf "ambiguous reference: %s -> %s" source target)
        ~cause:"several pages claim this key at one precedence tier, so resolution is corpus-order luck"
        ~fix:"disambiguate the reference (full slug or doc: role), or retitle/realias one claimant"
        ()
  (* L3: the document asserted a CONTRACT about a section that is not
     kept — a finer failure than a dead link, which is why it is separate. *)
  | Dead_anchor { source; target; anchor } ->
      make ~level:L3_contract ~origin:Specification ~impact:Blocks_credit
        ~node:"corpus/anchors" ~subject:source
        ~message:(Printf.sprintf "dead anchor: %s -> %s#%s" source target anchor)
        ~cause:"the target page exists but carries no such heading or ^block anchor"
        ~fix:"add the heading or ^id in the target, or point the reference at one that exists"
        ()
  (* L2: the page's own metadata capability is incomplete. *)
  | Schema_gap { page; field } ->
      make ~level:L2_capability ~origin:Specification ~impact:Blocks_credit
        ~node:"corpus/schema" ~subject:page
        ~message:(Printf.sprintf "schema gap: %s lacks %s" page field)
        ~cause:"the PKM schema requires this field of every document (spec section 3)"
        ~fix:"run schema_backfill for an evidence-based proposal, or author the field"
        ()
  (* L5: a rendered trace no longer matches its pinned receipt. *)
  | Drifted_render { page } ->
      make ~level:L5_trace ~origin:Evidence ~impact:Blocks_credit ~node:"corpus/render"
        ~subject:page
        ~message:(Printf.sprintf "render drifted: %s" page)
        ~cause:"the rendered bytes differ from the pinned baseline and the source is unchanged"
        ~fix:"explain the drift in both directions, then re-pin deliberately if intended"
        ()
  (* LX: the REGISTER disagreed with the system — a control-plane fact,
     never a corpus finding (R9). *)
  | Stale_declaration { row } ->
      make ~level:LX_control ~origin:Control ~impact:Blocks_credit ~node:"control/register"
        ~subject:row
        ~message:(Printf.sprintf "stale declaration: %s" row)
        ~cause:"the row declares a readiness its live probe contradicts"
        ~fix:"fix the feature or correct the declaration; the probe is what decides"
        ()
  (* L1: a family of claims failed to stand together. *)
  | Grounded_anomaly { claim } ->
      make ~level:L1_family ~origin:Specification ~impact:No_effect ~node:"corpus/discourse"
        ~subject:claim
        ~message:(Printf.sprintf "claim outside the grounded extension: %s" claim)
        ~cause:"an @opposes attack on this claim is undefended in the argumentation frame"
        ~fix:"defend the claim, retract it, or record the opposition as accepted"
        ()
  (* L0: a corpus-wide navigability fact, informational by design. *)
  | Orphan { page } ->
      make ~level:L0_product ~origin:Specification ~impact:No_effect ~node:"corpus/navigation"
        ~subject:page
        ~message:(Printf.sprintf "orphan: %s has no inbound link" page)
        ~cause:"no document links here, so a reader can only arrive by search or URL"
        ~fix:"link it from a MoC or hub, or accept it as a deliberate entry point"
        ()
  (* LX: a reuse-backlog fact about the system's own construction. *)
  | Unported_mirror { module_; row } ->
      make ~level:LX_control ~origin:Control ~impact:No_effect ~node:"control/imports"
        ~subject:module_
        ~message:(Printf.sprintf "mirror awaiting its port: %s (row %s)" module_ row)
        ~cause:"the module is imported as a reference and its register row is not yet Built"
        ~fix:"port it under that row, or reclassify it honestly as operational or superseded"
        ()
  (* LX: the control mechanism itself refused. *)
  | Ratchet_breach { gauge; previous; current } ->
      make ~level:LX_control ~origin:Control ~impact:Blocks_credit ~node:"control/ratchet"
        ~subject:gauge
        ~message:(Printf.sprintf "ratchet breached: %s %d -> %d" gauge previous current)
        ~cause:"a monitored count increased, and the ratchet permits only decreases"
        ~fix:"reduce the count, or re-pin deliberately with the increase explained"
        ()
  (* L4: a fixture — the journal file — violated its own append-only law. *)
  | Journal_violation { file; detail } ->
      make ~level:L4_fixture ~origin:Evidence ~impact:Blocks_credit ~node:"corpus/journal"
        ~subject:file
        ~message:(Printf.sprintf "journal integrity: %s (%s)" file detail)
        ~cause:"a journal is append-only and R16-named; this file broke one of those"
        ~fix:"restore the prefix and append instead, or rename to the dated form"
        ()
  (* L2: the vocabulary capability — a term referenced, defined nowhere. *)
  | Term_gap { page; term } ->
      make ~level:L2_capability ~origin:Specification ~impact:Blocks_credit
        ~node:"corpus/glossary" ~subject:page
        ~message:(Printf.sprintf "term used and undefined: %s in %s" term page)
        ~cause:"no glossary page (topics: [glossary]) carries a heading defining this term"
        ~fix:"define the term in the glossary, or correct the [[term:...]] reference"
        ()
  (* L3: a see-entry asserted a CONTRACT about another entry that is not kept. *)
  | Index_violation { page; target } ->
      make ~level:L3_contract ~origin:Specification ~impact:Blocks_credit
        ~node:"corpus/index" ~subject:page
        ~message:(Printf.sprintf "index see-target missing: -> %s in %s" target page)
        ~cause:"the see-entry redirects to an index term no entry defines"
        ~fix:"author the target entry at its point of relevance, or retarget the see"
        ()
  (* L4: an include's SOURCE FILE is the fixture the document quotes, and
     the fixture could not be read or sliced. Evidence origin: the
     reference moved, the document did not. *)
  | Include_gap { page; path; reason } ->
      make ~level:L4_fixture ~origin:Evidence ~impact:Blocks_credit ~node:"corpus/includes"
        ~subject:page
        ~message:(Printf.sprintf "include unresolved: %s in %s (%s)" path page reason)
        ~cause:"the quoted source file or its marker region no longer exists as addressed"
        ~fix:"repoint the path, restore the marker, or quote a region that still exists"
        ()
  (* L2: the navigation capability — a declared edge that could not be
     made. The declaration is the contract; the target did not keep it. *)
  | Toc_gap { page; target } ->
      make ~level:L2_capability ~origin:Specification ~impact:Blocks_credit
        ~node:"corpus/navigation" ~subject:page
        ~message:(Printf.sprintf "toc declaration unresolved: %s in %s" target page)
        ~cause:"the declared navigation target resolves to no page under any resolver key"
        ~fix:"correct the target, or remove the declaration if the page is gone"
        ()
  (* L0: the corpus itself is structurally wrong — the render gate refuses. *)
  | Corpus_defect { detail } ->
      make ~level:L0_product ~origin:Specification ~impact:Blocks_credit
        ~node:"corpus/integrity" ~subject:detail
        ~message:(Printf.sprintf "corpus defect: %s" detail)
        ~cause:"a duplicate slug, unknown discourse type, or duplicate block anchor"
        ~fix:"repair the document the defect names; the render driver refuses until then"
        ()

let all_findings_sample =
  [ Dead_link { source = "a"; target = "b" };
    Ambiguous_ref { source = "a"; target = "b" };
    Dead_anchor { source = "a"; target = "b"; anchor = "s" };
    Schema_gap { page = "a"; field = "ktype" };
    Drifted_render { page = "a" };
    Stale_declaration { row = "HW.1.1.1" };
    Grounded_anomaly { claim = "c" };
    Orphan { page = "p" };
    Unported_mirror { module_ = "m"; row = "HW.1.1.1" };
    Ratchet_breach { gauge = "g"; previous = 0; current = 1 };
    Journal_violation { file = "f.md"; detail = "d" };
    Term_gap { page = "p"; term = "quirk" };
    Index_violation { page = "p"; target = "t" };
    Corpus_defect { detail = "duplicate slug: x" };
    Include_gap { page = "p"; path = "src/a.ml"; reason = "cannot read" };
    Toc_gap { page = "p"; target = "ghost" } ]

let to_otel ~ts (d : t) =
  let severity =
    match d.impact with
    | Denies_credit | Blocks_credit -> Wiki_otel.Warn
    | No_effect -> Wiki_otel.Info
  in
  Wiki_otel.record ~ts ~severity ~body:d.message
    ~attrs:
      [ ("fractal.level", level_name d.level);
        ("fractal.origin", origin_name d.origin);
        ("fractal.impact", effect_name d.impact);
        ("fractal.node", d.node);
        ("subject", d.subject);
        ("cause", d.cause);
        ("fix", d.fix) ]
