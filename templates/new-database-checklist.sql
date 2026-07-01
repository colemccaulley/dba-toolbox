/*
    Script: new-database-checklist.sql
    Purpose: Template that generates CREATE DATABASE and post-creation configuration statements with safe dry-run defaults.
    Compatible: SQL Server 2016+
    Requires: CREATE DATABASE permission for execution; read-only when @DryRun = 1
    Impact: Dry-run by default; creates/configures database only when @DryRun = 0
    Scope: Instance
    Safety: DryRunDefault
*/

DECLARE @DatabaseName SYSNAME = N'NewDatabase';
DECLARE @DataPath NVARCHAR(260) = N'D:\SQLData\';
DECLARE @LogPath NVARCHAR(260) = N'E:\SQLLogs\';
DECLARE @InitialSizeMB INT = 1024;
DECLARE @GrowthMB INT = 256;
DECLARE @LogSizeMB INT = 512;
DECLARE @LogGrowthMB INT = 128;
DECLARE @RecoveryModel NVARCHAR(10) = N'FULL';
DECLARE @DryRun BIT = 1;

IF DB_ID(@DatabaseName) IS NOT NULL
BEGIN
    THROW 50000, 'Database already exists. Choose a different @DatabaseName or review current state.', 1;
END;

DECLARE @QuotedDatabaseName NVARCHAR(258) = QUOTENAME(@DatabaseName);
DECLARE @SQL NVARCHAR(MAX) = N'
CREATE DATABASE ' + @QuotedDatabaseName + N'
ON PRIMARY (
    NAME = N' + QUOTENAME(@DatabaseName + N'_Data', '''') + N',
    FILENAME = N' + QUOTENAME(@DataPath + @DatabaseName + N'_Data.mdf', '''') + N',
    SIZE = ' + CONVERT(NVARCHAR(20), @InitialSizeMB) + N'MB,
    FILEGROWTH = ' + CONVERT(NVARCHAR(20), @GrowthMB) + N'MB
)
LOG ON (
    NAME = N' + QUOTENAME(@DatabaseName + N'_Log', '''') + N',
    FILENAME = N' + QUOTENAME(@LogPath + @DatabaseName + N'_Log.ldf', '''') + N',
    SIZE = ' + CONVERT(NVARCHAR(20), @LogSizeMB) + N'MB,
    FILEGROWTH = ' + CONVERT(NVARCHAR(20), @LogGrowthMB) + N'MB
);';

DECLARE @PostSQL NVARCHAR(MAX) = N'
ALTER DATABASE ' + @QuotedDatabaseName + N' SET RECOVERY ' + @RecoveryModel + N';
ALTER DATABASE ' + @QuotedDatabaseName + N' SET COMPATIBILITY_LEVEL = ' + CONVERT(NVARCHAR(3), (SELECT compatibility_level FROM sys.databases WHERE name = 'master')) + N';
ALTER DATABASE ' + @QuotedDatabaseName + N' SET QUERY_STORE = ON;
ALTER DATABASE ' + @QuotedDatabaseName + N' SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1024,
    QUERY_CAPTURE_MODE = AUTO,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30)
);
ALTER DATABASE ' + @QuotedDatabaseName + N' SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE ' + @QuotedDatabaseName + N' SET AUTO_SHRINK OFF;
ALTER DATABASE ' + @QuotedDatabaseName + N' SET AUTO_CLOSE OFF;';

PRINT @SQL;
PRINT N'';
PRINT @PostSQL;

IF @DryRun = 0
BEGIN
    EXEC sys.sp_executesql @SQL;
    EXEC sys.sp_executesql @PostSQL;
    PRINT N'Database created and configured.';
END
ELSE
BEGIN
    PRINT N'DRY RUN: Set @DryRun = 0 to execute after reviewing generated SQL.';
END;
