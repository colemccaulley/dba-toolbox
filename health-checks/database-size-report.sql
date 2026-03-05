/*
    Database Size Report
    --------------------
    Shows size, space used, and growth trends for all databases.
    
    Compatible: SQL Server 2016+
    Impact: Read-only, safe to run in production
*/

SELECT 
    d.name AS [Database],
    d.state_desc AS [State],
    d.recovery_model_desc AS [RecoveryModel],
    
    -- Data file size
    CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size END) * 8.0 / 1024 AS DECIMAL(12,2)) AS [DataSizeMB],
    
    -- Log file size
    CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size END) * 8.0 / 1024 AS DECIMAL(12,2)) AS [LogSizeMB],
    
    -- Total size
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(12,2)) AS [TotalSizeMB],
    CAST(SUM(mf.size) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS [TotalSizeGB],
    
    -- File counts
    SUM(CASE WHEN mf.type = 0 THEN 1 ELSE 0 END) AS [DataFiles],
    SUM(CASE WHEN mf.type = 1 THEN 1 ELSE 0 END) AS [LogFiles],
    
    -- Auto-growth settings (show the first data file's growth)
    MAX(CASE 
        WHEN mf.type = 0 AND mf.is_percent_growth = 1 
        THEN CAST(mf.growth AS VARCHAR(10)) + '%'
        WHEN mf.type = 0 AND mf.is_percent_growth = 0 
        THEN CAST(mf.growth * 8 / 1024 AS VARCHAR(10)) + ' MB'
    END) AS [DataGrowth],
    
    MAX(CASE 
        WHEN mf.type = 1 AND mf.is_percent_growth = 1 
        THEN CAST(mf.growth AS VARCHAR(10)) + '%'
        WHEN mf.type = 1 AND mf.is_percent_growth = 0 
        THEN CAST(mf.growth * 8 / 1024 AS VARCHAR(10)) + ' MB'
    END) AS [LogGrowth],
    
    d.create_date AS [Created]

FROM sys.databases d
JOIN sys.master_files mf ON d.database_id = mf.database_id
GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.create_date
ORDER BY SUM(mf.size) DESC;
