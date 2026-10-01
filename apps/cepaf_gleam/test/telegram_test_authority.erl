-module(telegram_test_authority).
-export([
    seed_test_sa_plan_task/6
]).

%% @doc Seeds an executing task record into a test SQLite database for test verification.
-spec seed_test_sa_plan_task(binary(), binary(), binary(), binary(), integer(), integer()) ->
    {ok, nil} | {error, term()}.
seed_test_sa_plan_task(DbPath0, PlanId, TaskId, Worker, Attempt, LeaseUntilNs) ->
    DbPath = to_path_list(DbPath0),
    case esqlite3:open(DbPath) of
        {ok, Conn} ->
            try
                ok = esqlite3:exec(Conn,
                    "CREATE TABLE IF NOT EXISTS sa_plan_plan ("
                    "  id TEXT PRIMARY KEY"
                    ");"
                    "CREATE TABLE IF NOT EXISTS sa_plan_task ("
                    "  plan_id TEXT NOT NULL,"
                    "  id TEXT NOT NULL,"
                    "  name TEXT,"
                    "  ordinal INTEGER NOT NULL DEFAULT 1,"
                    "  parent_id TEXT,"
                    "  task_type TEXT NOT NULL DEFAULT 'standard',"
                    "  title TEXT NOT NULL DEFAULT 'test task',"
                    "  estimate_points INTEGER,"
                    "  priority INTEGER NOT NULL DEFAULT 0,"
                    "  state TEXT NOT NULL CHECK (state IN ('available','executing','completed')),"
                    "  worker TEXT,"
                    "  lease_until_ns INTEGER,"
                    "  attempt INTEGER NOT NULL DEFAULT 0,"
                    "  result TEXT,"
                    "  completed_at_ns INTEGER,"
                    "  PRIMARY KEY (plan_id, id)"
                    ");"
                    "CREATE TABLE IF NOT EXISTS sa_plan_dependency ("
                    "  plan_id TEXT NOT NULL,"
                    "  task_id TEXT NOT NULL,"
                    "  dependency_id TEXT NOT NULL,"
                    "  PRIMARY KEY (plan_id, task_id, dependency_id)"
                    ");"),
                _ = esqlite3:q(Conn, "INSERT OR IGNORE INTO sa_plan_plan (id) VALUES (?);", [PlanId]),
                _ = esqlite3:q(Conn, "INSERT OR REPLACE INTO sa_plan_task "
                               "(plan_id, id, name, ordinal, parent_id, task_type, title, estimate_points, priority, state, worker, lease_until_ns, attempt) "
                               "VALUES (?, ?, ?, 1, NULL, 'standard', 'test task', 0, 0, 'executing', ?, ?, ?);",
                               [PlanId, TaskId, TaskId, Worker, LeaseUntilNs, Attempt]),
                {ok, nil}
            catch
                Class:Reason ->
                    {error, {Class, Reason}}
            after
                try esqlite3:close(Conn) catch _:_ -> ok end
            end;
        {error, Err} ->
            {error, Err}
    end.

to_path_list(Path) when is_binary(Path) -> unicode:characters_to_list(Path);
to_path_list(Path) when is_list(Path) -> Path.
