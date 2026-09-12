/**
 * SCENARIO75 "Cookie Reuse & MFA Bypass"
 * Intentionally VULNERABLE Admin Feedback System.
 * Built for training purposes only (Red vs Blue cyber range).
 *
 * DO NOT deploy this outside an isolated lab network.
 */

const express = require("express");
const cookieParser = require("cookie-parser");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const app = express();
const PORT = 3075;
const LOG_DIR = process.env.LOG_DIR || "/opt/admin/logs";

// Make sure log dir exists (also works if running outside Docker for local testing)
fs.mkdirSync(LOG_DIR, { recursive: true });
const accessLogPath = path.join(LOG_DIR, "access.log");
const errorLogPath = path.join(LOG_DIR, "error.log");

app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(cookieParser());


// In-memory "database" of submitted feedback (the admin reviews these later)
// This is where our storedXSS payload lives.

let feedbackStore = [];


// Logging helpers nginx-style access.log + application error.log

function nowStamp() {
  return new Date().toISOString().replace("T", " ").substring(0, 19);
}

function logAccess(req, status, extra = {}) {
  const xff = extra.xff ? ` xff="${extra.xff}"` : "";
  const line = `${req.ip} - - [${nowStamp()}] "${req.method} ${req.originalUrl} HTTP/1.1" ${status} "-" "${req.headers["user-agent"] || "-"}"${xff}\n`;
  fs.appendFileSync(accessLogPath, line);
}

function logError(level, message) {
  const line = `[${nowStamp()}] [${level}] ${message}\n`;
  fs.appendFileSync(errorLogPath, line);
}


// PHASE 1: Reconnaissance


// Expose backend tech via header (instead of Express' default "Express")
app.disable("x-powered-by");
app.use((req, res, next) => {
  res.setHeader("X-Powered-By", "Node.js");
  next();
});

// robots.txt hints at the hidden admin verification endpoint
app.get("/robots.txt", (req, res) => {
  logAccess(req, 200);
  res.type("text/plain").send(
    "User-agent: *\nDisallow: /api/verify-mfa\nDisallow: /dashboard\n"
  );
});

// Landing page: sets the pre-auth session cookie + ASCII art hint in source
app.get("/", (req, res) => {
  res.cookie("pre_mfa_session", "pending_mfa_verification", {
    httpOnly: false, // <-- intentionally vulnerable
  });
  logAccess(req, 200);
  res.send(`
<!--
   _____ _               _      _____ _
  / ____| |             | |    |  __ \\ |
 | |    | |__   ___  ___| | __ | |__) |_
 | |    | '_ \\ / _ \\/ __| |/ / |  _  /| |
 | |____| | | |  __/ (__|   <  | | \\ \\| |
  \\_____|_| |_|\\___|\\___|_|\\_\\ |_|  \\_\\_|

  Hint: not everything a robot is allowed to see... /robots.txt ;)
-->
<html>
<head><title>Admin Feedback System</title></head>
<body>
  <h1>Corporate Admin Feedback System</h1>
  <p>Have feedback for the admin team? Submit it below.</p>
  <form method="POST" action="/api/feedback">
    <textarea name="message" rows="4" cols="50"></textarea><br/>
    <button type="submit">Submit Feedback</button>
  </form>
  <p><a href="/login">Admin login</a></p>
</body>
</html>
  `);
});


// Fake login + MFA flow (so there's a "legit" admin session to steal)

app.get("/login", (req, res) => {
  logAccess(req, 200);
  res.send(`
<html><body>
<h2>Admin Login</h2>
<form method="POST" action="/login">
  <input name="username" placeholder="username" value="admin"/><br/>
  <input name="password" type="password" placeholder="password"/><br/>
  <button type="submit">Login</button>
</form>
</body></html>`);
});

app.post("/login", (req, res) => {
  // Demo only: any credentials are "accepted" and move to MFA step
  logAccess(req, 302);
  res.redirect("/api/verify-mfa");
});

app.get("/api/verify-mfa", (req, res) => {
  logAccess(req, 200);
  res.send(`
<html><body>
<h2>MFA Verification</h2>
<form method="POST" action="/api/verify-mfa">
  <input name="otp" placeholder="6-digit OTP"/><br/>
  <button type="submit">Verify</button>
</form>
</body></html>`);
});

app.post("/api/verify-mfa", (req, res) => {
  // Demo only: any OTP is "accepted". This is the ONLY legitimate path
  // that should ever grant an adm_sess cookie.
  const token = crypto.randomBytes(8).toString("hex");
  res.cookie(`adm_sess_${token}`, "authenticated", {
    httpOnly: false, // <-- intentionally vulnerable (stealable via JS)
  });
  logAccess(req, 200);
  res.redirect("/dashboard");
});


// PHASE 2: Defense Evasion (rudimentary WAF + stored XSS)

app.post("/api/feedback", (req, res) => {
  const message = req.body.message || "";

  // Rudimentary WAF: blocks the literal <script tag...
  if (/<script/i.test(message)) {
    logAccess(req, 403);
    logError("CRITICAL", `WAF blocked <script> payload from ${req.ip}`);
    return res.status(403).json({ error: "Blocked by WAF" });
  }

  // ...but does nothing to stop <svg onload=...> or other HTML5 vectors.
  feedbackStore.push({
    message, // stored as-is: intentionally vulnerable (stored XSS)
    submittedAt: new Date().toISOString(),
  });

  logAccess(req, 200);
  res.json({ status: "Feedback submitted, thank you!" });
});


// PHASE 3: Initial Access MFA bypass via session (cookie) replay

app.get("/dashboard", (req, res) => {
  // VULNERABILITY: the backend trusts ANY cookie whose *name* starts with
  // "adm_sess" as proof of authentication. It never re-checks /api/verify-mfa,
  // so a stolen cookie can simply be replayed by an attacker.
  const cookieNames = Object.keys(req.cookies || {});
  const hasAdminSession = cookieNames.some((name) => name.startsWith("adm_sess"));

  if (!hasAdminSession) {
    logAccess(req, 401);
    return res.status(401).send("Unauthorized please log in and complete MFA.");
  }

  logAccess(req, 200);

  const feedbackHtml = feedbackStore
    .map((f) => `<div class="xss-payload">${f.message}</div>`)
    .join("\n");

  res.send(`
<html>
<head><title>Admin Dashboard</title></head>
<body>
  <h1>Admin Dashboard</h1>
  <h3>Recent Feedback</h3>
  ${feedbackHtml || "<p>No feedback yet.</p>"}

  <!-- Final flag, visible once authenticated -->
  <p style="display:none" id="flag">SCENARIO75{RED_C00k13_MFA_Byp4ss_0wn3d}</p>
</body>
</html>
  `);
});

app.listen(PORT, () => {
  console.log(`Admin Feedback System running on http://0.0.0.0:${PORT}`);
  console.log(`Logs writing to ${LOG_DIR}`);
});
