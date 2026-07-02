/*
    Script: post-migration-validation.sql
    Purpose: Snapshot object counts, table row counts, and security principals for a database so source and target can be diffed after migration.
    Compatible: SQL Server 2016+
    Requires: VIEW DATABASE STATE in target database
    Impact: Read-only
    Scope: Database (run in the database being validated)
    Safety: ReadOnly

    Notes:
    - Run in the same database on the source and the target, export each result set
      (the PowerShell assessment wrapper writes CSVs), and diff the outputs.
    - Row counts come from sys.dm_db_partition_stats: fast and accurate enough for
      validation as long as the database is quiesced during comparison.
    - For content-level checks on critical tables, follow up with e.g.
      SELECT CHECKSUM_AGG(BINARY_CHECKSUM(*)) FROM dbo.CriticalTable;
*/

-- ============================================
-- 1. Context (proves which side/database the snapshot came from)
-- ============================================
SELECT
    SERVERPROPERTY('ServerName') AS [ServerName],
    DB_NAME() AS [Database],
    DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS [Collation],
    (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()) AS [CompatLevel],
    SYSDATETIME() AS [CapturedAt];

-- ============================================
-- 2. Object counts by type
-- ============================================
SELECT o.type_desc AS [ObjectType], COUNT(*) AS [Count]
FROM sys.objects AS o
WHERE o.is_ms_shipped = 0
GROUP BY o.type_desc
ORDER BY o.type_desc;

-- ============================================
-- 3. Row counts per table
-- ============================================
SELECT
    sch.name AS [Schema],
    t.name AS [Table],
    SUM(ps.row_count) AS [Rows]
FROM sys.tables AS t
JOIN sys.schemas AS sch ON t.schema_id = sch.schema_id
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = t.object_id AND ps.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
GROUP BY sch.name, t.name
ORDER BY sch.name, t.name;

-- ============================================
-- 4. Schema and security element counts
-- ============================================
SELECT 'Indexes' AS [ElementClass],
       COUNT(*) AS [Count]
FROM sys.indexes AS i
JOIN sys.tables AS t ON i.object_id = t.object_id
WHERE i.index_id > 0 AND t.is_ms_shipped = 0
UNION ALL
SELECT 'ForeignKeys', COUNT(*) FROM sys.foreign_keys WHERE is_ms_shipped = 0
UNION ALL
SELECT 'CheckConstraints', COUNT(*) FROM sys.check_constraints WHERE is_ms_shipped = 0
UNION ALL
SELECT 'DefaultConstraints', COUNT(*) FROM sys.default_constraints WHERE is_ms_shipped = 0
UNION ALL
SELECT 'Triggers', COUNT(*) FROM sys.triggers WHERE is_ms_shipped = 0
UNION ALL
SELECT 'DatabaseUsers', COUNT(*)
FROM sys.database_principals
WHERE type IN ('S', 'U', 'G') AND principal_id > 4
UNION ALL
SELECT 'DatabaseRoles', COUNT(*)
FROM sys.database_principals
WHERE type = 'R' AND is_fixed_role = 0 AND principal_id > 4
ORDER BY [ElementClass];

-- ============================================
-- 5. Orphaned users (SQL users whose login SID does not exist on this instance)
-- ============================================
SELECT
    dp.name AS [OrphanedUser],
    dp.type_desc AS [Type],
    dp.create_date AS [Created]
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON dp.sid = sp.sid
WHERE dp.type = 'S'
  AND dp.principal_id > 4
  AND dp.authentication_type = 1
  AND sp.sid IS NULL
ORDER BY dp.name;
