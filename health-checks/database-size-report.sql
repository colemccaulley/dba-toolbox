/*
    Script: database-size-report.sql
    Purpose: Shows database data/log size, file counts, and autogrowth settings.
    Compatible: SQL Server 2016+
    Requires: VIEW ANY DATABASE; public can see databases it can access
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly
*/

SELECT
    d.name AS [Database],
    d.state_desc AS [State],
    d.recovery_model_desc AS [RecoveryModel],
    CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size ELSE 0 END) * 8.0 / 1024 AS DECIMAL(18,2)) AS [DataSizeMB],
    CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size ELSE 0 END) * 8.0 / 1024 AS DECIMAL(18,2)) AS [LogSizeMB],
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS [TotalSizeMB],
    CAST(SUM(mf.size) * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS [TotalSizeGB],
    SUM(CASE WHEN mf.type = 0 THEN 1 ELSE 0 END) AS [DataFiles],
    SUM(CASE WHEN mf.type = 1 THEN 1 ELSE 0 END) AS [LogFiles],
    MAX(CASE
        WHEN mf.type = 0 AND mf.is_percent_growth = 1 THEN CONVERT(VARCHAR(20), mf.growth) + '%'
        WHEN mf.type = 0 THEN CONVERT(VARCHAR(20), mf.growth * 8 / 1024) + ' MB'
    END) AS [DataGrowth],
    MAX(CASE
        WHEN mf.type = 1 AND mf.is_percent_growth = 1 THEN CONVERT(VARCHAR(20), mf.growth) + '%'
        WHEN mf.type = 1 THEN CONVERT(VARCHAR(20), mf.growth * 8 / 1024) + ' MB'
    END) AS [LogGrowth],
    d.create_date AS [Created]
FROM sys.databases AS d
JOIN sys.master_files AS mf ON d.database_id = mf.database_id
GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.create_date
ORDER BY SUM(mf.size) DESC;
