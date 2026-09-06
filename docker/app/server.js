const express = require("express");

const port = Number(process.env.PORT || 3000);
const app = express();

app.get("/", (request, response) => {
  response.json({
    name: "default-express-app",
    status: "ok",
    path: request.url
  });
});

app.listen(port, "127.0.0.1", () => {
  console.log(`Default Express app listening on 127.0.0.1:${port}`);
});
