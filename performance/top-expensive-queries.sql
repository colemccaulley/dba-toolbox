/*
    Top Expensive Queries
    ---------------------
    Find the most resource-intensive queries on the instance.
    Uses the plan cache — results reset on service restart or plan eviction.
    
    Compatible: SQL Server 2016+
    Impact: Read-only, safe to run in production
*/

-- ============================================
-- Parameters
-- ============================================
DECLARE @TopN INT = 25;
DECLARE @OrderBy VARCHAR(20) = 'TotalCPU'; -- Options: TotalCPU, AvgCPU, TotalReads, AvgReads, ExecutionCount, TotalDuration

-- ============================================
-- Top Queries by Resource Usage
-- ============================================
SELECT TOP (@TopN)
    DB_NAME(qt.dbid) AS [Database],
    OBJECT_NAME(qt.objectid, qt.dbid) AS [ObjectName],
    qs.execution_count AS [Executions],
    
    -- CPU
    qs.total_worker_time / 1000 AS [TotalCPU_ms],
    (qs.total_worker_time / 1000) / NULLIF(qs.execution_count, 0) AS [AvgCPU_ms],
    
    -- Duration
    qs.total_elapsed_time / 1000 AS [TotalDuration_ms],
    (qs.total_elapsed_time / 1000) / NULLIF(qs.execution_count, 0) AS [AvgDuration_ms],
    
    -- Reads
    qs.total_logical_reads AS [TotalLogicalReads],
    qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS [AvgLogicalReads],
    
    -- Writes
    qs.total_logical_writes AS [TotalLogicalWrites],
    
    -- Plan info
    qs.creation_time AS [PlanCreated],
    qs.last_execution_time AS [LastExecuted],
    
    -- Query text (first 500 chars)
    SUBSTRING(qt.text, 
        (qs.statement_start_offset / 2) + 1,
        (CASE 
            WHEN qs.statement_end_offset = -1 THEN LEN(CONVERT(NVARCHAR(MAX), qt.text)) * 2
            ELSE qs.statement_end_offset 
        END - qs.statement_start_offset) / 2 + 1
    ) AS [QueryText],
    
    -- Query plan (click to view in SSMS)
    qp.query_plan AS [QueryPlan]

FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qt.dbid IS NOT NULL
  AND qt.dbid > 4  -- skip system databases
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
