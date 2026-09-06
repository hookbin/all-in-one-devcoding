const http = require("http");

const port = Number(process.env.PORT || 3000);

const server = http.createServer((request, response) => {
  response.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify({
    name: "default-node-app",
    status: "ok",
    path: request.url
  }) + "\n");
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Default Node.js app listening on 127.0.0.1:${port}`);
});
