"""Loopback-only fixture server for the integration suite. Development use only."""
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import ssl
import socket
import subprocess
import tempfile
import threading


class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        if self.path == "/disconnect":
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
            return
        self.send_response({"/ok": 204, "/redirect": 302}.get(self.path, 405))
        if self.path == "/redirect":
            self.send_header("Location", "/ok")
        self.end_headers()

    def do_GET(self):
        self.send_error(500, "GET must never be used")

    def log_message(self, *_):
        pass


with tempfile.TemporaryDirectory(prefix="workbench-test-") as directory:
    key, cert = (str(Path(directory) / name) for name in ("key.pem", "cert.pem"))
    subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", key, "-out", cert, "-days", "1", "-subj", "/CN=localhost"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    plain = HTTPServer(("127.0.0.1", 0), Handler)
    tls = HTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    tls.socket = context.wrap_socket(tls.socket, server_side=True)
    threading.Thread(target=plain.serve_forever, daemon=True).start()
    threading.Thread(target=tls.serve_forever, daemon=True).start()
    print(f"http://127.0.0.1:{plain.server_port}/ok https://127.0.0.1:{tls.server_port}/ok", flush=True)
    threading.Event().wait()
