/*
    Script: query-store-top-duration.sql
    Purpose: Find high-duration Query Store queries in the current database over a recent time window.
    Compatible: SQL Server 2016+
    Requires: VIEW DATABASE STATE in the current database; Query Store enabled
    Impact: Read-only
    Scope: Database
    Safety: ReadOnly
*/

DECLARE @TopN INT = 25;
DECLARE @LookbackHours INT = 24;

IF NOT EXISTS (SELECT 1 FROM sys.database_query_store_options WHERE actual_state_desc = 'READ_WRITE')
BEGIN
    SELECT 'Query Store is not READ_WRITE for this database.' AS [Message];
    RETURN;
END;

SELECT TOP (@TopN)
    OBJECT_SCHEMA_NAME(q.object_id) AS [SchemaName],
    OBJECT_NAME(q.object_id) AS [ObjectName],
    qt.query_sql_text AS [QueryText],
    SUM(rs.count_executions) AS [Executions],
    CAST(SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS DECIMAL(18,2)) AS [WeightedAvgDuration_ms],
    CAST(MAX(rs.max_duration) / 1000.0 AS DECIMAL(18,2)) AS [MaxDuration_ms],
    MIN(rsi.start_time) AS [FirstInterval],
    MAX(rsi.end_time) AS [LastInterval]
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
JOIN sys.query_store_query AS q ON p.query_id = q.query_id
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE rsi.start_time >= DATEADD(HOUR, -@LookbackHours, SYSDATETIMEOFFSET())
GROUP BY q.object_id, qt.query_sql_text
ORDER BY [WeightedAvgDuration_ms] DESC;
