# Blocking Incident Response

Use this runbook when users report timeouts or hangs and you suspect lock contention. Blocking is normal in small doses; the incident is when one session holds locks long enough to stall everyone behind it.

## 1. Confirm and size the problem

```sql
:r performance/blocking-check.sql
```

The first result set shows blocked sessions; the second identifies **head blockers** — the sessions at the root of each chain. Record immediately (evidence disappears when the chain clears):

- Head blocker SPID, login, host, program name
- Number of sessions blocked and chain depth
- Wait types and longest wait time
- Blocking and blocked query text

Re-run it two or three times a minute apart. A chain that churns (different SPIDs each time) is contention under load; a chain with the **same head blocker growing** is a stuck session and needs intervention.

## 2. Understand what the head blocker is doing

```sql
:r monitoring/long-running-requests.sql
```

Find the head blocker's row and check:

- **Is it actively running?** High `CpuSec`/`LogicalReads` climbing = a long query that will finish. Estimate whether waiting is cheaper than killing.
- **Is it idle with `OpenTrans > 0`?** A sleeping session holding an open transaction (application forgot to commit, someone ran `BEGIN TRAN` in SSMS and went to lunch) will *never* release on its own. These are the classic kill candidates.
- **Is it a maintenance/DDL operation?** Index rebuilds, schema changes, and bulk loads take restrictive locks by design. Killing mid-operation can mean a long rollback — see step 4.

## 3. Escalate before you kill

Killing a session is the last resort, not the first move:

1. Contact the session owner (login + host from step 1 usually identifies them). An owner committing or cancelling their own work is always cleaner than a kill.
2. If it's an application connection, ask the app team whether the process can be stopped gracefully.
3. If business impact of waiting exceeds impact of killing, get explicit approval from whoever owns that call, and record it.

## 4. Kill safely (if it comes to that)

Before running `KILL`:

```sql
-- How much work would roll back?
DBCC OPENTRAN;                      -- oldest active transaction in the current database
SELECT session_id, database_transaction_log_bytes_used
FROM sys.dm_tran_database_transactions
WHERE transaction_id IN (SELECT transaction_id FROM sys.dm_tran_session_transactions
                         WHERE session_id = <HeadBlockerSPID>);
```

A transaction that wrote gigabytes of log will take a long time to roll back — and it **keeps its locks during rollback**. Killing can make the incident longer, not shorter. If you proceed:

```sql
KILL <spid>;
KILL <spid> WITH STATUSONLY;   -- monitor rollback progress
```

Never restart the SQL Server service to clear blocking — recovery on restart replays the same rollback, with the whole instance offline instead of one chain.

## 5. Post-incident review

Within a day or two, while Query Store still has the window:

- `performance/query-store-top-duration.sql` — did the blocking query's plan regress?
- `performance/missing-index-report.sql` — was a scan escalating locks where a seek would touch a few rows?
- `index-maintenance/statistics-health-report.sql` — stale stats causing a bad plan?
- Ask the app team about transaction scope (transactions held open across user think-time or external calls) and isolation level; `READ COMMITTED SNAPSHOT` removes reader/writer blocking but is an application-level decision to test, not an incident-time fix.

Write up: timeline, head blocker query, root cause, and the prevention item with an owner. A blocking incident without a prevention item will repeat.
