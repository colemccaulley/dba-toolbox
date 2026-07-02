/*
    Script: missing-index-report.sql
    Purpose: Rank missing-index suggestions from the DMVs and generate candidate CREATE INDEX statements.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE
    Impact: Read-only; generated CREATE INDEX statements are printed, not executed
    Scope: Instance
    Safety: GeneratesCommandsOnly

    Notes:
    - Missing-index DMVs reset on instance restart and after index changes on the table.
    - Suggestions are hints, not designs: consolidate overlapping candidates, check
      existing indexes first, and rename before creating anything.
*/

DECLARE @TopN INT = 25;
DECLARE @MinImprovementMeasure DECIMAL(18,2) = 10000;

-- How much history is behind these numbers
SELECT
    sqlserver_start_time AS [InstanceStartTime],
    DATEDIFF(DAY, sqlserver_start_time, SYSDATETIME()) AS [DaysOfDmvData]
FROM sys.dm_os_sys_info;

SELECT TOP (@TopN)
    CAST(migs.avg_total_user_cost * (migs.avg_user_impact / 100.0)
         * (migs.user_seeks + migs.user_scans) AS DECIMAL(18,2)) AS [ImprovementMeasure],
    DB_NAME(mid.database_id) AS [Database],
    mid.statement AS [Table],
    mid.equality_columns AS [EqualityColumns],
    mid.inequality_columns AS [InequalityColumns],
    mid.included_columns AS [IncludedColumns],
    migs.user_seeks AS [UserSeeks],
    migs.user_scans AS [UserScans],
    migs.avg_user_impact AS [AvgImpactPct],
    migs.avg_total_user_cost AS [AvgQueryCost],
    migs.last_user_seek AS [LastUserSeek],
    N'CREATE NONCLUSTERED INDEX ' + QUOTENAME(N'IX_missing_' + CAST(mig.index_handle AS NVARCHAR(20)))
    + N' ON ' + mid.statement
    + N' (' + ISNULL(mid.equality_columns, N'')
    + CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN N', ' ELSE N'' END
    + ISNULL(mid.inequality_columns, N'') + N')'
    + ISNULL(N' INCLUDE (' + mid.included_columns + N')', N'')
    + N';' AS [CandidateCommand_ReviewFirst]
FROM sys.dm_db_missing_index_groups AS mig
JOIN sys.dm_db_missing_index_group_stats AS migs ON mig.index_group_handle = migs.group_handle
JOIN sys.dm_db_missing_index_details AS mid ON mig.index_handle = mid.index_handle
WHERE mid.database_id > 4
  AND migs.avg_total_user_cost * (migs.avg_user_impact / 100.0)
      * (migs.user_seeks + migs.user_scans) >= @MinImprovementMeasure
ORDER BY [ImprovementMeasure] DESC;
