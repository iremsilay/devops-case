import express from "express";
import db from "../db/conn.mjs";
import { ObjectId } from "mongodb";

const router = express.Router();

// Express 4 does not automatically forward rejected async route promises.
const handleAsync = (handler) => (req, res, next) => {
  Promise.resolve(handler(req, res, next)).catch(next);
};

router.get("/", handleAsync(async (req, res) => {
  const results = await db.collection("records").find({}).toArray();
  res.status(200).json(results);
}));

router.get("/:id", handleAsync(async (req, res) => {
  const result = await db.collection("records").findOne({ _id: new ObjectId(req.params.id) });
  if (!result) return res.status(404).send("Not found");
  res.status(200).json(result);
}));

router.post("/", handleAsync(async (req, res) => {
  const newDocument = {
    name: req.body.name,
    position: req.body.position,
    level: req.body.level,
  };
  const result = await db.collection("records").insertOne(newDocument);
  res.status(200).json(result);
}));

router.patch("/:id", handleAsync(async (req, res) => {
  const query = { _id: new ObjectId(req.params.id) };
  const updates = { $set: {
    name: req.body.name,
    position: req.body.position,
    level: req.body.level,
  } };
  const result = await db.collection("records").updateOne(query, updates);
  res.status(200).json(result);
}));

router.delete("/:id", handleAsync(async (req, res) => {
  const result = await db.collection("records").deleteOne({ _id: new ObjectId(req.params.id) });
  res.status(200).json(result);
}));

// A database outage must not become an unhandled rejection that kills Node.js.
router.use((error, req, res, next) => {
  console.error(`Record API ${req.method} ${req.originalUrl}:`, error);
  if (res.headersSent) return next(error);
  if (error?.name === "MongoServerSelectionError" || error?.name === "MongoNetworkError" || error?.name === "MongoTopologyClosedError") {
    return res.status(503).json({ error: "Database temporarily unavailable" });
  }
  // Input validation (F-02) is intentionally not changed by this F-08 patch.
  res.status(500).json({ error: "Internal server error" });
});

export default router;
