import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "publish_release.py"


class ReleaseServer(ThreadingHTTPServer):
    def __init__(self):
        super().__init__(("127.0.0.1", 0), ReleaseHandler)
        self.release = None
        self.uploaded = None
        self.fail_upload = False
        self.fail_publish = False
        self.calls = []

    @property
    def url(self):
        host, port = self.server_address
        return f"http://{host}:{port}"


class ReleaseHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def respond(self, status, body):
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", "0")))

    def do_POST(self):
        self.server.calls.append(("POST", self.path))
        body = self.read_body()
        if self.path == "/repos/example/ipad/releases":
            if self.server.release:
                self.respond(422, {"message": "release already exists"})
                return
            self.server.release = {
                **json.loads(body),
                "id": 42,
                "upload_url": self.server.url + "/upload/42{?name,label}",
                "assets": [],
            }
            self.respond(201, self.server.release)
        elif urlsplit(self.path).path == "/upload/42":
            if self.server.fail_upload:
                self.respond(500, {"message": "upload failed"})
                return
            self.server.uploaded = {
                "name": parse_qs(urlsplit(self.path).query)["name"][0],
                "body": body,
                "content_type": self.headers.get("Content-Type"),
            }
            self.server.release["assets"].append({
                "name": self.server.uploaded["name"],
                "size": len(body),
                "digest": "sha256:" + hashlib.sha256(body).hexdigest(),
            })
            self.respond(201, {"name": self.server.uploaded["name"]})
        else:
            self.respond(404, {"message": "unknown endpoint"})

    def do_PATCH(self):
        self.server.calls.append(("PATCH", self.path))
        body = json.loads(self.read_body())
        if self.path == "/repos/example/ipad/releases/42" and self.server.release:
            if self.server.fail_publish:
                self.respond(500, {"message": "publish failed"})
                return
            self.server.release.update(body)
            self.respond(200, self.server.release)
        else:
            self.respond(404, {"message": "unknown endpoint"})

    def do_GET(self):
        self.server.calls.append(("GET", self.path))
        path = urlsplit(self.path).path
        if path == "/repos/example/ipad/releases":
            self.respond(200, [self.server.release] if self.server.release else [])
        elif path == "/repos/example/ipad/releases/tags/v1.2.3" and self.server.release and not self.server.release['draft']:
            self.respond(200, self.server.release)
        else:
            self.respond(404, {"message": "unknown endpoint"})


class PublishReleaseTest(unittest.TestCase):
    def setUp(self):
        self.server = ReleaseServer()
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.tmp = tempfile.TemporaryDirectory(prefix="release-test-")
        self.ipa = Path(self.tmp.name) / "iPadBatteryExercise-v1.2.3.ipa"
        self.ipa.write_bytes(b"example ipa content")

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.tmp.cleanup()

    def run_publisher(self):
        env = dict(os.environ, GITHUB_TOKEN="test-token", PYTHONDONTWRITEBYTECODE="1")
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--repo", "example/ipad", "--tag", "v1.2.3",
             "--ipa", str(self.ipa), "--api-url", self.server.url],
            env=env, capture_output=True, text=True, encoding="utf-8", check=False,
        )

    def test_uploads_ipa_before_publishing_draft(self):
        result = self.run_publisher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.server.release["tag_name"], "v1.2.3")
        self.assertFalse(self.server.release["draft"])
        self.assertEqual(self.server.uploaded["name"], self.ipa.name)
        self.assertEqual(self.server.uploaded["body"], self.ipa.read_bytes())
        self.assertEqual(self.server.uploaded["content_type"], "application/octet-stream")
        self.assertEqual([method for method, _ in self.server.calls], ["GET", "POST", "POST", "PATCH"])

    def test_upload_failure_leaves_release_unpublished(self):
        self.server.fail_upload = True
        result = self.run_publisher()
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNotNone(self.server.release)
        self.assertTrue(self.server.release["draft"])
        self.assertNotIn("PATCH", [method for method, _ in self.server.calls])

    def test_retry_reuses_matching_asset_in_existing_draft(self):
        self.server.fail_publish = True
        first = self.run_publisher()
        self.assertNotEqual(first.returncode, 0)
        self.assertTrue(self.server.release["draft"])
        self.server.fail_publish = False
        second = self.run_publisher()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertFalse(self.server.release["draft"])
        uploads = [path for method, path in self.server.calls if method == "POST" and path.startswith("/upload/")]
        self.assertEqual(len(uploads), 1)


if __name__ == "__main__":
    unittest.main()
