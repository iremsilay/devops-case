import express from "express";
import { isDatabaseReady } from "../db/conn.mjs";

const router = express.Router();

// Liveness: the Node.js process can respond to HTTP requests.
router.get("/", (req, res) => {
  res.status(200).json({
    uptime: process.uptime(),
    message: "OK",
    timestamp: Date.now(),
  });
});

// Readiness: database-dependent requests can be served.
router.get("/ready", async (req, res) => {
  const ready = await isDatabaseReady();
  res.status(ready ? 200 : 503).json({
    message: ready ? "READY" : "NOT_READY",
    timestamp: Date.now(),
  });
});

export default router;
