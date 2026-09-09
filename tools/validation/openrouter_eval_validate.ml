(* Independent validators. Golden answers are test fixtures only and are never
   read by this implementation. Strict parsing never strips markdown or repairs
   model output. A semantic pass is distinct from an unrun native interpreter. *)
open Openrouter_eval_expr
open Openrouter_eval_catalog
type check = {law:string;passed:bool;detail:string}
type parsed = Expression of term | Proof of string | Structured
type validation = {checks:check list;fragment:parsed}
let check law passed detail={law;passed;detail}
let object_fields = function `Assoc fields->fields|_->reject "JSON object required"
let keys required object_ =
 let fields=object_fields object_ in
 require(List.sort String.compare(List.map fst fields)=List.sort String.compare required) "unknown, duplicate or missing JSON fields";fields
let field name object_ = try List.assoc name (object_fields object_) with Not_found->reject("missing "^name)
let string = function `String x->x|_->reject "JSON string required"
let integer = function `Int x->x|_->reject "bounded JSON integer required"
let bool = function `Bool x->x|_->reject "JSON Boolean required"
let array = function `List xs->xs|_->reject "JSON array required"
let rec depth n value =
 require(n<=12) "JSON depth bound";
 match value with
 | `Assoc fields -> require(List.length fields<=32) "object field bound";List.iter(fun(_,v)->depth(n+1)v)fields
 | `List xs -> require(List.length xs<=64) "JSON array bound";List.iter(depth(n+1))xs
 | `String text -> require(String.length text<=2048) "JSON string byte bound"
 | `Int n -> require(n>= -1000000 && n<=1000000) "JSON integer bound"
 | `Bool _|`Null -> ()
 | `Float _|`Intlit _|`Tuple _|`Variant _ -> reject "unsupported JSON value type"
let parse_answer c bytes =
 require(String.length bytes>0 && String.length bytes<=16384) "answer byte bound";
 let json=try Yojson.Safe.from_string bytes with Yojson.Json_error _->reject "invalid JSON; no markdown repair" in
 depth 0 json;
 ignore(keys["schema_version";"case_id";"solution"]json);
 require(integer(field "schema_version" json)=1) "unsupported answer schema";
 require(string(field "case_id" json)=c.id) "answer case_id mismatch";
 field "solution" json
let solution_fields c = match c.domain with
 | Gleam_case|Ocaml_case|Mojo_case|Quint_case->["expression"]|Lean_case->["proof"]
 | Stm_case->["committed";"version";"value"]|Bayesian_case->["alpha";"beta";"mean_num";"mean_den";"ignored"]
 | Rete_case->["before";"after"]|Stpa_case->["ucas";"execute";"authority"]|Fmea_case->["rows";"selected";"blocked";"effect_authority"]

let normalize_proof proof =
 require(String.length proof<=128) "proof byte bound";
 let words=String.split_on_char ' ' (String.map(function '\n'|'\r'|'\t'->' '|c->c)proof)|>List.filter((<>)"") in
 let normalized=String.concat " " words in
 require(List.mem normalized["by omega";"by rfl";"by assumption";"by simp [same]"]) "proof outside the fixed tactic grammar";
 normalized
let pairs json =
 let result=array json |> List.map(function `List[`String a;`String b]->require(List.mem a["a";"b";"c";"d";"e";"x"] && List.mem b["a";"b";"c";"d";"e";"x"])"unknown fact symbol";a,b|_->reject "pair must contain two symbol strings") in
 require(List.sort_uniq compare result=result) "pair list must be sorted with no duplicates";result
