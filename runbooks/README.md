# Runbooks

Operator-facing procedures that tie the toolbox scripts into decisions. Each runbook assumes you're under some pressure, so they lead with what to check and what *not* to do.

## Pick by symptom

| You're facing | Runbook |
|---|---|
| New/unfamiliar instance, need a baseline | [`day-one-instance-review.md`](day-one-instance-review.md) |
| "Everything is slow" | [`performance-triage.md`](performance-triage.md) |
| Timeouts, sessions hanging on locks | [`blocking-incident-response.md`](blocking-incident-response.md) |
| Data lost or bad, need to rewind a database | [`point-in-time-restore.md`](point-in-time-restore.md) |
| CHECKDB errors, SUSPECT database, 823/824/825 | [`corruption-response.md`](corruption-response.md) |
| Drive full or filling fast | [`disk-space-emergency.md`](disk-space-emergency.md) |
| Backup job failed / backups going stale | [`backup-failure-triage.md`](backup-failure-triage.md) |
| AG failover — planned or forced | [`ag-failover-response.md`](ag-failover-response.md) |
| Moving a database to a new instance | [`migration-cutover.md`](migration-cutover.md) |

## Conventions

- `:r path/script.sql` lines are SQLCMD-mode includes; run the referenced script from the repo root in SSMS (SQLCMD mode) or `sqlcmd`.
- Runbooks never assume permission to change things: destructive or high-impact steps call out the approval to obtain and the evidence to record first.
- Save the script outputs referenced in a runbook while the incident is live — the PowerShell wrapper (`powershell/Invoke-DbaToolboxAssessment.ps1`) writes CSVs if you need one-command capture.
- Every incident runbook ends with a close-out step. The write-up is part of the job: an incident without a prevention item will repeat.
