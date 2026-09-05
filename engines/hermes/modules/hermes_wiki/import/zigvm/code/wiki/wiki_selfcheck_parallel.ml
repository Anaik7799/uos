type 'a run = {
  values : 'a array;
  visits : int array;
  workers : int;
  worker_items : int array;
  worker_ns : int64 array;
}

let recommended_workers () =
  max 1 (min 16 (Domain.recommended_domain_count () - 1))

let now_ns () =
  Unix.gettimeofday () *. 1_000_000_000. |> Int64.of_float

let map_gss ~workers f input =
  let n = Array.length input in
  let workers = max 1 (min (max 1 workers) (max 1 n)) in
  let cursor = Atomic.make 0 in
  let slots = Array.make n None in
  let visits = Array.make n 0 in
  let worker_items = Array.make workers 0 in
  let worker_ns = Array.make workers 0L in
  (* Guided self-scheduling: each successful claimant receives ceil(R/P)
     coordinates, where R is the remaining work and P the bounded worker count.
     CAS is paid per chunk, never per note. *)
  let rec claim () =
    let first = Atomic.get cursor in
    if first >= n then None
    else
      let remaining = n - first in
      let chunk = max 1 ((remaining + workers - 1) / workers) in
      let last = min n (first + chunk) in
      if Atomic.compare_and_set cursor first last then Some (first, last)
      else claim () in
  let work worker =
    let started = now_ns () in
    let rec loop items =
      match claim () with
      | None -> items
      | Some (first, last) ->
          for i = first to last - 1 do
            slots.(i) <- Some (f input.(i));
            visits.(i) <- visits.(i) + 1
          done;
          loop (items + last - first) in
    worker_items.(worker) <- loop 0;
    worker_ns.(worker) <- Int64.sub (now_ns ()) started in
  if n > 0 then (
    if workers = 1 then work 0
    else
      Eio_main.run (fun env ->
        let domain_mgr = Eio.Stdenv.domain_mgr env in
        List.init workers Fun.id
        |> Eio.Fiber.List.iter ~max_fibers:workers (fun worker ->
               Eio.Domain_manager.run_raw domain_mgr (fun () -> work worker))));
  let values =
    Array.mapi
      (fun i -> function
        | Some value -> value
        | None -> failwith (Printf.sprintf "wiki GSS left coordinate %d unassigned" i))
      slots in
  { values; visits; workers; worker_items; worker_ns }
