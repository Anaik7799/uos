(* Independent structural validator for captured homeostasis evidence.
   Runs no UOS control action. Output is a scoped receipt, never admission. *)
open Yojson.Safe.Util
let require label value = if not value then failwith label
let load path = Yojson.Safe.from_file path
let read path = let ch=open_in_bin path in Fun.protect ~finally:(fun()->close_in ch) (fun()->really_input_string ch (in_channel_length ch))
let run command args =
  let ch=Unix.open_process_args_in command (Array.of_list(command::args)) in
  let result=Buffer.create 128 in
  (try while true do Buffer.add_string result (input_line ch); Buffer.add_char result '\n' done with End_of_file->());
  require (command ^ " failed") (Unix.close_process_in ch=Unix.WEXITED 0);
  String.trim(Buffer.contents result)
let digest path = let text=run "sha256sum" ["--";path] in String.sub text 0 64
let safe s = String.map(function '/'->'-'|c->c)s
let components=["provenance";"controls";"pid";"phase";"physiology";"runtime";"pareto";"quorum";"stream";"checklist"]
let tasks=List.concat_map(fun mode->
  List.map(fun page->mode,page,"all")["homeostasis";"homeostasis/evolution";"homeostasis/terminal"] @
  List.map(fun component->mode,"homeostasis/components",component)components)["real";"test"]
let string_value key json=member key json |> to_string
let int_value key json=match member key json with
  | `Int value -> value
  | `Float value when Float.is_finite value && Float.floor value=value && Float.abs value<=9007199254740991. -> int_of_float value
  | _ -> failwith (key ^ " must be a safe integer")
let occurrences pattern text =
  let regex=Str.regexp_string pattern in
  let rec count offset result=try let at=Str.search_forward regex text offset in count (at+String.length pattern) (result+1) with Not_found->result in
  count 0 0
let artifact path=`Assoc["path",`String path;"sha256",`String(digest path);"bytes",`Int((Unix.stat path).Unix.st_size)]
let video folder (mode,page,component) =
  let name="20260908-0045-"^mode^"-"^safe page^"-"^component in
  let receipt_path=Filename.concat folder(name^".json") in
  let video_path=Filename.concat folder(name^".webm") in
  let receipt=load receipt_path in
  require (name^" identity") (string_value "mode" receipt=mode && string_value "page" receipt=page && string_value "component" receipt=component);
  let cycles=member "cycles" receipt |> to_list in
  require (name^" cycle count") (List.length cycles=30);
  let previous=ref 0 in let previous_time=ref 0 in
  List.iteri(fun index row->
    require (name^" ordered cycle") (int_value "cycle" row=index+1);
    let observed=member "observed" row in
    let frames=int_value "frames" observed in
    require (name^" stalled render") (frames > !previous);
    previous:=frames;
    require (name^" field count") (int_value "fields" observed=21);
    if mode="real" then begin
      require (name^" false real attribution") (string_value "status" observed="observed" && string_value "generation" observed="UNKNOWN");
      let at=int_value "source_time" observed in
      require (name^" source clock failed to advance") (at > !previous_time);
      previous_time:=at
    end else begin
      require (name^" false simulation attribution") (string_value "status" observed="simulated" && member "source_time" observed=`Null);
      let generation=string_value "generation" observed |> int_of_string in
      require (name^" model bounds") (generation>=1 && generation<=30)
    end
  ) cycles;
  let probe=run "ffprobe" ["-v";"error";"-show_entries";"format=duration";"-of";"default=noprint_wrappers=1:nokey=1";video_path] |> float_of_string in
  require (name^" duration below 30 seconds") (probe>=30. && probe<=60.);
  `Assoc["mode",`String mode;"page",`String page;"component",`String component;"cycles",`Int 30;
    "continuous_updates",`Bool true;"duration_seconds",`Float probe;"video",artifact video_path;"receipt",artifact receipt_path]
let pty folder mode =
  let prefix=Filename.concat folder("20260908-0045-pty-"^mode) in
  let text=read(prefix^".txt") in
  require (mode^" PTY exit") (occurrences "COMMAND_EXIT_CODE=\"0\"" text=1);
  require (mode^" PTY cycle count") (occurrences "VERIFIED_CYCLE " text=30);
  for n=1 to 30 do require (mode^" PTY cycle sequence") (occurrences (Printf.sprintf "VERIFIED_CYCLE %d/30" n) text=1) done;
  require (mode^" PTY mode") (occurrences ("HOMEOSTASIS | "^(if mode="real" then "OBSERVED" else "SIMULATED")) text=30);
  require (mode^" PTY authority") (occurrences "Control authority: NONE" text=30);
  `Assoc["mode",`String mode;"cycles",`Int 30;"transcript",artifact(prefix^".txt");"timing",artifact(prefix^".timing")]
let () =
  require "usage: evidence-check RECORDING_DIR" (Array.length Sys.argv=2);
  let folder=Sys.argv.(1) in
  let videos=List.map(video folder) tasks in
  let ptys=List.map(pty folder)["real";"test"] in
  print_endline(Yojson.Safe.pretty_to_string(`Assoc[
    "contract",`String "SC-HOMEO-UI-001";"status",`String "SCOPED_CHECK_PASS";
    "runtime_admission",`String "NOT_GRANTED";"control_authority",`String "NONE";
    "scope",`String "private candidate capture; receipt continuity and media integrity, not current production health";
    "browser_views",`Int 26;"browser_verified_cycles",`Int 780;"native_terminal_cycles",`Int 60;
    "videos",`List videos;"pty",`List ptys]))
