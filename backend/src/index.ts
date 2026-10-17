import { createServer } from "node:http";

const port = Number(process.env.PORT ?? 3000);
createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true }));
    return;
  }
  res.writeHead(404).end();
}).listen(port, () => console.log(`LuckyScan50 API: http://localhost:${port}`));
