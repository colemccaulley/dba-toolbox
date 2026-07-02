# Availability Group Failover

Use this runbook for planned failovers (patching, maintenance) and unplanned ones (primary lost). The technology differs only at step 3 — the assessment and the post-failover work are the same, and the post-failover work is what usually gets missed.

## 1. Assess current state

```sql
:r ha-dr/availability-group-health.sql
```

On (or against) the intended new primary, confirm:

- **Replica role and health**: target is `SECONDARY`, `CONNECTED`, `HEALTHY`.
- **SyncState per database**: `SYNCHRONIZED` (sync-commit) or `SYNCHRONIZING` (async).
- **LogSendQueueKB on the target**: for an async replica this is approximately the **data you lose** if you force failover now.
- **RedoQueueKB / EstRedoCatchupSec**: how long the new primary needs to finish redo before it's fully available.

## 2. Planned failover (no data loss)

1. If the target replica is async-commit, switch it to synchronous-commit and wait for `SYNCHRONIZED`:
   ```sql
   ALTER AVAILABILITY GROUP [YourAG]
   MODIFY REPLICA ON N'TargetReplica' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);
   ```
2. Quiesce heavy writers if possible (pause ETL/agent jobs) — smaller send/redo queues mean a faster role switch.
3. On the **target** replica:
   ```sql
   ALTER AVAILABILITY GROUP [YourAG] FAILOVER;
   ```
4. Verify with `ha-dr/availability-group-health.sql`: new roles correct, all databases `SYNCHRONIZED`/`SYNCHRONIZING`, no `SuspendReason`.
5. Restore the original availability modes if you changed them in step 1.

## 3. Forced failover (primary is gone)

Forced failover (`WITH DATA_LOSS`) is a business decision when the target isn't synchronized — the `LogSendQueueKB` you recorded is the price. Get the approval, record it, then on the target:

```sql
ALTER AVAILABILITY GROUP [YourAG] FORCE_FAILOVER_ALLOW_DATA_LOSS;
```

Immediately after:

- Database copies on other secondaries (and the old primary, if it returns) are **suspended** to protect the divergence point. Resume each one only after deciding it can discard its divergent changes:
  ```sql
  ALTER DATABASE [YourDatabase] SET HADR RESUME;   -- run on each secondary, per database
  ```
- If the old primary comes back, it rejoins as a secondary and discards unsent transactions — anything it had that never reached the new primary is what the business agreed to lose. If those transactions matter, take that replica's databases out and salvage from them *before* resuming data movement.
- If quorum itself was lost (multi-node failure/DR site), the cluster may need a forced quorum first — coordinate with whoever owns Windows clustering; forcing quorum wrong can split-brain the cluster.

## 4. Post-failover checklist (where failovers actually go wrong)

The AG moves databases — **nothing else**. On the new primary, verify:

- **Logins**: SQL logins must exist with matching SIDs or database users orphan. Check with `migration/post-migration-validation.sql` (orphaned-users section) in each AG database; fix by creating logins with the original SID.
- **Agent jobs**: backup, maintenance, and ETL jobs exist on all replicas but should only *run* on the primary. Confirm they're present and their role checks work (`monitoring/agent-job-status.sql`).
- **Backups**: confirm the next log backup actually runs on the correct replica (check `automated_backup_preference` and job logic), and that the log chain continues — `backup-restore/backup-status-report.sql`.
- **Applications**: connections via the listener recover on their own; anything hard-coded to a server name is now pointing at a secondary. `ReadIntent`-only secondaries will refuse read-write connections.
- **Untracked server objects**: linked servers, credentials, server-level triggers, Database Mail profiles, operators — anything created only on the old primary.

## 5. Close out

- Re-run `ha-dr/availability-group-health.sql` and file the output as the post-incident state.
- For a forced failover: document the data-loss window, who approved it, and reconcile salvaged data with the owner.
- Feed friction back into readiness: anything you had to fix by hand in step 4 belongs in a synchronization job (or dbatools sync script) so the next failover is boring.
