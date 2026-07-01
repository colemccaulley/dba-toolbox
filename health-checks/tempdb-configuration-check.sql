/*
    Script: tempdb-configuration-check.sql
    Purpose: Review tempdb file count, file sizes, growth settings, and common configuration red flags.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE recommended
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly
*/

DECLARE @CpuCount INT = (SELECT cpu_count FROM sys.dm_os_sys_info);

SELECT
    @CpuCount AS [CpuCount],
    COUNT(*) AS [TempdbDataFiles],
    CASE
        WHEN COUNT(*) = 1 AND @CpuCount > 1 THEN 'WARN_ONLY_ONE_DATA_FILE'
        WHEN COUNT(*) > 8 AND COUNT(*) > @CpuCount THEN 'REVIEW_TOO_MANY_FILES'
        ELSE 'OK'
    END AS [FileCountAssessment]
FROM tempdb.sys.database_files
WHERE type_desc = 'ROWS';

SELECT
    name AS [LogicalName],
    physical_name AS [PhysicalName],
    type_desc AS [FileType],
    CAST(size * 8.0 / 1024 AS DECIMAL(18,2)) AS [SizeMB],
    CASE is_percent_growth
        WHEN 1 THEN CONVERT(VARCHAR(20), growth) + '%'
        ELSE CONVERT(VARCHAR(20), growth * 8 / 1024) + ' MB'
    END AS [Growth],
    CASE
        WHEN is_percent_growth = 1 THEN 'WARN_PERCENT_GROWTH'
        WHEN growth = 0 THEN 'WARN_NO_GROWTH'
        ELSE 'OK'
    END AS [GrowthAssessment]
FROM tempdb.sys.database_files
ORDER BY type_desc, file_id;
