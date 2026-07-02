# Performance Incident Triage

Use this runbook when "the database is slow" and you need to find the actual bottleneck fast. Work top-down; stop at the first step that explains the symptom.

## 1. Is anything blocked right now?

```sql
:r performance/blocking-check.sql
```

Blocking chains explain sudden, widespread slowness better than anything else. If you find one, switch to `runbooks/blocking-incident-response.md`.

## 2. What is actually running?

```sql
:r monitoring/long-running-requests.sql
```

Look for:
- A runaway query (huge `ElapsedSec`/`LogicalReads`) — often an unbounded report or a missing `WHERE` clause.
- Many sessions stuck on the same `CurrentWait` — points at a shared resource.
- `OpenTrans > 0` on idle-looking sessions — long transactions hold locks and log space.

## 3. What is the instance waiting on?

```sql
:r performance/wait-stats-delta-snapshot.sql
```

The delta snapshot shows waits during the incident, not since startup. Rough map:

| Dominant wait | Usual suspect |
|---|---|
| `LCK_M_*` | Blocking/lock contention (back to step 1) |
| `PAGEIOLATCH_*` | Storage reads — memory pressure or scan-heavy plans |
| `WRITELOG` | Transaction log latency |
| `CXPACKET`/`CXCONSUMER` | Parallelism — check MAXDOP/cost threshold and big scans |
| `RESOURCE_SEMAPHORE` | Memory grants — few huge queries starving the rest |
| `SOS_SCHEDULER_YIELD` | CPU pressure |

## 4. Which queries are responsible?

```sql
:r performance/top-expensive-queries.sql
:r performance/query-store-top-duration.sql   -- run in the affected database
```

Query Store also answers "did this plan regress?" — compare current vs. historical plans for the top offenders.

## 5. Is it a tuning gap?

```sql
:r performance/missing-index-report.sql
:r index-maintenance/statistics-health-report.sql   -- run in the affected database
```

Stale statistics after a large load are a classic cause of sudden plan regressions; an `UPDATE STATISTICS` is a cheap, low-risk first fix.

## 6. Recurring at night or in bursts?

```sql
:r monitoring/deadlock-report.sql
:r monitoring/agent-job-status.sql
```

Deadlock patterns and overlapping maintenance/ETL jobs explain most "slow every day at 2am" complaints.

## Capture before it heals

Slowness evidence evaporates when the incident ends. While it is happening, save the outputs of steps 1–3 (the PowerShell wrapper writes CSVs) so the post-incident review works from data, not memory.
