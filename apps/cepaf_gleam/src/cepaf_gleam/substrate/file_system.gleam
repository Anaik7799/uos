import gleam/bit_array

pub type FileError {
  FileNotFound
  PermissionDenied
  Other(String)
}

@external(erlang, "cepaf_gleam_ffi", "file_read")
fn erl_file_read(path: String) -> Result(BitArray, String)

@external(erlang, "cepaf_gleam_ffi", "file_write")
fn erl_file_write(path: String, content: BitArray) -> Result(Nil, String)

pub fn read_file(path: String) -> Result(String, String) {
  case erl_file_read(path) {
    Ok(binary) -> {
      case bit_array.to_string(binary) {
        Ok(s) -> Ok(s)
        Error(_) -> Error("Invalid UTF-8")
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn write_file(path: String, content: String) -> Result(Nil, String) {
  erl_file_write(path, bit_array.from_string(content))
}

@external(erlang, "cepaf_gleam_ffi", "file_rename")
fn erl_file_rename(old: String, new: String) -> Result(Nil, String)

@external(erlang, "cepaf_gleam_ffi", "os_cmd")
fn erl_os_cmd(cmd: String) -> Result(BitArray, BitArray)

pub fn write_file_atomic(path: String, content: String) -> Result(Nil, String) {
  let tmp_path = path <> ".tmp"
  case write_file(tmp_path, content) {
    Ok(_) -> erl_file_rename(tmp_path, path)
    Error(e) -> Error(e)
  }
}

pub fn run_cmd(cmd: String) -> Result(String, String) {
  case erl_os_cmd(cmd) {
    Ok(result) -> {
      case bit_array.to_string(result) {
        Ok(s) -> Ok(s)
        Error(_) -> Error("Command output invalid UTF-8")
      }
    }
    Error(e) -> {
      case bit_array.to_string(e) {
        Ok(s) -> Error(s)
        Error(_) -> Error("Command error invalid UTF-8")
      }
    }
  }
}

pub fn git_sync(path: String, message: String) -> Result(String, String) {
  let cmd = "git add " <> path <> " && git commit -m \"" <> message <> "\""
  run_cmd(cmd)
}
