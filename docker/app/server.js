const express = require("express");
const { execFile } = require("child_process");
const { promisify } = require("util");
const {
  createSessionToken,
  decodeBase32,
  verifySessionToken,
  verifyTotp
} = require("./totp");

const port = Number(process.env.PORT || 3000);
const execFileAsync = promisify(execFile);
const nginxConfig = "/config/nginx/nginx.conf";
const cookieName = "nginx_admin_session";
const cookieLifetimeSeconds = 24 * 60 * 60;
const totpPeriodSeconds = 30;
const totpToleranceSeconds = 10 * 60;
const totpWindow = totpToleranceSeconds / totpPeriodSeconds;
const nginxTotpSecret = getTotpSecret(
  process.env.NGINX_TOTP_SECRET || "ASDF2345ASDF2345ASDF2345ASDF2345"
);
const app = express();

function getTotpSecret(value) {
  if (!value) {
    console.warn("NGINX_TOTP_SECRET is not configured; Nginx admin API disabled");
    return null;
  }

  const secret = value.trim().toUpperCase();
  try {
    if (decodeBase32(secret).length < 16) {
      throw new Error("secret must decode to at least 16 bytes");
    }
    return secret;
  } catch (error) {
    console.error(`Invalid NGINX_TOTP_SECRET: ${error.message}`);
    return null;
  }
}

function getCookie(request, name) {
  const cookieHeader = request.get("cookie") || "";
  for (const cookie of cookieHeader.split(";")) {
    const separator = cookie.indexOf("=");
    if (separator === -1 || cookie.slice(0, separator).trim() !== name) {
      continue;
    }
    return cookie.slice(separator + 1).trim();
  }
  return "";
}

function createCookie(request, value, maxAge) {
  const forwardedProtocol = (request.get("x-forwarded-proto") || "")
    .split(",")[0]
    .trim()
    .toLowerCase();
  const secure = request.secure || forwardedProtocol === "https";
  const expires = new Date(Date.now() + maxAge * 1000).toUTCString();
  return [
    `${cookieName}=${value}`,
    `Max-Age=${maxAge}`,
    `Expires=${expires}`,
    "Path=/",
    "HttpOnly",
    "SameSite=Strict",
    secure ? "Secure" : ""
  ]
    .filter(Boolean)
    .join("; ");
}

app.get("/", (request, response) => {
  response.json({
    name: "default-express-app",
    status: "ok",
    path: request.url
  });
});

app.get("/api/nginx/status", (request, response) => {
  response.json({
    config: nginxConfig,
    adminReloadEnabled: Boolean(nginxTotpSecret),
    authentication: "totp-cookie",
    cookieLifetimeSeconds,
    totpPeriodSeconds,
    totpToleranceSeconds
  });
});

app.post("/api/nginx/auth", (request, response) => {
  if (!nginxTotpSecret) {
    return response.status(503).json({ error: "TOTP is not configured" });
  }

  const requestToken = request.get("x-nginx-totp") || "";
  if (!verifyTotp(requestToken, nginxTotpSecret, { window: totpWindow })) {
    return response.status(401).json({ error: "Invalid TOTP code" });
  }

  const sessionToken = createSessionToken(nginxTotpSecret, {
    ttlSeconds: cookieLifetimeSeconds
  });
  response.set("Cache-Control", "no-store");
  response.set("Set-Cookie", createCookie(request, sessionToken, cookieLifetimeSeconds));
  return response.json({
    status: "authenticated",
    expiresInSeconds: cookieLifetimeSeconds
  });
});

app.post("/api/nginx/logout", (request, response) => {
  response.set("Cache-Control", "no-store");
  response.set("Set-Cookie", createCookie(request, "", 0));
  return response.json({ status: "logged-out" });
});

app.all("/api/nginx/verify", (request, response) => {
  if (!nginxTotpSecret) {
    return response.status(401).end();
  }

  const sessionToken = getCookie(request, cookieName);
  if (!verifySessionToken(sessionToken, nginxTotpSecret)) {
    return response.status(401).end();
  }

  response.set("Cache-Control", "no-store");
  return response.status(204).end();
});

app.get("/auth/status", (request, response) => {
  response.json({ status: "authenticated" });
});

app.post("/api/nginx/reload", async (request, response, next) => {
  if (!nginxTotpSecret) {
    return response.status(503).json({ error: "TOTP is not configured" });
  }

  const sessionToken = getCookie(request, cookieName);
  if (!verifySessionToken(sessionToken, nginxTotpSecret)) {
    return response.status(401).json({ error: "Invalid or expired session" });
  }

  try {
    const testResult = await execFileAsync("nginx", ["-t", "-c", nginxConfig]);
    await execFileAsync("nginx", ["-c", nginxConfig, "-s", "reload"]);

    response.json({
      status: "reloaded",
      config: nginxConfig,
      output: `${testResult.stdout}${testResult.stderr}`.trim()
    });
  } catch (error) {
    next(error);
  }
});

app.use((error, request, response, next) => {
  console.error("Nginx management error:", error);
  response.status(500).json({ error: "Nginx operation failed" });
});

app.listen(port, "127.0.0.1", () => {
  console.log(`Default Express app listening on 127.0.0.1:${port}`);
});
