/*
    Script: database-growth-trend.sql
    Purpose: Trend database growth from full-backup history and project space needs without any monitoring infrastructure.
    Compatible: SQL Server 2016+
    Requires: msdb read access
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly

    Notes:
    - backup_size is the uncompressed backup size, which tracks used data volume
      (not allocated file size), making it a good free proxy for growth trending.
    - Only as good as the retained backup history: check msdb history cleanup
      (sp_delete_backuphistory) before trusting long trends.
*/

DECLARE @MonthsBack INT = 12;
DECLARE @ProjectionMonths INT = 6;

-- ============================================
-- 1. Month-by-month size with growth deltas
-- ============================================
;WITH MonthlySize AS (
    SELECT
        bs.database_name,
        DATEFROMPARTS(YEAR(bs.backup_finish_date), MONTH(bs.backup_finish_date), 1) AS [Month],
        CAST(MAX(bs.backup_size) / 1048576.0 AS DECIMAL(18,2)) AS [MaxFullBackupMB]
    FROM msdb.dbo.backupset AS bs
    WHERE bs.type = 'D'
      AND bs.backup_finish_date >= DATEADD(MONTH, -@MonthsBack, SYSDATETIME())
      AND bs.database_name IN (SELECT name FROM sys.databases WHERE database_id > 4)
    GROUP BY bs.database_name, DATEFROMPARTS(YEAR(bs.backup_finish_date), MONTH(bs.backup_finish_date), 1)
)
SELECT
    database_name AS [Database],
    [Month],
    [MaxFullBackupMB] AS [DataSizeMB],
    [MaxFullBackupMB]
        - LAG([MaxFullBackupMB]) OVER (PARTITION BY database_name ORDER BY [Month]) AS [GrowthMB]
FROM MonthlySize
ORDER BY database_name, [Month];

-- ============================================
-- 2. Per-database growth summary and naive linear projection
-- ============================================
;WITH MonthlySize AS (
    SELECT
        bs.database_name,
        DATEFROMPARTS(YEAR(bs.backup_finish_date), MONTH(bs.backup_finish_date), 1) AS [Month],
        CAST(MAX(bs.backup_size) / 1048576.0 AS DECIMAL(18,2)) AS [MaxFullBackupMB]
    FROM msdb.dbo.backupset AS bs
    WHERE bs.type = 'D'
      AND bs.backup_finish_date >= DATEADD(MONTH, -@MonthsBack, SYSDATETIME())
      AND bs.database_name IN (SELECT name FROM sys.databases WHERE database_id > 4)
    GROUP BY bs.database_name, DATEFROMPARTS(YEAR(bs.backup_finish_date), MONTH(bs.backup_finish_date), 1)
), Spans AS (
    SELECT DISTINCT
        database_name,
        FIRST_VALUE([MaxFullBackupMB]) OVER (PARTITION BY database_name ORDER BY [Month]) AS [StartMB],
        LAST_VALUE([MaxFullBackupMB]) OVER (PARTITION BY database_name ORDER BY [Month]
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS [CurrentMB],
        COUNT(*) OVER (PARTITION BY database_name) AS [MonthsOfData]
    FROM MonthlySize
)
SELECT
    database_name AS [Database],
    [MonthsOfData],
    [StartMB],
    [CurrentMB],
    CAST(([CurrentMB] - [StartMB]) / NULLIF([MonthsOfData] - 1, 0) AS DECIMAL(18,2)) AS [AvgMonthlyGrowthMB],
    CAST([CurrentMB] + @ProjectionMonths
        * (([CurrentMB] - [StartMB]) / NULLIF([MonthsOfData] - 1, 0)) AS DECIMAL(18,2))
        AS [ProjectedMBIn6Months]
FROM Spans
ORDER BY [CurrentMB] DESC;
