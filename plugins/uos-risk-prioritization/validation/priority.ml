(* SC-RISK-PRIORITY-001: bounded, report-only ordering. No Store or runtime writes. *)
exception Invalid of string
let require ok why = if not ok then raise (Invalid why)
let rating n = require (n >= 1 && n <= 5) "rating outside 1..5"; n
let score xs =
  require (List.length xs = 5) "exactly five factors required";
  List.fold_left (fun acc n -> acc * rating n) 1 xs
let rpn s o det = rating s * rating o * rating det
let band n =
  require (n >= 1 && n <= 125) "RPN outside 1..125";
  if n <= 5 then 1 else if n <= 15 then 2 else if n <= 35 then 3
  else if n <= 70 then 4 else 5
let fmea s o det = max (rating s) (band (rpn s o det))
let class_number = function
  | "P0" -> 0 | "P1" -> 1 | "P2" -> 2 | "P3" -> 3
  | _ -> raise (Invalid "unknown safety class")
let valid_utc s =
  try
    require (String.length s = 20) "UTC must be YYYY-MM-DDTHH:MM:SSZ";
    List.iter (fun (i,c) -> require (s.[i] = c) "UTC separators")
      [4,'-';7,'-';10,'T';13,':';16,':';19,'Z'];
    let part pos len =
      let t = String.sub s pos len in
      String.iter (fun c -> require (c >= '0' && c <= '9') "UTC digits") t;
      int_of_string t
    in
    let y = part 0 4 and m = part 5 2 and d = part 8 2 in
    let h = part 11 2 and mi = part 14 2 and se = part 17 2 in
    let leap = y mod 4 = 0 && (y mod 100 <> 0 || y mod 400 = 0) in
    let days = match m with
      | 2 -> if leap then 29 else 28
      | 4|6|9|11 -> 30 | 1|3|5|7|8|10|12 -> 31 | _ -> 0
    in
    y >= 1 && d >= 1 && d <= days && h < 24 && mi < 60 && se < 60
  with Invalid _ | Failure _ | Invalid_argument _ -> false
let fresh ~now ~observed ~expires =
  require (valid_utc now && valid_utc observed && valid_utc expires) "invalid UTC";
  require (observed < expires) "expiry must follow observation";
  observed <= now && now < expires
