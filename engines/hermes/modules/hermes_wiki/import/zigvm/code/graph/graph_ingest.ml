module Graph = Graph_intelligence

let stopwords =
  [
    "and"; "are"; "but"; "for"; "from"; "has"; "have"; "into"; "its"; "not";
    "of"; "on"; "or"; "that"; "the"; "their"; "this"; "to"; "was"; "were";
    "will"; "with"; "you"; "your";
  ]

let is_word = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '#' | '@' | '_' | '-' -> true
  | _ -> false

let tokenize text =
  let flush buffer tokens =
    if Buffer.length buffer = 0 then tokens
    else
      let token = Buffer.contents buffer |> String.lowercase_ascii in
      Buffer.clear buffer;
      if String.length token < 3 || List.mem token stopwords then tokens else token :: tokens
  in
  let buffer = Buffer.create 24 in
  let tokens = ref [] in
  String.iter
    (fun character ->
      if is_word character then Buffer.add_char buffer character
      else tokens := flush buffer !tokens)
    text;
  tokens := flush buffer !tokens;
  List.rev !tokens

let statements text =
  let buffer = Buffer.create 128 in
  let result = ref [] in
  let flush () =
    let statement = Buffer.contents buffer |> String.trim in
    Buffer.clear buffer;
    if statement <> "" then result := statement :: !result
  in
  String.iter
    (fun character ->
      match character with
      | '.' | '?' | '!' | '\n' | '\r' -> flush ()
      | _ -> Buffer.add_char buffer character)
    text;
  flush ();
  List.rev !result

let pair left right = if String.compare left right <= 0 then (left, right) else (right, left)

let from_text ?(window = 4) ~id ~title text =
  let window = Int.max 1 (Int.min 12 window) in
  let frequencies = Hashtbl.create 128 and relations = Hashtbl.create 256 in
  let add_frequency token =
    Hashtbl.replace frequencies token
      (1 + Option.value ~default:0 (Hashtbl.find_opt frequencies token))
  in
  List.iter
    (fun statement ->
      let tokens = tokenize statement |> Array.of_list in
      Array.iter add_frequency tokens;
      for left_index = 0 to Array.length tokens - 1 do
        let last = Int.min (Array.length tokens - 1) (left_index + window) in
        for right_index = left_index + 1 to last do
          let left, right = pair tokens.(left_index) tokens.(right_index) in
          if not (String.equal left right) then
            Hashtbl.replace relations (left, right)
              (1 + Option.value ~default:0 (Hashtbl.find_opt relations (left, right)))
        done
      done)
    (statements text);
  let nodes =
    Hashtbl.fold
      (fun token frequency nodes ->
        Graph.
          {
            id = "Concept:" ^ token;
            label = token;
            kind = "Concept";
            layer = "L5";
            group = "text";
            detail = Printf.sprintf "%d occurrence(s)" frequency;
            weight = float_of_int frequency;
          }
        :: nodes)
      frequencies []
  in
  let edges =
    Hashtbl.fold
      (fun (left, right) frequency edges ->
        Graph.
          {
            source = "Concept:" ^ left;
            target = "Concept:" ^ right;
            relation = "coOccurs";
            weight = float_of_int frequency;
          }
        :: edges)
      relations []
  in
  Graph.normalize { id; title; kind = "text"; nodes; edges }

let positive = [ "clear"; "correct"; "good"; "improve"; "robust"; "safe"; "success"; "verified" ]
let negative = [ "bad"; "blocked"; "error"; "fail"; "hazard"; "loss"; "risk"; "unsafe" ]

let sentiment text =
  let score, count =
    tokenize text
    |> List.fold_left
         (fun (score, count) token ->
           if List.mem token positive then (score + 1, count + 1)
           else if List.mem token negative then (score - 1, count + 1)
           else (score, count))
         (0, 0)
  in
  if count = 0 then 0. else float_of_int score /. float_of_int count

