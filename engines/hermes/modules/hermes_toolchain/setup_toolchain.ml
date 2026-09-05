#!/usr/bin/env -S opam exec -- ocaml

#use "topfind"

#require "bos.setup"

open Bos

(**
  * @description Reproduce and verify the ZigVM OCaml 5.5.0 toolchain.
  * @agent_intent Install the exact compiler-compatible dependency sources,
  * pins, PPX stack, and direct project dependency closure without shell glue.
  *
  * @laws
  * - Setup idempotence: a second install preserves every admitted source tree.
  * - Fail-fast composition: no pin or package install follows a failed check.
  * - Source provenance: every patched dependency denotes one expected Git tree.
  * - Check purity: --check performs observations only.
  *)

let ( let* ) value f =
  match value with Ok x -> f x | Error _ as error -> error

type dependency = {
  package : string;
  version : string;
  directory : string;
  upstream : string;
  base_commit : string;
  expected_tree : string;
  patch : string option;
}

let dependencies =
  [
    {
      package = "base";
      version = "v0.18~preview.130.106+341";
      directory = "base_55";
      upstream = "https://github.com/janestreet/base.git";
      base_commit = "28d466710aa1858a70fd3c1fcbeae07a07ac8106";
      expected_tree = "5a6bf70c4367fb055c89901dcf801e2b391988c6";
      patch = Some "base/ocaml-5.5.patch";
    };
    {
      package = "core";
      version = "v0.18~preview.130.106+341";
      directory = "core_55";
      upstream = "https://github.com/janestreet/core.git";
      base_commit = "dbceee5ddaf6b2fe88a9a395ffe9646b1c21f14a";
      expected_tree = "896df751156646ba325cd8a45574007eaef2f123";
      patch = Some "core/ocaml-5.5.patch";
    };
    {
      package = "ppxlib";
      version = "0.38.0";
      directory = "ppxlib_jane_55";
      upstream = "https://github.com/janestreet/ppxlib.git";
      base_commit = "3a791083c612e91fa4e6a9660ef69776ea750324";
      expected_tree = "94c2c37c31e50137f455ef13eca86eb7753fff15";
      patch = Some "ppxlib/ocaml-5.5.patch";
    };
    {
      package = "ppxlib_jane";
      version = "v0.18~preview.130.106+341";
      directory = "ppxlib_jane_pkg_55";
      upstream = "https://github.com/janestreet/ppxlib_jane.git";
      base_commit = "7b8f20f517f208f87a6349d791258d09df2b9209";
      expected_tree = "1b10ae959a2c65a2150d92989da78a5c79825df3";
      patch = Some "ppxlib_jane/ocaml-5.5.patch";
    };
    {
      package = "ppx_template";
      version = "v0.18~preview.130.106+341";
      directory = "ppx_template_55";
      upstream = "https://github.com/janestreet/ppx_template.git";
      base_commit = "4c44de2ac26f17d4d284498540dfde1b710bfe00";
      expected_tree = "d4910e0bbd4e07be054fe8aa1938201e8c68c72c";
      patch = Some "ppx_template/ocaml-5.5.patch";
    };
    {
      package = "ppx_deriving";
      version = "6.1.3";
      directory = "ppx_deriving_613_55";
      upstream = "https://github.com/ocaml-ppx/ppx_deriving.git";
      base_commit = "39303d86dcf5150b692599b88d774345d124d225";
      expected_tree = "1ec38003e487a00bdf75bf5ab2669b0fa55dd011";
      patch = Some "ppx_deriving/ocaml-5.5.patch";
    };
    {
      package = "ppx_deriving_yojson";
      version = "dev";
      directory = "ppx_deriving_yojson_55";
      upstream = "https://github.com/ocaml-ppx/ppx_deriving_yojson.git";
      base_commit = "1a4b06d2045ed91f30d72cdd8cce7d002c3c2503";
      expected_tree = "46aa413547da134bd41915f0382ff8a00ef8ba1b";
      patch = Some "ppx_deriving_yojson/ocaml-5.5.patch";
    };
    {
      package = "ppx_cold";
      version = "v0.17.0";
      directory = "ppx_cold_55";
      upstream = "https://github.com/janestreet/ppx_cold.git";
      base_commit = "150c14534f8bdafdda98f55f08ce414ec29d05d3";
      expected_tree = "031b09c4b4b13782cea7c0a620b88970e57634f3";
      patch = Some "ppx_cold/ocaml-5.5.patch";
    };
    {
      package = "ppx_yojson_conv_lib";
      version = "v0.18~preview.130.106+341";
      directory = "ppx_yojson_conv_lib_55";
      upstream = "https://github.com/janestreet/ppx_yojson_conv_lib.git";
      base_commit = "5025d6179f17b11580512e1400912768d22779b2";
      expected_tree = "5957dd61218aca9b3d8909c81f06ffeec1db411b";
      patch = Some "ppx_yojson_conv_lib/ocaml-5.5.patch";
    };
    {
      package = "gen_js_api";
      version = "1.1.7";
      directory = "gen_js_api_55";
      upstream = "https://github.com/LexiFi/gen_js_api.git";
      base_commit = "dcdd0b1dd852b4566745e864d98d95e4e838a763";
      expected_tree = "6ddc2cc1139031db6ae19f5df4854048427c1d56";
      patch = Some "gen_js_api/ocaml-5.5.patch";
    };
    {
      package = "lwt_ppx";
      version = "5.9.3";
      directory = "lwt_55";
      upstream = "https://github.com/ocsigen/lwt.git";
      base_commit = "bfd18ca21965a348ff3fe0e09ffd822e07610cae";
      expected_tree = "8ddd662aa566e0c744c9e0c35f61b4a5e2ef19f3";
      patch = Some "lwt/ocaml-5.5.patch";
    };
    {
      package = "ppx_expect";
      version = "v0.18~preview.130.106+341";
      directory = "ppx_expect_55";
      upstream = "https://github.com/janestreet/ppx_expect.git";
      base_commit = "54e2846ae50ffd72c00e528f62fb4a33948d0be2";
      expected_tree = "5c8d0ddb36cc513f593e37fa76471d4de0672576";
      patch = Some "ppx_expect/ocaml-5.5.patch";
    };
    {
      package = "expect_test_helpers_base";
      version = "v0.18~preview.130.106+341";
      directory = "expect_test_helpers_base_55";
      upstream = "https://github.com/janestreet/expect_test_helpers_base.git";
      base_commit = "d5b095618eea6aefde4fdf143b99c0042f07aacc";
      expected_tree = "a964831fa0f72c3d437af1f8f22f98467ff3dc19";
      patch = Some "expect_test_helpers_base/ocaml-5.5.patch";
    };
    {
      package = "expect_test_helpers_core";
      version = "v0.18~preview.130.106+341";
      directory = "expect_test_helpers_core_55";
      upstream = "https://github.com/janestreet/expect_test_helpers_core.git";
      base_commit = "83f95987c4fd1dcd8e6118038dcc07758f31dfff";
      expected_tree = "d0ffc3fb674b406d721cf3be6ec25c4189eea12f";
      patch = Some "expect_test_helpers_core/ocaml-5.5.patch";
    };
    {
      package = "virtual_dom";
      version = "v0.18~preview.130.106+341";
      directory = "virtual_dom_55";
      upstream = "https://github.com/janestreet/virtual_dom.git";
      base_commit = "4e9549cdd71dc62f0e78917e088d607b219f1ba3";
      expected_tree = "df8c6c56bfb9dc29322c1f28aed63b71a97c083c";
      patch = Some "virtual_dom/ocaml-5.5.patch";
    };
    {
      package = "bonsai";
      version = "v0.18~preview.130.106+341";
      directory = "bonsai_55";
      upstream = "https://github.com/janestreet/bonsai.git";
      base_commit = "f31661450eb133fe89564219d97669c2735c6622";
      expected_tree = "3f66f7a5ef9d98756c7a3933859e0f113b36483c";
      patch = Some "bonsai/ocaml-5.5.patch";
    };
    {
      package = "bonsai_web";
      version = "v0.18~preview.130.106+341";
      directory = "bonsai_web_55";
      upstream = "https://github.com/janestreet/bonsai_web.git";
      base_commit = "989c18b5381cad767365923d4f0b758c6f3c602c";
      expected_tree = "18b5aba22047129330d26d3c19d90fc50d6239de";
      patch = Some "bonsai_web/ocaml-5.5.patch";
    };
    {
      package = "dream";
      version = "dev";
      directory = "dream_55";
      upstream = "https://github.com/aantron/dream.git";
      base_commit = "2ce65e1010f2501f9319e8735eec8e1eeb676d4e";
      expected_tree = "92a7f6e73842ebec54e5b9e528dffd64ba096392";
      patch = Some "dream/ocaml-5.5.patch";
    };
    {
      package = "playwright";
      version = "dev";
      directory = "ocaml_playwright_55";
      upstream = "https://github.com/dmytro-melno/ocaml-playwright.git";
      base_commit = "7e860b0154fffff8d0c712cd8e35a85be9cf17d0";
      expected_tree = "cd8b1bc3b19680019515bdada815959d5654e1b2";
      patch = Some "playwright/ocaml-direct-driver.patch";
    };
    {
      package = "ocamlformat-lib";
      version = "0.29.0";
      directory = "ocamlformat_55";
      upstream = "https://github.com/ocaml-ppx/ocamlformat.git";
      base_commit = "195e470387ecdcfb0f9ce309b0d8d17807bde25d";
      expected_tree = "288717170d7c4fc20de99079b3922a424a09c22c";
      patch = Some "ocamlformat/ocaml-5.5.patch";
    };
    {
      package = "ocamlformat";
      version = "0.29.0";
      directory = "ocamlformat_55";
      upstream = "https://github.com/ocaml-ppx/ocamlformat.git";
      base_commit = "195e470387ecdcfb0f9ce309b0d8d17807bde25d";
      expected_tree = "288717170d7c4fc20de99079b3922a424a09c22c";
      patch = Some "ocamlformat/ocaml-5.5.patch";
    };
    {
      package = "ocaml-lsp-server";
      version = "1.27.0";
      directory = "ocaml_lsp_55";
      upstream = "https://github.com/ocaml/ocaml-lsp.git";
      base_commit = "b90cbe7cdfb096eaf32df92b8db6681c428a5643";
      expected_tree = "b58b67dd1066c9a34d4430a87414531cc34d3bb0";
      patch = Some "ocaml-lsp-server/ocaml-5.5.patch";
    };
    {
      package = "config";
      version = "0.0.3";
      directory = "config_pkg";
      upstream = "https://github.com/ocaml-sys/config.ml.git";
      base_commit = "f850715";
      expected_tree = "12b2b031058b20b20111283f2e440fede9af751c";
      patch = Some "config/ocaml-5.5.patch";
    };
    {
      package = "gluon";
      version = "0.0.9";
      directory = "gluon";
      upstream = "https://github.com/riot-ml/gluon.git";
      base_commit = "0b9e2f648ddb6e88fe13a3fa39e1644a53ba44d1";
      expected_tree = "b0d46081c855908616792d5869da1e498ea75f4e";
      patch = None;
    };
    {
      package = "riot";
      version = "0.0.9";
      directory = "riot";
      upstream = "https://github.com/riot-ml/riot.git";
      base_commit = "310a486";
      expected_tree = "f968f524ffd1e2c1adbb018ef89154dc1b73c37a";
      patch = Some "riot/0001-fix-support-OCaml-5.5-runtime-stack.patch";
    };
    {
      package = "notty";
      version = "0.2.3";
      directory = "notty_pkg";
      upstream = "https://github.com/pqwy/notty.git";
      base_commit = "e035d06";
      expected_tree = "18a0c72af8886aed40fb2ca03b4f5c51948a12ea";
      patch = Some "notty/0001-Patch-out_width.patch";
    };
    {
      package = "bisect_ppx";
      version = "2.8.3";
      directory = "bisect_ppx";
      upstream = "https://github.com/aantron/bisect_ppx.git";
      base_commit = "2d8dffb";
      expected_tree = "ba5c1cbc797e13f8582ed22958602173181779cc";
      patch = Some "bisect_ppx/ocaml-5.5.patch";
    };
    (* Gospel and Ortac target the OCaml 5.2+ parsetree, while this switch pins
       ppxlib to the ast500 branch. Both patches therefore port BACKWARDS across
       the 5.2 AST refactor — they are not 5.5 compatibility shims in the usual
       direction, and they must be revisited whenever the ppxlib pin moves. *)
    {
      package = "gospel";
      version = "0.3.1";
      directory = "gospel_55";
      upstream = "https://github.com/ocaml-gospel/gospel.git";
      base_commit = "5597c61db68efe950b838832f412aa6a9c8e6229";
      expected_tree = "1acfeaba9fea2eaa7ba1b4365edc0570f8424559";
      patch = Some "gospel/ocaml-5.5.patch";
    };
    {
      (* `ortac` is not a package: the tree publishes ortac-core,
         ortac-qcheck-stm, ortac-runtime and friends. ortac-core stands for the
         tree here; the qcheck-stm plugin is pinned from the same directory. *)
      package = "ppx_deriving_qcheck";
      version = "0.9";
      directory = "qcheck_55";
      upstream = "https://github.com/c-cube/qcheck.git";
      base_commit = "6cdd8409ce373807e1b541ae420dc7eb45537e91";
      expected_tree = "caefbf73faf0e26c78347ed1c941470fa0dadce7";
      patch = Some "ppx_deriving_qcheck/ocaml-5.5.patch";
    };
    {
      package = "ortac-core";
      version = "0.8.0";
      directory = "ortac_55";
      upstream = "https://github.com/ocaml-gospel/ortac.git";
      base_commit = "a86251abd76694e2e444bc88ea5c05e342053db9";
      expected_tree = "76b21618fa8d5c386e121baae0ed4e28814a23f6";
      patch = Some "ortac/ocaml-5.5.patch";
    };
  ]

