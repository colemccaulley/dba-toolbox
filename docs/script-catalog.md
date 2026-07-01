# DBA Toolbox Script Catalog

| Script | Category | Purpose | Impact | Scope |
|---|---|---|---|---|
| `backup-restore/backup-status-report.sql` | Backup/Restore | Identify stale or missing database backups | Read-only | Instance |
| `health-checks/database-size-report.sql` | Health Checks | Report database/data/log file size and growth settings | Read-only | Instance |
| `health-checks/server-health-check.sql` | Health Checks | Day-one instance health overview and red flags | Read-only | Instance |
| `health-checks/tempdb-configuration-check.sql` | Health Checks | Review tempdb file count, sizing, growth, and trace flags | Read-only | Instance |
| `index-maintenance/index-fragmentation-report.sql` | Index Maintenance | Report fragmented indexes and generate optional commands | Generates commands only | Database |
| `monitoring/agent-job-status.sql` | Monitoring | Review SQL Agent job state and recent execution outcome | Read-only | Instance |
| `performance/blocking-check.sql` | Performance | Inspect current blocking chains and head blockers | Read-only | Instance |
| `performance/query-store-top-duration.sql` | Performance | Find high-duration Query Store queries | Read-only | Database |
| `performance/top-expensive-queries.sql` | Performance | Find expensive cached plans by CPU/reads/duration | Read-only | Instance |
| `performance/wait-stats-delta-snapshot.sql` | Performance | Measure wait stats over a short sampling window | Read-only | Instance |
| `performance/wait-stats-snapshot.sql` | Performance | Review cumulative wait stats since startup | Read-only | Instance |
| `security/permission-audit.sql` | Security | Audit server/database roles, object permissions, and orphaned users | Read-only | Instance + current database |
| `templates/new-database-checklist.sql` | Templates | Generate safe new database creation/configuration SQL | Dry-run default | Instance |

## Safety levels

- **Read-only**: Queries DMVs/catalog views/history tables only.
- **Generates commands only**: Prints statements for operator review; does not execute changes.
- **Dry-run default**: Generates and prints change SQL unless an explicit execute flag is changed.
