import React, { useState } from "react";

interface Comment {
  comment_id: number;
  body: string;
  created_at: string;
  thread_id: number;
  bet_id: number;
}

const UserCommentsPanel: React.FC = () => {
  const [userId, setUserId] = useState("");
  const [comments, setComments] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const fetchComments = async () => {
    setLoading(true);
    setError("");
    try {
      const res = await fetch(
        `http://localhost:5000/users/${userId}/comments/recent?limit=5`
      );
      if (!res.ok) throw new Error("Network response was not ok");
      const data: Comment[] = await res.json();
      setComments(data);
    } catch (err) {
      console.error(err);
      setError("Failed to load comments");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ padding: "1rem" }}>
      <h3>Recent Comments by User</h3>
      <input
        type="text"
        placeholder="Enter user ID"
        value={userId}
        onChange={(e) => setUserId(e.target.value)}
      />
      <button onClick={fetchComments} disabled={!userId || loading}>
        {loading ? "Loading..." : "Fetch Comments"}
      </button>

      {error && <p style={{ color: "red" }}>{error}</p>}

      <ul>
        {comments.map((c) => (
          <li key={c.comment_id}>
            <strong>Bet {c.bet_id}</strong> – {c.body}{" "}
            <em>({new Date(c.created_at).toLocaleString()})</em>
          </li>
        ))}
      </ul>
    </div>
  );
};

export default UserCommentsPanel;