let source_only_dependencies =
  [
    {
      package = "microsoft-playwright-source";
      version = "1.59.0";
      directory = "microsoft_playwright_159";
      upstream = "https://github.com/microsoft/playwright.git";
      base_commit = "01b2b1533e0bfa1c582117e3ec109fcb57657747";
      expected_tree = "e1bcfae84368d3c9b7cedf3ab24ea491d67d61c5";
      patch = None;
    };
    {
      package = "stanc3";
      version = "d9ed7977fd92f7fe1a737fd44ea44f22ee39472d";
      directory = "../vendor/stanc3";
      upstream = "https://github.com/stan-dev/stanc3.git";
      base_commit = "d9ed7977fd92f7fe1a737fd44ea44f22ee39472d";
      expected_tree = "26272b0c35598ea7cd9a043243706d299a8b2f32";
      patch = Some "stanc3/ocaml-5.5.patch";
    };
  ]

let jane_repository =
  {
    package = "janestreet-opam";
    version = "v0.18~preview.130.106+341";
    directory = "janestreet_opam_55";
    upstream = "https://github.com/janestreet/opam-repository.git";
    base_commit = "6789b91abef324f0f9dc2a07332afc4843c7dbe5";
    expected_tree = "3efc7b7407c07292ddb5f4726f1635131804b5e3";
    patch = Some "janestreet-opam/ocaml-5.5.patch";
  }

