/*
    Script: pre-migration-inventory.sql
    Purpose: Capture a source-instance inventory before a migration/upgrade: version, config, database flags, files, logins, jobs, linked servers.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE, VIEW ANY DEFINITION; msdb read access for job inventory
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly

    Notes:
    - Run on the source instance and keep the output with the migration plan.
    - Pair with migration/post-migration-validation.sql (run per database on both
      sides) to verify object and row counts after cutover.
    - SQL logins must be moved with their SIDs and password hashes (sp_help_revlogin
      or dbatools Copy-DbaLogin) or database users will orphan.
*/

-- ============================================
-- 1. Instance properties
-- ============================================
SELECT
    SERVERPROPERTY('ServerName') AS [ServerName],
    SERVERPROPERTY('ProductVersion') AS [Version],
    SERVERPROPERTY('ProductLevel') AS [ProductLevel],
    SERVERPROPERTY('Edition') AS [Edition],
    SERVERPROPERTY('Collation') AS [ServerCollation],
    SERVERPROPERTY('IsClustered') AS [IsClustered],
    SERVERPROPERTY('IsHadrEnabled') AS [AlwaysOnEnabled],
    SERVERPROPERTY('IsFullTextInstalled') AS [FullTextInstalled],
    SERVERPROPERTY('FilestreamConfiguredLevel') AS [FilestreamLevel],
    CASE SERVERPROPERTY('IsIntegratedSecurityOnly') WHEN 1 THEN 'Windows' ELSE 'Mixed' END AS [AuthMode];

-- ============================================
-- 2. Instance configuration worth carrying forward (or deliberately changing)
-- ============================================
SELECT name AS [Setting], value_in_use AS [ValueInUse]
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)', 'min server memory (MB)',
    'max degree of parallelism', 'cost threshold for parallelism',
    'optimize for ad hoc workloads', 'backup compression default',
    'backup checksum default', 'remote admin connections',
    'clr enabled', 'xp_cmdshell', 'Database Mail XPs', 'Ad Hoc Distributed Queries'
)
ORDER BY name;

-- ============================================
-- 3. Database inventory with migration-relevant flags
-- ============================================
SELECT
    d.name AS [Database],
    d.compatibility_level AS [CompatLevel],
    d.collation_name AS [Collation],
    CASE WHEN d.collation_name <> CAST(SERVERPROPERTY('Collation') AS SYSNAME)
         THEN 1 ELSE 0 END AS [CollationDiffersFromServer],
    d.recovery_model_desc AS [RecoveryModel],
    d.state_desc AS [State],
    d.is_read_only AS [ReadOnly],
    d.containment_desc AS [Containment],
    d.is_encrypted AS [TDE],                    -- certificate must be restored on target first
    d.is_cdc_enabled AS [CDC],
    d.is_published AS [ReplPublisher],
    d.is_subscribed AS [ReplSubscriber],
    d.is_broker_enabled AS [ServiceBroker],
    d.is_trustworthy_on AS [Trustworthy],
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS [SizeMB],
    MAX(CASE WHEN mf.type_desc = 'FILESTREAM' THEN 1 ELSE 0 END) AS [HasFilestream]
FROM sys.databases AS d
JOIN sys.master_files AS mf ON d.database_id = mf.database_id
WHERE d.database_id > 4
GROUP BY d.name, d.compatibility_level, d.collation_name, d.recovery_model_desc, d.state_desc,
         d.is_read_only, d.containment_desc, d.is_encrypted, d.is_cdc_enabled,
         d.is_published, d.is_subscribed, d.is_broker_enabled, d.is_trustworthy_on
ORDER BY [SizeMB] DESC;

-- ============================================
-- 4. File layout (plan target drive mapping / MOVE clauses)
-- ============================================
SELECT
    DB_NAME(mf.database_id) AS [Database],
    mf.name AS [LogicalName],
    mf.type_desc AS [FileType],
    mf.physical_name AS [PhysicalPath],
    CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2)) AS [SizeMB],
    CASE mf.is_percent_growth WHEN 1 THEN CAST(mf.growth AS VARCHAR(10)) + '%'
         ELSE CAST(mf.growth * 8 / 1024 AS VARCHAR(20)) + ' MB' END AS [Growth]
FROM sys.master_files AS mf
WHERE mf.database_id > 4
ORDER BY [Database], mf.type, mf.file_id;

-- ============================================
-- 5. Logins to migrate
-- ============================================
SELECT
    sp.name AS [Login],
    sp.type_desc AS [Type],
    sp.is_disabled AS [Disabled],
    sp.default_database_name AS [DefaultDatabase],
    sp.create_date AS [Created]
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT %'
ORDER BY sp.type_desc, sp.name;

-- ============================================
-- 6. Agent jobs to recreate
-- ============================================
SELECT
    j.name AS [JobName],
    CASE j.enabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS [Status],
    SUSER_SNAME(j.owner_sid) AS [Owner],
    c.name AS [Category],
    (SELECT COUNT(*) FROM msdb.dbo.sysjobschedules AS js WHERE js.job_id = j.job_id) AS [Schedules],
    (SELECT COUNT(*) FROM msdb.dbo.sysjobsteps AS st WHERE st.job_id = j.job_id) AS [Steps]
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.syscategories AS c ON j.category_id = c.category_id
ORDER BY j.name;

-- ============================================
-- 7. Linked servers (recreate with credentials on the target)
-- ============================================
SELECT
    s.name AS [LinkedServer],
    s.product AS [Product],
    s.provider AS [Provider],
    s.data_source AS [DataSource],
    s.catalog AS [Catalog]
FROM sys.servers AS s
WHERE s.is_linked = 1
ORDER BY s.name;
