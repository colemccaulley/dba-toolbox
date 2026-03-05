/*
    Index Fragmentation Report
    --------------------------
    Identifies fragmented indexes and recommends action.
    
    General guidelines:
    - 5-30% fragmentation → REORGANIZE
    - >30% fragmentation → REBUILD
    - <5% → leave it alone
    - Only look at indexes with 1000+ pages (small indexes don't benefit)
    
    Compatible: SQL Server 2016+
    Impact: Can be CPU-intensive on large databases. 
            Use LIMITED mode (default) for quick checks.
            Use DETAILED mode for accurate page-level stats.
    
    ⚠️ This is a REPORT ONLY. It does not modify anything.
*/

-- ============================================
-- Parameters
-- ============================================
DECLARE @DatabaseName NVARCHAR(128) = NULL;  -- NULL = current database
DECLARE @MinPageCount INT = 1000;            -- Skip small indexes
DECLARE @MinFragPct DECIMAL(5,2) = 5.0;     -- Only show indexes above this threshold
DECLARE @ScanMode NVARCHAR(20) = 'LIMITED';  -- LIMITED (fast) or DETAILED (thorough)

-- ============================================
-- Fragmentation Report
-- ============================================
SELECT 
    DB_NAME() AS [Database],
    OBJECT_SCHEMA_NAME(ips.object_id) AS [Schema],
    OBJECT_NAME(ips.object_id) AS [Table],
    i.name AS [Index],
    i.type_desc AS [IndexType],
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,2)) AS [FragPct],
    ips.page_count AS [Pages],
    CAST(ips.page_count * 8.0 / 1024 AS DECIMAL(10,2)) AS [SizeMB],
    ips.record_count AS [Rows],
    
    -- Recommendation
    CASE 
        WHEN ips.avg_fragmentation_in_percent < 5 THEN 'OK'
        WHEN ips.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN 'REORGANIZE'
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
    END AS [Action],
    
    -- Generated command (copy and run if needed)
    CASE 
        WHEN ips.avg_fragmentation_in_percent BETWEEN 5 AND 30 
            THEN 'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REORGANIZE;'
        WHEN ips.avg_fragmentation_in_percent > 30 
            THEN 'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REBUILD WITH (ONLINE = ON);'
        ELSE ''
    END AS [Command]

FROM sys.dm_db_index_physical_stats(
    DB_ID(@DatabaseName), NULL, NULL, NULL, @ScanMode
) ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent >= @MinFragPct
  AND ips.page_count >= @MinPageCount
  AND i.name IS NOT NULL  -- skip heaps
  AND ips.alloc_unit_type_desc = 'IN_ROW_DATA'
ORDER BY ips.avg_fragmentation_in_percent DESC;
