/*
    Backup Status Report
    --------------------
    Overview of backup health across all databases.
    Flags databases with missing or stale backups.
    
    Compatible: SQL Server 2016+
    Impact: Read-only, safe to run in production
*/

-- ============================================
-- Parameters
-- ============================================
DECLARE @FullBackupThresholdHours INT = 24;    -- Alert if full backup older than this
DECLARE @LogBackupThresholdHours INT = 1;      -- Alert if log backup older than this (FULL recovery only)

-- ============================================
-- Backup Status by Database
-- ============================================
SELECT 
    d.name AS [Database],
    d.recovery_model_desc AS [RecoveryModel],
    d.state_desc AS [State],
    
    -- Full backups
    bf.last_full_backup AS [LastFull],
    bf.full_backup_size_mb AS [FullSizeMB],
    DATEDIFF(HOUR, bf.last_full_backup, GETDATE()) AS [HoursSinceFull],
    
    -- Diff backups
    bd.last_diff_backup AS [LastDiff],
    
    -- Log backups
    bl.last_log_backup AS [LastLog],
    DATEDIFF(MINUTE, bl.last_log_backup, GETDATE()) AS [MinSinceLog],
    
    -- Status
    CASE 
        WHEN d.state_desc != 'ONLINE' THEN '⚪ OFFLINE'
        WHEN bf.last_full_backup IS NULL THEN '🔴 NEVER BACKED UP'
        WHEN DATEDIFF(HOUR, bf.last_full_backup, GETDATE()) > @FullBackupThresholdHours THEN '🔴 FULL BACKUP OVERDUE'
        WHEN d.recovery_model_desc = 'FULL' 
             AND (bl.last_log_backup IS NULL OR DATEDIFF(HOUR, bl.last_log_backup, GETDATE()) > @LogBackupThresholdHours) 
             THEN '🟡 LOG BACKUP OVERDUE'
        ELSE '🟢 OK'
    END AS [Status]

FROM sys.databases d

-- Last full backup
LEFT JOIN (
    SELECT 
        database_name,
        MAX(backup_finish_date) AS last_full_backup,
        CAST(MAX(backup_size) / 1048576.0 AS DECIMAL(10,2)) AS full_backup_size_mb
    FROM msdb.dbo.backupset 
    WHERE type = 'D'
    GROUP BY database_name
) bf ON d.name = bf.database_name

-- Last diff backup
LEFT JOIN (
    SELECT database_name, MAX(backup_finish_date) AS last_diff_backup
    FROM msdb.dbo.backupset WHERE type = 'I'
    GROUP BY database_name
) bd ON d.name = bd.database_name

-- Last log backup
LEFT JOIN (
    SELECT database_name, MAX(backup_finish_date) AS last_log_backup
    FROM msdb.dbo.backupset WHERE type = 'L'
    GROUP BY database_name
) bl ON d.name = bl.database_name

WHERE d.database_id > 4  -- skip system DBs
ORDER BY 
    CASE 
        WHEN bf.last_full_backup IS NULL THEN 0
        ELSE 1
    END,
    DATEDIFF(HOUR, bf.last_full_backup, GETDATE()) DESC;
