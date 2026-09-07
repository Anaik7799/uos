open Core
module Crdt = Sa_plan_crdt
module Deck = Sa_plan_deck
module Mail = Sa_plan_mail
module Journal = Sa_plan_journal
module Oban = Sa_plan_oban
module Temporal = Sa_plan_temporal
module Management = Sa_plan_management
module Store = Sa_plan_store
module Name = Sa_plan_name
module Observability = Sa_plan_observability
module Observation = Sa_plan_observation
module Pipeline_telemetry = Sa_plan_pipeline_telemetry
module C3i_reference = Sa_plan_c3i_reference
module Guardian = Guardian
module Control_plane = Sa_plan_control_plane
module Control_plane_oracle = Sa_plan_control_plane_oracle

(** High-level API for orchestrating the Sa-Plan system.
    This serves as the main entry point to manage CRDT-backed tasks and generate C3I outputs. *)

type orchestration_config = {
  title: string;
  report_dir: string;
  notification_email: string option;
}

let publish state config =
  (* 1. Generate Slide Deck *)
  let deck = Deck.generate_deck state ~title:config.title in
  let deck_path = Filename.concat config.report_dir "slide_deck.md" in
  Out_channel.write_all deck_path ~data:deck;

  (* 2. Generate C3I Journal *)
  let md_journal = Journal.generate_markdown state ~title:config.title in
  let md_path = Filename.concat config.report_dir "journal.md" in
  Out_channel.write_all md_path ~data:md_journal;

  let html_journal = Journal.generate_html state ~title:config.title in
  let html_path = Filename.concat config.report_dir "journal.html" in
  Out_channel.write_all html_path ~data:html_journal;

  (* 3. Generate Email Payload *)
  match config.notification_email with
  | Some email ->
      let payload = Mail.generate_email_payload state ~to_addr:email ~subject:config.title in
      let mail_path = Filename.concat config.report_dir "notification.eml" in
      Out_channel.write_all mail_path ~data:payload
  | None -> ()

let create_task ~id ~title ~description ~status =
  { Crdt.Task.
    id; title; description; status;
    timestamp = Time_ns.now () |> Time_ns.to_span_since_epoch |> Time_ns.Span.to_sec;
  }
