# 🛠️ DBA Toolbox

A collection of reusable PowerShell and T-SQL scripts for SQL Server database administration. Built from years of experience across multiple environments — these are the scripts I reach for on day one at any new gig.

## Structure

| Folder | Description |
|--------|-------------|
| `health-checks/` | Server health assessments, disk space, backup status, database state |
| `index-maintenance/` | Index rebuild/reorg, fragmentation analysis, statistics updates |
| `performance/` | Wait stats, blocking analysis, query plan review, expensive queries |
| `security/` | Login audits, permission reports, orphaned users, vulnerability scans |
| `backup-restore/` | Backup scripts, restore testing, backup history reports |
| `monitoring/` | Agent job monitoring, alerting, error log parsing |
| `migration/` | Schema comparison helpers, data migration utilities, pre/post checks |
| `templates/` | Starter templates for common DBA tasks |

## Usage

Most scripts are designed to run against any SQL Server 2016+ instance. Some PowerShell scripts use the `SqlServer` module.

### Prerequisites

- SQL Server 2016+ (most scripts)
- PowerShell 5.1+ or PowerShell 7+
- `SqlServer` PowerShell module (for PS scripts): `Install-Module SqlServer`

### Quick Start

```sql
-- Run any T-SQL script against your target instance
-- Most scripts use dynamic SQL and work across databases
-- Review and adjust parameters at the top of each script before running
```

## Script Conventions

- **Parameters at the top** — every script has configurable variables in the first section
- **Non-destructive by default** — scripts that modify anything have a `@DryRun` flag
- **Comments explain the "why"** — not just what, but why you'd use it
- **Tested on** — each script notes compatible SQL Server versions

## Contributing

This is a personal toolbox, but if you find it useful and want to suggest improvements, feel free to open an issue.

## License

MIT — use these however you want. If they save you time, that's the whole point.
