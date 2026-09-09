#use "topfind";;
#require "unix,yojson,cryptokit";;
let stage=Sys.argv.(1)
let read p=let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c(in_channel_length c))
let rec mkdir p=if not(Sys.file_exists p)then(mkdir(Filename.dirname p);Unix.mkdir p 0o755)
let write p b=mkdir(Filename.dirname p);let c=open_out_bin p in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c b)
let root=stage^"/content/cases"
let player="docs/music/20260907-1052-swarm-durga-player.md"
let mix="generated/20260907-1230-uos-hive-sings-full-mix.wav"
let named n p=root^"/"^n^"/"^p
let ()=if not(String.starts_with ~prefix:"/tmp/" stage) || Sys.file_exists root then failwith"fresh private cases required";
let original=read(stage^"/content/"^player)in
List.iter(fun n->mkdir(Filename.dirname(named n player)))["missing";"symlink-file";"directory";"fifo";"denied";"zero-file"];
write(named"exact-document"player)(original^String.make(2097152-String.length original)' ');
write(named"oversize-document"player)(String.make 2097153 'x');
write(named"denied"player)original;Unix.chmod(named"denied"player)0;
write(named"zero-file"player)"";
Unix.mkdir(named"directory"player)0o755;
Unix.mkfifo(named"fifo"player)0o600;
Unix.symlink(stage^"/content/"^player)(named"symlink-file"player);
mkdir(root^"/symlink-parent");Unix.symlink(stage^"/content/docs")(root^"/symlink-parent/docs");
Unix.symlink(stage^"/content")(root^"/root-symlink");
write(named"missing-studio"player)original;
let a="data:audio/mp3;base64,"in
write(named"invalid-base64"player)(a^"!\" "^a^"!\"");
let fake=Cryptokit.transform_string(Cryptokit.Base64.encode_compact())(String.make 128 'x')in
write(named"wrong-magic"player)(a^fake^"\" "^a^fake^"\"");
write(named"duplicate-preview"player)(original^a^fake^"\"");
write(named"single-preview"player)(a^fake^"\"");
let wav bytes=let b=Bytes.make bytes '\000'in
let put offset s=Bytes.blit_string s 0 b offset(String.length s)in
let u16 i n=Bytes.set b i(Char.chr(n land 255));Bytes.set b(i+1)(Char.chr((n lsr 8) land 255))in
let u32 i n=u16 i(n land 65535);u16(i+2)(n lsr 16)in
put 0"RIFF";u32 4(bytes-8);put 8"WAVEfmt ";u32 16 16;u16 20 1;u16 22 1;u32 24 22050;u32 28 44100;u16 32 2;u16 34 16;put 36"data";u32 40(bytes-44);Bytes.to_string b in
write(named"exact-wav"mix)(wav 4194304);
write(named"oversize-wav"mix)(String.make 4194305 'x');
let bad=Bytes.of_string(wav 100)in Bytes.set bad 4 '\000';write(named"bad-wav-size"mix)(Bytes.to_string bad);
Yojson.Safe.to_file(stage^"/fixture-scope.json")(`Assoc["scope",`String"Private read-refusal and exact-bound fixtures; zero-filled PCM is a structural fixture, no musical or playback evidence";"cases",`Int 18;"root",`String root]);print_endline root
