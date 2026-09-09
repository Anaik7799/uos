(* Bounded, effect-free expression algebra used only for synthetic repair cases.
   @agent_intent: Parse a small language fragment before any native interpretation.
   @laws: recursive and compiled observations agree; unknown identifiers/tokens,
   overlarge terms and ill-typed operations are rejected before native execution. *)
type language = Gleam | Ocaml | Mojo | Quint
type value = Number of int | Boolean of bool
type op = Add | Sub | Eq | Ne | Lt | Le | Gt | Ge | And | Or | Min | Max
type term = Constant of value | Variable of string | Not of term | Binary of op * term * term
type token = Name of string | Integer of int | Symbol of string
exception Invalid of string
let reject message = raise (Invalid message)
let require condition message = if not condition then reject message
let valid_name_char = function 'a'..'z'|'A'..'Z'|'_' -> true | _ -> false
let tokenize language source =
  require (String.length source > 0 && String.length source <= 1024) "expression byte bound";
  let n=String.length source in
  let rec scan i acc =
    require(List.length acc <= 256) "expression token bound";
    if i=n then List.rev acc else match source.[i] with
    | ' '| '\t'|'\r'|'\n' -> scan(i+1)acc
    | '0'..'9' ->
      let j=ref(i+1) in while !j<n && source.[!j]>='0' && source.[!j]<='9' do incr j done;
      require(!j-i<=4) "integer literal bound";
      let value=int_of_string(String.sub source i (!j-i)) in
      require(value<=1000) "integer literal bound";scan !j (Integer value::acc)
    | c when valid_name_char c ->
      let j=ref(i+1) in while !j<n && valid_name_char source.[!j] do incr j done;
      scan !j(Name(String.sub source i (!j-i))::acc)
    | '{'|'}' as c -> require(language=Gleam) "braces only group Gleam expressions";scan(i+1)(Symbol(String.make 1 c)::acc)
    | '('|')' as c -> require(language<>Gleam) "Gleam groups expressions with braces";scan(i+1)(Symbol(String.make 1 c)::acc)
    | ',' -> require(language=Mojo) "only Mojo min/max calls accept comma";scan(i+1)(Symbol ","::acc)
    | '+'|'-' -> scan(i+1)(Symbol(String.make 1 source.[i])::acc)
    | '='|'!'|'<'|'>'|'&'|'|' ->
      let two=if i+1<n then String.sub source i 2 else "" in
      if List.mem two ["==";"!=";"<>";"<=";">=";"&&";"||"] then scan(i+2)(Symbol two::acc)
      else scan(i+1)(Symbol(String.make 1 source.[i])::acc)
    | _ -> reject "unsupported character: expressions cannot contain strings, imports or effects"
  in scan 0 []

let binary language = function
 | Symbol "+" -> Some(5,Add) | Symbol "-" -> Some(5,Sub)
 | Symbol "<" -> Some(4,Lt) | Symbol "<=" -> Some(4,Le)
 | Symbol ">" -> Some(4,Gt) | Symbol ">=" -> Some(4,Ge)
 | Symbol "=" when language=Ocaml -> Some(3,Eq)
 | Symbol "<>" when language=Ocaml -> Some(3,Ne)
 | Symbol "==" when language<>Ocaml -> Some(3,Eq)
 | Symbol "!=" when language<>Ocaml -> Some(3,Ne)
 | Symbol "&&" when language=Gleam || language=Ocaml -> Some(2,And)
 | Symbol "||" when language=Gleam || language=Ocaml -> Some(1,Or)
 | Name "and" when language=Mojo || language=Quint -> Some(2,And)
 | Name "or" when language=Mojo || language=Quint -> Some(1,Or)
 | _ -> None

