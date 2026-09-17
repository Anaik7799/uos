with open("tools/run_tri_sovereign_c501_c505_review.py") as f:
    text = f.read()

old_insert = """        cur_plan.execute(\"\"\"
            INSERT OR REPLACE INTO sa_plan_task (
                plan_id, id, ordinal, task_type, description, status,
                assigned_worker, created_at_ns, completed_at_ns
            ) VALUES (?, ?, ?, ?, ?, 'completed', ?, ?, ?)
        \"\"\", (
            PLAN_ID,
            task_id,
            ord_idx,
            ttype,
            desc,
            WORKER_CLAUDE,
            start_ns,
            now_ns()
        ))"""

new_insert = """        cur_plan.execute(\"\"\"
            INSERT OR REPLACE INTO sa_plan_task (
                plan_id, id, name, ordinal, task_type, title, state,
                worker, completed_at_ns
            ) VALUES (?, ?, ?, ?, ?, ?, 'completed', ?, ?)
        \"\"\", (
            PLAN_ID,
            task_id,
            task_id,
            ord_idx,
            ttype,
            desc,
            WORKER_CLAUDE,
            now_ns()
        ))"""

assert old_insert in text, "Could not find old_insert"
text = text.replace(old_insert, new_insert)

with open("tools/run_tri_sovereign_c501_c505_review.py", "w") as f:
    f.write(text)

print("Fixed sa_plan_task insert!")
