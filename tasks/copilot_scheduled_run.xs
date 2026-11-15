// COP-5 story 05 — every hour: the copilot works on its own tasks for every business where the owner switched scheduled work on (approval level scheduled_work; off by default). The whole rule lives in copilot/scheduled_run (one place): it closes runs that never finished, runs each switched-on business once (a unique lock stops two runs overlapping), and always writes a COP-5 run_tick event with the counts, even when nothing ran — a task that writes nothing looks healthy.
task copilot_scheduled_run {
  stack {
    function.run "copilot/scheduled_run" {
      input = {account_id: 0, trigger: "schedule"}
    } as $result
  }

  schedule = [{starts_on: 2026-11-15 21:20:00+0000, freq: 3600}]
}
