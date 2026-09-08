#use "release_process.ml";;
let guard_unit source = 
 let tmp=temp "uos-guard-unit-" in
 mkdir(tmp^"/src")0o700;mkdir(tmp^"/src/cepaf_gleam")0o700;mkdir(tmp^"/src/cepaf_gleam/ha")0o700;
 copy(source^"/apps/cepaf_gleam/src/cepaf_gleam/ha/module_guard.gleam")(tmp^"/src/cepaf_gleam/ha/module_guard.gleam");
 copy(source^"/apps/cepaf_gleam/test/module_guard_contract_test.gleam")(tmp^"/src/module_guard_contract_test.gleam");
 write_new(tmp^"/gleam.toml") "name = \"guard_checks\"\nversion = \"1.0.0\"\ntarget = \"erlang\"\n[dependencies]\ngleam_stdlib = \">= 0.60.0 and < 2.0.0\"\ngleam_json = \">= 3.0.0 and < 4.0.0\"\ngleeunit = \">= 1.0.0 and < 2.0.0\"\n";
 let lib=canonical^"/apps/cepaf_gleam/build/dev/erlang" in
 let built=run ~seconds:45. "/home/an/.nix-profile/bin/gleam" ["compile-package";"--target";"erlang";"--package";tmp;"--out";tmp^"/compiled";"--lib";lib] in
 write_new(tmp^"/build.log")built.output;require(built.code=0)("guard build failed: "^built.output);
 let paths=Sys.readdir lib|>Array.to_list|>List.filter_map(fun d->let p=lib^"/"^d^"/ebin" in if Sys.file_exists p then Some p else None) in
 let prefix=["+S";"2:2";"-noshell";"-pa"]@paths@["-pa";tmp^"/compiled/ebin";"-eval"] in
 let tested=run ~seconds:20. (otp^"/erl")(prefix@["case eunit:test(module_guard_contract_test,[verbose]) of ok->halt(0);error->halt(1) end."]) in
 write_new(tmp^"/unit.log")tested.output;
 let table=checked(otp^"/erl")(prefix@["module_guard_contract_test:report(),halt()."]) in
 write_new(tmp^"/cases.json")table;
 emit "guard-unit" (if tested.code=0 then "PASS" else "FAIL") ["exit",`Int tested.code;"evidence",`String tmp];
 exit tested.code;;
let ()=match Array.to_list Sys.argv with [_;source]->guard_unit source|_->failwith "usage: output_guard_check.ml SOURCE";;
