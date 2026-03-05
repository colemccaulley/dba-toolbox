/*
    New Database Setup Checklist
    ----------------------------
    Template for setting up a new database with best practices.
    
    ⚠️ REVIEW AND MODIFY before running. This is a template, not a click-and-run script.
    
    Compatible: SQL Server 2016+
*/

-- ============================================
-- Parameters — CHANGE THESE
-- ============================================
DECLARE @DatabaseName NVARCHAR(128) = 'NewDatabase';
DECLARE @DataPath NVARCHAR(256) = 'D:\SQLData\';       -- Your data file path
DECLARE @LogPath NVARCHAR(256) = 'E:\SQLLogs\';        -- Your log file path
DECLARE @InitialSizeMB INT = 1024;                      -- Starting data file size
DECLARE @GrowthMB INT = 256;                            -- Data file auto-growth
DECLARE @LogSizeMB INT = 512;                           -- Starting log file size
DECLARE @LogGrowthMB INT = 128;                         -- Log file auto-growth
DECLARE @DryRun BIT = 1;                                -- 1 = print only, 0 = execute

-- ============================================
-- Generate CREATE DATABASE
-- ============================================
DECLARE @SQL NVARCHAR(MAX) = '
CREATE DATABASE [' + @DatabaseName + ']
ON PRIMARY (
    NAME = N''' + @DatabaseName + '_Data'',
    FILENAME = N''' + @DataPath + @DatabaseName + '_Data.mdf'',
    SIZE = ' + CAST(@InitialSizeMB AS VARCHAR(10)) + 'MB,
    FILEGROWTH = ' + CAST(@GrowthMB AS VARCHAR(10)) + 'MB
)
LOG ON (
    NAME = N''' + @DatabaseName + '_Log'',
    FILENAME = N''' + @LogPath + @DatabaseName + '_Log.ldf'',
    SIZE = ' + CAST(@LogSizeMB AS VARCHAR(10)) + 'MB,
    FILEGROWTH = ' + CAST(@LogGrowthMB AS VARCHAR(10)) + 'MB
);';

PRINT @SQL;
PRINT '';

-- ============================================
-- Post-Creation Settings
-- ============================================
DECLARE @PostSQL NVARCHAR(MAX) = '
-- Set recovery model (FULL for production, SIMPLE for dev/test)
ALTER DATABASE [' + @DatabaseName + '] SET RECOVERY FULL;

-- Set compatibility level to current instance version
ALTER DATABASE [' + @DatabaseName + '] SET COMPATIBILITY_LEVEL = ' + 
    CAST((SELECT compatibility_level FROM sys.databases WHERE name = 'master') AS VARCHAR(3)) + ';

-- Enable Query Store (recommended for SQL 2016+)
ALTER DATABASE [' + @DatabaseName + '] SET QUERY_STORE = ON;
ALTER DATABASE [' + @DatabaseName + '] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1024,
    QUERY_CAPTURE_MODE = AUTO,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30)
);

-- Page verify (should always be CHECKSUM)
ALTER DATABASE [' + @DatabaseName + '] SET PAGE_VERIFY CHECKSUM;

-- Never enable these
ALTER DATABASE [' + @DatabaseName + '] SET AUTO_SHRINK OFF;
ALTER DATABASE [' + @DatabaseName + '] SET AUTO_CLOSE OFF;
';

PRINT @PostSQL;

-- ============================================
-- Execute if not dry run
-- ============================================
IF @DryRun = 0
BEGIN
    EXEC sp_executesql @SQL;
    EXEC sp_executesql @PostSQL;
    PRINT '✅ Database created and configured.';
END
ELSE
    PRINT '-- DRY RUN: Set @DryRun = 0 to execute --';
