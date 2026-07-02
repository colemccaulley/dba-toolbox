/*
    Script: unused-index-report.sql
    Purpose: Find nonclustered indexes with writes but no reads since startup and generate commented DROP statements.
    Compatible: SQL Server 2016+
    Requires: VIEW DATABASE STATE in target database
    Impact: Read-only; DROP statements are printed commented out, not executed
    Scope: Database (run in the target database)
    Safety: GeneratesCommandsOnly

    Notes:
    - Usage stats reset on instance restart (and on index rebuild in older builds).
      Check the uptime result set before trusting "unused".
    - Excludes primary keys, unique indexes/constraints, and disabled/hypothetical
      indexes. An index may still back a periodic report or year-end job: script
      the definition before dropping so it can be recreated.
*/

DECLARE @MinSizeMB DECIMAL(18,2) = 1.0;   -- ignore trivially small indexes

-- How much history is behind these numbers
SELECT
    sqlserver_start_time AS [InstanceStartTime],
    DATEDIFF(DAY, sqlserver_start_time, SYSDATETIME()) AS [DaysOfUsageData]
FROM sys.dm_os_sys_info;

SELECT
    DB_NAME() AS [Database],
    sch.name AS [Schema],
    o.name AS [Table],
    i.name AS [Index],
    i.type_desc AS [IndexType],
    CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18,2)) AS [SizeMB],
    ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) AS [TotalReads],
    ISNULL(us.user_updates, 0) AS [TotalWrites],
    us.last_user_update AS [LastWrite],
    N'-- DROP INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(sch.name) + N'.' + QUOTENAME(o.name)
    + N';  -- script definition first' AS [ReviewBeforeDropping]
FROM sys.indexes AS i
JOIN sys.objects AS o ON i.object_id = o.object_id
JOIN sys.schemas AS sch ON o.schema_id = sch.schema_id
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
LEFT JOIN sys.dm_db_index_usage_stats AS us
       ON us.database_id = DB_ID() AND us.object_id = i.object_id AND us.index_id = i.index_id
WHERE o.is_ms_shipped = 0
  AND o.type = 'U'
  AND i.index_id > 1                 -- nonclustered only
  AND i.is_primary_key = 0
  AND i.is_unique = 0
  AND i.is_unique_constraint = 0
  AND i.is_disabled = 0
  AND i.is_hypothetical = 0
  AND ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) = 0
GROUP BY sch.name, o.name, i.name, i.type_desc,
         us.user_seeks, us.user_scans, us.user_lookups, us.user_updates, us.last_user_update
HAVING CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18,2)) >= @MinSizeMB
ORDER BY [SizeMB] DESC;
