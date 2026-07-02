# 🛠️ DBA Toolbox

A practical collection of reusable T-SQL and PowerShell tooling for SQL Server database administration. The repo is organized as an operational DBA assessment toolkit: read-only checks first, generated commands second, and dry-run defaults for anything that can change an instance.

## Quick Start

```sql
-- In SSMS/sqlcmd, run the scripts that match the task.
-- Review parameters at the top of each script before running.
:r health-checks/server-health-check.sql
:r backup-restore/backup-status-report.sql
:r monitoring/agent-job-status.sql
```

PowerShell assessment wrapper:

```powershell
Install-Module SqlServer -Scope CurrentUser
./powershell/Invoke-DbaToolboxAssessment.ps1 -SqlInstance 'MyServer' -WhatIf
./powershell/Invoke-DbaToolboxAssessment.ps1 -SqlInstance 'MyServer'
```

## Structure

| Folder | Description |
|--------|-------------|
| `health-checks/` | Server/database health, disk space, tempdb, DBCC CHECKDB status |
| `index-maintenance/` | Fragmentation, unused indexes, statistics health, reviewable command generation |
| `performance/` | Wait stats, blocking analysis, plan cache, Query Store, missing indexes |
| `security/` | Login audits, permission reports, orphaned users, failed-login analysis |
| `backup-restore/` | Backup health reporting and point-in-time restore command generation |
| `monitoring/` | SQL Agent jobs, long-running requests, deadlock capture |
| `migration/` | Pre-migration inventory and post-migration source/target validation |
| `ha-dr/` | Always On Availability Group health and RPO/RTO exposure |
| `capacity-planning/` | Growth trending and space projection from backup history |
| `templates/` | Safe starter templates for common DBA tasks |
| `powershell/` | PowerShell wrappers for repeatable operational workflows |
| `runbooks/` | Operator-facing procedures that tie scripts together |
| `docs/` | Script catalog and usage notes |

## Script Catalog

See `docs/script-catalog.md` for a full inventory with purpose, scope, and safety level.

## Safety Conventions

Every SQL script should declare:

- `Script`
- `Purpose`
- `Compatible`
- `Requires`
- `Impact`
- `Scope`
- `Safety`

Safety levels:

- `ReadOnly` — queries DMVs/catalog/history tables only.
- `GeneratesCommandsOnly` — produces statements for review; does not execute them.
- `DryRunDefault` — prints planned changes unless an explicit execute flag is changed.

## Prerequisites

- SQL Server 2016+ for most scripts.
- `security/permission-audit.sql` and `backup-restore/restore-command-generator.sql` require SQL Server 2017+ because they use `STRING_AGG`.
- `health-checks/dbcc-checkdb-status.sql` requires SQL Server 2016 SP2+ (`LastGoodCheckDbTime`).
- PowerShell 5.1+ or PowerShell 7+ for PowerShell wrappers.
- `SqlServer` PowerShell module for `powershell/Invoke-DbaToolboxAssessment.ps1`.

## Validation

This repo intentionally includes dependency-light validation:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/validate_repo.py
```

GitHub Actions runs the same checks on push and pull requests.

## Runbooks

Start with:

- `runbooks/day-one-instance-review.md`
- `runbooks/blocking-incident-response.md`
- `runbooks/performance-triage.md`
- `runbooks/point-in-time-restore.md`

## Contributing

This is a personal DBA toolbox, but issues and suggestions are welcome. Scripts should be safe by default, clearly documented, and reusable across SQL Server environments.

## License

MIT — see `LICENSE`.
