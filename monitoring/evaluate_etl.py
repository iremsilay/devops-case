
#!/usr/bin/env python3

import json
import sys
from datetime import datetime, timezone


def parse_timestamp(value):
    return datetime.fromisoformat(
        value.replace("Z", "+00:00")
    )


def evaluate_etl(jobs, cronjob_name, last_success_timestamp, now):
    """
    Evaluate failed ETL Jobs and the age of the latest successful run.

    This function does not access Kubernetes or external services.
    """

    last_success = (
        parse_timestamp(last_success_timestamp)
        if last_success_timestamp
        else None
    )

    failed_jobs = []

    for job in jobs:
        metadata = job.get("metadata", {})
        owners = metadata.get("ownerReferences", [])

        owned_by_etl = any(
            owner.get("kind") == "CronJob"
            and owner.get("name") == cronjob_name
            and owner.get("controller", False)
            for owner in owners
        )

        if not owned_by_etl:
            continue

        conditions = job.get("status", {}).get("conditions", [])

        failed_condition = next(
            (
                condition
                for condition in conditions
                if condition.get("type") == "Failed"
                and condition.get("status") == "True"
            ),
            None,
        )

        if failed_condition is None:
            continue

        job_name = metadata.get("name", "unknown")
        transition_timestamp = failed_condition.get("lastTransitionTime")

        if not transition_timestamp:
            raise ValueError(
                f"Missing failure transition time for {job_name}"
            )

        failed_at = parse_timestamp(transition_timestamp)

        # Ignore failures older than the latest successful ETL.
        if last_success is not None and failed_at <= last_success:
            continue

        failed_jobs.append(job_name)

    if last_success is None:
        last_success_age = None
    else:
        last_success_age = int(
            (now - last_success).total_seconds()
        )

        if last_success_age < 0:
            raise ValueError(
                "ETL lastSuccessfulTime is in the future"
            )

    return {
        "failed_jobs": failed_jobs,
        "last_success_age": last_success_age,
    }


def main():
    if len(sys.argv) != 3:
        print(
            "Usage: evaluate_etl.py CRONJOB_NAME LAST_SUCCESS_TIMESTAMP",
            file=sys.stderr,
        )
        return 2

    cronjob_name = sys.argv[1]
    last_success_timestamp = sys.argv[2]

    try:
        data = json.load(sys.stdin)

        result = evaluate_etl(
            jobs=data.get("items", []),
            cronjob_name=cronjob_name,
            last_success_timestamp=last_success_timestamp,
            now=datetime.now(timezone.utc),
        )

        failed_jobs = result["failed_jobs"]
        last_success_age = result["last_success_age"]

        print(
            "FAILED|"
            + (",".join(failed_jobs) if failed_jobs else "none")
        )

        print(
            "LAST_SUCCESS_AGE|"
            + (
                str(last_success_age)
                if last_success_age is not None
                else "none"
            )
        )

        return 0

    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as error:
        print(f"ETL evaluation failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
