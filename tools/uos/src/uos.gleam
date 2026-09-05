import main

@external(erlang, "uos_ffi", "get_arguments")
fn get_arguments() -> List(String)

pub fn main() {
  let args = get_arguments()
  let cmd = main.parse_args(args)
  main.execute(cmd)
}
