(* The Bonsai frontend: PROGRESSIVE ENHANCEMENT, never a replacement.

   Every page is complete server-rendered; this app hydrates one element
   (`#wiki-app`) with a filterable component/plan table. If the script
   never loads, the page is unchanged — the no-JS law in the restructure
   plan, kept structural by mounting into an element the server leaves
   EMPTY rather than one it fills. *)

open! Core
open Bonsai_web
open Bonsai.Let_syntax

module Row = struct
  type t = { name : string; level : string; grade : string }

  let matches query t =
    let query = String.lowercase query in
    String.is_empty query
    || String.is_substring (String.lowercase t.name) ~substring:query
    || String.is_substring (String.lowercase t.level) ~substring:query
    || String.is_substring (String.lowercase t.grade) ~substring:query
end

(* Rows are handed to the client by the server as a JSON island, so the
   frontend never re-derives what the read model already computed. *)
let rows_of_json json =
  match json with
  | `List entries ->
      List.filter_map entries ~f:(function
        | `Assoc fields ->
            let text key =
              match List.Assoc.find fields key ~equal:String.equal with
              | Some (`String s) -> s
              | _ -> ""
            in
            Some { Row.name = text "name"; level = text "level"; grade = text "grade" }
        | _ -> None)
  | _ -> []

let table_view rows query =
  let open Vdom in
  let visible = List.filter rows ~f:(Row.matches query) in
  Node.table
    [ Node.tr
        [ Node.th [ Node.text "component" ]; Node.th [ Node.text "level" ];
          Node.th [ Node.text "grade" ] ]
    ; Node.fragment
        (List.map visible ~f:(fun row ->
             Node.tr
               [ Node.td [ Node.text row.Row.name ]
               ; Node.td [ Node.text row.Row.level ]
               ; Node.td [ Node.text row.Row.grade ]
               ]))
    ]

let app rows graph =
  (* Bonsai v0.18: state takes the graph; there is no let%sub. *)
  let query, set_query = Bonsai.state "" graph in
  let%arr query = query
  and set_query = set_query in
  let open Vdom in
  Node.div
    [ Node.input
        ~attrs:
          [ Attr.type_ "search"
          ; Attr.placeholder "filter components…"
          ; Attr.value query
          ; Attr.on_input (fun _ value -> set_query value)
          ]
        ()
    ; table_view rows query
    ]

let () =
  let rows =
    match Js_of_ocaml.Dom_html.getElementById_opt "wiki-app-data" with
    | None -> []
    | Some element ->
        let text =
          Js_of_ocaml.Js.Opt.case element##.textContent
            (fun () -> "")
            Js_of_ocaml.Js.to_string
        in
        (try rows_of_json (Yojson.Safe.from_string text) with _ -> [])
  in
  Bonsai_web.Start.start ~bind_to_element_with_id:"wiki-app" (app rows)
