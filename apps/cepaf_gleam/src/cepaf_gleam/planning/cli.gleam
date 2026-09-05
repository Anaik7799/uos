import cepaf_gleam/core/ids
import cepaf_gleam/core/types
import cepaf_gleam/planning/domain
import cepaf_gleam/planning/manager
import cepaf_gleam/planning/parser
import cepaf_gleam/planning/task
import cepaf_gleam/substrate/file_system
import gleam/int
import gleam/io
import gleam/list

// =============================================================================
// Task Management CLI Entrypoint
// =============================================================================

import cepaf_gleam/podman/domain as podman_domain
import cepaf_gleam/podman/http_client
import cepaf_gleam/podman/manager as podman_manager

pub fn run(args: List(String)) -> Nil {
  case args {
    ["status"] -> show_status()
    ["list"] -> show_status()
    ["start", id] -> start_task(id)
    ["complete", id] -> complete_task(id)
    ["sync"] -> sync_todolist()
    ["add", title, priority] -> add_task(title, priority)
    ["delete", id] -> delete_task(id)
    ["dispatch", id] -> dispatch_task(id)
    ["update", id, status, priority] -> update_task(id, status, priority)
    // Mesh Commands
    ["up"] -> start_mesh()
    ["down"] -> stop_mesh()
    ["mesh-status"] -> check_mesh_status()
    ["restart-node", name] -> restart_node(name)
    _ ->
      io.println(
        "Usage: sa-plan [status|list|start|complete|sync|add|delete|dispatch|update|up|down|mesh-status|restart-node]",
      )
  }
}

fn get_podman_client() {
  let uid = get_uid_cli()
  let socket_path = "/run/user/" <> uid <> "/podman/podman.sock"
  let config =
    podman_domain.PodmanClientConfig(
      socket: podman_domain.Rootless(uid: uid, path: socket_path),
      api_version: "5.7.0",
      timeout_ms: 30_000,
      retry_count: 3,
      retry_delay_ms: 1000,
    )
  http_client.create(config)
}

@external(erlang, "cepaf_gleam_ffi", "get_uid")
fn get_uid_cli() -> String

fn start_mesh() {
  let client = get_podman_client()
  case podman_manager.start_mesh(client) {
    Ok(_) -> io.println("✅ Mesh started successfully.")
    Error(e) -> io.println("❌ Error starting mesh: " <> e)
  }
}

fn stop_mesh() {
  let client = get_podman_client()
  case podman_manager.stop_mesh(client) {
    Ok(_) -> io.println("✅ Mesh stopped.")
    Error(e) -> io.println("❌ Error stopping mesh: " <> e)
  }
}

fn check_mesh_status() {
  let client = get_podman_client()
  case podman_manager.check_mesh_status(client) {
    Ok(_) -> Nil
    Error(e) -> io.println("❌ Error checking status: " <> e)
  }
}

fn restart_node(name: String) {
  let client = get_podman_client()
  case podman_manager.restart_container(client, name) {
    Ok(_) -> io.println("✅ Node " <> name <> " restarted.")
    Error(e) -> io.println("❌ Error restarting node: " <> e)
  }
}

fn show_status() {
  // 1. Try remote authoritative state first (Centralized State Mandate)
  case manager.list_tasks_remote() {
    Ok(tasks) -> {
      io.println("📋 TASK STATUS (Authoritative sa-plan-daemon):")
      render_task_list(tasks)
    }
    Error(_) -> {
      // 2. Fallback to SQLite (Local)
      let db_paths = [
        "/home/an/dev/ver/c3i/sub-projects/c3i/data/smriti/Smriti.db",
        "../../sub-projects/c3i/data/smriti/Smriti.db",
        "sub-projects/c3i/data/smriti/Smriti.db",
        "data/smriti/Smriti.db",
      ]

      let tasks_res =
        list.find_map(db_paths, fn(path) {
          case manager.list_tasks_sqlite(path) {
            Ok(tasks) -> Ok(tasks)
            Error(_) -> Error(Nil)
          }
        })

      case tasks_res {
        Ok(tasks) -> {
          io.println("📋 TASK STATUS (Local SQLite Fallback):")
          render_task_list(tasks)
        }
        Error(_) -> {
          let _ = manager.init_db()
          case manager.list_tasks() {
            Ok(tasks) -> {
              io.println("📋 TASK STATUS (Local DuckDB Fallback):")
              render_task_list(tasks)
            }
            Error(e) -> io.println("Error listing tasks: " <> e)
          }
        }
      }
    }
  }
}

fn render_task_list(tasks: List(domain.Task)) {
  list.each(tasks, fn(t) {
    let status = types.task_status_to_string(t.status)
    let id = ids.task_id_to_string(t.id)
    let title = types.non_empty_string_value(t.title)
    let priority = types.priority_to_string(t.priority)
    io.println(
      "  - [" <> status <> "] (" <> priority <> ") " <> id <> ": " <> title,
    )
  })
}

