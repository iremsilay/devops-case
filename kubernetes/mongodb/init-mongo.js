
/*
 * MongoDB initialization script.
 * Creates separate users for the MERN backend and GitHub ETL.
 * Runs only during the first initialization of an empty database.
 */

const backendUsername = process.env.MONGO_BACKEND_USERNAME;
const backendPassword = process.env.MONGO_BACKEND_PASSWORD;

const etlUsername = process.env.MONGO_ETL_USERNAME;
const etlPassword = process.env.MONGO_ETL_PASSWORD;

if (
  !backendUsername ||
  !backendPassword ||
  !etlUsername ||
  !etlPassword
) {
  throw new Error("Missing MongoDB application credentials");
}

// Backend: read/write access only to sample_training.
const backendDB = db.getSiblingDB("sample_training");

backendDB.createUser({
  user: backendUsername,
  pwd: backendPassword,
  roles: [{ role: "readWrite", db: "sample_training" }]
});

print("MongoDB backend user created");

// ETL: read/write access only to github_etl.
const etlDB = db.getSiblingDB("github_etl");

etlDB.createUser({
  user: etlUsername,
  pwd: etlPassword,
  roles: [{ role: "readWrite", db: "github_etl" }]
});

print("MongoDB ETL user created");
print("MongoDB initialization completed");
