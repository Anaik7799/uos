//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/planning/parser</module>
////     <fsharp-lineage>Cepaf.Core.Planning.Parser.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <mesh-domain>Markdown Todolist Parsing</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-PLAN-002</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="fparsec">
////       F# `FParsec` ↠ Gleam `regexp` parsing.
////       Mitigation: Explicit regular expressions mapped directly to the AST.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/core/ids
import cepaf_gleam/core/types
import cepaf_gleam/planning/domain.{type Task, Task}
import gleam/list
import gleam/option.{None, Some}
import gleam/regexp
import gleam/set
import gleam/string

pub fn main_todo_regex() -> regexp.Regexp {
  let assert Ok(re) =
    regexp.from_string("^##\\s*([\\d\\.]+)\\s*-\\s*(.*?)\\s*\\[(.*?)\\]$")
  re
}

pub fn priority_regex() -> regexp.Regexp {
  let assert Ok(re) = regexp.from_string("\\((P\\d)\\)")
  re
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Valid markdown text string. </P>
///     <C> parse_todolist(content) </C>
///     <Q> Returns a list of strictly-typed Domain Task records. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn parse_todolist(content: String) -> List(Task) {
  let lines = string.split(content, "\n")
  let parsed_tasks: List(Task) = []

  let res =
    list.try_fold(lines, parsed_tasks, fn(acc, line) {
      let trimmed_line = string.trim(line)

      // Skip empty lines only; let regex handle the ## matching
      case trimmed_line == "" {
        True -> Ok(acc)
        False -> {
          case regexp.scan(main_todo_regex(), trimmed_line) {
            [match] -> {
              case match.submatches {
                [Some(id_str), Some(full_desc), Some(status_str)] -> {
                  let priority_str = case
                    regexp.scan(priority_regex(), full_desc)
                  {
                    [p_match] -> {
                      case p_match.submatches {
                        [Some(p)] -> p
                        _ -> "P2"
                      }
                    }
                    _ -> "P2"
                  }

                  let desc_clean =
                    string.replace(full_desc, "(" <> priority_str <> ")", "")
                    |> string.trim()

                  let id = ids.task_id_from_string(id_str)
                  let title = case types.new_non_empty_string(desc_clean) {
                    Ok(t) -> t
                    Error(_) -> {
                      let assert Ok(t) = types.new_non_empty_string("Untitled")
                      t
                    }
                  }

                  let task =
                    Task(
                      id: id,
                      title: title,
                      description: None,
                      status: types.task_status_from_string(status_str),
                      priority: types.priority_from_string(priority_str),
                      created_at: "2026-04-01T00:00:00Z",
                      updated_at: "2026-04-01T00:00:00Z",
                      due_date: None,
                      completed_at: None,
                      assignee_id: None,
                      project_id: None,
                      sprint_id: None,
                      parent_task_id: None,
                      tags: set.new(),
                      dependencies: set.new(),
                      estimated_minutes: None,
                      actual_minutes: None,
                      version: 0,
                    )

                  Ok(list.append(acc, [task]))
                }
                _ -> Ok(acc)
                // Submatch extraction failed, skip silently
              }
            }
            [] -> Ok(acc)
            // Skip non-matching lines
            _ -> Ok(acc)
          }
        }
      }
    })

  case res {
    Ok(tasks) -> tasks
    Error(_) -> []
  }
}

pub fn parse_todolist_sqlite_output(content: String) -> List(Task) {
  let lines = string.split(content, "\n")
  list.filter_map(lines, fn(line) {
    case string.split(line, "|") {
      [id, title, status, priority, created, parent_id, owner] -> {
        Ok(Task(
          id: ids.task_id_from_string(id),
          title: case types.new_non_empty_string(title) {
            Ok(t) -> t
            Error(_) -> {
              let assert Ok(t) = types.new_non_empty_string("Untitled")
              t
            }
          },
          description: None,
          status: types.task_status_from_string(status),
          priority: types.priority_from_string(priority),
          created_at: created,
          updated_at: created,
          due_date: None,
          completed_at: None,
          assignee_id: case owner {
            "" -> None
            _ -> Some(ids.user_id_from_string(owner))
          },
          project_id: None,
          sprint_id: None,
          parent_task_id: case parent_id {
            "" -> None
            _ -> Some(ids.task_id_from_string(parent_id))
          },
          tags: set.new(),
          dependencies: set.new(),
          estimated_minutes: None,
          actual_minutes: None,
          version: 0,
        ))
      }
      _ -> Error(Nil)
    }
  })
}

pub fn serialize_todolist(tasks: List(Task)) -> String {
  "# PROJECT TODOLIST (Generated by Cepaf.Planning)\n\n"
  <> {
    list.map(tasks, serialize_task)
    |> string.join("\n")
  }
}

fn serialize_task(task: Task) -> String {
  let id = ids.task_id_to_string(task.id)
  let title = types.non_empty_string_value(task.title)
  "## "
  <> id
  <> " - "
  <> title
  <> " ("
  <> types.priority_to_string(task.priority)
  <> ") ["
  <> string.uppercase(types.task_status_to_string(task.status))
  <> "]"
}
