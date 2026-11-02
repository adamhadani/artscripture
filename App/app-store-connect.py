#!/usr/bin/env python3
"""App Store Connect, from the command line, for the steps after `make upload`.

    App/app-store-connect.py status
    App/app-store-connect.py wait-build <build> [--timeout <seconds>]
    App/app-store-connect.py prepare-version <version> <build> --whats-new <file>

`status` prints the App Store versions and the most recent builds. `wait-build`
polls until a build has finished processing. `prepare-version` creates the App
Store version record if it does not exist yet, attaches the build to it, and sets
"What's New in This Version" on every localisation. Every step is idempotent: run it
twice and the second run changes nothing it does not need to. It never submits for
review and never releases anything — those stay a person's decision.

**Why `wait-build` exists.** `make upload` has sat idle for hours and then exited 0,
and `altool` prints UPLOAD SUCCEEDED before Apple has processed anything. The only
proof a build arrived is App Store Connect listing it as VALID, so that is what this
asks for — with a deadline, because a stalled upload otherwise looks exactly like a
slow one.

Credentials are the same three the Makefile's App Store targets use, read from the
environment and never printed: ARTSCRIBE_ASC_ISSUER_ID, ARTSCRIBE_ASC_KEY_ID and
ARTSCRIBE_ASC_KEY_PATH (a Team key with the Admin role; see README).

Standard library only. The ES256 token is signed with `openssl`, because PyJWT is not
installed here and nothing else needs it; openssl emits a DER signature, and JWS wants
the raw 64-byte r||s, hence `_der_to_raw`.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
# Permanent once published — see project.yml. Overridable for a fork.
BUNDLE_ID = os.environ.get("ARTSCRIBE_BUNDLE_ID", "com.artscribe.Artscribe")
PLATFORM = "IOS"  # The App Store build is the iPhone/iPad app; the Mac ships directly.


class AscError(Exception):
    pass


# MARK: - Transport


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_to_raw(der: bytes) -> bytes:
    """ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER }  ->  r || s, 32 bytes each."""
    if der[0] != 0x30:
        raise AscError("openssl did not return a DER ECDSA signature")
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    raw = b""
    for _ in range(2):
        if der[i] != 0x02:
            raise AscError("malformed DER integer in signature")
        n = der[i + 1]
        raw += der[i + 2 : i + 2 + n].lstrip(b"\x00").rjust(32, b"\x00")
        i += 2 + n
    return raw


def _token() -> str:
    try:
        issuer = os.environ["ARTSCRIBE_ASC_ISSUER_ID"]
        key_id = os.environ["ARTSCRIBE_ASC_KEY_ID"]
        key_path = os.environ["ARTSCRIBE_ASC_KEY_PATH"]
    except KeyError as missing:
        raise AscError(f"{missing.args[0]} is not set — see README, The App Store") from None
    now = int(time.time())
    header = _b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    claims = {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    payload = _b64url(json.dumps(claims).encode())
    signing_input = f"{header}.{payload}".encode()
    signed = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input,
        capture_output=True,
    )
    if signed.returncode != 0:
        raise AscError("openssl could not sign with the key at ARTSCRIBE_ASC_KEY_PATH")
    return f"{header}.{payload}.{_b64url(_der_to_raw(signed.stdout))}"


def _call(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method)
    request.add_header("Authorization", f"Bearer {_token()}")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        # The API's own explanation, which is the useful part. It names fields and
        # states, never the credentials.
        try:
            details = [
                f"{e.get('title', '')}: {e.get('detail', '')}".strip(": ")
                for e in json.loads(error.read()).get("errors", [])
            ]
        except (ValueError, AttributeError):
            details = []
        raise AscError(f"{method} {path.split('?')[0]} -> HTTP {error.code}. " + " / ".join(details))


def get(path: str) -> dict:
    return _call("GET", path)


# MARK: - Lookups


def app_id() -> str:
    apps = get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}&fields[apps]=name")["data"]
    if not apps:
        raise AscError(f"no app with bundle ID {BUNDLE_ID} is visible to this key")
    return apps[0]["id"]


def versions(app: str) -> list[dict]:
    fields = "versionString,appStoreState,releaseType,copyright,platform,createdDate"
    path = (
        f"/v1/apps/{app}/appStoreVersions?filter[platform]={PLATFORM}"
        f"&fields[appStoreVersions]={fields}&limit=50"
    )
    return get(path)["data"]


def find_build(app: str, build: str) -> dict | None:
    path = (
        f"/v1/builds?filter[app]={app}&filter[version]={build}"
        "&include=preReleaseVersion&fields[builds]=version,processingState,uploadedDate,"
        "preReleaseVersion&fields[preReleaseVersions]=version"
    )
    response = get(path)
    if not response["data"]:
        return None
    found = response["data"][0]
    marketing = {
        inc["id"]: inc["attributes"]["version"]
        for inc in response.get("included", [])
        if inc["type"] == "preReleaseVersions"
    }
    rel = found["relationships"]["preReleaseVersion"]["data"]
    found["marketingVersion"] = marketing.get(rel["id"]) if rel else None
    return found


# MARK: - Commands


def cmd_status(_: argparse.Namespace) -> int:
    app = app_id()
    print(f"app {app} ({BUNDLE_ID})")
    for v in sorted(versions(app), key=lambda v: v["attributes"]["createdDate"], reverse=True)[:5]:
        a = v["attributes"]
        print(f"  version {a['versionString']:<8} {a['appStoreState']:<24} release={a['releaseType']}")
    path = f"/v1/builds?filter[app]={app}&sort=-uploadedDate&limit=5&fields[builds]=version,processingState,uploadedDate"
    for b in get(path)["data"]:
        a = b["attributes"]
        print(f"  build   {a['version']:<8} {a['processingState']:<24} uploaded {a['uploadedDate'][:16]}")
    return 0


def cmd_wait_build(args: argparse.Namespace) -> int:
    app = app_id()
    deadline = time.time() + args.timeout
    last = None
    while True:
        found = find_build(app, args.build)
        state = found["attributes"]["processingState"] if found else "NOT LISTED YET"
        if state != last:
            print(f"build {args.build}: {state}", flush=True)
            last = state
        if state == "VALID":
            return 0
        if state in ("FAILED", "INVALID"):
            return 1
        if time.time() > deadline:
            print(f"build {args.build} is still '{state}' after {args.timeout} s — treat the upload as stalled")
            return 2
        time.sleep(30)


def cmd_prepare_version(args: argparse.Namespace) -> int:
    with open(args.whats_new, encoding="utf-8") as handle:
        whats_new = handle.read().strip()
    if not whats_new:
        raise AscError(f"{args.whats_new} is empty")
    if len(whats_new) > 4000:
        raise AscError(f"What's New is {len(whats_new)} characters; the App Store allows 4000")

    app = app_id()

    # The build first: attaching the wrong one is the mistake that costs a review cycle.
    build = find_build(app, args.build)
    if build is None:
        raise AscError(f"build {args.build} is not in App Store Connect — run wait-build first")
    state = build["attributes"]["processingState"]
    if state != "VALID":
        raise AscError(f"build {args.build} is {state}, not VALID")
    if build["marketingVersion"] != args.version:
        raise AscError(
            f"build {args.build} carries version {build['marketingVersion']}, not {args.version} — "
            "App Store Connect will not attach it to this version record"
        )

    existing = {v["attributes"]["versionString"]: v for v in versions(app)}
    version = existing.get(args.version)
    if version is None:
        # Mirror the last version's release type and copyright, so a new record
        # behaves like the one before it unless someone decides otherwise.
        previous = sorted(existing.values(), key=lambda v: v["attributes"]["createdDate"])
        attributes = {"platform": PLATFORM, "versionString": args.version}
        if previous:
            for key in ("releaseType", "copyright"):
                if previous[-1]["attributes"].get(key):
                    attributes[key] = previous[-1]["attributes"][key]
        body = {
            "data": {
                "type": "appStoreVersions",
                "attributes": attributes,
                "relationships": {"app": {"data": {"type": "apps", "id": app}}},
            }
        }
        version = _call("POST", "/v1/appStoreVersions", body)["data"]
        print(f"created version {args.version} (release={attributes.get('releaseType', 'default')})")
    else:
        print(f"version {args.version} exists ({version['attributes']['appStoreState']})")
    version_id = version["id"]

    attached = get(f"/v1/appStoreVersions/{version_id}/build?fields[builds]=version").get("data")
    if attached and attached["attributes"]["version"] == args.build:
        print(f"build {args.build} already attached")
    else:
        body = {"data": {"type": "builds", "id": build["id"]}}
        _call("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build", body)
        print(f"attached build {args.build}")

    locs_fields = "?fields[appStoreVersionLocalizations]=locale,whatsNew,promotionalText"
    locs_path = f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations{locs_fields}"
    localizations = get(locs_path)["data"]
    if not localizations:
        raise AscError("the version has no localisations to put What's New on")

    # A new version record copies the description, keywords, URLs and screenshots
    # from the one before it — but **not the promotional text**, so a release that
    # did nothing about it would quietly drop it from the store page the day it
    # went live. Carry it forward where the new record has none; never overwrite.
    previous_promo: dict[str, str] = {}
    older = [
        v
        for v in versions(app)
        if v["id"] != version_id and v["attributes"]["createdDate"] < version["attributes"].get("createdDate", "~")
    ]
    if older:
        last = max(older, key=lambda v: v["attributes"]["createdDate"])
        path = f"/v1/appStoreVersions/{last['id']}/appStoreVersionLocalizations{locs_fields}"
        for loc in get(path)["data"]:
            if loc["attributes"].get("promotionalText"):
                previous_promo[loc["attributes"]["locale"]] = loc["attributes"]["promotionalText"]

    for loc in localizations:
        locale = loc["attributes"]["locale"]
        changes = {}
        if (loc["attributes"].get("whatsNew") or "").strip() != whats_new:
            changes["whatsNew"] = whats_new
        if not loc["attributes"].get("promotionalText") and locale in previous_promo:
            changes["promotionalText"] = previous_promo[locale]
        if not changes:
            print(f"{locale}: What's New and promotional text already in place")
            continue
        body = {
            "data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": changes}
        }
        _call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", body)
        print(f"{locale}: set {' and '.join(changes)}")

    # Read it all back rather than trusting the writes.
    final = get(f"/v1/appStoreVersions/{version_id}?fields[appStoreVersions]=versionString,appStoreState")
    attached = get(f"/v1/appStoreVersions/{version_id}/build?fields[builds]=version")["data"]
    texts = [l["attributes"].get("whatsNew") or "" for l in get(locs_path)["data"]]
    ok = attached and attached["attributes"]["version"] == args.build and all(t.strip() == whats_new for t in texts)
    a = final["data"]["attributes"]
    print(
        f"read back: version {a['versionString']} {a['appStoreState']}, "
        f"build {attached['attributes']['version'] if attached else 'none'}, "
        f"What's New set on {sum(t.strip() == whats_new for t in texts)}/{len(texts)} localisation(s)"
    )
    print("Not submitted. Review and submit in App Store Connect when ready.")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status").set_defaults(run=cmd_status)
    wait = sub.add_parser("wait-build")
    wait.add_argument("build")
    wait.add_argument("--timeout", type=int, default=900)
    wait.set_defaults(run=cmd_wait_build)
    prepare = sub.add_parser("prepare-version")
    prepare.add_argument("version")
    prepare.add_argument("build")
    prepare.add_argument("--whats-new", required=True, metavar="FILE")
    prepare.set_defaults(run=cmd_prepare_version)
    args = parser.parse_args()
    try:
        return args.run(args)
    except AscError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
