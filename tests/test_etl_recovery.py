
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

MONITORING_DIR = Path(__file__).resolve().parents[1] / "monitoring"
sys.path.insert(0, str(MONITORING_DIR))

from evaluate_etl import evaluate_etl


TEST_NOW = datetime(2026, 11, 9, 20, 0, 0, tzinfo=timezone.utc)


def failed_job(name, failed_at, cronjob_name="github-etl"):
    return {
        "metadata": {
            "name": name,
            "ownerReferences": [
                {
                    "kind": "CronJob",
                    "name": cronjob_name,
                    "controller": True,
                }
            ],
        },
        "status": {
            "conditions": [
                {
                    "type": "Failed",
                    "status": "True",
                    "lastTransitionTime": failed_at,
                }
            ]
        },
    }


class TestETLRecovery(unittest.TestCase):

    def evaluate(self, jobs, last_success):
        return evaluate_etl(
            jobs=jobs,
            cronjob_name="github-etl",
            last_success_timestamp=last_success,
            now=TEST_NOW,
        )

    def test_old_failed_job_is_ignored(self):
        result = self.evaluate(
            [failed_job("old-failure", "2026-11-09T17:00:00Z")],
            "2026-11-09T18:00:07Z",
        )

        self.assertEqual(result["failed_jobs"], [])

    def test_new_failed_job_triggers_alert(self):
        result = self.evaluate(
            [failed_job("new-failure", "2026-11-09T19:30:00Z")],
            "2026-11-09T19:00:07Z",
        )

        self.assertEqual(
            result["failed_jobs"],
            ["new-failure"],
        )

    def test_recovery_after_failure(self):
        jobs = [
            failed_job("failed-etl", "2026-11-09T18:30:00Z")
        ]

        before = self.evaluate(
            jobs,
            "2026-11-09T18:00:07Z",
        )

        after = self.evaluate(
            jobs,
            "2026-11-09T19:00:07Z",
        )

        self.assertEqual(
            before["failed_jobs"],
            ["failed-etl"],
        )
        self.assertEqual(after["failed_jobs"], [])

    def test_no_previous_success_triggers_alert(self):
        result = self.evaluate(
            [failed_job("first-failure", "2026-11-09T17:00:00Z")],
            "",
        )

        self.assertEqual(
            result["failed_jobs"],
            ["first-failure"],
        )
        self.assertIsNone(result["last_success_age"])

    def test_missing_failure_timestamp_raises_error(self):
        job = failed_job("invalid-job", "2026-11-09T17:00:00Z")
        del job["status"]["conditions"][0]["lastTransitionTime"]

        with self.assertRaises(ValueError):
            self.evaluate(
                [job],
                "2026-11-09T18:00:07Z",
            )

    def test_other_cronjob_failure_is_ignored(self):
        result = self.evaluate(
            [
                failed_job(
                    "unrelated-failure",
                    "2026-11-09T19:30:00Z",
                    cronjob_name="another-cronjob",
                )
            ],
            "2026-11-09T19:00:07Z",
        )

        self.assertEqual(result["failed_jobs"], [])


if __name__ == "__main__":
    unittest.main()
