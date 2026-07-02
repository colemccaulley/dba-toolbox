# DBA Toolbox Script Catalog

| Script | Category | Purpose | Impact | Scope |
|---|---|---|---|---|
| `backup-restore/backup-status-report.sql` | Backup/Restore | Identify stale or missing database backups | Read-only | Instance |
| `backup-restore/restore-command-generator.sql` | Backup/Restore | Build a point-in-time restore sequence (full + diff + logs) from msdb history | Generates commands only | Instance |
| `capacity-planning/database-growth-trend.sql` | Capacity Planning | Trend database growth from backup history and project space needs | Read-only | Instance |
| `ha-dr/availability-group-health.sql` | HA/DR | Review AG replica roles, sync state, send/redo queues, and listeners | Read-only | Instance |
| `health-checks/database-size-report.sql` | Health Checks | Report database/data/log file size and growth settings | Read-only | Instance |
| `health-checks/dbcc-checkdb-status.sql` | Health Checks | Report last known good DBCC CHECKDB and generate commands for overdue databases | Generates commands only | Instance |
| `health-checks/server-health-check.sql` | Health Checks | Day-one instance health overview and red flags | Read-only | Instance |
| `health-checks/tempdb-configuration-check.sql` | Health Checks | Review tempdb file count, sizing, growth, and trace flags | Read-only | Instance |
| `index-maintenance/index-fragmentation-report.sql` | Index Maintenance | Report fragmented indexes and generate optional commands | Generates commands only | Database |
| `index-maintenance/statistics-health-report.sql` | Index Maintenance | Find stale statistics and generate UPDATE STATISTICS commands | Generates commands only | Database |
| `index-maintenance/unused-index-report.sql` | Index Maintenance | Find write-only indexes and generate commented DROP statements | Generates commands only | Database |
| `migration/post-migration-validation.sql` | Migration | Snapshot object/row/security counts for source-vs-target diffing | Read-only | Database |
| `migration/pre-migration-inventory.sql` | Migration | Capture source-instance inventory before a migration or upgrade | Read-only | Instance |
| `monitoring/agent-job-status.sql` | Monitoring | Review SQL Agent job state and recent execution outcome | Read-only | Instance |
| `monitoring/deadlock-report.sql` | Monitoring | Pull recent deadlock graphs from system_health and shred participants | Read-only | Instance |
| `monitoring/long-running-requests.sql` | Monitoring | Show currently executing requests over a duration threshold | Read-only | Instance |
| `performance/blocking-check.sql` | Performance | Inspect current blocking chains and head blockers | Read-only | Instance |
| `performance/missing-index-report.sql` | Performance | Rank missing-index suggestions and generate candidate CREATE INDEX statements | Generates commands only | Instance |
| `performance/query-store-top-duration.sql` | Performance | Find high-duration Query Store queries | Read-only | Database |
| `performance/top-expensive-queries.sql` | Performance | Find expensive cached plans by CPU/reads/duration | Read-only | Instance |
| `performance/wait-stats-delta-snapshot.sql` | Performance | Measure wait stats over a short sampling window | Read-only | Instance |
| `performance/wait-stats-snapshot.sql` | Performance | Review cumulative wait stats since startup | Read-only | Instance |
| `security/failed-login-report.sql` | Security | Summarize failed login attempts from the error log by login and client | Read-only | Instance |
| `security/permission-audit.sql` | Security | Audit server/database roles, object permissions, and orphaned users | Read-only | Instance + current database |
| `templates/new-database-checklist.sql` | Templates | Generate safe new database creation/configuration SQL | Dry-run default | Instance |

## Safety levels

- **Read-only**: Queries DMVs/catalog views/history tables only.
- **Generates commands only**: Prints statements for operator review; does not execute changes.
- **Dry-run default**: Generates and prints change SQL unless an explicit execute flag is changed.