type candidate = {
  id : string; class_ : string; own_score : int option; upper : int;
  state : string; readiness : string; dependencies : string list;
  observed : string; expires : string; ready_since : string;
}
type ranked = {
  task : candidate; effective_class : int; effective_score : int;
  origins : string list;
}
let rank ~now nodes =
  require (List.length nodes <= 1000) "portfolio exceeds 1000 records";
  require (List.fold_left (fun count n->count+List.length n.dependencies) 0 nodes<=10000)
    "portfolio exceeds 10000 dependency edges";
  let table = Hashtbl.create (List.length nodes) in
  List.iter (fun n ->
    require (n.id <> "" && not (Hashtbl.mem table n.id)) "duplicate/empty task ID";
    ignore (class_number n.class_);
    require (List.mem n.state ["available";"executing";"completed"]) "invalid task state";
    require (List.mem n.readiness ["ready";"blocked";"needs_evidence"]) "invalid readiness";
    require (n.upper >= 1 && n.upper <= 3125) "invalid score bound";
    Option.iter (fun s -> require (s >= 1 && s <= n.upper) "invalid point score") n.own_score;
    require (valid_utc n.ready_since) "invalid ready_since";
    ignore (fresh ~now ~observed:n.observed ~expires:n.expires);
    require (List.length n.dependencies = List.length (List.sort_uniq String.compare n.dependencies))
      "duplicate dependency";
    Hashtbl.add table n.id n) nodes;
  let get id = match Hashtbl.find_opt table id with
    | Some n -> n | None -> raise (Invalid ("missing dependency: " ^ id)) in
  let colors = Hashtbl.create (List.length nodes) in
  let rec visit id =
    match Hashtbl.find_opt colors id with
    | Some 1 -> raise (Invalid ("dependency cycle: " ^ id))
    | Some 2 -> ()
    | _ -> Hashtbl.replace colors id 1;
        List.iter visit (get id).dependencies;
        Hashtbl.replace colors id 2
  in
  List.iter (fun n -> visit n.id) nodes;
  let consumers = Hashtbl.create (List.length nodes) in
  List.iter (fun n ->
    if n.state <> "completed" then List.iter (fun dep ->
      let old = Option.value (Hashtbl.find_opt consumers dep) ~default:[] in
      Hashtbl.replace consumers dep (n.id::old)) n.dependencies) nodes;
  let urgency n =
    let seen = Hashtbl.create 16 in
    let rec gather id =
      if not (Hashtbl.mem seen id) then (
        Hashtbl.add seen id ();
        List.iter gather (Option.value (Hashtbl.find_opt consumers id) ~default:[]))
    in
    gather n.id;
    let related = Hashtbl.fold (fun id () acc -> get id :: acc) seen [] in
    let urgent_class = List.fold_left
      (fun c x -> min c (class_number x.class_)) 3 related in
    (* Only scores within the most urgent inherited class determine that class's order. *)
    let leaders = List.filter (fun x -> class_number x.class_ = urgent_class) related in
    let effective_score = List.fold_left (fun s x ->
      max s (Option.value x.own_score ~default:x.upper)) 1 leaders in
    { task=n; effective_class=urgent_class; effective_score;
      origins=List.map (fun x -> x.id) leaders |> List.sort_uniq String.compare }
  in
  let is_fresh n = fresh ~now ~observed:n.observed ~expires:n.expires in
  let eligible n =
    n.state = "available" && n.readiness = "ready" && n.own_score <> None &&
    is_fresh n && n.ready_since <= now && List.for_all (fun id ->
      let d = get id in d.state = "completed" && is_fresh d) n.dependencies
  in
  nodes |> List.filter eligible |> List.map urgency |> List.sort (fun a b ->
    let c = compare a.effective_class b.effective_class in if c <> 0 then c else
    let c = compare b.effective_score a.effective_score in if c <> 0 then c else
    let c = String.compare a.task.ready_since b.task.ready_since in if c <> 0 then c else
    String.compare a.task.id b.task.id)

let selftest () =
  let count = ref 0 in
  let check name value = incr count; require value ("selftest: " ^ name) in
  let rejects name f =
    check name (try f (); false with Invalid _ -> true) in
  check "minimum" (score [1;1;1;1;1] = 1);
  check "maximum" (score [5;5;5;5;5] = 3125);
  check "five-factor example" (score [3;4;4;5;4] = 960);
  rejects "zero rating" (fun () -> ignore (score [0;1;1;1;1]));
  rejects "oversize rating" (fun () -> ignore (score [6;1;1;1;1]));
  rejects "missing factor" (fun () -> ignore (score [1;1;1;1]));
  check "severe rare failure floor" (fmea 5 1 1 = 5);
  check "occurrence and detection raise band" (fmea 2 5 5 = 4);
  check "RPN is not normalized score" (rpn 4 3 3 = 36 && fmea 4 3 3 = 4);
  List.iter (fun (n,want) -> check ("band " ^ string_of_int n) (band n = want))
    [1,1;5,1;6,2;15,2;16,3;35,3;36,4;70,4;71,5;125,5];
  for s=1 to 5 do for o=1 to 5 do for d=1 to 5 do
    check "FMEA bounded/severity floor" (fmea s o d >= s && fmea s o d <= 5);
    if o < 5 then check "occurrence monotonic" (fmea s o d <= fmea s (o+1) d);
    if d < 5 then check "detection monotonic" (fmea s o d <= fmea s o (d+1))
  done done done;
  check "invalid date" (not (valid_utc "2026-02-30T12:00:00Z"));
  check "leap date" (valid_utc "2028-02-29T12:00:00Z");
  let now = "2026-09-07T16:00:00Z" in
  let n ?(class_="P2") ?(s=100) ?(state="available") ?(readiness="ready")
      ?(deps=[]) ?(expires="2026-09-08T00:00:00Z") id =
    {id;class_;own_score=Some s;upper=s;state;readiness;dependencies=deps;
     observed="2026-09-07T15:00:00Z";expires;ready_since="2026-09-07T15:00:00Z"}
  in
  let ids xs = List.map (fun x -> x.task.id) (rank ~now xs) in
  check "class defeats raw score"
    (ids [n ~class_:"P3" ~s:3125 "feature";n ~class_:"P1" "repair"] = ["repair";"feature"]);
  let prereq = n ~class_:"P3" ~s:1 "prereq" in
  let release = n ~class_:"P1" ~s:2000 ~readiness:"blocked" ~deps:["prereq"] "release" in
  let ranked = rank ~now [prereq;release;n ~s:1000 "other"] in
  check "prerequisite inherits; release remains blocked"
    (List.map (fun x->x.task.id) ranked = ["prereq";"other"]);
  check "inheritance has provenance"
    ((List.hd ranked).effective_class = 1 &&
     (List.hd ranked).effective_score = 2000 &&
     (List.hd ranked).origins = ["release"]);
  check "finished dependency permits consumer"
    (ids [n ~state:"completed" "dep";n ~deps:["dep"] "consumer"] = ["consumer"]);
  check "executing not reselected" (ids [n ~state:"executing" "busy"] = []);
  check "expired at exact boundary" (ids [n ~expires:now "stale"] = []);
  check "future ready time excluded"
    (ids [{(n "future") with ready_since="2026-09-08T00:00:00Z"}] = []);
  check "unknown blocks clearance" (ids [{(n "unknown") with own_score=None}] = []);
  check "blocked score is ineligible" (ids [n ~readiness:"blocked" ~s:3125 "blocked"] = []);
  check "stable ID tie" (ids [n "b";n "a"] = ["a";"b"]);
  check "oldest ready breaks tie"
    (ids [n "a";{(n "z") with ready_since="2026-09-07T14:00:00Z"}] = ["z";"a"]);
  rejects "missing dependency" (fun () -> ignore (rank ~now [n ~deps:["missing"] "a"]));
  rejects "cycle" (fun () -> ignore (rank ~now [n ~deps:["b"] "a";n ~deps:["a"] "b"]));
  rejects "duplicate task" (fun () -> ignore (rank ~now [n "a";n "a"]));
  (* Two killed semantic mutants: score-only sort and severity-free RPN band. *)
  check "score-only mutant killed" (100 < 3125 &&
    ids [n ~class_:"P1" "repair";n ~class_:"P3" ~s:3125 "feature"] <> ["feature";"repair"]);
  check "severity-free mutant killed" (band (rpn 5 1 1) <> fmea 5 1 1);
  !count
