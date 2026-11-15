// COP-2 story 06 — every hour: remind once about copilot actions waiting over 24 hours, and expire those waiting over 72 hours. Expired actions are never carried out; silence never approves anything (decision D-5). The rule itself lives in copilot/expire_waiting (one place); the Approvals screen runs the same function per account before listing. Live task id 20.
task copilot_expire_waiting {
  stack {
    function.run "copilot/expire_waiting" {
      input = {account_id: 0}
    } as $result
  }

  schedule = [{starts_on: 2026-11-15 07:00:00+0000, freq: 3600}]
}
