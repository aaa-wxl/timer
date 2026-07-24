const http = require("http");
const { URL } = require("url");

let delays = [];
let firstMs = null;
let lastMs = null;

function reset() {
  delays = [];
  firstMs = null;
  lastMs = null;
}

function snapshot() {
  const sorted = [...delays].sort((a, b) => a - b);
  const count = sorted.length;
  const at = (p) => sorted[Math.min(Math.floor(count * p), count - 1)];
  const data = {
    count,
    first_ms: firstMs,
    last_ms: lastMs,
    span_ms: firstMs == null || lastMs == null ? null : lastMs - firstMs,
  };
  if (count) {
    data.min = sorted[0];
    data.avg = sorted.reduce((a, b) => a + b, 0) / count;
    data.max = sorted[count - 1];
    data.p50 = at(0.50);
    data.p90 = at(0.90);
    data.p95 = at(0.95);
    data.p99 = at(0.99);
    data.under_1s = sorted.filter((x) => x < 1000).length;
    data.under_2s = sorted.filter((x) => x < 2000).length;
    data.under_5s = sorted.filter((x) => x < 5000).length;
  }
  return data;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  if (req.method === "GET" && url.pathname === "/reset") {
    reset();
    res.end("ok");
    return;
  }
  if (req.method === "GET" && url.pathname === "/stats") {
    const body = JSON.stringify(snapshot());
    res.setHeader("content-type", "application/json");
    res.end(body);
    return;
  }
  req.resume();
  req.on("end", () => {
    const now = Date.now();
    const target = Number(url.searchParams.get("targetMs") || now);
    delays.push(now - target);
    firstMs = firstMs == null ? now : Math.min(firstMs, now);
    lastMs = now;
    res.end("ok");
  });
});

server.listen(Number(process.argv[2] || 9999), "0.0.0.0", 8192);
