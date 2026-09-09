module.exports = {
  apps: [
    {
      name: "default-node-app",
      script: "/config/app/server.js",
      interpreter: "node",
      watch: ["/config/app"],
      watch_delay: 1000,
      ignore_watch: ["node_modules", "logs", "*.log", ".nginx-totp-secret"],
      env: {
        PORT: "3000",
        NGINX_TOTP_SECRET: process.env.NGINX_TOTP_SECRET || "",
        NODE_PATH: "/opt/npm-global/lib/node_modules"
      }
    }
  ]
};
