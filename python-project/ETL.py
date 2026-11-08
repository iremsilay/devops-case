"""Başlangıç Python ETL kodu.

Bu dosya bilinçli olarak tamamlanmamıştır. Beklenen davranış ve teslim
kanıtları için aynı klasördeki README.md dosyasını inceleyin.
"""
"""
import requests

response = requests.get("https://api.github.com")
print(response)
print(response.json()) """

"""Fetch public GitHub repositories and upsert them into MongoDB."""

import logging
import os
import sys
from datetime import datetime, timezone
from urllib.parse import quote

import requests
from pymongo import ASCENDING, MongoClient
from pymongo.errors import PyMongoError


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("github-etl")


def required_env(name):
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def fetch_repositories(username, token):
    """Retrieve all public repositories using GitHub API pagination."""
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "devops-case-etl",
    }

    if token:
        headers["Authorization"] = f"Bearer {token}"

    repositories = []
    page = 1
    username = quote(username, safe="")

    with requests.Session() as session:
        while True:
            response = session.get(
                f"https://api.github.com/users/{username}/repos",
                params={
                    "per_page": 100,
                    "page": page,
                    "type": "owner",
                },
                headers=headers,
                timeout=30,
            )

            if not response.ok:
                logger.error(
                    "GitHub API request failed: status=%s page=%s",
                    response.status_code,
                    page,
                )

            response.raise_for_status()
            batch = response.json()

            if not isinstance(batch, list):
                raise ValueError("Unexpected GitHub API response format")

            repositories.extend(batch)

            if len(batch) < 100:
                break

            page += 1

    return repositories


def transform_repository(repo):
    """Select repository fields to store in MongoDB."""
    if not isinstance(repo.get("id"), int):
        raise ValueError("GitHub repository ID is missing or invalid")

    return {
        "github_id": repo["id"],
        "name": repo["name"],
        "full_name": repo["full_name"],
        "html_url": repo["html_url"],
        "description": repo.get("description"),
        "language": repo.get("language"),
        "stars": repo.get("stargazers_count", 0),
        "forks": repo.get("forks_count", 0),
        "private": repo.get("private", False),
        "github_updated_at": repo.get("updated_at"),
    }


def main():
    mongo_uri = required_env("ATLAS_URI")
    database_name = required_env("MONGO_DB")
    collection_name = required_env("MONGO_COLLECTION")
    username = required_env("GITHUB_USERNAME")
    token = os.getenv("GITHUB_TOKEN")

    logger.info("ETL started: github_user=%s", username)

    with MongoClient(
        mongo_uri,
        serverSelectionTimeoutMS=5000,
    ) as client:
        client.admin.command("ping")
        logger.info("MongoDB connection successful")

        collection = client[database_name][collection_name]

        # Enforce repository uniqueness at the database level.
        collection.create_index(
            [("github_id", ASCENDING)],
            unique=True,
        )

        repositories = fetch_repositories(username, token)
        logger.info("GitHub repositories retrieved: %d", len(repositories))

        inserted = 0
        updated = 0
        unchanged = 0

        for repo in repositories:
            document = transform_repository(repo)

            result = collection.update_one(
                {"github_id": document["github_id"]},
                {
                    "$set": {
                        **document,
                        "last_synced_at": datetime.now(timezone.utc),
                    }
                },
                upsert=True,
            )

            if result.upserted_id is not None:
                inserted += 1
                logger.info("INSERTED repository=%s", document["full_name"])
            elif result.matched_count == 1:
                updated += 1
                logger.info("UPDATED repository=%s", document["full_name"])
            else:
                unchanged += 1

        logger.info(
            "ETL completed successfully: fetched=%d inserted=%d "
            "updated=%d unchanged=%d",
            len(repositories),
            inserted,
            updated,
            unchanged,
        )


if __name__ == "__main__":
    try:
        main()
    except (requests.RequestException, PyMongoError, ValueError, KeyError):
        logger.exception("ETL failed")
        sys.exit(1)

