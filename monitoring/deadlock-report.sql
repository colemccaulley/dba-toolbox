/*
    Script: deadlock-report.sql
    Purpose: Pull recent deadlock graphs from the built-in system_health Extended Events session and shred the participants.
    Compatible: SQL Server 2016+
    Requires: VIEW SERVER STATE
    Impact: Read-only (uses a session temp table to avoid reading the XE files twice)
    Scope: Instance
    Safety: ReadOnly

    Notes:
    - system_health is always on; its files roll over, so only recent deadlocks are
      retained (typically days, depending on event volume).
    - Save the DeadlockGraph XML as a .xdl file to view it graphically in SSMS.
*/

IF OBJECT_ID('tempdb..#deadlocks') IS NOT NULL DROP TABLE #deadlocks;

SELECT CONVERT(XML, event_data) AS event_xml
INTO #deadlocks
FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
WHERE object_name = 'xml_deadlock_report';

-- ============================================
-- 1. Deadlock list with full graph XML
-- ============================================
SELECT
    event_xml.value('(event/@timestamp)[1]', 'DATETIME2(0)') AS [DeadlockTimeUTC],
    event_xml.query('event/data/value/deadlock') AS [DeadlockGraph]
FROM #deadlocks
ORDER BY [DeadlockTimeUTC] DESC;

-- ============================================
-- 2. Participants per deadlock
-- ============================================
SELECT
    d.event_xml.value('(event/@timestamp)[1]', 'DATETIME2(0)') AS [DeadlockTimeUTC],
    p.value('@spid', 'INT') AS [SPID],
    CASE WHEN d.event_xml.value('(event/data/value/deadlock/victim-list/victim/@id)[1]', 'NVARCHAR(50)')
              = p.value('@id', 'NVARCHAR(50)')
         THEN 1 ELSE 0 END AS [IsVictim],
    p.value('@loginname', 'NVARCHAR(128)') AS [Login],
    p.value('@hostname', 'NVARCHAR(128)') AS [Host],
    p.value('@clientapp', 'NVARCHAR(256)') AS [Application],
    DB_NAME(p.value('@currentdb', 'INT')) AS [Database],
    p.value('@isolationlevel', 'NVARCHAR(60)') AS [IsolationLevel],
    p.value('@waitresource', 'NVARCHAR(256)') AS [WaitResource],
    p.value('@lockMode', 'NVARCHAR(10)') AS [LockMode],
    LEFT(p.value('(inputbuf/text())[1]', 'NVARCHAR(MAX)'), 500) AS [InputBuffer]
FROM #deadlocks AS d
CROSS APPLY d.event_xml.nodes('event/data/value/deadlock/process-list/process') AS proc_nodes(p)
ORDER BY [DeadlockTimeUTC] DESC, [IsVictim] DESC;

DROP TABLE #deadlocks;
