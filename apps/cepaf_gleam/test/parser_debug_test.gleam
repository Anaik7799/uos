import cepaf_gleam/planning/parser
import gleam/int
import gleam/io
import gleam/list
import gleam/regexp

pub fn debug_parser_test() {
  let content =
    "# PROJECT TODOLIST\n\n## 1.1.1 - Test task (P0) [COMPLETED]\n## 1.1.2 - Another task (P1) [PENDING]\n"
  let re = parser.main_todo_regex()
  let lines = [
    "## 1.1.1 - Test task (P0) [COMPLETED]",
    "## 1.1.2 - Another task (P1) [PENDING]",
  ]
  list.each(lines, fn(line) {
    let matches = regexp.scan(re, line)
    io.println("Line: " <> line)
    io.println("Matches: " <> int.to_string(list.length(matches)))
  })
  let tasks = parser.parse_todolist(content)
  io.println("Parsed tasks: " <> int.to_string(list.length(tasks)))
}
