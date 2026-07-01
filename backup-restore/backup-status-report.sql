/*
    Script: backup-status-report.sql
    Purpose: Overview of backup health across all user databases; flags stale or missing full/log backups.
    Compatible: SQL Server 2016+
    Requires: msdb read access; VIEW ANY DATABASE recommended
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly
*/

DECLARE @FullBackupThresholdHours INT = 24;
DECLARE @LogBackupThresholdMinutes INT = 60;

;WITH LastFull AS (
    SELECT database_name, MAX(backup_finish_date) AS last_full_backup,
           CAST(MAX(backup_size) / 1048576.0 AS DECIMAL(18,2)) AS full_backup_size_mb,
           CAST(MAX(compressed_backup_size) / 1048576.0 AS DECIMAL(18,2)) AS compressed_backup_size_mb,
           MAX(CAST(is_copy_only AS INT)) AS has_copy_only_full
    FROM msdb.dbo.backupset
    WHERE type = 'D'
    GROUP BY database_name
), LastDiff AS (
    SELECT database_name, MAX(backup_finish_date) AS last_diff_backup
    FROM msdb.dbo.backupset
    WHERE type = 'I'
    GROUP BY database_name
), LastLog AS (
    SELECT database_name, MAX(backup_finish_date) AS last_log_backup
    FROM msdb.dbo.backupset
    WHERE type = 'L'
    GROUP BY database_name
)
SELECT
    d.name AS [Database],
    d.recovery_model_desc AS [RecoveryModel],
    d.state_desc AS [State],
    d.is_read_only AS [ReadOnly],
    d.log_reuse_wait_desc AS [LogReuseWait],
    lf.last_full_backup AS [LastFull],
    lf.full_backup_size_mb AS [FullSizeMB],
    lf.compressed_backup_size_mb AS [CompressedFullSizeMB],
    DATEDIFF(HOUR, lf.last_full_backup, SYSDATETIME()) AS [HoursSinceFull],
    ld.last_diff_backup AS [LastDiff],
    ll.last_log_backup AS [LastLog],
    DATEDIFF(MINUTE, ll.last_log_backup, SYSDATETIME()) AS [MinutesSinceLog],
    CASE
        WHEN d.state_desc <> 'ONLINE' THEN 'OFFLINE_OR_RESTORING'
        WHEN lf.last_full_backup IS NULL THEN 'FAIL_NEVER_BACKED_UP'
        WHEN DATEDIFF(HOUR, lf.last_full_backup, SYSDATETIME()) > @FullBackupThresholdHours THEN 'FAIL_FULL_BACKUP_OVERDUE'
        WHEN d.recovery_model_desc = 'FULL'
             AND d.is_read_only = 0
             AND (ll.last_log_backup IS NULL OR DATEDIFF(MINUTE, ll.last_log_backup, SYSDATETIME()) > @LogBackupThresholdMinutes)
             THEN 'WARN_LOG_BACKUP_OVERDUE'
        ELSE 'OK'
    END AS [Status]
FROM sys.databases AS d
LEFT JOIN LastFull AS lf ON d.name = lf.database_name
LEFT JOIN LastDiff AS ld ON d.name = ld.database_name
LEFT JOIN LastLog AS ll ON d.name = ll.database_name
WHERE d.database_id > 4
ORDER BY
    CASE
        WHEN lf.last_full_backup IS NULL THEN 0
        WHEN DATEDIFF(HOUR, lf.last_full_backup, SYSDATETIME()) > @FullBackupThresholdHours THEN 1
        ELSE 2
    END,
    DATEDIFF(HOUR, lf.last_full_backup, SYSDATETIME()) DESC;
