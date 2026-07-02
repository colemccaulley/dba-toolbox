/*
    Script: failed-login-report.sql
    Purpose: Summarize failed login attempts from the SQL Server error log by login and client address.
    Compatible: SQL Server 2016+
    Requires: securityadmin or sysadmin (xp_readerrorlog)
    Impact: Read-only (uses a session temp table)
    Scope: Instance
    Safety: ReadOnly

    Notes:
    - Requires "Failed logins only" (default) or "Both" login auditing in server
      properties; otherwise the error log has nothing to report.
    - Spikes from a single client address can indicate a misconfigured application
      (stale password) or a brute-force attempt - correlate before concluding.
*/

DECLARE @LogsToRead INT = 3;   -- current error log plus N-1 archived logs

IF OBJECT_ID('tempdb..#errorlog') IS NOT NULL DROP TABLE #errorlog;
CREATE TABLE #errorlog (LogDate DATETIME, ProcessInfo NVARCHAR(64), LogText NVARCHAR(MAX));

DECLARE @LogNumber INT = 0;
WHILE @LogNumber < @LogsToRead
BEGIN
    BEGIN TRY
        INSERT INTO #errorlog (LogDate, ProcessInfo, LogText)
        EXEC master.dbo.xp_readerrorlog @LogNumber, 1, N'Login failed';
    END TRY
    BEGIN CATCH
        BREAK;   -- fewer archived logs exist than requested
    END CATCH;
    SET @LogNumber += 1;
END;

-- ============================================
-- 1. Summary by login and client address
-- ============================================
SELECT
    SUBSTRING(LogText, CHARINDEX('''', LogText) + 1,
        CHARINDEX('''', LogText, CHARINDEX('''', LogText) + 1) - CHARINDEX('''', LogText) - 1) AS [Login],
    CASE WHEN LogText LIKE '%CLIENT:%'
         THEN LTRIM(RTRIM(REPLACE(SUBSTRING(LogText, CHARINDEX('[CLIENT:', LogText) + 8, 46), ']', '')))
         ELSE 'unknown' END AS [ClientAddress],
    COUNT(*) AS [Attempts],
    MIN(LogDate) AS [FirstSeen],
    MAX(LogDate) AS [LastSeen]
FROM #errorlog
WHERE LogText LIKE 'Login failed for user%'
GROUP BY
    SUBSTRING(LogText, CHARINDEX('''', LogText) + 1,
        CHARINDEX('''', LogText, CHARINDEX('''', LogText) + 1) - CHARINDEX('''', LogText) - 1),
    CASE WHEN LogText LIKE '%CLIENT:%'
         THEN LTRIM(RTRIM(REPLACE(SUBSTRING(LogText, CHARINDEX('[CLIENT:', LogText) + 8, 46), ']', '')))
         ELSE 'unknown' END
ORDER BY [Attempts] DESC, [LastSeen] DESC;

-- ============================================
-- 2. Most recent raw entries (reason codes live in the message text)
-- ============================================
SELECT TOP (200)
    LogDate AS [When],
    LogText AS [Message]
FROM #errorlog
WHERE LogText LIKE 'Login failed for user%'
ORDER BY LogDate DESC;

DROP TABLE #errorlog;
