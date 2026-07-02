/*
    Script: long-running-requests.sql
    Purpose: Show currently executing requests over a duration threshold with waits, blocking, and statement text.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly
*/

DECLARE @MinElapsedSeconds INT = 30;

SELECT
    r.session_id AS [SPID],
    s.login_name AS [Login],
    s.host_name AS [Host],
    s.program_name AS [Program],
    DB_NAME(r.database_id) AS [Database],
    r.status AS [Status],
    r.command AS [Command],
    r.start_time AS [StartTime],
    r.total_elapsed_time / 1000 AS [ElapsedSec],
    r.cpu_time / 1000 AS [CpuSec],
    r.logical_reads AS [LogicalReads],
    r.wait_type AS [CurrentWait],
    r.wait_time / 1000 AS [WaitSec],
    r.blocking_session_id AS [BlockedBy],
    r.open_transaction_count AS [OpenTrans],
    r.percent_complete AS [PctComplete],   -- populated for BACKUP/RESTORE/DBCC and a few others
    CASE r.transaction_isolation_level
        WHEN 0 THEN 'Unspecified'
        WHEN 1 THEN 'ReadUncommitted'
        WHEN 2 THEN 'ReadCommitted'
        WHEN 3 THEN 'RepeatableRead'
        WHEN 4 THEN 'Serializable'
        WHEN 5 THEN 'Snapshot'
    END AS [IsolationLevel],
    SUBSTRING(t.text,
        r.statement_start_offset / 2 + 1,
        (CASE WHEN r.statement_end_offset = -1
              THEN DATALENGTH(t.text)
              ELSE r.statement_end_offset
         END - r.statement_start_offset) / 2 + 1) AS [CurrentStatement],
    t.text AS [FullBatch]
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND r.session_id <> @@SPID
  AND r.total_elapsed_time >= @MinElapsedSeconds * 1000
ORDER BY r.total_elapsed_time DESC;
