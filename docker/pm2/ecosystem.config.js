module.exports = {
  apps: [
    {
      name: "default-node-app",
      script: "/config/app/server.js",
      interpreter: "node",
      env: {
        PORT: "3000"
      }
    },
    {
      name: "mongo-express",
      script: "/opt/npm-global/bin/mongo-express",
      interpreter: "none",
      env: {
        ME_CONFIG_MONGODB_URL: "mongodb://127.0.0.1:27017",
        ME_CONFIG_MONGODB_SERVER: "127.0.0.1",
        ME_CONFIG_MONGODB_PORT: "27017",
        ME_CONFIG_BASICAUTH: "false",
        PORT: "8081",
        HOST: "127.0.0.1"
      }
    }
  ]
};
