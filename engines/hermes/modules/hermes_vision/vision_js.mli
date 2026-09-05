(* JavaScript GENERATED from OCaml, never authored as JavaScript.

   R1 forbids authoring JS in this repository. A `{|...|}` blob of
   JavaScript inside an OCaml file obeys the letter of that and violates
   its point: it is still hand-written JavaScript, unchecked by any
   compiler, and a typo in it fails at runtime inside a browser where
   nothing here can see it.

   So the browser probe is built from a small typed expression algebra.
   The OCaml type system then rules out the errors that actually happen
   when emitting code by concatenation — an unescaped quote in a
   selector, a property name that is silently a free variable, a
   forgotten `return` — because those states are not constructible.

   This is the SMALL end of the same discipline as the wiki frontend,
   which compiles OCaml to `wiki_app.bc.js` with js_of_ocaml. Use
   js_of_ocaml when the browser-side logic is a program; use this when it
   is a single expression handed to `page.evaluate`, where dragging in a
   whole compilation unit would cost more than it protects. *)

type expr

(* literals — the only place a raw value enters, and each is escaped for
   its own context *)
val str : string -> expr
val int_ : int -> expr
val bool_ : bool -> expr
val raw_ident : string -> expr   (* a bare identifier: `document`, `v` *)

(* member access and calls. [field] escapes its name, so a property that
   is not a valid identifier still emits correctly as ["..."]. *)
val field : expr -> string -> expr
val call : expr -> string -> expr list -> expr
val obj : (string * expr) list -> expr
val arrow : string list -> expr -> expr        (* (a, b) => expr *)
val seq : expr list -> expr                    (* comma-sequenced *)
val ternary : expr -> expr -> expr -> expr

(* Rendered source. TOTAL: every [expr] renders, and the result needs no
   further quoting by the caller. *)
val render : expr -> string

(* The probe the browser oracle evaluates: collect one sample per
   COMPOSITED frame via requestVideoFrameCallback, then resolve with the
   element's own quality counters.

   [selector] is escaped, so a selector containing a quote cannot break
   out of the generated source — the browser-side equivalent of the argv
   discipline in Vision_intent. *)
val frame_probe : selector:string -> ms:int -> max_frames:int -> string

(* The page records ITSELF via MediaRecorder over captureStream() and
   POSTs the WebM to [post_to]. Needs no X server, no browser driver and
   no screen grab: captureStream taps the element's own decoded output,
   so what is recorded is what the browser actually painted. *)
val recorder : selector:string -> ms:int -> post_to:string -> string
