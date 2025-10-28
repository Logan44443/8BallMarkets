import express from "express";
import { pool } from "../db/connection.js";

export const commentsRouter = express.Router();

commentsRouter.get("/users/:userId/comments/recent", async (req, res) => {
  const { userId } = req.params;
  const limit = parseInt(req.query.limit) || 5;

  try {
    const [rows] = await pool.query(
      `
      SELECT c.comment_id, c.body, c.created_at, c.thread_id, t.bet_id
      FROM Comments c
      JOIN Bet_Threads t ON t.thread_id = c.thread_id
      WHERE c.author_id = ? AND c.is_deleted = FALSE
      ORDER BY c.created_at DESC
      LIMIT ?;
      `,
      [userId, limit]
    );

    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Server error" });
  }
});
