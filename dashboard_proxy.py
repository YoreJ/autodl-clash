#!/usr/bin/env python3
import argparse
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote


HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


class DashboardProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    target_host = "127.0.0.1"
    target_port = 6006

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        if self.path in ("", "/"):
            host = self.headers.get("Host", "127.0.0.1").split(":", 1)[0]
            location = f"/ui/?hostname={quote(host)}&port={self.target_port}"
            self.send_response(302)
            self.send_header("Location", location)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        self.proxy_request()

    def do_HEAD(self):
        self.proxy_request()

    def do_OPTIONS(self):
        self.proxy_request()

    def do_POST(self):
        self.proxy_request()

    def do_PUT(self):
        self.proxy_request()

    def do_PATCH(self):
        self.proxy_request()

    def do_DELETE(self):
        self.proxy_request()

    def proxy_request(self):
        body = None
        content_length = self.headers.get("Content-Length")
        if content_length:
            body = self.rfile.read(int(content_length))

        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP_HEADERS
        }
        headers["Host"] = f"{self.target_host}:{self.target_port}"

        conn = http.client.HTTPConnection(self.target_host, self.target_port, timeout=30)
        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            response = conn.getresponse()
            response_body = response.read()

            self.send_response(response.status, response.reason)
            for key, value in response.getheaders():
                if key.lower() not in HOP_BY_HOP_HEADERS and key.lower() != "content-length":
                    self.send_header(key, value)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()

            if self.command != "HEAD":
                self.wfile.write(response_body)
        except Exception as exc:
            message = f"dashboard proxy error: {exc}\n".encode()
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(message)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(message)
        finally:
            conn.close()


def main():
    parser = argparse.ArgumentParser(description="Dashboard entry proxy for mihomo external-ui")
    parser.add_argument("--listen-host", default="0.0.0.0")
    parser.add_argument("--listen-port", type=int, default=6008)
    parser.add_argument("--target-host", default="127.0.0.1")
    parser.add_argument("--target-port", type=int, default=6006)
    args = parser.parse_args()

    DashboardProxyHandler.target_host = args.target_host
    DashboardProxyHandler.target_port = args.target_port

    server = ThreadingHTTPServer((args.listen_host, args.listen_port), DashboardProxyHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
