type status = Pending | Passed | Failed of string

type check = {
  name : string;
  status : status;
}

let readiness checks =
  match
    List.find_opt
      (fun check -> match check.status with Failed _ -> true | Pending | Passed -> false)
      checks
  with
  | Some { name; status = Failed message } -> Failed (name ^ ": " ^ message)
  | Some _ -> assert false
  | None ->
      if checks = [] then Pending
      else if List.for_all (fun check -> check.status = Passed) checks then Passed
      else Pending
