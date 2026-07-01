/*
    Script: top-expensive-queries.sql
    Purpose: Find resource-intensive cached plans by CPU, reads, execution count, or duration.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly
*/

DECLARE @TopN INT = 25;
DECLARE @OrderBy VARCHAR(20) = 'TotalCPU'; -- TotalCPU, AvgCPU, TotalReads, AvgReads, ExecutionCount, TotalDuration
DECLARE @IncludeQueryPlan BIT = 0;

SELECT TOP (@TopN)
    DB_NAME(qt.dbid) AS [Database],
    OBJECT_NAME(qt.objectid, qt.dbid) AS [ObjectName],
    qs.execution_count AS [Executions],
    qs.total_worker_time / 1000 AS [TotalCPU_ms],
    (qs.total_worker_time / 1000) / NULLIF(qs.execution_count, 0) AS [AvgCPU_ms],
    qs.total_elapsed_time / 1000 AS [TotalDuration_ms],
    (qs.total_elapsed_time / 1000) / NULLIF(qs.execution_count, 0) AS [AvgDuration_ms],
    qs.total_logical_reads AS [TotalLogicalReads],
    qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS [AvgLogicalReads],
    qs.total_logical_writes AS [TotalLogicalWrites],
    qs.creation_time AS [PlanCreated],
    qs.last_execution_time AS [LastExecuted],
    SUBSTRING(qt.text, (qs.statement_start_offset / 2) + 1,
        (CASE WHEN qs.statement_end_offset = -1 THEN LEN(CONVERT(NVARCHAR(MAX), qt.text)) * 2 ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2 + 1) AS [QueryText],
    CASE WHEN @IncludeQueryPlan = 1 THEN qp.query_plan ELSE NULL END AS [QueryPlan]
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
OUTER APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE qt.dbid IS NOT NULL AND qt.dbid > 4
ORDER BY
    CASE @OrderBy
        WHEN 'TotalCPU' THEN qs.total_worker_time
        WHEN 'AvgCPU' THEN qs.total_worker_time / NULLIF(qs.execution_count, 0)
        WHEN 'TotalReads' THEN qs.total_logical_reads
        WHEN 'AvgReads' THEN qs.total_logical_reads / NULLIF(qs.execution_count, 0)
        WHEN 'ExecutionCount' THEN qs.execution_count
        WHEN 'TotalDuration' THEN qs.total_elapsed_time
        ELSE qs.total_worker_time
    END DESC;
