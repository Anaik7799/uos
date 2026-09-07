#use "test_product_catalog.ml";;
#use "product_workflow_view.ml";;
let () =
 let path=Filename.temp_file "uos-product-view-test-" ".sqlite3" in
 Fun.protect ~finally:(fun()->Sys.remove path) (fun()->with_db ~readonly:false path(fun db->
  import db (fixture()) ~authorize:(fun()->());
  let candidate=init db "test" "v1" "test-worker" "isolated#test" ~authorize:(fun()->()) in
  let body=render_view db candidate in
  let contains fragment=try ignore(Str.search_forward(Str.regexp_string fragment)body 0);true with Not_found->false in
  List.iter(fun fragment->require(contains fragment)("view missing "^fragment))
   ["Product state: UNRUN";"1 required acceptance cases";"No execution receipts";
    "Sa-plan reference is unresolved";"CHK-18-JJ";"http://nas-1.tail55d152.ts.net:4100/planning"];
  require(md "<script>|`&"="&lt;script&gt;\\|&#96;&amp;") "view markup escaping failed";
  require(query db "SELECT count(*) FROM product_workflow_receipts" []=[[Sqlite3.Data.INT 0L]]) "view created execution evidence";
  print_endline "product-view: missing evidence, unresolved authority, escaping, checklist and read-only projection passed"))
