import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/restoration_observer as observer
import gleam/erlang/process
import gleam/string

pub fn inactive_missing_and_mixed_services_are_not_healthy_test() {
  let active =
    "ActiveState=active\nActiveState=active\nActiveState=active\nActiveState=active\nActiveState=active\n"
  assert observer.services_active(active)
  assert !observer.services_active("")
  assert !observer.services_active("ActiveState=active\n")
  assert !observer.services_active(active <> "ActiveState=failed\n")
  assert !observer.services_active(
    "ActiveState=active\nActiveState=active\nActiveState=failed\nActiveState=active\nActiveState=active\n",
  )
}

pub fn observer_refuses_private_path_escape_test() {
  assert observer.load("../grant.json", "review.json")
    == Error("private_filenames")
  assert observer.load("grant.json", "../review.json")
    == Error("private_filenames")
}

pub fn stopped_worker_is_observed_without_restart_wait_test() {
  let pid = process.spawn_unlinked(fn() { process.sleep(10) })
  assert observer.wait_for_worker(pid, 1000) == Error("observer_worker_stopped")
}

pub fn live_worker_wait_is_bounded_test() {
  let pid = process.spawn_unlinked(fn() { process.sleep(1000) })
  let result = observer.wait_for_worker(pid, 10)
  process.kill(pid)
  assert result == Error("observer_process_window_expired")
}

fn query(sql: String) -> String {
  let assert Ok(raw) =
    dev.bounded("/usr/bin/sqlite3", ["-batch", ":memory:", sql], 3000)
  string.trim(raw)
}

pub fn task_scope_is_date_independent_and_excludes_near_matches_test() {
  let fixture =
    "WITH rows(name,plan_id) AS (VALUES "
    <> "('a','uos/full-merge/20261025-0638'),"
    <> "('b','uos/telegram-runtime/20271025-0101'),"
    <> "('c','uos/telegram-new_feature/20300101-0000'),"
    <> "('d','uos/agy-operations/20280101-0000'),"
    <> "('x1','unrelated/20261024'),"
    <> "('x2','x/uos/full-merge/20261025-0638'),"
    <> "('x3','uos/full-merge-other/20261025-0638'),"
    <> "('x4','uos/agy-operations-other/20261024'),"
    <> "('x5','uos/full-merge/'),"
    <> "('x6','uos/telegram-/')) "
  let actual =
    query(
      fixture
      <> "SELECT group_concat(name, ',') FROM (SELECT name FROM rows WHERE "
      <> observer.task_filter()
      <> " ORDER BY name);",
    )
  assert actual == "a,b,c,d"
}

pub fn job_scope_includes_parent_plan_and_legacy_names_without_parsing_bad_json_test() {
  let fixture =
    "WITH rows(name,id,args) AS (VALUES "
    <> "('a','uos/full-merge/20261025-0638/review','broken-json'),"
    <> "('b','opaque-job','{\"plan\":\"uos/full-merge/20271025-0638\"}'),"
    <> "('c','opaque-telegram','{\"plan\":\"uos/telegram-media/20300101-0000\"}'),"
    <> "('d','telegram/command-catalog1335','not-json'),"
    <> "('e','uos/agy-operations/20280101-0000/review','{}'),"
    <> "('x1','unrelated/20261024','{}'),"
    <> "('x2','malformed','not-json'),"
    <> "('x3','near','{\"plan\":\"uos/full-merge-other/20261025\"}'),"
    <> "('x4','uos/agy-operations-other/20261024','{}'),"
    <> "('x5','telegram/','{}'),"
    <> "('x6','wrong-field','{\"other\":\"uos/full-merge/20261025\"}')) "
  let actual =
    query(
      fixture
      <> "SELECT group_concat(name, ',') FROM (SELECT name FROM rows WHERE "
      <> observer.job_filter()
      <> " ORDER BY name);",
    )
  assert actual == "a,b,c,d,e"
}

pub fn completion_marker_ignores_unrelated_and_incomplete_work_test() {
  let fixture =
    "CREATE TABLE sa_plan_task(plan_id TEXT,state TEXT,completed_at_ns INTEGER);"
    <> "INSERT INTO sa_plan_task VALUES "
    <> "('uos/full-merge/20261025-0638','completed',10),"
    <> "('uos/telegram-media/20300101-0000','completed',20),"
    <> "('uos/agy-operations/20261025','available',999),"
    <> "('unrelated/20261024','completed',1000);"
  assert query(fixture <> observer.completion_marker_query()) == "2:20"
  assert query(
      fixture
      <> "INSERT INTO sa_plan_task VALUES ('unrelated/new','completed',2000);"
      <> observer.completion_marker_query(),
    )
    == "2:20"
  assert query(
      fixture
      <> "INSERT INTO sa_plan_task VALUES ('uos/full-merge/20300101','completed',30);"
      <> observer.completion_marker_query(),
    )
    == "3:30"
}