let required_packages =
  [
    "alcotest";
    "alt-ergo-lib";
    "bisect_ppx";
    "bos";
    "cmdliner";
    "config";
    "coq";
    "base";
    "bonsai";
    "bonsai_web";
    "core";
    "core_unix";
    "ctypes";
    "ctypes-foreign";
    "curl";
    "domainslib";
    "dream";
    "dune";
    "eio";
    "eio_linux";
    "eio_main";
    "fmt";
    "gluon";
    "hugin";
    "js_of_ocaml";
    "js_of_ocaml-ppx";
    "kaun";
    "expect_test_helpers_base";
    "expect_test_helpers_core";
    "gen_js_api";
    "lwt";
    "lwt_ppx";
    "menhir";
    "menhirLib";
    "notty";
    "nx";
    "nx-datasets";
    "ocaml-lsp-server";
    "ocamlfind";
    "ocamlformat";
    "ocamlformat-lib";
    "odoc";
    "ppx_assert";
    "ppx_base";
    "ppx_bench";
    "ppx_bin_prot";
    "ppx_blob";
    "ppx_cold";
    "ppx_compare";
    "ppx_custom_printf";
    "ppx_derivers";
    "ppx_deriving";
    "ppx_deriving_yojson";
    "ppx_diff";
    "ppx_disable_unused_warnings";
    "ppx_enumerate";
    "ppx_expect";
    "ppx_fields_conv";
    "ppx_fixed_literal";
    "ppx_globalize";
    "ppx_hash";
    "ppx_here";
    "ppx_ignore_instrumentation";
    "ppx_inline_test";
    "ppx_jane";
    "ppx_js_style";
    "ppx_let";
    "ppx_log";
    "ppx_module_timer";
    "ppx_optcomp";
    "ppx_optional";
    "ppx_pattern_bind";
    "ppx_quick_test";
    "ppx_pipebang";
    "ppx_sexp_conv";
    "ppx_sexp_message";
    "ppx_sexp_value";
    "ppx_stable";
    "ppx_stable_witness";
    "ppx_string";
    "ppx_string_conv";
    "ppx_tydi";
    "ppx_typed_fields";
    "ppx_typerep_conv";
    "ppx_variants_conv";
    "ppx_yojson_conv";
    "ppx_yojson_conv_lib";
    "ppxlib";
    "ppxlib_jane";
    "ppx_template";
    "qcheck";
    "patdiff";
    "playwright";
    "riot";
    "rune";
    "saga";
    "smtml";
    "sqlite" ^ "3";
    "talon";
    "time_now";
    "utop";
    "virtual_dom";
    "wasm_of_ocaml-compiler";
    "yojson";
    "z3";
  ]

