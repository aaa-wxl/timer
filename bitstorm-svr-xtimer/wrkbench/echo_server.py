"""Lightweight echo HTTP server for xtimer callback testing.

No disk I/O, no logging per request. Returns 200 OK and keeps in-memory stats.
Usage: python echo_server.py [port]
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import sys
import threading
import time
from urllib.parse import parse_qs, urlparse


class EchoServer(ThreadingHTTPServer):
    request_queue_size = 4096
    daemon_threads = True


stats_lock = threading.Lock()
stats = {
    "count": 0,
    "delays": [],
    "first_ms": None,
    "last_ms": None,
}


def reset_stats():
    with stats_lock:
        stats["count"] = 0
        stats["delays"] = []
        stats["first_ms"] = None
        stats["last_ms"] = None


def snapshot_stats():
    with stats_lock:
        delays = sorted(stats["delays"])
        count = stats["count"]
        first_ms = stats["first_ms"]
        last_ms = stats["last_ms"]
    data = {
        "count": count,
        "first_ms": first_ms,
        "last_ms": last_ms,
        "span_ms": None if first_ms is None or last_ms is None else last_ms - first_ms,
    }
    if delays:
        def pct(p):
            return delays[min(int(len(delays) * p), len(delays) - 1)]

        data.update({
            "min": delays[0],
            "avg": sum(delays) / len(delays),
            "max": delays[-1],
            "p50": pct(0.50),
            "p90": pct(0.90),
            "p95": pct(0.95),
            "p99": pct(0.99),
            "under_1s": sum(1 for d in delays if d < 1000),
            "under_2s": sum(1 for d in delays if d < 2000),
            "under_5s": sum(1 for d in delays if d < 5000),
        })
    return data


class EchoHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        if length:
            self.rfile.read(length)
        now_ms = int(time.time() * 1000)
        query = parse_qs(urlparse(self.path).query)
        target_ms = int(query.get("targetMs", [now_ms])[0])
        with stats_lock:
            stats["count"] += 1
            stats["delays"].append(now_ms - target_ms)
            stats["first_ms"] = now_ms if stats["first_ms"] is None else min(stats["first_ms"], now_ms)
            stats["last_ms"] = now_ms
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', '2')
        self.end_headers()
        self.wfile.write(b'ok')

    def do_GET(self):
        if self.path.startswith("/reset"):
            reset_stats()
            body = b'ok'
        elif self.path.startswith("/stats"):
            body = json.dumps(snapshot_stats(), separators=(",", ":")).encode()
        else:
            body = b'ok'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # silence


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9999
    srv = EchoServer(('0.0.0.0', port), EchoHandler)
    print(f'echo server on :{port}', flush=True)
    srv.serve_forever()
