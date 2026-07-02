/*
    Script: restore-command-generator.sql
    Purpose: Build a reviewable point-in-time restore sequence (full + diff + log chain) from msdb backup history.
    Compatible: SQL Server 2017+ (uses STRING_AGG)
    Requires: msdb read access
    Impact: Read-only; prints RESTORE commands for review, executes nothing
    Scope: Instance
    Safety: GeneratesCommandsOnly

    Notes:
    - If the point in time is later than the newest log backup, take (or locate) a
      tail-log backup first, then re-run this script.
    - When overwriting an existing database, take a tail-log backup with NORECOVERY
      before restoring, and only then consider @IncludeReplace = 1.
    - Striped backups (multiple files per set) are handled automatically.
*/

SET NOCOUNT ON;

DECLARE @DatabaseName   SYSNAME       = N'YourDatabase';
DECLARE @PointInTime    DATETIME      = NULL;   -- NULL = end of the newest log backup
DECLARE @RestoreAsName  SYSNAME       = NULL;   -- NULL = original name; side-by-side restores also need new file paths
DECLARE @DataFilePath   NVARCHAR(260) = NULL;   -- e.g. N'D:\SQLData\'; generates MOVE clauses when set
DECLARE @LogFilePath    NVARCHAR(260) = NULL;   -- e.g. N'L:\SQLLog\'
DECLARE @IncludeReplace BIT           = 0;      -- 1 adds WITH REPLACE; only for deliberate overwrites

DECLARE @TargetName SYSNAME = COALESCE(@RestoreAsName, @DatabaseName);

-- ============================================
-- 1. Most recent full backup at or before the point in time
-- ============================================
DECLARE @FullSetId INT, @FullMediaSetId INT, @FullPosition INT,
        @FullLastLsn NUMERIC(25,0), @FullCheckpointLsn NUMERIC(25,0), @FullFinish DATETIME;

SELECT TOP (1)
    @FullSetId = bs.backup_set_id,
    @FullMediaSetId = bs.media_set_id,
    @FullPosition = bs.position,
    @FullLastLsn = bs.last_lsn,
    @FullCheckpointLsn = bs.checkpoint_lsn,
    @FullFinish = bs.backup_finish_date
FROM msdb.dbo.backupset AS bs
WHERE bs.database_name = @DatabaseName
  AND bs.type = 'D'
  AND bs.is_copy_only = 0
  AND (@PointInTime IS NULL OR bs.backup_finish_date <= @PointInTime)
ORDER BY bs.backup_finish_date DESC;

IF @FullSetId IS NULL
BEGIN
    RAISERROR('No full backup found for [%s] at or before the requested point in time.', 16, 1, @DatabaseName);
    RETURN;
END;

-- ============================================
-- 2. Most recent differential that belongs to that full
-- ============================================
DECLARE @DiffSetId INT, @DiffMediaSetId INT, @DiffPosition INT,
        @DiffLastLsn NUMERIC(25,0), @DiffFinish DATETIME;

SELECT TOP (1)
    @DiffSetId = bs.backup_set_id,
    @DiffMediaSetId = bs.media_set_id,
    @DiffPosition = bs.position,
    @DiffLastLsn = bs.last_lsn,
    @DiffFinish = bs.backup_finish_date
FROM msdb.dbo.backupset AS bs
WHERE bs.database_name = @DatabaseName
  AND bs.type = 'I'
  AND bs.database_backup_lsn = @FullCheckpointLsn   -- diff must be based on the chosen full
  AND (@PointInTime IS NULL OR bs.backup_finish_date <= @PointInTime)
ORDER BY bs.backup_finish_date DESC;

DECLARE @BaseLastLsn NUMERIC(25,0) = COALESCE(@DiffLastLsn, @FullLastLsn);

-- ============================================
-- 3. Optional MOVE clauses (logical files come from the chosen full backup)
-- ============================================
DECLARE @MoveClause NVARCHAR(MAX) = N'';