let development_tools =
  [
    "ocaml-lsp-server.1.27.0"; "ocamlformat.0.29.0"; "odoc.3.2.1"; "utop.2.17.0";
  ]

let command_output command =
  match OS.Cmd.run_out command |> OS.Cmd.to_string with
  | Ok output -> Ok (String.trim output)
  | Error (`Msg message) -> Error (`Msg message)

let run command =
  match OS.Cmd.run command with
  | Ok () -> Ok ()
  | Error (`Msg message) -> Error (`Msg message)

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search index =
    if index + needle_length > haystack_length then false
    else if String.sub haystack index needle_length = needle then true
    else search (index + 1)
  in
  needle_length = 0 || search 0

let dependency_path root dependency =
  Filename.concat (Filename.concat root "third_party") dependency.directory

let patch_path root relative =
  Filename.concat (Filename.concat root "vendor/ocaml-5.5-patches") relative

let all_sources = jane_repository :: (dependencies @ source_only_dependencies)

let git_output path arguments =
  command_output Cmd.(v "git" % "-C" % path %% of_list arguments)

let validate_dependency root dependency =
  let path = dependency_path root dependency in
  if not (Sys.file_exists path) then
    Error (`Msg (Printf.sprintf "%s is missing" path))
  else
    let* dirty = git_output path [ "status"; "--porcelain" ] in
    if dirty <> "" then
      Error (`Msg (Printf.sprintf "%s has uncommitted changes" path))
    else
      let* tree = git_output path [ "rev-parse"; "HEAD^{tree}" ] in
      if tree = dependency.expected_tree then Ok ()
      else
        Error
          (`Msg
             (Printf.sprintf "%s tree mismatch: expected %s, found %s" path
                dependency.expected_tree tree))

let remove_if_present path =
  if Sys.file_exists path then OS.Path.delete ~recurse:true (Fpath.v path)
  else Ok ()

let provision_dependency root dependency =
  let target = dependency_path root dependency in
  if Sys.file_exists target then validate_dependency root dependency
  else
    let temporary = target ^ ".tmp" in
    let* () = remove_if_present temporary in
    let* _ = OS.Dir.create (Fpath.v (Filename.dirname target)) in
    let provision () =
      let* () =
        run
          Cmd.(
            v "git" % "clone" % "--no-checkout" % dependency.upstream
            % temporary)
      in
      let* () =
        run
          Cmd.(
            v "git" % "-C" % temporary % "checkout" % "--detach"
            % dependency.base_commit)
      in
      let* () =
        match dependency.patch with
        | None -> Ok ()
        | Some relative ->
            run
              Cmd.(v "git" % "-C" % temporary % "am" % patch_path root relative)
      in
      let* () =
        run
          Cmd.(v "git" % "-C" % temporary % "switch" % "-c" % "zigvm-ocaml-5.5")
      in
      let* tree = git_output temporary [ "rev-parse"; "HEAD^{tree}" ] in
      if tree <> dependency.expected_tree then
        Error
          (`Msg
             (Printf.sprintf
                "%s provisioned tree mismatch: expected %s, found %s"
                dependency.package dependency.expected_tree tree))
      else OS.Path.move (Fpath.v temporary) (Fpath.v target)
    in
    match provision () with
    | Ok () -> validate_dependency root dependency
    | Error _ as error ->
        let _ = remove_if_present temporary in
        error

