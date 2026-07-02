# Point-in-Time Restore

Use this runbook when data has been lost or corrupted and a database (or a copy of it) must be recovered to a specific moment.

## 1. Establish scope and authority

- Confirm the database, the target point in time, and who is authorizing the restore.
- Decide restore-in-place vs. side-by-side. Prefer side-by-side (`@RestoreAsName`) when the goal is recovering specific rows: it avoids destroying the current state.
- If restoring in place, confirm applications are stopped or pointed elsewhere.

## 2. Protect what still exists

If the database is still accessible and you are about to overwrite it, take a tail-log backup first:

```sql
BACKUP LOG [YourDatabase] TO DISK = N'...\YourDatabase_tail.trn' WITH NORECOVERY, CHECKSUM;
```

This captures activity since the last log backup and (with `NORECOVERY`) puts the database into a restoring state so nothing changes underneath you.

## 3. Generate the restore sequence

Run `backup-restore/restore-command-generator.sql` with:

- `@DatabaseName` — the source database
- `@PointInTime` — the recovery target (`NULL` = latest possible)
- `@RestoreAsName` / `@DataFilePath` / `@LogFilePath` — for side-by-side restores
- `@IncludeReplace = 1` — only for a deliberate in-place overwrite

Review every generated command before running anything. Verify:

- The full/diff backups selected match your expectation (check the summary result set).
- The log chain is unbroken (script fails loudly if no full exists; a gap in logs shows up as fewer `RESTORE LOG` steps than expected).
- `MOVE` targets do not collide with the live database's files on side-by-side restores.

## 4. Execute and verify

1. Run the commands in order; every step but the last uses `NORECOVERY`.
2. After `WITH RECOVERY`, run `DBCC CHECKDB` on the restored database with `NO_INFOMSGS`.
3. Have the data owner validate the recovered data before anyone calls it done.

## 5. Close out

- If restored in place: re-enable jobs, confirm the next full backup runs (the restore may reset the diff base), and re-check `backup-restore/backup-status-report.sql`.
- If side-by-side: copy the needed data across with the data owner, then drop the scratch copy.
- Document: what was lost, why, the recovery point achieved, and time to recover. Feed gaps (missing log backups, slow restore) back into backup strategy.

## Practice note

Restores you have never tested are hopes, not plans. Run this procedure against a non-production copy on a schedule and record the timing — it is the evidence behind your RTO.
