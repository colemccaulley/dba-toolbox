/*
    Script: dbcc-checkdb-status.sql
    Purpose: Report the last known good DBCC CHECKDB per database and generate commands for overdue databases.
    Compatible: SQL Server 2016 SP2+ (DATABASEPROPERTYEX LastGoodCheckDbTime)
    Requires: VIEW ANY DATABASE; sysadmin/db_owner gives complete values on all databases
    Impact: Read-only; generated DBCC commands are printed, not executed
    Scope: Instance
    Safety: GeneratesCommandsOnly
*/

DECLARE @MaxDaysSinceCheck INT = 7;
DECLARE @PhysicalOnlyOverGB DECIMAL(18,2) = 500;  -- suggest PHYSICAL_ONLY above this size; run full CHECKDB on a longer cadence

-- ============================================
-- 1. Last known good CHECKDB per database
-- ============================================
;WITH DbSize AS (
    SELECT database_id, CAST(SUM(size) * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS SizeGB
    FROM sys.master_files
    GROUP BY database_id
), CheckStatus AS (
    SELECT
        d.name,
        d.state_desc,
        d.is_read_only,
        s.SizeGB,
        NULLIF(CONVERT(DATETIME2(0), DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime')), '1900-01-01') AS LastGoodCheckDb
    FROM sys.databases AS d
    JOIN DbSize AS s ON d.database_id = s.database_id
    WHERE d.name <> 'tempdb'
)
SELECT
    name AS [Database],
    state_desc AS [State],
    SizeGB AS [SizeGB],
    LastGoodCheckDb AS [LastGoodCheckDb],
    DATEDIFF(DAY, LastGoodCheckDb, SYSDATETIME()) AS [DaysSinceCheck],
    CASE
        WHEN state_desc <> 'ONLINE' THEN 'SKIP_NOT_ONLINE'
        WHEN LastGoodCheckDb IS NULL THEN 'FAIL_NEVER_CHECKED'
        WHEN DATEDIFF(DAY, LastGoodCheckDb, SYSDATETIME()) > @MaxDaysSinceCheck THEN 'FAIL_OVERDUE'
        ELSE 'OK'
    END AS [Status]
FROM CheckStatus
ORDER BY
    CASE
        WHEN state_desc <> 'ONLINE' THEN 3
        WHEN LastGoodCheckDb IS NULL THEN 0
        WHEN DATEDIFF(DAY, LastGoodCheckDb, SYSDATETIME()) > @MaxDaysSinceCheck THEN 1
        ELSE 2
    END,
    LastGoodCheckDb;

-- ============================================
-- 2. Generated commands for overdue databases (run in a maintenance window)
--    PHYSICAL_ONLY is faster on very large databases; still run a full
--    CHECKDB with DATA_PURITY on a regular schedule.
-- ============================================
;WITH DbSize AS (
    SELECT database_id, CAST(SUM(size) * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS SizeGB
    FROM sys.master_files
    GROUP BY database_id
)
SELECT
    N'DBCC CHECKDB (' + QUOTENAME(d.name) + N') WITH NO_INFOMSGS'
    + CASE WHEN s.SizeGB > @PhysicalOnlyOverGB THEN N', PHYSICAL_ONLY' ELSE N', DATA_PURITY' END
    + N';' AS [RunInMaintenanceWindow]
FROM sys.databases AS d
JOIN DbSize AS s ON d.database_id = s.database_id
WHERE d.name <> 'tempdb'
  AND d.state_desc = 'ONLINE'
  AND (
        DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') IS NULL
        OR CONVERT(DATETIME2(0), DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime')) = '1900-01-01'
        OR DATEDIFF(DAY, CONVERT(DATETIME2(0), DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime')), SYSDATETIME()) > @MaxDaysSinceCheck
      )
ORDER BY s.SizeGB;
