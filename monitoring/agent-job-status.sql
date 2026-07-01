/*
    Script: agent-job-status.sql
    Purpose: Review SQL Agent job enablement, recent status, duration, schedule, owner, and failure message.
    Compatible: SQL Server 2016+
    Requires: msdb read access; SQLAgentReaderRole recommended
    Impact: Read-only
    Scope: Instance
    Safety: ReadOnly
*/

-- ============================================
-- Job Overview with Last Run Status
-- ============================================
SELECT 
    j.name AS [JobName],
    CASE j.enabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS [Status],
    
    -- Last run info
    CASE h.run_status
        WHEN 0 THEN '🔴 Failed'
        WHEN 1 THEN '🟢 Succeeded'
        WHEN 2 THEN '🟡 Retry'
        WHEN 3 THEN '⚪ Canceled'
        WHEN 4 THEN '🔵 In Progress'
        ELSE '⚪ Unknown'
    END AS [LastRunStatus],
    
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS [LastRunTime],
    
    -- Duration formatted as HH:MM:SS
    STUFF(STUFF(RIGHT('000000' + CAST(h.run_duration AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS [Duration],
    
    -- Next run
    CASE 
        WHEN ja.next_scheduled_run_date IS NOT NULL AND ja.next_scheduled_run_date > '19000101'
        THEN ja.next_scheduled_run_date
        ELSE NULL
    END AS [NextRun],
    
    -- Schedule description
    ISNULL(sch.name, 'No schedule') AS [Schedule],
    
    -- Job category
    c.name AS [Category],
    
    j.description AS [Description]

FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.syscategories c ON j.category_id = c.category_id

-- Last run history (most recent only)
OUTER APPLY (
    SELECT TOP 1 run_status, run_date, run_time, run_duration
    FROM msdb.dbo.sysjobhistory
    WHERE job_id = j.job_id AND step_id = 0
    ORDER BY run_date DESC, run_time DESC
) h

-- Next scheduled run
LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
    AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.sysjobactivity)

-- Schedule name
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules sch ON js.schedule_id = sch.schedule_id

ORDER BY 
    CASE h.run_status WHEN 0 THEN 0 ELSE 1 END,  -- Failed first
    j.name;
