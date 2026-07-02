# Corruption Response

Use this runbook when DBCC CHECKDB reports errors, a database is marked SUSPECT/RECOVERY_PENDING, or the error log shows 823/824/825 I/O errors. Corruption incidents are won or lost on the first three decisions, so slow down.

## Rule zero: do not make it worse

Before anything else, know what **not** to do:

- **Do not restart SQL Server** "to see if it clears." It won't, and you may turn a partially accessible database into an inaccessible one.
- **Do not detach the database.** A detached suspect database may refuse to reattach — you've converted a repair problem into a much harder one.
- **Do not run `REPAIR_ALLOW_DATA_LOSS` as a first move.** The name is literal. It deallocates whatever it can't fix, and it's irreversible.
- **Do not delete or shrink anything** while you still need every byte of evidence and log.

Your backups are the primary recovery path. Everything else is fallback.

## 1. Capture the facts

```sql
-- What does the instance already know?
SELECT db_name(database_id) AS [Database], file_id, page_id,
       event_type, error_count, last_update_date
FROM msdb.dbo.suspect_pages
ORDER BY last_update_date DESC;
```

- Check the SQL Server error log for 823/824/825 messages (825 = read-retry succeeded: the storage is failing *and warning you first*).
- Check `health-checks/dbcc-checkdb-status.sql` — when was the last clean CHECKDB? That bounds when corruption could have appeared and which backups are known-good.
- If the database is online, get the full picture:

```sql
DBCC CHECKDB (N'YourDatabase') WITH NO_INFOMSGS, ALL_ERRORMSGS;
```

Save the complete output. The summary line tells you the minimum repair level; the per-object errors tell you what's actually damaged.

## 2. Classify the damage

The CHECKDB output determines the path:

| Damage | Path |
|---|---|
| Errors only in **nonclustered indexes** (index_id > 1) | Best case: drop and recreate the affected indexes. No data loss, no restore. |
| A few **data pages** in one table, FULL recovery, unbroken log chain | Page-level restore (Enterprise: online). Fast and surgical. |
| **Widespread data damage** or allocation errors | Full restore from backup. |
| Damage predates every backup you retain | Salvage: `REPAIR_ALLOW_DATA_LOSS` or manual extraction — with sign-off (step 5). |

For page restore, verify recovery model is FULL and the log chain from the last full backup is intact (`backup-restore/backup-status-report.sql`).

## 3. Restore path (default)

1. Take a **tail-log backup** if the log is still readable — it may make the recovery lossless:
   `BACKUP LOG [YourDatabase] TO DISK = N'...' WITH NO_TRUNCATE, NORECOVERY;`
2. Generate the sequence with `backup-restore/restore-command-generator.sql`. Restore **side-by-side first** if disk allows — confirm the backup itself is clean before overwriting anything.
3. Run `DBCC CHECKDB` on the restored copy. If the corruption is in the backup too, walk back to an older full and replay more log.
4. Cut over, then run application-level validation with the data owner.

## 4. Find the cause — corruption is a symptom

SQL Server almost never corrupts its own pages; the I/O path (disk, controller, driver, filter drivers, SAN firmware) does. In parallel with recovery:

- Get the storage/infrastructure team checking hardware logs for the volume.
- Check whether other databases on the same volume have issues (`suspect_pages` covers all databases).
- Confirm `PAGE_VERIFY = CHECKSUM` on every database and `backup checksum default = 1` — they don't prevent corruption, they make it detectable early.

Recovering onto failing storage means doing this again next week.

## 5. Salvage path (last resort, with sign-off)

Only when no viable backup exists, and only with the data owner's written acknowledgment of data loss:

```sql
ALTER DATABASE [YourDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC CHECKDB (N'YourDatabase', REPAIR_ALLOW_DATA_LOSS) WITH NO_INFOMSGS, ALL_ERRORMSGS;
ALTER DATABASE [YourDatabase] SET MULTI_USER;
```

Afterwards: re-run CHECKDB to confirm clean, run `DBCC CHECKCONSTRAINTS` (repair ignores constraints), and have the owner assess what was lost. Take a full backup immediately — this is the new baseline.

## 6. Close out

- Full backup of the recovered database; verify the next scheduled CHECKDB runs clean.
- Record: detection time, damage classification, path chosen, data-loss window (if any), root cause.
- Fix the gap that made this scary: CHECKDB not running weekly? Backups not covering the corruption window? Alerts on 823/824/825 and severity ≥ 24 not configured? At least one of those was true, or this incident would have been routine.
