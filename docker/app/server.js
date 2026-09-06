const express = require("express");
const crypto = require("crypto");
const { execFile } = require("child_process");
const { promisify } = require("util");

const port = Number(process.env.PORT || 3000);
const execFileAsync = promisify(execFile);
const nginxConfig = "/config/nginx/nginx.conf";
const nginxAdminToken = process.env.NGINX_ADMIN_TOKEN;
const app = express();

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
    adminReloadEnabled: Boolean(nginxAdminToken)
  });
});

app.post("/api/nginx/reload", async (request, response, next) => {
  const requestToken = request.get("x-nginx-admin-token") || "";

  if (
    !nginxAdminToken ||
    requestToken.length !== nginxAdminToken.length ||
    !crypto.timingSafeEqual(
      Buffer.from(requestToken),
      Buffer.from(nginxAdminToken)
    )
  ) {
    return response.status(401).json({ error: "Invalid Nginx admin token" });
  }

  try {
    const testResult = await execFileAsync("nginx", ["-t", "-c", nginxConfig]);
    await execFileAsync("nginx", ["-s", "reload"]);

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
