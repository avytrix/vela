#!/usr/bin/env python3
"""Serves out/ under the base path the way GitHub Pages serves avytrix.dev, for a local check.

GitHub Pages answers /docs/install with docs/install.html, even though the export also has a
docs/install/ folder (the client-side navigation data), and a missing page with 404.html. Plain
`python3 -m http.server` redirects to the folder instead, so it can open only the .html URLs.
This server does what GitHub Pages does.

Usage (from site/, after a build): python3 scripts/serve.py [port]
Then open http://localhost:8000/opensource/gitlab-vela (NEXT_PUBLIC_BASE_PATH sets the prefix).
"""
import http.server
import os
import shutil
import sys
import tempfile
from pathlib import Path

BASE = os.environ.get("NEXT_PUBLIC_BASE_PATH", "/opensource/gitlab-vela").rstrip("/")
OUT = Path(__file__).resolve().parent.parent / "out"


class Handler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path) and os.path.isfile(path.rstrip("/") + ".html"):
            self.path = self.path.split("?")[0].split("#")[0] + ".html"
        elif not os.path.exists(path):
            self.path = f"{BASE}/404.html"
        return super().send_head()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    root = Path(tempfile.mkdtemp())
    target = root / BASE.lstrip("/")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(OUT, target)
    os.chdir(root)
    print(f"http://localhost:{port}{BASE}")
    http.server.ThreadingHTTPServer(("", port), Handler).serve_forever()
