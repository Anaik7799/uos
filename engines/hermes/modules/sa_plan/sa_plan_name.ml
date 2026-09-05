type t = string list

let is_ascii_alnum = function
  | 'a' .. 'z' | '0' .. '9' -> true
  | _ -> false

let valid_segment segment =
  String.length segment > 0
  && not (String.equal segment "." || String.equal segment "..")
  && is_ascii_alnum segment.[0]
  && is_ascii_alnum segment.[String.length segment - 1]
  && String.for_all
       (function
         | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' -> true
         | _ -> false)
       segment

let make segments =
  let segments = List.map String.lowercase_ascii segments in
  if List.length segments < 2 then
    Error "hierarchical name requires at least two segments"
  else
    match List.find_opt (fun segment -> not (valid_segment segment)) segments with
    | Some segment -> Error ("invalid hierarchical name segment: " ^ segment)
    | None -> Ok segments

let to_string segments = String.concat "/" segments
let segments name = name
let parse value = make (String.split_on_char '/' value)
let append name segment = make (name @ [ segment ])

let parent = function
  | [] | [ _ ] | [ _; _ ] -> None
  | segments ->
      let rec drop_last = function
        | [] | [ _ ] -> []
        | head :: tail -> head :: drop_last tail
      in
      Some (drop_last segments)

let to_relpath = to_string

