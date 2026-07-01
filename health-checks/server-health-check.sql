/*
    Script: server-health-check.sql
    Purpose: Quick day-one overview of SQL Server instance health and operational red flags.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE for complete DMV output; msdb read access for Agent/backup sections
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly
*/

SELECT
    SERVERPROPERTY('ServerName') AS [ServerName],
    SERVERPROPERTY('ProductVersion') AS [Version],
    SERVERPROPERTY('ProductLevel') AS [ProductLevel],
    SERVERPROPERTY('Edition') AS [Edition],
    SERVERPROPERTY('EngineEdition') AS [EngineEdition],
    SERVERPROPERTY('Collation') AS [Collation],
    SERVERPROPERTY('IsClustered') AS [IsClustered],
    SERVERPROPERTY('IsHadrEnabled') AS [AlwaysOnEnabled],
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) AS [CurrentUserSessions];

SELECT
    d.name AS [Database],
    d.state_desc AS [State],
    d.recovery_model_desc AS [RecoveryModel],
    d.compatibility_level AS [CompatLevel],
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS [SizeMB],
    d.is_read_only AS [ReadOnly],
    d.is_auto_shrink_on AS [AutoShrink_BAD],
    d.is_auto_close_on AS [AutoClose_BAD]
FROM sys.databases AS d
JOIN sys.master_files AS mf ON d.database_id = mf.database_id
GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.compatibility_level, d.is_read_only, d.is_auto_shrink_on, d.is_auto_close_on
ORDER BY [SizeMB] DESC;

SELECT DISTINCT
    vs.volume_mount_point AS [Drive],
    CAST(vs.total_bytes / 1073741824.0 AS DECIMAL(18,2)) AS [TotalGB],
    CAST(vs.available_bytes / 1073741824.0 AS DECIMAL(18,2)) AS [FreeGB],
    CAST(vs.available_bytes * 100.0 / NULLIF(vs.total_bytes, 0) AS DECIMAL(5,2)) AS [FreePct]
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
ORDER BY [FreePct] ASC;

SELECT
    d.name AS [Database],
    d.recovery_model_desc AS [RecoveryModel],
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS [LastFull],
    MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS [LastDiff],
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS [LastLog],
    DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), SYSDATETIME()) AS [HoursSinceFullBackup]
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b ON d.name = b.database_name
WHERE d.database_id > 4 AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
ORDER BY [HoursSinceFullBackup] DESC;

SELECT
    j.name AS [JobName],
    h.step_name AS [StepName],
    h.message AS [ErrorMessage],
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS [FailTime]
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON h.job_id = j.job_id
WHERE h.run_status = 0
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) > DATEADD(HOUR, -24, SYSDATETIME())
ORDER BY [FailTime] DESC;

SELECT 'AUTO_SHRINK enabled' AS [RedFlag], name AS [Database]
FROM sys.databases WHERE is_auto_shrink_on = 1
UNION ALL
SELECT 'AUTO_CLOSE enabled', name
FROM sys.databases WHERE is_auto_close_on = 1;
