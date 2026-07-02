# Database Migration Cutover

Use this runbook to move a database to a new instance (new hardware, version upgrade, consolidation) with a checked plan instead of a hopeful copy. It uses backup/restore as the transport — the method that works everywhere and doubles as a restore test.

## 1. Plan (days or weeks before)

```sql
:r migration/pre-migration-inventory.sql        -- on the source
```

Work through the inventory result sets; each flags something the restore will *not* carry:

- **TDE**: the certificate must be backed up from the source and restored on the target **before** the database restore, or the restore fails outright.
- **Replication / CDC**: publications and capture jobs need scripting and re-setup; a restored database does not resume them.
- **Collation differences** between database and server: tempdb-collation conflicts may surface on the new instance — test the application, don't assume.
- **Compatibility level**: decide the target level *and* test at it. Upgrading the engine while pinning old compat is a valid interim state; drifting there forever is not a plan.
- **Logins, jobs, linked servers**: server-level objects need their own migration (sp_help_revlogin or dbatools `Copy-DbaLogin` preserves SQL login SIDs and password hashes; script jobs and linked servers with credentials).
- **Instance settings** (result set 2): decide deliberately which to carry (MAXDOP, cost threshold, max memory sized for the new host).

Capture the baseline for validation later:

```sql
:r migration/post-migration-validation.sql      -- on the source, save the output
```

Agree the cutover window, the rollback rule ("we roll back if X isn't true by HH:MM"), and who validates the application.

## 2. Rehearse (before the real window)

Restore a recent backup onto the target (`backup-restore/restore-command-generator.sql` with `@DataFilePath`/`@LogFilePath` for the new drive layout) and run the application against it. The rehearsal — not the cutover — is where you discover the missing login, the collation surprise, and the real restore duration. Time it: restore time drives the size of the cutover window.

## 3. Cutover

The pattern that keeps downtime proportional to the *last log*, not the database size:

1. **Ahead of the window**: restore the latest full (and diff) onto the target `WITH NORECOVERY`.
2. Keep restoring log backups `WITH NORECOVERY` as they're taken — the target trails the source by minutes.
3. **Window opens**: stop application writes (disable logins or set the app offline — verify with `monitoring/long-running-requests.sql` that activity is actually gone).
4. Take a final log backup on the source; restore it on the target, then `RESTORE DATABASE [YourDatabase] WITH RECOVERY;`.
5. On the target: fix orphaned users if any login SIDs didn't survive, set the agreed compatibility level, and take an **immediate full backup** — the new instance has no chain yet.

## 4. Validate before opening the doors

```sql
:r migration/post-migration-validation.sql      -- on the target
```

Diff against the source baseline from step 1: object counts, row counts, security elements, and the orphaned-users result set (must be empty). Then:

- `DBCC CHECKDB` with `NO_INFOMSGS` on the target copy.
- Application smoke test by the owner — their sign-off is the gate, not yours.
- `health-checks/server-health-check.sql` and `backup-restore/backup-status-report.sql` on the target: backups scheduled and green, jobs enabled.

Only then repoint applications / DNS and re-enable logins.

## 5. Decommission deliberately

- Set the **source** database offline (or read-only) rather than dropping it — it's your instant rollback for the agreed soak period.
- Disable (don't delete) source-side jobs so nothing keeps backing up or maintaining the dead copy.
- After the soak period: archive a final source backup per retention policy, then drop and reclaim.
- Update documentation, monitoring targets, and the CMDB; watch the new instance's first week with `performance/wait-stats-delta-snapshot.sql` and Query Store — a new box with new settings can shift plans, and "slow since the migration" tickets deserve data.
