let boot_id =
  let doc = "Untrusted operator boot identity; external capture binds provenance." in
  Cmdliner.Arg.(required & opt (some string) None & info ["boot-id"] ~docv:"BOOT_ID" ~doc)

let run_id =
  let doc = "Untrusted operator run identity; external capture must ensure uniqueness." in
  Cmdliner.Arg.(required & opt (some string) None & info ["run-id"] ~docv:"RUN_ID" ~doc)

module type MTIME = sig
  val elapsed_ns : unit -> int64
end

module Make (Mtime : MTIME) = struct
  let stop message = Lwt.fail_with ("uos-mirage-metrics: " ^ message)

  let start _mtime boot_id run_id =
    let started_at_ns = 0L in
    let statistics = Gc.quick_stat () in
    let sampled_at_ns = Mtime.elapsed_ns () in
    match Mirage_metrics.make_probe ~name:"emission" ~checked_at_ns:sampled_at_ns
            Mirage_metrics.Unknown with
    | Error message -> stop message
    | Ok guest_probe ->
        match Mirage_metrics.make_sample ~boot_id ~run_id ~started_at_ns ~sampled_at_ns
                ~heap_words:statistics.Gc.heap_words
                ~top_heap_words:statistics.Gc.top_heap_words
                ~minor_collections:statistics.Gc.minor_collections
                ~major_collections:statistics.Gc.major_collections [guest_probe] with
        | Error message -> stop message
        | Ok sample ->
            print_endline (Mirage_metrics.encode_console sample);
            Lwt.return_unit
end
