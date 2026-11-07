import { MongoClient } from "mongodb";

const connectionString = process.env.ATLAS_URI || "mongodb://localhost:27017";
const databaseName = process.env.MONGO_DB_NAME || "sample_training";

// MongoDB connects on the first operation and can rediscover the server
// after a temporary outage. Do not create an unhandled startup rejection.
const client = new MongoClient(connectionString, {
  serverSelectionTimeoutMS: 5000,
});

const db = client.db(databaseName);

export async function isDatabaseReady() {
  try {
    await db.command({ ping: 1 });
    return true;
  } catch (error) {
    console.error("MongoDB readiness check failed:", error.message);
    return false;
  }
}

export default db;
