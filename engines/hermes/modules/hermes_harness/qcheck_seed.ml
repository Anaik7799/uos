(* Restores the seed and verbosity contract that `run_tests_main` provided.

   The R30 migration replaced `run_tests_main` with `run_tests` in five fuzz
   suites, because the former never returns and so the telemetry tail was
   unreachable. That was correct — but `run_tests_main` also parsed argv and
   the environment, and dropping it silently removed an operator's ability to
   re-run a fuzz failure under a FIXED SEED.

   Seed reproduction is determinacy machinery, not a convenience. R14's
   determinacy gate holds that a non-reproducible run is a defect fixed
   constructively, never hidden; a fuzz failure you cannot replay is exactly
   that. Two converter agents disclosed the loss independently rather than
   absorbing it, which is why this exists.

   The contract, matching `run_tests_main` as documented in
   QCheck_base_runner.mli:

     --seed <n> | -s <n>   repeat a previous run
     --verbose  | -v       verbose tests
     QCHECK_SEED=<n>       same seed, via the environment

   argv beats the environment: a flag typed at the point of reproduction is a
   later and more specific intent than an exported variable.

   R19: an unparseable seed is a REFUSAL, never a silent fallback to a random
   one. Falling back would make the run look reproducible while being
   anything but — the precise failure this module exists to prevent. *)

let refuse message =
  prerr_endline ("qcheck_seed: " ^ message);
  exit 2

let parse_seed origin text =
  match int_of_string_opt (String.trim text) with
  | Some n -> n
  | None ->
      refuse
        (Printf.sprintf
           "%s is not an integer: %S. A seed that cannot be parsed must not fall back \
            to a random one — the run would look reproducible and not be."
           origin text)

(* Applies the environment first, then argv, so a typed flag wins. Returns the
   seed actually in force when one was requested, for disclosure by the
   caller: a reproducible run should say what it is reproducing. *)
let configure ?(argv = Sys.argv) () =
  let chosen = ref None in
  (match Sys.getenv_opt "QCHECK_SEED" with
  | Some text ->
      let seed = parse_seed "QCHECK_SEED" text in
      QCheck_base_runner.set_seed seed;
      chosen := Some seed
  | None -> ());
  let n = Array.length argv in
  let rec scan i =
    if i >= n then ()
    else
      match argv.(i) with
      | "-v" | "--verbose" ->
          QCheck_base_runner.set_verbose true;
          scan (i + 1)
      | "-s" | "--seed" ->
          if i + 1 >= n then refuse "--seed requires an integer argument"
          else begin
            let seed = parse_seed "--seed" argv.(i + 1) in
            QCheck_base_runner.set_seed seed;
            chosen := Some seed;
            scan (i + 2)
          end
      | _ -> scan (i + 1)
  in
  scan 1;
  !chosen

(* One line, only when a seed was pinned. A run that is reproducing something
   says so; an ordinary run stays silent rather than adding a token per suite
   to every battery (R22 — economy on success). *)
let disclose = function
  | None -> ()
  | Some seed -> Printf.printf "qcheck: seed pinned to %d (reproducible run)\n" seed
