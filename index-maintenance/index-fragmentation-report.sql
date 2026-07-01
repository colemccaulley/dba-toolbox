/*
    Script: index-fragmentation-report.sql
    Purpose: Identify fragmented indexes and generate reviewable maintenance commands.
    Compatible: SQL Server 2016+
    Requires: VIEW DATABASE STATE in target database
    Impact: Read-only; physical stats can be CPU/IO intensive on large databases
    Scope: Database
    Safety: GeneratesCommandsOnly
*/

DECLARE @DatabaseName SYSNAME = NULL;       -- NULL = current database
DECLARE @MinPageCount INT = 1000;
DECLARE @MinFragPct DECIMAL(5,2) = 5.0;
DECLARE @ScanMode NVARCHAR(20) = 'LIMITED'; -- LIMITED, SAMPLED, DETAILED
DECLARE @UseOnlineRebuild BIT = 0;          -- ONLINE = ON can fail by edition/index type; opt in only
DECLARE @SortInTempdb BIT = 0;
DECLARE @MaxDop INT = NULL;

;WITH Frag AS (
    SELECT
        ips.object_id,
        ips.index_id,
        ips.avg_fragmentation_in_percent,
        ips.page_count,
        ips.record_count,
        ips.alloc_unit_type_desc
    FROM sys.dm_db_index_physical_stats(DB_ID(@DatabaseName), NULL, NULL, NULL, @ScanMode) AS ips
    WHERE ips.avg_fragmentation_in_percent >= @MinFragPct
      AND ips.page_count >= @MinPageCount
      AND ips.alloc_unit_type_desc = 'IN_ROW_DATA'
)
SELECT
    DB_NAME(COALESCE(DB_ID(@DatabaseName), DB_ID())) AS [Database],
    OBJECT_SCHEMA_NAME(f.object_id) AS [Schema],
    OBJECT_NAME(f.object_id) AS [Table],
    i.name AS [Index],
    i.type_desc AS [IndexType],
    CAST(f.avg_fragmentation_in_percent AS DECIMAL(5,2)) AS [FragPct],
    f.page_count AS [Pages],
    CAST(f.page_count * 8.0 / 1024 AS DECIMAL(18,2)) AS [SizeMB],
    f.record_count AS [Rows],
    CASE
        WHEN f.avg_fragmentation_in_percent < 5 THEN 'OK'
        WHEN f.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN 'REORGANIZE'
        WHEN f.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
    END AS [Action],
    CASE
        WHEN f.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN
            N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(f.object_id)) + N'.' + QUOTENAME(OBJECT_NAME(f.object_id)) + N' REORGANIZE;'
        WHEN f.avg_fragmentation_in_percent > 30 THEN
            N'ALTER INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(f.object_id)) + N'.' + QUOTENAME(OBJECT_NAME(f.object_id)) + N' REBUILD' +
            CASE
                WHEN @UseOnlineRebuild = 1 OR @SortInTempdb = 1 OR @MaxDop IS NOT NULL THEN N' WITH (' +
                    STUFF(
                        CASE WHEN @UseOnlineRebuild = 1 THEN N', ONLINE = ON' ELSE N'' END +
                        CASE WHEN @SortInTempdb = 1 THEN N', SORT_IN_TEMPDB = ON' ELSE N'' END +
                        CASE WHEN @MaxDop IS NOT NULL THEN N', MAXDOP = ' + CONVERT(NVARCHAR(10), @MaxDop) ELSE N'' END,
                        1, 2, N''
                    ) + N')'
                ELSE N''
            END + N';'
        ELSE N''
    END AS [Command]
FROM Frag AS f
JOIN sys.indexes AS i ON f.object_id = i.object_id AND f.index_id = i.index_id
WHERE i.name IS NOT NULL
ORDER BY f.avg_fragmentation_in_percent DESC;
