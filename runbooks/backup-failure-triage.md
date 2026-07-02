# Backup Failure Triage

Use this runbook when a backup job fails or `backup-restore/backup-status-report.sql` shows a database going stale. A missed backup isn't an inconvenience — it's your RPO silently growing until someone needs a restore.

## 1. Measure the exposure first

```sql
:r backup-restore/backup-status-report.sql
```

Before debugging anything, know the stakes:

- Which databases are affected and how far back the last good full/diff/log is — that gap **is** the current data-loss exposure.
- A `FULL`-recovery database with failing **log** backups has a second problem coming: the log file grows until the drive fills (see `runbooks/disk-space-emergency.md`).

If the exposure already violates the agreed RPO, say so to the service owner now, not after you've fixed it.

## 2. Get the real error

```sql
:r monitoring/agent-job-status.sql
```

The job's last-run message often truncates the useful part. Get the full text from the step history (job → View History → step details) and the SQL Server error log — backup failures log there with the underlying OS error code. Common causes, roughly in order of frequency:

| Symptom in error text | Cause | Fix |
|---|---|---|
| Operating system error 3/53/67 (path/network) | Backup share moved, renamed, or DNS/permissions changed | Fix the path or the job's target; test with a manual backup |
| Operating system error 5 (access denied) | Service account lost write permission on the target | Restore the ACL; check for recent security "cleanup" |
| Operating system error 112 (not enough space) | Backup target full — often old backups not being purged | Free space; fix the retention/cleanup step (step 4) |
| `BACKUP detected corruption` / checksum error | Damaged page hit during backup | Stop — switch to `runbooks/corruption-response.md`; the backup failure just found real corruption |
| Semaphore timeout / VDI errors | Third-party backup tool or snapshot agent issues | Check the tool's own logs; try a native backup to isolate |
| Deadlocked or blocked by other maintenance | CHECKDB/rebuilds overlapping the backup window | Re-sequence the maintenance schedule |

## 3. Close the gap — don't wait for the next schedule

Once the cause is fixed, run the missed backup **manually now**:

```sql
BACKUP DATABASE [YourDatabase] TO DISK = N'...' WITH CHECKSUM, COMPRESSION, STATS = 10;
-- and for FULL-recovery databases:
BACKUP LOG [YourDatabase] TO DISK = N'...' WITH CHECKSUM, COMPRESSION;
```

Then verify the chain is actually usable, not just present:

- Re-run `backup-restore/backup-status-report.sql` — everything back to `OK`.
- Run `backup-restore/restore-command-generator.sql` for the affected database — if it can build a complete sequence to now, the chain is whole. If log backups were failing long enough that the chain broke, take a fresh **full** backup to start a new chain, and note the unprotected window.
- `RESTORE VERIFYONLY FROM DISK = N'...' WITH CHECKSUM;` on the new backup file.

## 4. Check what else was quietly wrong

One failure often hides another with the same root cause:

- Other jobs writing to the same target (other instances, log shipping, cleanup steps) — `monitoring/agent-job-status.sql` across the estate.
- Retention cleanup: if backups are kept forever the target *will* fill; if cleanup is too aggressive it may be deleting the only full backup your diffs and logs depend on.
- Alerting: this triage should have started from an alert, not a user request. If it didn't, add failure notifications (job operator + alert on the backup job) before closing.

## 5. Close out

Record: affected databases, exposure window (last good backup → first new good backup), root cause, and the detection gap. If the failure ran for days unnoticed, the action item is monitoring, not the backup job.
