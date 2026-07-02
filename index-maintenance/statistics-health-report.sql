/*
    Script: statistics-health-report.sql
    Purpose: Find stale statistics using modification counters and generate UPDATE STATISTICS commands.
    Compatible: SQL Server 2016+
    Requires: VIEW DATABASE STATE in target database
    Impact: Read-only; UPDATE STATISTICS commands are printed, not executed
    Scope: Database (run in the target database)
    Safety: GeneratesCommandsOnly

    Notes:
    - "STALE" uses the modern auto-update threshold, SQRT(1000 * rows), so it flags
      statistics that auto-update should have caught plus large tables where the
      default sample may be too shallow.
    - RESAMPLE keeps the existing sample rate; switch to FULLSCAN for statistics
      that keep causing bad estimates.
*/

DECLARE @MinRows BIGINT = 10000;   -- ignore small tables; auto-update handles them well

SELECT
    QUOTENAME(sch.name) + N'.' + QUOTENAME(o.name) AS [Table],
    s.name AS [Statistic],
    s.auto_created AS [AutoCreated],
    s.no_recompute AS [NoRecompute],
    sp.last_updated AS [LastUpdated],
    sp.rows AS [Rows],
    sp.rows_sampled AS [RowsSampled],
    CAST(sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) AS DECIMAL(5,2)) AS [SamplePct],
    sp.modification_counter AS [ModificationsSinceUpdate],
    CAST(sp.modification_counter * 100.0 / NULLIF(sp.rows, 0) AS DECIMAL(18,2)) AS [ModPct],
    CASE
        WHEN sp.last_updated IS NULL THEN 'NEVER_UPDATED'
        WHEN sp.modification_counter >= SQRT(1000.0 * sp.rows) THEN 'STALE'
        ELSE 'OK'
    END AS [Status],
    CASE
        WHEN sp.last_updated IS NULL OR sp.modification_counter >= SQRT(1000.0 * sp.rows)
        THEN N'UPDATE STATISTICS ' + QUOTENAME(sch.name) + N'.' + QUOTENAME(o.name)
             + N' ' + QUOTENAME(s.name) + N' WITH RESAMPLE;'
        ELSE NULL
    END AS [Command]
FROM sys.stats AS s
JOIN sys.objects AS o ON s.object_id = o.object_id
JOIN sys.schemas AS sch ON o.schema_id = sch.schema_id
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE o.is_ms_shipped = 0
  AND o.type = 'U'
  AND sp.rows >= @MinRows
ORDER BY
    CASE
        WHEN sp.last_updated IS NULL THEN 0
        WHEN sp.modification_counter >= SQRT(1000.0 * sp.rows) THEN 1
        ELSE 2
    END,
    sp.modification_counter DESC;
