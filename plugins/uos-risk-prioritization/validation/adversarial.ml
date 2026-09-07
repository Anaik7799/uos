open Priority
open Record
let run () =
  let s = schema () and ex = sample () in
  let bad = change "properties"
    (change "optional_backdoor" (`Assoc ["type",`String "string";"not",`Assoc []])
      (field "properties" s)) s in
  require
    (try ignore (check_record bad ex); false with Invalid _ -> true)
    "unsupported assertion in absent optional property was accepted";
  1

