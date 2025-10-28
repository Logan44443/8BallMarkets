import express from "express";
import cors from "cors";
import { commentsRouter } from "./routes/comments.js";

const app = express();
app.use(cors());
app.use(express.json());

app.use(commentsRouter);

const PORT = 5000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