let verify_compiler root =
  let* switch = command_output Cmd.(v "opam" % "switch" % "show") in
  let switch = Unix.realpath switch in
  if switch <> root then
    Error
      (`Msg
         (Printf.sprintf "active opam switch is %s, expected local switch %s"
            switch root))
  else
    let* version = command_output Cmd.(v "ocamlc" % "-version") in
    if version = "5.5.0" then Ok ()
    else Error (`Msg (Printf.sprintf "OCaml 5.5.0 required, found %s" version))

let installed_package_names () =
  let* output =
    command_output
      Cmd.(v "opam" % "list" % "--installed" % "--short" % "--safe")
  in
  Ok (String.split_on_char '\n' output)

let verify_packages () =
  let* installed = installed_package_names () in
  let missing =
    List.filter
      (fun package -> not (List.mem package installed))
      required_packages
  in
  match missing with
  | [] -> Ok ()
  | _ ->
      Error
        (`Msg
           (Printf.sprintf "missing OCaml packages: %s"
              (String.concat ", " missing)))

let opam_with_jobs arguments =
  Cmd.(v "env" % "OPAMJOBS=4" % "opam" %% of_list arguments)

let internalhash_stub root =
  Filename.concat root "_opam/lib/stublibs/dllbase_internalhash_types_stubs.so"

let verify_runtime_artifacts root =
  let path = internalhash_stub root in
  if Sys.file_exists path then Ok ()
  else
    Error
      (`Msg
         (Printf.sprintf
            "installed Base runtime is incomplete: missing %s; run --install \
             to repair it"
            path))

