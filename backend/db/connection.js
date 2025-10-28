import mysql from "mysql2/promise";

export const pool = mysql.createPool({
  host: "localhost",
  user: "root",
  password: "yourpassword",
  database: "yourdbname",
  waitForConnections: true,
  connectionLimit: 10,
});
