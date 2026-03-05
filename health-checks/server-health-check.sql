/*
    Server Health Check
    -------------------
    Quick overview of SQL Server instance health.
    Run this on day one at a new environment or as a periodic check.
    
    Compatible: SQL Server 2016+
    Impact: Read-only, safe to run in production
*/

-- ============================================
-- 1. Instance Info
-- ============================================
SELECT 
    SERVERPROPERTY('ServerName') AS [ServerName],
    SERVERPROPERTY('ProductVersion') AS [Version],
    SERVERPROPERTY('ProductLevel') AS [ServicePack],
    SERVERPROPERTY('Edition') AS [Edition],
    SERVERPROPERTY('EngineEdition') AS [EngineEdition],
    SERVERPROPERTY('Collation') AS [Collation],
    SERVERPROPERTY('IsClustered') AS [IsClustered],
    SERVERPROPERTY('IsHadrEnabled') AS [AlwaysOnEnabled],
    @@MAX_CONNECTIONS AS [MaxConnections],
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) AS [CurrentUserSessions];

-- ============================================
-- 2. Database Status Overview
-- ============================================
SELECT 
    d.name AS [Database],
    d.state_desc AS [State],
    d.recovery_model_desc AS [RecoveryModel],
    d.compatibility_level AS [CompatLevel],
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(10,2)) AS [SizeMB],
    d.create_date AS [Created],
    d.is_read_only AS [ReadOnly],
    d.is_auto_shrink_on AS [AutoShrink_BAD]
FROM sys.databases d
JOIN sys.master_files mf ON d.database_id = mf.database_id
GROUP BY d.name, d.state_desc, d.recovery_model_desc, 
         d.compatibility_level, d.create_date, d.is_read_only, d.is_auto_shrink_on
ORDER BY [SizeMB] DESC;

-- ============================================
-- 3. Disk Space by Drive
-- ============================================
SELECT DISTINCT
    vs.volume_mount_point AS [Drive],
    CAST(vs.total_bytes / 1073741824.0 AS DECIMAL(10,2)) AS [TotalGB],
    CAST(vs.available_bytes / 1073741824.0 AS DECIMAL(10,2)) AS [FreeGB],
    CAST((vs.available_bytes * 100.0 / vs.total_bytes) AS DECIMAL(5,2)) AS [FreePct]
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY [FreePct] ASC;

-- ============================================
-- 4. Last Backup Status
-- ============================================
SELECT 
    d.name AS [Database],
    d.recovery_model_desc AS [RecoveryModel],
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS [LastFull],
    MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS [LastDiff],
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS [LastLog],
    DATEDIFF(HOUR, 
        MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), 
        GETDATE()) AS [HoursSinceFullBackup]
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name
WHERE d.database_id > 4  -- skip system DBs
  AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
ORDER BY [HoursSinceFullBackup] DESC;

-- ============================================
-- 5. SQL Agent Job Failures (Last 24 Hours)
-- ============================================
SELECT 
    j.name AS [JobName],
    h.step_name AS [StepName],
    h.message AS [ErrorMessage],
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS [FailTime]
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE h.run_status = 0  -- failed
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) > DATEADD(HOUR, -24, GETDATE())
ORDER BY [FailTime] DESC;

-- ============================================
-- 6. Red Flags
-- ============================================
PRINT '--- RED FLAG CHECK ---';

-- Auto-shrink enabled (never do this)
IF EXISTS (SELECT 1 FROM sys.databases WHERE is_auto_shrink_on = 1)
    PRINT '⚠️  AUTO_SHRINK is enabled on one or more databases. Disable immediately.';

-- Databases not backed up in 24+ hours
IF EXISTS (
    SELECT 1 FROM sys.databases d
    LEFT JOIN (
        SELECT database_name, MAX(backup_finish_date) AS last_backup
        FROM msdb.dbo.backupset WHERE type = 'D'
        GROUP BY database_name
    ) b ON d.name = b.database_name
    WHERE d.database_id > 4 AND d.state_desc = 'ONLINE'
      AND (b.last_backup IS NULL OR DATEDIFF(HOUR, b.last_backup, GETDATE()) > 24)
)
    PRINT '⚠️  One or more databases have not been backed up in 24+ hours.';

-- Disk space < 10%
IF EXISTS (
    SELECT 1 FROM sys.master_files mf
    CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
    WHERE (vs.available_bytes * 100.0 / vs.total_bytes) < 10
)
    PRINT '⚠️  One or more drives have less than 10% free space.';

PRINT '--- END RED FLAG CHECK ---';