let repair_runtime_artifacts root =
  if Sys.file_exists (internalhash_stub root) then Ok ()
  else
    let* () =
      run
        (opam_with_jobs
           [
             "reinstall";
             "--yes";
             "base_internalhash_types.v0.18~preview.130.106+341";
           ])
    in
    verify_runtime_artifacts root

let verify_pins root =
  let* output =
    command_output Cmd.(v "opam" % "pin" % "list" % "--normalise")
  in
  let missing =
    dependencies
    |> List.filter_map (fun dependency ->
        let package = dependency.package ^ "." ^ dependency.version in
        let source = "file://" ^ dependency_path root dependency in
        if contains output package && contains output source then None
        else Some (package ^ " -> " ^ dependency_path root dependency))
  in
  match missing with
  | [] -> Ok ()
  | _ -> Error (`Msg ("missing local pins: " ^ String.concat ", " missing))

let pin_dependency root dependency =
  let package = dependency.package ^ "." ^ dependency.version in
  run
    Cmd.(
      v "opam" % "pin" % "add" % "--yes" % "--no-action" % package
      % dependency_path root dependency)

let jane_repository_url root =
  "git+file://" ^ dependency_path root jane_repository

let verify_repository root =
  let* output =
    command_output Cmd.(v "opam" % "repository" % "list" % "--all")
  in
  let expected = jane_repository_url root in
  if contains output "janestreet-bleeding" && contains output expected then
    Ok ()
  else
    Error
      (`Msg (Printf.sprintf "janestreet-bleeding must resolve to %s" expected))