let parse language variables source =
 let nodes=ref 0 in
 let make depth term = incr nodes;require(!nodes<=128 && depth<=20) "expression depth/node bound";term in
 let rec expression depth minimum tokens =
  let lhs,remaining=atom(depth+1)tokens in continue depth minimum lhs remaining
 and continue depth minimum lhs tokens = match tokens with
  | tok::tail -> (match binary language tok with
    | Some(precedence,operator) when precedence>=minimum ->
      let rhs,rest=expression(depth+1)(precedence+1)tail in
      continue depth minimum (make depth(Binary(operator,lhs,rhs)))rest
    | _ -> lhs,tokens)
  | [] -> lhs,[]
 and atom depth = function
  | Integer value::rest -> make depth(Constant(Number value)),rest
  | Name name::rest when List.mem name variables -> make depth(Variable name),rest
  | Name("true" as name)::rest | Name("false" as name)::rest when language=Ocaml || language=Quint ->
    make depth(Constant(Boolean(name="true"))),rest
  | Name("True" as name)::rest | Name("False" as name)::rest when language=Gleam || language=Mojo ->
    make depth(Constant(Boolean(name="True"))),rest
  | Symbol "!"::rest when language=Gleam -> let child,tail=atom(depth+1)rest in make depth(Not child),tail
  | Name "not"::rest when language<>Gleam -> let child,tail=atom(depth+1)rest in make depth(Not child),tail
  | Symbol "-"::Integer value::rest -> make depth(Constant(Number(-value))),rest
  | Symbol opening::rest when opening="(" || opening="{" ->
    let child,tail=expression(depth+1)0 rest in
    let closing=if opening="(" then ")" else "}" in
    (match tail with Symbol c::remaining when c=closing -> child,remaining | _ -> reject "unclosed expression group")
  | Name name::Symbol "("::rest when language=Mojo && (name="min" || name="max") ->
    let a,tail=expression(depth+1)0 rest in
    (match tail with Symbol ","::remaining ->
      let b,last=expression(depth+1)0 remaining in
      (match last with Symbol ")"::ending -> make depth(Binary((if name="min" then Min else Max),a,b)),ending
      | _ -> reject "min/max requires two arguments")
    | _ -> reject "min/max requires two arguments")
  | _ -> reject "invalid or unknown expression atom"
 in
 let result,rest=expression 0 0 (tokenize language source) in
 require(rest=[]) "trailing expression tokens";
 let rec term_depth=function Constant _|Variable _->1|Not child->1+term_depth child|Binary(_,a,b)->1+max(term_depth a)(term_depth b) in
 require(term_depth result<=20) "expression AST depth bound";result

let same a b = match a,b with
 | Number x,Number y -> x=y | Boolean x,Boolean y -> x=y | _ -> false
let number = function Number n -> n | Boolean _ -> reject "expected integer"
let boolean = function Boolean b -> b | Number _ -> reject "expected Boolean"
let apply operator a b = match operator with
 | Add -> Number(number a+number b) | Sub -> Number(number a-number b)
 | Min -> Number(min(number a)(number b)) | Max -> Number(max(number a)(number b))
 | Eq -> require((match a,b with Number _,Number _|Boolean _,Boolean _->true|_->false)) "equality type mismatch";Boolean(same a b)
 | Ne -> require((match a,b with Number _,Number _|Boolean _,Boolean _->true|_->false)) "inequality type mismatch";Boolean(not(same a b))
 | Lt -> Boolean(number a<number b) | Le -> Boolean(number a<=number b)
 | Gt -> Boolean(number a>number b) | Ge -> Boolean(number a>=number b)
 | And -> Boolean(boolean a && boolean b) | Or -> Boolean(boolean a || boolean b)
let lookup environment name = try List.assoc name environment with Not_found -> reject "missing variable"
let rec observe environment = function
 | Constant value -> value | Variable name -> lookup environment name
 | Not child -> Boolean(not(boolean(observe environment child)))
 | Binary(operator,a,b) -> apply operator (observe environment a)(observe environment b)
let rec compile = function
 | Constant value -> (fun _ -> value)
 | Variable name -> (fun environment -> lookup environment name)
 | Not child -> let f=compile child in fun environment -> Boolean(not(boolean(f environment)))
 | Binary(operator,a,b) -> let left=compile a and right=compile b in fun environment -> apply operator(left environment)(right environment)
let json_value = function Number n -> `Int n | Boolean b -> `Bool b

(* Render only the admitted AST, never interpolate unparsed model bytes. *)
let rec render language = function
 | Constant(Number n) -> if n<0 then (if language=Gleam then "{" else "(")^string_of_int n^(if language=Gleam then "}" else ")") else string_of_int n
 | Constant(Boolean b) -> if language=Gleam || language=Mojo then (if b then "True" else "False") else string_of_bool b
 | Variable name -> name
 | Not child -> (if language=Gleam then "!{" else "not (")^render language child^(if language=Gleam then "}" else ")")
 | Binary((Min|Max as operator),a,b) ->
   require(language=Mojo) "min/max target mismatch";
   (if operator=Min then "min" else "max")^"("^render language a^", "^render language b^")"
 | Binary(operator,a,b) ->
   let symbol=match operator with
   | Add->"+"|Sub->"-"|Eq->if language=Ocaml then "=" else "=="
   | Ne->if language=Ocaml then "<>" else "!="|Lt->"<"|Le->"<="|Gt->">"|Ge->">="
   | And->if language=Gleam || language=Ocaml then "&&" else "and"
   | Or->if language=Gleam || language=Ocaml then "||" else "or"
   | Min|Max->reject "handled min/max" in
   (if language=Gleam then "{" else "(")^render language a^" "^symbol^" "^render language b^(if language=Gleam then "}" else ")")