fn add_task(title: String, priority_str: String) {
  case manager.add_task_remote(title, priority_str) {
    Ok(id) -> io.println("✅ Task created (remote): " <> id)
    Error(_) -> {
      // Fallback to local
      let _ = manager.init_db()
      let priority = types.priority_from_string(priority_str)
      case manager.create_task(title, priority) {
        Ok(task) -> {
          let _ = manager.upsert_task(task)
          io.println(
            "✅ Task created (local): " <> ids.task_id_to_string(task.id),
          )
        }
        Error(e) -> io.println("❌ Error creating task: " <> e)
      }
    }
  }
}

fn delete_task(id: String) {
  case manager.delete_task_remote(id) {
    Ok(_) -> io.println("✅ Task deleted (remote): " <> id)
    Error(_) -> {
      // Fallback to local
      let _ = manager.init_db()
      case manager.delete_task(id) {
        Ok(_) -> io.println("✅ Task deleted (local): " <> id)
        Error(e) -> io.println("❌ Error deleting task: " <> e)
      }
    }
  }
}

fn dispatch_task(id: String) {
  let _ = manager.init_db()
  case manager.dispatch_task(id) {
    Ok(_) -> io.println("✅ Task dispatched: " <> id)
    Error(e) -> io.println("❌ Error dispatching task: " <> e)
  }
}

fn update_task(id: String, status_str: String, priority_str: String) {
  case manager.update_task_remote(id, status_str) {
    Ok(_) -> io.println("✅ Task updated (remote): " <> id)
    Error(_) -> {
      // Fallback to local
      let _ = manager.init_db()
      case manager.list_tasks() {
        Ok(tasks) -> {
          case manager.find_task(tasks, id) {
            Ok(task_obj) -> {
              let status = types.task_status_from_string(status_str)
              let priority = types.priority_from_string(priority_str)
              let updated =
                task_obj
                |> task.set_status(status)
                |> task.set_priority(priority)
              let _ = manager.upsert_task(updated)
              io.println("✅ Task updated (local): " <> id)
            }
            Error(_) -> io.println("❌ Task not found: " <> id)
          }
        }
        Error(e) -> io.println("Error reading tasks: " <> e)
      }
    }
  }
}

fn start_task(id: String) {
  case manager.update_task_remote(id, "in_progress") {
    Ok(_) -> io.println("✅ Task started (remote): " <> id)
    Error(_) -> {
      // Fallback to local
      let _ = manager.init_db()
      case manager.list_tasks() {
        Ok(tasks) -> {
          case manager.find_task(tasks, id) {
            Ok(task) -> {
              case manager.update_task_status(task, types.InProgress) {
                Ok(updated) -> {
                  let _ = manager.upsert_task(updated)
                  io.println("✅ Task started (local): " <> id)
                }
                Error(_) -> io.println("❌ Invalid transition for task: " <> id)
              }
            }
            Error(_) -> io.println("❌ Task not found: " <> id)
          }
        }
        Error(e) -> io.println("Error reading tasks: " <> e)
      }
    }
  }
}

fn complete_task(id: String) {
  case manager.update_task_remote(id, "completed") {
    Ok(_) -> io.println("✅ Task completed (remote): " <> id)
    Error(_) -> {
      // Fallback to local
      let _ = manager.init_db()
      case manager.list_tasks() {
        Ok(tasks) -> {
          case manager.find_task(tasks, id) {
            Ok(task) -> {
              case manager.update_task_status(task, types.Completed) {
                Ok(updated) -> {
                  let _ = manager.upsert_task(updated)
                  io.println("✅ Task completed (local): " <> id)
                }
                Error(_) -> io.println("❌ Invalid transition for task: " <> id)
              }
            }
            Error(_) -> io.println("❌ Task not found: " <> id)
          }
        }
        Error(e) -> io.println("Error reading tasks: " <> e)
      }
    }
  }
}

fn sync_todolist() {
  io.println("Synchronizing PROJECT_TODOLIST.md...")
  case manager.sync_todolist_remote() {
    Ok(_) -> io.println("✅ Global sync complete (remote).")
    Error(_) -> {
      io.println("  [!] Remote sync failed, attempting local fallback...")
      let _ = manager.init_db()
      let paths = ["PROJECT_TODOLIST.md", "../../PROJECT_TODOLIST.md"]
      let result =
        list.find_map(paths, fn(path) {
          case file_system.read_file(path) {
            Ok(content) -> Ok(#(path, content))
            Error(_) -> Error(Nil)
          }
        })

      case result {
        Ok(#(path, content)) -> {
          io.println("  [found] " <> path)
          let tasks = parser.parse_todolist(content)
          list.each(tasks, fn(t) {
            let _ = manager.upsert_task(t)
          })
          io.println(
            "✅ Local sync complete. "
            <> int.to_string(list.length(tasks))
            <> " tasks processed.",
          )
        }
        Error(_) ->
          io.println("❌ PROJECT_TODOLIST.md not found in common paths.")
      }
    }
  }
}