let configure_repository root =
  let* output =
    command_output Cmd.(v "opam" % "repository" % "list" % "--all")
  in
  let url = jane_repository_url root in
  if contains output "janestreet-bleeding" then
    run Cmd.(v "opam" % "repository" % "set-url" % "janestreet-bleeding" % url)
  else run Cmd.(v "opam" % "repository" % "add" % "janestreet-bleeding" % url)

let install root =
  let* () = verify_compiler root in
  let* () =
    List.fold_left
      (fun result dependency ->
        let* () = result in
        provision_dependency root dependency)
      (Ok ()) all_sources
  in
  let* () = configure_repository root in
  let* () = verify_repository root in
  let* () = run (opam_with_jobs [ "update"; "janestreet-bleeding" ]) in
  let* () =
    List.fold_left
      (fun result dependency ->
        let* () = result in
        pin_dependency root dependency)
      (Ok ()) dependencies
  in
  let* () = run (opam_with_jobs [ "install"; "--yes"; "."; "--deps-only" ]) in
  let* () = run (opam_with_jobs ([ "install"; "--yes" ] @ development_tools)) in
  let* () = repair_runtime_artifacts root in
  let* () = verify_pins root in
  let* () = verify_packages () in
  verify_runtime_artifacts root

let check root =
  let* () = verify_compiler root in
  let* () =
    List.fold_left
      (fun result dependency ->
        let* () = result in
        validate_dependency root dependency)
      (Ok ()) all_sources
  in
  let* () = verify_repository root in
  let* () = verify_pins root in
  let* () = verify_packages () in
  verify_runtime_artifacts root

let usage () =
  Printf.eprintf "usage: modules/hermes_toolchain/setup_toolchain.ml [--check|--install]\n";
  exit 2

let () =
  let root = Unix.realpath (Sys.getcwd ()) in
  if not (Sys.file_exists (Filename.concat root "hermes_workspace.opam")) then begin
    Printf.eprintf "run this script from the Hermes workspace root (it needs hermes_workspace.opam)\n";
    exit 2
  end;
  let operation =
    match Array.to_list Sys.argv with
    | [ _; "--check" ] -> check root
    | [ _; "--install" ] -> install root
    | _ -> usage ()
  in
  match operation with
  | Ok () ->
      Printf.printf "OCaml 5.5.0 toolchain verified: %d pins, %d packages\n"
        (List.length dependencies)
        (List.length required_packages)
  | Error (`Msg message) ->
      Printf.eprintf "OCaml toolchain setup failed: %s\n" message;
      exit 1
