module.exports = {
  apps: [
    {
      name: "default-node-app",
      script: "/config/app/server.js",
      interpreter: "node",
      watch: ["/config/app"],
      watch_delay: 1000,
      ignore_watch: ["node_modules", "logs", "*.log"],
      env: {
        PORT: "3000",
        NGINX_ADMIN_TOKEN: process.env.NGINX_ADMIN_TOKEN || "",
        NODE_PATH: "/opt/npm-global/lib/node_modules"
      }
    }
  ]
};
