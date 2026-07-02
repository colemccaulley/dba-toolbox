# Disk Space Emergency

Use this runbook when a SQL Server drive is at or near 100%. When a data or log drive fills completely, writes stop (error 9002 for log, 1105 for data) and the databases on it effectively go read-only or offline — treat sub-5% free on a SQL volume as an active incident.

## 1. Find what is consuming and what is still growing

```sql
:r health-checks/server-health-check.sql      -- drive free-space section
:r health-checks/database-size-report.sql     -- file sizes, growth settings, free space inside files
```

Identify the specific file(s) that grew. The fix differs completely depending on whether it's a **transaction log**, **tempdb**, or a **data file** — don't act until you know which.

## 2. Transaction log full (the most common case)

First ask the database why it can't reuse the log:

```sql
SELECT name, log_reuse_wait_desc FROM sys.databases ORDER BY name;
```

| `log_reuse_wait_desc` | Meaning | Fix |
|---|---|---|
| `LOG_BACKUP` | FULL recovery, log backups missing or too infrequent | Take a log backup **now**; fix the schedule |
| `ACTIVE_TRANSACTION` | A long-running/open transaction pins the log | Find it (`monitoring/long-running-requests.sql`, `OpenTrans > 0`); commit, or kill with rollback-size awareness (`runbooks/blocking-incident-response.md` step 4) |
| `AVAILABILITY_REPLICA` | An AG secondary is behind or suspended | `ha-dr/availability-group-health.sql` — resume/fix the replica; the log clears once it catches up |
| `REPLICATION` / `CDC` | Log reader hasn't processed the log | Check the log reader agent / CDC jobs |
| `ACTIVE_BACKUP_OR_RESTORE` | A running backup pins the log | Usually just wait; check `PctComplete` in long-running-requests |

After the cause is cleared and a log backup has run, the log file has free *internal* space but is still huge on disk. Shrinking a log file is the **one routinely acceptable shrink**:

```sql
DBCC SHRINKFILE (N'YourDatabase_log', 8192);   -- target MB: size it for normal workload, not for zero
```

Then set a sane autogrowth (fixed MB, not percent) so it doesn't creep back via tiny growths.

## 3. tempdb full

- Find the consumers: `monitoring/long-running-requests.sql` — big sorts, hash spills, and version-store users (long snapshot transactions) are the usual causes.
- Killing the offending session releases its tempdb allocation.
- **Do not restart the instance just to clear tempdb** while sessions are killable — a restart takes everything down and loses all diagnostic state. It's the fallback, not the first move.
- Afterwards, check `health-checks/tempdb-configuration-check.sql`: undersized, unevenly sized, or growth-capped tempdb files make this recur.

## 4. Data file / drive genuinely full

Short term, in order of preference:

1. **Delete non-database junk on the volume** — old trace files, dumps, copied backups. (Never delete live `.mdf/.ndf/.ldf` files, and don't delete backup files that are part of the current retention chain without checking `backup-restore/backup-status-report.sql`.)
2. **Move a database's files to a roomier volume** (requires brief downtime: `ALTER DATABASE ... MODIFY FILE` + offline/online move).
3. **Add a data file on another volume** to the full filegroup — new allocations flow there immediately, no downtime.

**Avoid `DBCC SHRINKDATABASE` / shrinking data files** as the fix. It fragments every index it moves, the space usually grows right back, and it can run for hours generating I/O during your emergency. If a one-time event (archive delete, dropped table) genuinely freed a large fraction of a file and it will never be reused, shrink once, off-hours, then rebuild the fragmented indexes.

## 5. Prevent the next one

- `capacity-planning/database-growth-trend.sql` — project when each volume runs out at current growth; put a review date on the calendar *before* that.
- Alert at 20%/10% free (page at 10%), not at 2% when options have run out.
- Review autogrowth settings from `health-checks/database-size-report.sql`: percent-growth on large files produces monster growth events; unlimited growth on a shared volume lets one database starve its neighbors.
- Confirm msdb history cleanup and old-backup retention jobs exist and run (`monitoring/agent-job-status.sql`).
