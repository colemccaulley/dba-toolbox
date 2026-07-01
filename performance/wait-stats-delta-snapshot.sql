/*
    Script: wait-stats-delta-snapshot.sql
    Purpose: Sample wait stats over a short interval so current waits are not hidden by cumulative history.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE
    Impact: Read-only; waits for @SampleSeconds
    Scope: Instance
    Safety: ReadOnly
*/

DECLARE @SampleSeconds INT = 30;
DECLARE @TopN INT = 25;

IF OBJECT_ID('tempdb..#waits_before') IS NOT NULL DROP TABLE #waits_before;

SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #waits_before
FROM sys.dm_os_wait_stats;

DECLARE @Delay CHAR(8) = CONVERT(CHAR(8), DATEADD(SECOND, @SampleSeconds, CONVERT(TIME, '00:00:00')), 108);
WAITFOR DELAY @Delay;

WITH Delta AS (
    SELECT
        after_waits.wait_type,
        after_waits.waiting_tasks_count - before_waits.waiting_tasks_count AS waiting_tasks_count,
        after_waits.wait_time_ms - before_waits.wait_time_ms AS wait_time_ms,
        after_waits.signal_wait_time_ms - before_waits.signal_wait_time_ms AS signal_wait_time_ms
    FROM sys.dm_os_wait_stats AS after_waits
    JOIN #waits_before AS before_waits ON after_waits.wait_type = before_waits.wait_type
), Filtered AS (
    SELECT *, wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
    FROM Delta
    WHERE wait_time_ms > 0 AND waiting_tasks_count > 0
      AND wait_type NOT LIKE 'SLEEP%'
      AND wait_type NOT IN ('WAITFOR','LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT')
)
SELECT TOP (@TopN)
    wait_type AS [WaitType], waiting_tasks_count AS [WaitCount],
    CAST(wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS [TotalWait_Sec],
    CAST(resource_wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS [ResourceWait_Sec],
    CAST(signal_wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS [SignalWait_Sec],
    CAST(wait_time_ms / NULLIF(waiting_tasks_count, 0) AS DECIMAL(18,2)) AS [AvgWait_ms]
FROM Filtered
ORDER BY wait_time_ms DESC;
