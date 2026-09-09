open Bootstrap_model
let oracle observations =
  List.for_all (fun fact ->
    List.filter (fun (candidate, _) -> candidate = fact) observations = [fact, true]) facts
let accepted observations = match verify observations with Ok _ -> true | Error _ -> false
let check name condition = if not condition then failwith name
let () =
  for mask = 0 to 511 do
    let observations = List.mapi (fun bit fact -> fact, mask land (1 lsl bit) <> 0) facts in
    List.iter (fun values ->
      check "predicate agrees with independent universal oracle" (accepted values = oracle values))
      [observations; List.rev observations];
    List.iter (fun fact ->
      check "duplicate refuses" (not (accepted ((fact,true)::observations)));
      check "missing refuses" (not (accepted (List.filter(fun(f,_)->f<>fact)observations)))) facts
  done;
  let positive = List.map(fun f->f,true)facts in
  (match verify positive with Error _ -> failwith "positive" | Ok value ->
    check "all observable facts retained" (List.sort compare(observed value)=List.sort compare facts));
  List.iter(fun seed->let a=Random.State.make[|seed|] and b=Random.State.make[|seed|] in
    for _=1 to 1024 do
      let generate rng=List.map(fun f->f,Random.State.bool rng)facts in
      check "twin seed interpretation" (accepted(generate a)=oracle(generate b))
    done)[104729;130363];
  print_endline "PASS bootstrap formal predicate: all 512 truth assignments, reverse permutations, 9216 missing/duplicate falsifiers and 2048 twin-seed interpretations"