IF @DataFilePath IS NOT NULL OR @LogFilePath IS NOT NULL
BEGIN
    SELECT @MoveClause = STRING_AGG(CONVERT(NVARCHAR(MAX),
        N',' + CHAR(13) + CHAR(10)
        + N'    MOVE N''' + bf.logical_name + N''' TO N'''
        + CASE WHEN bf.file_type = 'L'
               THEN COALESCE(@LogFilePath, @DataFilePath)
               ELSE COALESCE(@DataFilePath, @LogFilePath) END
        + RIGHT(bf.physical_name, CHARINDEX('\', REVERSE(REPLACE(bf.physical_name, '/', '\')) + '\') - 1)
        + N''''), N'') WITHIN GROUP (ORDER BY bf.file_number)
    FROM msdb.dbo.backupfile AS bf
    WHERE bf.backup_set_id = @FullSetId
      AND bf.is_present = 1;
END;

-- ============================================
-- 4. Build the command sequence
-- ============================================
DECLARE @Commands TABLE (Seq INT IDENTITY(1,1) PRIMARY KEY, Command NVARCHAR(MAX) NOT NULL);

INSERT INTO @Commands (Command)
SELECT N'RESTORE DATABASE ' + QUOTENAME(@TargetName)
     + CHAR(13) + CHAR(10) + N'FROM ' + m.Disks
     + CHAR(13) + CHAR(10) + N'WITH FILE = ' + CAST(@FullPosition AS NVARCHAR(10))
     + N', NORECOVERY, CHECKSUM, STATS = 10'
     + CASE WHEN @IncludeReplace = 1 THEN N', REPLACE' ELSE N'' END
     + @MoveClause + N';'
FROM (
    SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), N'DISK = N''' + bmf.physical_device_name + N''''), N', ') AS Disks
    FROM msdb.dbo.backupmediafamily AS bmf
    WHERE bmf.media_set_id = @FullMediaSetId
) AS m;

IF @DiffSetId IS NOT NULL
INSERT INTO @Commands (Command)
SELECT N'RESTORE DATABASE ' + QUOTENAME(@TargetName)
     + CHAR(13) + CHAR(10) + N'FROM ' + m.Disks
     + CHAR(13) + CHAR(10) + N'WITH FILE = ' + CAST(@DiffPosition AS NVARCHAR(10))
     + N', NORECOVERY, CHECKSUM, STATS = 10;'
FROM (
    SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), N'DISK = N''' + bmf.physical_device_name + N''''), N', ') AS Disks
    FROM msdb.dbo.backupmediafamily AS bmf
    WHERE bmf.media_set_id = @DiffMediaSetId
) AS m;

-- Log chain: every log after the base, stopping at the first log that covers the point in time
;WITH Logs AS (
    SELECT bs.media_set_id, bs.position, bs.first_lsn, bs.last_lsn, bs.backup_finish_date,
           ROW_NUMBER() OVER (ORDER BY bs.first_lsn) AS rn
    FROM msdb.dbo.backupset AS bs
    WHERE bs.database_name = @DatabaseName
      AND bs.type = 'L'
      AND bs.last_lsn > @BaseLastLsn
), Cutoff AS (
    SELECT MIN(rn) AS stop_rn
    FROM Logs
    WHERE @PointInTime IS NOT NULL
      AND backup_finish_date >= @PointInTime
)
INSERT INTO @Commands (Command)
SELECT N'RESTORE LOG ' + QUOTENAME(@TargetName)
     + N' FROM ' + m.Disks
     + N' WITH FILE = ' + CAST(l.position AS NVARCHAR(10)) + N', NORECOVERY'
     + CASE WHEN @PointInTime IS NOT NULL AND l.rn = c.stop_rn
            THEN N', STOPAT = N''' + CONVERT(NVARCHAR(30), @PointInTime, 121) + N''''
            ELSE N'' END
     + N';'
FROM Logs AS l
CROSS JOIN Cutoff AS c
CROSS APPLY (
    SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), N'DISK = N''' + bmf.physical_device_name + N''''), N', ') AS Disks
    FROM msdb.dbo.backupmediafamily AS bmf
    WHERE bmf.media_set_id = l.media_set_id
) AS m
WHERE c.stop_rn IS NULL OR l.rn <= c.stop_rn
ORDER BY l.rn;

INSERT INTO @Commands (Command)
VALUES (N'RESTORE DATABASE ' + QUOTENAME(@TargetName) + N' WITH RECOVERY;');

-- ============================================
-- 5. Output: plan summary, then the commands to review and run manually
-- ============================================
SELECT
    @DatabaseName AS [SourceDatabase],
    @TargetName AS [RestoreAs],
    @PointInTime AS [PointInTime],
    @FullFinish AS [FullBackupUsed],
    @DiffFinish AS [DiffBackupUsed],
    (SELECT COUNT(*) FROM @Commands) - CASE WHEN @DiffSetId IS NULL THEN 2 ELSE 3 END AS [LogBackupsInChain];

SELECT Seq AS [Step], Command AS [ReviewThenRunManually]
FROM @Commands
ORDER BY Seq;
