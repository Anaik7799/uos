(* HW.7.1.1 — design tokens to generated CSS. Ported from the imported
   `wiki_theme_token_injector` (R14 mirror), with its premise lifted: the
   import shipped the theme block as a compile-time CONSTANT and audited
   pages for coverage. A constant is safe but not reviewable — you cannot
   ask it where a colour came from.

   THE LAW. `css t` is a PURE function of the tokens, and **every
   declaration carries the token path it came from**, so a reviewer can
   trace any pixel back to its source without reading the generator. That
   annotation is the whole feature; the CSS is a by-product.

   THE HAND-EDIT DETECTOR. The output opens with a GENERATED banner and
   is a pure function of its input, so regenerating and byte-comparing
   detects any hand edit. That is the same differential shape the render
   baseline uses, one layer down.

   FAIL CLOSED, TWICE OVER:
   - A binding naming a token that does not exist is a NAMED error, never
     a silently dropped declaration — a missing colour that renders as
     "inherit" is the kind of wrong that looks fine.
   - A token VALUE reaching a stylesheet is author text at a syntax
     boundary. A value containing `;`, `{`, `}`, `<` or a comment opener
     could close the declaration and inject rules, so such a value is
     refused rather than escaped. Refusing is honest; escaping CSS by
     hand is a second parser to get wrong.

   MODES SHARE NAMES (HW.7.1.2's precondition): every theme must bind the
   SAME variable names, only rebinding their values. A theme that binds a
   name no other theme has produces a variable that is undefined in some
   mode, which is a bug that only appears to users who switched. *)

type token = {
  path : string;   (* "color/neutral/900" — the address, not the meaning *)
  value : string;  (* "#1a1a1a" *)
}

type theme = {
  mode : string;                       (* "light" | "dark" | a print mode *)
  bindings : (string * string) list;   (* css variable name -> token path *)
}

type error =
  | Unknown_token of { mode : string; variable : string; path : string }
  | Unsafe_value of { path : string; value : string }
  | Mode_name_mismatch of { mode : string; missing : string list }
  | Duplicate_token of { path : string }

(* Human-readable, one line, naming the artifact and the fix. *)
val describe : error -> string

(* Every problem, in a deterministic order. [] means [css] will succeed —
   the two are checked against each other by the suite, so a generator
   that emits despite an error cannot pass. *)
val check : tokens:token list -> themes:theme list -> error list

(* The stylesheet, or the reasons it cannot be generated. PURE and
   deterministic: token and theme order cannot change the output, because
   both are sorted before emission. *)
val css : tokens:token list -> themes:theme list -> (string, error list) result

(* The banner every generated stylesheet opens with. Exposed so a checker
   can recognise a generated file without re-deriving the string. *)
val banner : string
