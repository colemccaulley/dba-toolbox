/*
    Permission Audit
    ----------------
    Comprehensive report of who has access to what.
    Run this periodically or when onboarding to a new environment.
    
    Compatible: SQL Server 2016+
    Impact: Read-only, safe to run in production
*/

-- ============================================
-- 1. Server-Level Logins and Roles
-- ============================================
SELECT 
    sp.name AS [Login],
    sp.type_desc AS [LoginType],
    sp.is_disabled AS [Disabled],
    sp.create_date AS [Created],
    sp.modify_date AS [Modified],
    ISNULL(STRING_AGG(sr.name, ', '), 'public only') AS [ServerRoles]
FROM sys.server_principals sp
LEFT JOIN sys.server_role_members srm ON sp.principal_id = srm.member_principal_id
LEFT JOIN sys.server_principals sr ON srm.role_principal_id = sr.principal_id
WHERE sp.type IN ('S', 'U', 'G')  -- SQL logins, Windows logins, Windows groups
  AND sp.name NOT LIKE '##%'       -- skip internal accounts
  AND sp.name NOT IN ('sa', 'NT AUTHORITY\SYSTEM', 'NT SERVICE\MSSQLSERVER', 'NT SERVICE\SQLSERVERAGENT')
GROUP BY sp.name, sp.type_desc, sp.is_disabled, sp.create_date, sp.modify_date
ORDER BY sp.name;

-- ============================================
-- 2. Sysadmin Members (know who has the keys)
-- ============================================
SELECT 
    sp.name AS [Login],
    sp.type_desc AS [LoginType],
    sp.is_disabled AS [Disabled]
FROM sys.server_role_members srm
JOIN sys.server_principals sr ON srm.role_principal_id = sr.principal_id
JOIN sys.server_principals sp ON srm.member_principal_id = sp.principal_id
WHERE sr.name = 'sysadmin'
ORDER BY sp.name;

-- ============================================
-- 3. Database-Level Permissions (current DB)
-- ============================================
SELECT 
    dp.name AS [User],
    dp.type_desc AS [UserType],
    ISNULL(STRING_AGG(dr.name, ', '), 'public only') AS [DatabaseRoles],
    dp.create_date AS [Created]
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members drm ON dp.principal_id = drm.member_principal_id
LEFT JOIN sys.database_principals dr ON drm.role_principal_id = dr.principal_id
WHERE dp.type IN ('S', 'U', 'G')
  AND dp.name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')
GROUP BY dp.name, dp.type_desc, dp.create_date
ORDER BY dp.name;

-- ============================================
-- 4. Explicit Object-Level Permissions (current DB)
-- ============================================
SELECT 
    dp.name AS [User],
    p.class_desc AS [PermClass],
    ISNULL(OBJECT_NAME(p.major_id), '') AS [Object],
    p.permission_name AS [Permission],
    p.state_desc AS [State]
FROM sys.database_permissions p
JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
WHERE dp.name NOT IN ('dbo', 'guest', 'public', 'INFORMATION_SCHEMA', 'sys')
  AND p.class_desc != 'DATABASE'
ORDER BY dp.name, OBJECT_NAME(p.major_id);

-- ============================================
-- 5. Orphaned Users (no matching server login)
-- ============================================
SELECT 
    dp.name AS [OrphanedUser],
    dp.type_desc AS [UserType],
    dp.create_date AS [Created]
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.type IN ('S', 'U')
  AND sp.sid IS NULL
  AND dp.name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys', 'MS_DataCollectorInternalUser')
  AND dp.authentication_type_desc != 'NONE';
