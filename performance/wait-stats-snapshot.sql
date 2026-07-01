/*
    Script: wait-stats-snapshot.sql
    Purpose: Review cumulative SQL Server waits since last service start or wait stats reset.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly
*/

DECLARE @TopN INT = 25;

WITH WaitStats AS (
    SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms,
           wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        'CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH',
        'WAITFOR','LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH',
        'BROKER_TASK_STOP','CLR_MANUAL_EVENT','CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
        'XE_DISPATCHER_WAIT','XE_DISPATCHER_JOIN','SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE','BROKER_EVENTHANDLER',
        'SLEEP_BPOOL_FLUSH','SLEEP_DBSTARTUP','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION','SP_SERVER_DIAGNOSTICS_SLEEP',
        'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE','QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','WAIT_XTP_CKPT_CLOSE',
        'KSOURCE_WAKEUP','BROKER_TRANSMITTER','PREEMPTIVE_OS_AUTHENTICATIONOPS','PREEMPTIVE_OS_GETPROCADDRESS'
    )
    AND waiting_tasks_count > 0
)
SELECT TOP (@TopN)
    wait_type AS [WaitType], waiting_tasks_count AS [WaitCount],
    CAST(wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS [TotalWait_Sec],
    CAST(resource_wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS [ResourceWait_Sec],
    CAST(signal_wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS [SignalWait_Sec],
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER(), 0) AS DECIMAL(5,2)) AS [PctOfTotal],
    CAST(wait_time_ms / NULLIF(waiting_tasks_count, 0) AS DECIMAL(18,2)) AS [AvgWait_ms]
FROM WaitStats
ORDER BY wait_time_ms DESC;
