/*
    Blocking Check
    --------------
    Find current blocking chains and what's causing them.
    Run this when users complain about slowness or timeouts.
    
    Compatible: SQL Server 2016+
    Impact: Read-only, safe to run in production
*/

-- ============================================
-- 1. Current Blocking Summary
-- ============================================
SELECT 
    r.session_id AS [BlockedSPID],
    r.blocking_session_id AS [BlockingSPID],
    DB_NAME(r.database_id) AS [Database],
    r.wait_type AS [WaitType],
    r.wait_time / 1000 AS [WaitTimeSec],
    r.status AS [Status],
    r.command AS [Command],
    
    -- What's being blocked
    blocked_text.text AS [BlockedQuery],
    
    -- What's doing the blocking
    blocker_text.text AS [BlockingQuery],
    
    -- Who's who
    blocked_sess.login_name AS [BlockedLogin],
    blocked_sess.host_name AS [BlockedHost],
    blocker_sess.login_name AS [BlockerLogin],
    blocker_sess.host_name AS [BlockerHost]

FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions blocked_sess ON r.session_id = blocked_sess.session_id
LEFT JOIN sys.dm_exec_sessions blocker_sess ON r.blocking_session_id = blocker_sess.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) blocked_text
OUTER APPLY (
    SELECT text FROM sys.dm_exec_requests r2
    CROSS APPLY sys.dm_exec_sql_text(r2.sql_handle)
    WHERE r2.session_id = r.blocking_session_id
) blocker_text
WHERE r.blocking_session_id > 0
ORDER BY r.wait_time DESC;

-- ============================================
-- 2. Head Blockers (root of the chain)
-- ============================================
;WITH BlockingChain AS (
    SELECT 
        session_id,
        blocking_session_id,
        session_id AS head_blocker,
        0 AS [Level]
    FROM sys.dm_exec_requests
    WHERE blocking_session_id = 0
      AND session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id > 0)
    
    UNION ALL
    
    SELECT 
        r.session_id,
        r.blocking_session_id,
        bc.head_blocker,
        bc.[Level] + 1
    FROM sys.dm_exec_requests r
    JOIN BlockingChain bc ON r.blocking_session_id = bc.session_id
    WHERE r.blocking_session_id > 0
)
SELECT 
    head_blocker AS [HeadBlockerSPID],
    COUNT(*) AS [SessionsBlocked],
    MAX([Level]) AS [ChainDepth]
FROM BlockingChain
WHERE [Level] > 0
GROUP BY head_blocker
ORDER BY [SessionsBlocked] DESC;
