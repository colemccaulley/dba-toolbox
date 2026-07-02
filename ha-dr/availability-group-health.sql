/*
    Script: availability-group-health.sql
    Purpose: Review Always On Availability Group health: replica roles, sync state, send/redo queues, and listeners.
    Compatible: SQL Server 2016+ (Enterprise, or Standard with basic AGs)
    Requires: VIEW SERVER STATE
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly

    Notes:
    - Queue/rate DMV columns are fully populated on the primary; run there for the
      complete picture.
    - LogSendQueueKB on an async replica approximates data at risk (RPO exposure);
      RedoQueueKB / RedoKBPerSec approximates failover catch-up time (RTO impact).
*/

-- ============================================
-- 1. Is Always On even enabled here?
-- ============================================
SELECT
    SERVERPROPERTY('ServerName') AS [ServerName],
    SERVERPROPERTY('IsHadrEnabled') AS [AlwaysOnEnabled],
    CASE WHEN SERVERPROPERTY('IsHadrEnabled') = 1
         THEN 'Result sets below show AG state'
         ELSE 'Always On is not enabled; remaining result sets will be empty'
    END AS [Note];

-- ============================================
-- 2. Availability group overview
-- ============================================
SELECT
    ag.name AS [AvailabilityGroup],
    ags.primary_replica AS [CurrentPrimary],
    ags.synchronization_health_desc AS [SyncHealth],
    ags.primary_recovery_health_desc AS [PrimaryRecoveryHealth],
    ag.automated_backup_preference_desc AS [BackupPreference]
FROM sys.availability_groups AS ag
JOIN sys.dm_hadr_availability_group_states AS ags ON ag.group_id = ags.group_id
ORDER BY ag.name;

-- ============================================
-- 3. Replica roles and failover configuration
-- ============================================
SELECT
    ag.name AS [AvailabilityGroup],
    ar.replica_server_name AS [Replica],
    ars.role_desc AS [Role],
    ar.availability_mode_desc AS [AvailabilityMode],
    ar.failover_mode_desc AS [FailoverMode],
    ars.operational_state_desc AS [OperationalState],
    ars.connected_state_desc AS [Connected],
    ars.synchronization_health_desc AS [SyncHealth],
    ar.secondary_role_allow_connections_desc AS [ReadableSecondary],
    ar.backup_priority AS [BackupPriority]
FROM sys.availability_replicas AS ar
JOIN sys.availability_groups AS ag ON ar.group_id = ag.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS ars
       ON ar.replica_id = ars.replica_id AND ar.group_id = ars.group_id
ORDER BY ag.name, ars.role_desc, ar.replica_server_name;

-- ============================================
-- 4. Database-level synchronization and queue depths
-- ============================================
SELECT
    ag.name AS [AvailabilityGroup],
    ar.replica_server_name AS [Replica],
    DB_NAME(drs.database_id) AS [Database],
    drs.is_local AS [IsLocal],
    drs.synchronization_state_desc AS [SyncState],
    drs.synchronization_health_desc AS [SyncHealth],
    drs.log_send_queue_size AS [LogSendQueueKB],
    drs.log_send_rate AS [LogSendKBPerSec],
    drs.redo_queue_size AS [RedoQueueKB],
    drs.redo_rate AS [RedoKBPerSec],
    CAST(drs.redo_queue_size / NULLIF(drs.redo_rate, 0.0) AS DECIMAL(18,1)) AS [EstRedoCatchupSec],
    drs.last_commit_time AS [LastCommitTime],
    drs.suspend_reason_desc AS [SuspendReason]
FROM sys.dm_hadr_database_replica_states AS drs
JOIN sys.availability_replicas AS ar ON drs.replica_id = ar.replica_id AND drs.group_id = ar.group_id
JOIN sys.availability_groups AS ag ON drs.group_id = ag.group_id
ORDER BY ag.name, [Database], ar.replica_server_name;

-- ============================================
-- 5. Listeners
-- ============================================
SELECT
    ag.name AS [AvailabilityGroup],
    agl.dns_name AS [ListenerName],
    agl.port AS [Port],
    agl.ip_configuration_string_from_cluster AS [IpConfiguration]
FROM sys.availability_group_listeners AS agl
JOIN sys.availability_groups AS ag ON agl.group_id = ag.group_id
ORDER BY ag.name;
