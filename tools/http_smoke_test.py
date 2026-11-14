#!/usr/bin/env python3
"""Exercise real R HTTP requests against a synthetic local DSpace fixture.

Optional developer test; Python is not an R package runtime dependency.
Run from any directory: python3 tools/http_smoke_test.py
Requires the R development package devtools and dspacer's dependencies.
"""

import hashlib
import json
import os
from pathlib import Path
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from urllib.parse import parse_qs, urlsplit


ITEM = "00000001-0000-0000-0000-000000000000"
BUNDLE = "00000002-0000-0000-0000-000000000000"
FILE = "00000003-0000-0000-0000-000000000000"
COLLECTION = "00000004-0000-0000-0000-000000000000"
TEXT = "## Heading\n\nالعَرَبِيَّة **نص**.\n".encode()
EVENTS = []


def page(objects, relation):
    return {
        "_embedded": {relation: objects},
        "page": {
            "number": 0,
            "size": 100,
            "totalElements": len(objects),
            "totalPages": 1,
        },
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, data=None, status=200, headers=None):
        body = data if isinstance(data, bytes) else json.dumps(data or {}).encode()
        if status == 204:
            body = b""
        self.send_response(status)
        self.send_header(
            "Content-Type",
            "text/markdown" if isinstance(data, bytes) else "application/hal+json",
        )
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlsplit(self.path).path.removeprefix("/server/api")
        EVENTS.append(("GET", path))
        base = f"http://127.0.0.1:{self.server.server_port}/server/api"
        if path == "":
            return self.send(
                {
                    "dspaceVersion": "DSpace synthetic fixture",
                    "_links": {
                        "items": {"href": base + "/core/items"},
                        "collections": {"href": base + "/core/collections"},
                    },
                }
            )
        if path == "/security/csrf":
            return self.send(
                status=204,
                headers={
                    "Set-Cookie": "DSPACE-XSRF-COOKIE=first; Path=/server",
                    "DSPACE-XSRF-TOKEN": "first",
                },
            )
        authenticated = (
            self.headers.get("Authorization") == "Bearer synthetic-token"
            and "DSPACE-XSRF-COOKIE=second" in self.headers.get("Cookie", "")
        )
        if path == "/authn/status":
            return self.send({"authenticated": authenticated})
        if not authenticated:
            return self.send(status=401)
        if path == "/core/collections":
            return self.send(page([{"uuid": COLLECTION, "name": "Documents"}], "collections"))
        if path == "/discover/search/objects":
            hit = {"_links": {"indexableObject": {"href": base + "/core/items/" + ITEM}}}
            return self.send({"_embedded": {"searchResult": page([hit], "objects")}})
        if path == "/core/items/" + ITEM:
            return self.send(
                {
                    "uuid": ITEM,
                    "name": "Synthetic document",
                    "inArchive": True,
                    "withdrawn": False,
                    "metadata": {
                        "custom.field": [
                            {"value": "first", "place": 0},
                            {"value": "second", "language": "en", "place": 1},
                        ]
                    },
                }
            )
        if path == "/core/items/" + ITEM + "/bundles":
            return self.send(
                page(
                    [
                        {
                            "uuid": BUNDLE,
                            "name": "ORIGINAL",
                            "_links": {
                                "bitstreams": {"href": base + "/core/bundles/" + BUNDLE + "/bitstreams"},
                                "primaryBitstream": {"href": base + "/primary"},
                            },
                        }
                    ],
                    "bundles",
                )
            )
        if path == "/primary":
            return self.send({"uuid": FILE})
        if path == "/core/bundles/" + BUNDLE + "/bitstreams":
            return self.send(
                page(
                    [
                        {
                            "uuid": FILE,
                            "name": "synthetic.md",
                            "sizeBytes": len(TEXT),
                            "checkSum": {
                                "checkSumAlgorithm": "MD5",
                                "value": hashlib.md5(TEXT).hexdigest(),
                            },
                            "_links": {
                                "format": {"href": base + "/format"},
                                "content": {"href": base + "/content"},
                            },
                        }
                    ],
                    "bitstreams",
                )
            )
        if path == "/format":
            return self.send({"mimetype": "text/markdown"})
        if path == "/content":
            return self.send(TEXT)
        self.send(status=404)

    def do_POST(self):
        path = urlsplit(self.path).path.removeprefix("/server/api")
        EVENTS.append(("POST", path))
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        if path == "/authn/login":
            form = parse_qs(body)
            valid = (
                form == {"user": ["synthetic-reader"], "password": ["synthetic-password"]}
                and self.headers.get("X-XSRF-TOKEN") == "first"
                and "DSPACE-XSRF-COOKIE=first" in self.headers.get("Cookie", "")
            )
            if not valid:
                return self.send(status=403)
            return self.send(
                headers={
                    "Authorization": "Bearer synthetic-token",
                    "DSPACE-XSRF-TOKEN": "second",
                    "Set-Cookie": "DSPACE-XSRF-COOKIE=second; Path=/server",
                }
            )
        if path == "/authn/logout" and self.headers.get("X-XSRF-TOKEN") == "second":
            return self.send(status=204)
        self.send(status=403)


def main():
    root = Path(__file__).resolve().parents[1]
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    worker = Thread(target=server.serve_forever, daemon=True)
    worker.start()
    env = os.environ.copy()
    env["DSPACER_FIXTURE_URL"] = f"http://127.0.0.1:{server.server_port}/server/api"
    r = r'''
library(devtools)
load_all(".", quiet = TRUE)
options(warn = 2)
con <- ds_connect(Sys.getenv("DSPACER_FIXTURE_URL"), allow_insecure = TRUE, quiet = TRUE)
ds_login(con, "synthetic-reader", "synthetic-password")
collections <- ds_get_collections(con)
items <- ds_get_items(con, scope = collections$collection_uuid[[1]])
metadata <- ds_get_metadata(items)
files <- ds_get_files(con, items)
texts <- ds_get_texts(con, files)
stopifnot(nrow(items) == 1L, identical(metadata$value, c("first", "second")))
stopifnot(nrow(texts) == 1L, grepl("العَرَبِيَّة نص", texts$text, fixed = TRUE))
directory <- tempfile()
download <- ds_download(con, files, directory)
stopifnot(file.exists(download$local_path))
unlink(directory, recursive = TRUE)
ds_disconnect(con)
stopifnot(con$closed, !file.exists(con$cookie_path))
cat("Real HTTP smoke test passed: cookies, rotating CSRF, login, search, metadata, files, text, download, logout.\n")
'''
    try:
        subprocess.run(["Rscript", "-e", r], cwd=root, env=env, check=True, timeout=90)
        assert ("POST", "/authn/login") in EVENTS
        assert ("POST", "/authn/logout") in EVENTS
        assert all(method == "GET" or path in {"/authn/login", "/authn/logout"} for method, path in EVENTS)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
