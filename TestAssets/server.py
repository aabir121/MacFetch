from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

root = Path(__file__).parent

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/macfetch-browser-trigger.txt":
            self.send_error(404)
            return
        data = (root / "macfetch-browser-trigger.txt").read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Disposition", 'attachment; filename="macfetch-browser-trigger.txt"')
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_args):
        pass

HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
