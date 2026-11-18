#!/usr/bin/env python3
"""Upload the built IPA to a draft GitHub release, then publish it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def request(method, url, token, data=None, content_type="application/json"):
    if isinstance(data, dict):
        data = json.dumps(data).encode("utf-8")
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "User-Agent": "iPadBatteryExercise-release",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if data is not None:
        headers["Content-Type"] = content_type
    req = Request(url, data=data, headers=headers, method=method)
    with urlopen(req, timeout=120) as response:
        return json.load(response)


def find_release(base, tag, token):
    # The tag endpoint only returns published releases. Listing also includes drafts
    # for an authenticated token with repository write access.
    found = None
    page = 1
    while True:
        releases = request("GET", f"{base}?per_page=100&page={page}", token)
        for candidate in releases:
            if candidate.get("tag_name") == tag:
                if found is not None:
                    raise ValueError(f"Multiple releases use {tag}; inspect them before retrying.")
                found = candidate
        if len(releases) < 100:
            return found
        page += 1


def publish(repo, tag, ipa, api_url, token):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Repository must be in owner/name form.")
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Version tag must have the form v1.2.3.")
    if not token:
        raise ValueError("GITHUB_TOKEN is required.")
    if not ipa.is_file():
        raise ValueError(f"IPA file does not exist: {ipa}")

    base = f"{api_url.rstrip('/')}/repos/{repo}/releases"
    release = find_release(base, tag, token)
    if release is None:
        try:
            release = request("POST", base, token, {
                "tag_name": tag,
                "name": tag,
                "draft": True,
                "prerelease": False,
            })
        except HTTPError as error:
            if error.code != 422:
                raise
            release = find_release(base, tag, token)
            if release is None:
                raise
    if not release.get("draft"):
        raise ValueError(f"Release {tag} is already published; refusing to change it.")

    existing = [asset for asset in release.get("assets", []) if asset.get("name") == ipa.name]
    if existing:
        digest = "sha256:" + hashlib.sha256(ipa.read_bytes()).hexdigest()
        if len(existing) != 1 or existing[0].get("digest") != digest or existing[0].get("size") != ipa.stat().st_size:
            raise ValueError(f"Existing draft asset {ipa.name} differs; inspect it before retrying.")
        print(f"Reusing verified draft asset {ipa.name}")
    else:
        upload_url = release["upload_url"].split("{", 1)[0]
        upload_url += "?" + urlencode({"name": ipa.name})
        request("POST", upload_url, token, ipa.read_bytes(), "application/octet-stream")
        print(f"Uploaded {ipa.name}")

    request("PATCH", f"{base}/{release['id']}", token, {"draft": False})
    print(f"Published release {tag}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="GitHub owner/repository")
    parser.add_argument("--tag", required=True, help="Version tag, e.g. v1.0.0")
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--api-url", default=os.environ.get("GITHUB_API_URL", "https://api.github.com"))
    args = parser.parse_args()
    try:
        publish(args.repo, args.tag, args.ipa, args.api_url, os.environ.get("GITHUB_TOKEN", ""))
    except (HTTPError, URLError, OSError, ValueError, KeyError) as error:
        print(f"Release publication failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
