# Day-One SQL Server Instance Review

Use this runbook when you inherit a SQL Server instance or need a quick operational baseline.

## 1. Capture the basics

Run:

```sql
:r health-checks/server-health-check.sql
:r health-checks/database-size-report.sql
:r health-checks/tempdb-configuration-check.sql
```

Look for:
- SQL Server version/build and edition
- Databases offline, suspect, read-only, or using unexpected recovery models
- Low disk space
- AUTO_SHRINK or AUTO_CLOSE
- tempdb file-count or growth red flags

## 2. Validate recoverability

Run:

```sql
:r backup-restore/backup-status-report.sql
```

Look for:
- Databases never backed up
- FULL recovery databases without recent log backups
- Read-only or AG secondary databases that need context-specific interpretation

## 3. Check active pain

Run:

```sql
:r performance/blocking-check.sql
:r performance/wait-stats-delta-snapshot.sql
:r performance/top-expensive-queries.sql
```

Use Query Store scripts in each user database where Query Store is enabled.

## 4. Review operations and access

Run:

```sql
:r monitoring/agent-job-status.sql
:r security/permission-audit.sql
```

Look for:
- Failed jobs, disabled jobs, jobs without schedules
- Unexpected sysadmin membership
- Orphaned users
- Broad explicit object permissions

## 5. Document findings

Create a short report with:
- Critical risks
- Warnings
- Follow-up questions
- Immediate remediations
- Scripts/output saved as evidence
