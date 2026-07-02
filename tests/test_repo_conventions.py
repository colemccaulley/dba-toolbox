import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_FILES = sorted(ROOT.glob("**/*.sql"))

REQUIRED_HEADER_FIELDS = [
    "Script:",
    "Purpose:",
    "Compatible:",
    "Requires:",
    "Impact:",
    "Scope:",
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class RepoConventionTests(unittest.TestCase):
    def test_license_file_exists(self):
        self.assertTrue((ROOT / "LICENSE").is_file())

    def test_all_sql_scripts_have_operational_metadata_headers(self):
        self.assertTrue(SQL_FILES, "expected SQL scripts in the toolbox")
        missing = {}
        for path in SQL_FILES:
            text = read(path)[:800]
            absent = [field for field in REQUIRED_HEADER_FIELDS if field not in text]
            if absent:
                missing[str(path.relative_to(ROOT))] = absent
        self.assertEqual({}, missing)

    def test_sql_scripts_do_not_claim_2016_when_using_string_agg(self):
        offenders = []
        for path in SQL_FILES:
            text = read(path)
            if "STRING_AGG" in text.upper() and "SQL Server 2016+" in text:
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual([], offenders)

    def test_generated_sql_uses_quotename_instead_of_manual_brackets(self):
        offenders = []
        risky_patterns = ["'[' +", "+ ']'"]
        for path in SQL_FILES:
            text = read(path)
            if "ALTER " in text or "CREATE DATABASE" in text:
                if any(pattern in text for pattern in risky_patterns):
                    offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual([], offenders)

    def test_script_catalog_lists_every_sql_script(self):
        catalog = read(ROOT / "docs" / "script-catalog.md")
        missing = [
            str(path.relative_to(ROOT))
            for path in SQL_FILES
            if f"`{path.relative_to(ROOT)}`" not in catalog
        ]
        self.assertEqual([], missing, "add new scripts to docs/script-catalog.md")

    def test_key_operational_assets_exist(self):
        expected = [
            ".editorconfig",
            ".gitignore",
            ".github/workflows/validate.yml",
            "docs/script-catalog.md",
            "runbooks/day-one-instance-review.md",
            "scripts/validate_repo.py",
            "powershell/Invoke-DbaToolboxAssessment.ps1",
            "performance/query-store-top-duration.sql",
            "performance/wait-stats-delta-snapshot.sql",
            "health-checks/tempdb-configuration-check.sql",
            "backup-restore/restore-command-generator.sql",
            "health-checks/dbcc-checkdb-status.sql",
            "ha-dr/availability-group-health.sql",
            "migration/pre-migration-inventory.sql",
            "migration/post-migration-validation.sql",
            "runbooks/point-in-time-restore.md",
            "runbooks/performance-triage.md",
            "runbooks/README.md",
            "runbooks/corruption-response.md",
            "runbooks/disk-space-emergency.md",
            "runbooks/backup-failure-triage.md",
            "runbooks/ag-failover-response.md",
            "runbooks/migration-cutover.md",
        ]
        missing = [path for path in expected if not (ROOT / path).exists()]
        self.assertEqual([], missing)


if __name__ == "__main__":
    unittest.main()