let facts=["p1","a","b";"p2","b","c";"p3","a","d";"p4","d","e";"p5","x","b"]
let join rows = List.concat_map(fun(_,x,y)->List.filter_map(fun(_,y2,z)->if y=y2 && x<>z then Some(x,z)else None)rows)rows |> List.sort_uniq compare
let stpa_classes=["A","not_provided";"B","provided_unsafe";"C","wrong_timing";"D","duration"]
let fmea_modes=["unsafe_effect",5,1,1,0,true;"stale_price",4,3,4,1,false;"cosmetic",2,5,5,3,true]
let validate c bytes =
 let solution=parse_answer c bytes in ignore(keys(solution_fields c)solution);
 let checks,fragment=match language c.domain with
 | Some language ->
   let expression=field "expression" solution |> string |> parse language (variables c.domain) in
   let compiled=compile expression in
   let checks=samples c |> List.mapi(fun index (environment,expected)->
     let observed=observe environment expression and optimized=compiled environment in
     require(same observed optimized) "oracle/compiled expression disagreement";
     check("behavior-"^string_of_int index)(same observed expected)
      (Yojson.Safe.to_string(`Assoc["input",`Assoc(List.map(fun(k,v)->k,json_value v)environment);"expected",json_value expected;"observed",json_value observed]))) in
   checks,Expression expression
 | None -> (match c.domain with
   | Lean_case -> [check "proof-grammar" true "Native Lean kernel check still required"],Proof(normalize_proof(string(field "proof" solution)))
   | Stm_case ->
     let decisions,version,value=List.fold_left(fun(acc,version,value)(expected,write)->if expected=version then true::acc,version+1,write else false::acc,version,value)([],4,10)[4,11;4,99;5,12;5,13;6,14] in
     [check "cas-decisions" (List.map bool(array(field "committed" solution))=List.rev decisions) "Stale snapshots cannot commit";
      check "cas-final-state" (integer(field "version" solution)=version && integer(field "value" solution)=value) "Refused writes preserve both fields"],Structured
   | Bayesian_case ->
     let alpha,beta,ignored=List.fold_left(fun(a,b,i)->function `Pass->a+1,b,i|`Fail->a,b+1,i|`Unknown->a,b,i+1)(2,3,0)[`Pass;`Fail;`Pass;`Unknown;`Pass] in
     [check "beta-evidence" (integer(field "alpha" solution)=alpha && integer(field "beta" solution)=beta && integer(field "ignored" solution)=ignored) "Only verified outcomes update the posterior";
      check "beta-exact-mean" (integer(field "mean_num" solution)=alpha && integer(field "mean_den" solution)=alpha+beta) "Exact unreduced alpha/(alpha+beta)"],Structured
   | Rete_case -> [check "join-before" (pairs(field "before" solution)=join facts) "Relational join oracle";
       check "join-after-retraction" (pairs(field "after" solution)=join(List.filter(fun(id,_,_)->id<>"p2")facts)) "Removing a supporting fact removes its dependent matches"],Structured
   | Stpa_case ->
     let ucas=field "ucas" solution in ignore(keys["A";"B";"C";"D"]ucas);
     List.map(fun(id,expected)->check("uca-"^id)(string(field id ucas)=expected)expected)stpa_classes @
     [check "authority-fail-closed" (not(bool(field "execute" solution)) && string(field "authority" solution)="sa_plan") "Model advice grants no deployment authority"],Structured
   | Fmea_case ->
     let rows=array(field "rows" solution) in
     let ids=List.map(fun row->ignore(keys["id";"s";"o";"d";"rpn"]row);string(field "id" row))rows in
     require(List.sort String.compare ids=["cosmetic";"stale_price";"unsafe_effect"]) "exactly one row per FMEA mode required";
     let raw=List.map(fun(id,s,o,d,_,_)->
       let row=List.find(fun row->string(field "id" row)=id)rows in
       check("raw-fmea-"^id)(integer(field "s" row)=s && integer(field "o" row)=o && integer(field "d" row)=d && integer(field "rpn" row)=s*o*d)"Canonical raw1..5 ratings and product retained")fmea_modes in
     let ready=List.filter(fun(_,_,_,_,_,ready)->ready)fmea_modes |> List.sort(fun(_,s1,o1,d1,c1,_)(_,s2,o2,d2,c2,_)->let class_order=compare c1 c2 in if class_order<>0 then class_order else compare(s2*o2*d2)(s1*o1*d1)) in
     let selected=match ready with(id,_,_,_,_,_)::_->id|[]->"" in
     raw @ [check "dependency-hold" (List.map string(array(field "blocked" solution))=["stale_price"]) "Unready dependency is held";
       check "safety-before-rpn" (string(field "selected" solution)=selected) "Safety class precedes raw RPN";
       check "no-effect-authority" (not(bool(field "effect_authority" solution))) "A score is not dispatch authority"],Structured
   | Gleam_case|Ocaml_case|Mojo_case|Quint_case -> reject "language case missing its interpreter")
 in {checks;fragment}
let passed validation=List.for_all(fun c->c.passed)validation.checks
let checks_json checks=`List(List.map(fun c->`Assoc["law",`String c.law;"status",`String(if c.passed then "passed" else "failed");"detail",`String c.detail])checks)
