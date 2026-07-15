#!/usr/bin/env python3
# RBGJL Step 06: Cloud-dispatched GAR package delete by convergence. Shared by
#   banish (Lode) and abjure (hallmark).
# Builder: gcr.io/cloud-builders/gcloud, digest-pinned (ZRBFC_DELETE_BUILDER —
#   the reliquary-less delete build runs as Director, so its bootstrap never
#   floats; python3 + urllib + json are the frozen needs).
# Runs as Director (the build's serviceAccount — the only identity holding
#   repoAdmin/delete; Mason stays writer-only). There is no host-issued DELETE, so
#   the build's success IS the delete outcome — closing the trust-200 LRO gap.
# Substitutions (automapSubstitutions provides as env vars):
#   ${_RBGL_GAR_API_BASE} ${_RBGL_GAR_PACKAGE_BASE} ${_RBGL_DELETE_PACKAGES}
#
# Why a convergence loop, not a single packages.delete. GAR refuses to delete a
# child manifest while its parent index still exists — FAILED_PRECONDITION,
# "manifest is referenced by parent manifests" — and a whole-package delete of a
# multi-arch web fails this way and removes nothing. This is GAR's documented
# behavior (cleanup policies "don't delete images referenced by a parent manifest;
# if the parent manifest is deleted, then any related images are deleted" on the
# next run) and the reason Google's own gcr-cleaner ships a --skip-errors flag. So
# rather than walk the parent/child topology, each round fires a delete at EVERY
# remaining version (force=true to drop tags) and at the package shell — parents
# succeed and un-reference their children, which the next round (or the same
# round's async settle) then deletes — and polls the package GET until it 404s.
# The eventual-consistency dance Google forces, and the same shape as the host's
# rbuh_poll_until_gone. Absence is the only truth: per-call delete errors are
# logged for the build trail, never branched on; the deadline is the sole failsafe.

import json
import os
import socket
import sys
import time
import urllib.error
import urllib.request


def die(msg):
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def require_env(name):
    val = os.environ.get(name, "")
    if not val:
        die(f"{name} missing")
    return val


METADATA_TOKEN_URL = (
    "http://metadata.google.internal/computeMetadata/v1/"
    "instance/service-accounts/default/token"
)


def metadata_token():
    """Fetch OAuth2 access token from GCE metadata server. Dies loud on any
    failure — without a token nothing downstream can run."""
    req = urllib.request.Request(METADATA_TOKEN_URL, headers={"Metadata-Flavor": "Google"})
    try:
        resp = urllib.request.urlopen(req, timeout=URLOPEN_TIMEOUT_SEC)
        return json.loads(resp.read())["access_token"]
    except (urllib.error.URLError, socket.timeout) as e:
        die(f"Metadata token fetch failed: {e}")


def gar_fetch(url, token, accept, method="GET"):
    headers = {"Authorization": f"Bearer {token}", "Accept": accept}
    req = urllib.request.Request(url, headers=headers, method=method)
    return urllib.request.urlopen(req, timeout=URLOPEN_TIMEOUT_SEC)


def gar_json(url, token, accept):
    resp = gar_fetch(url, token, accept)
    return json.loads(resp.read())


JSON_ACCEPT = "application/json"
ROUND_PAUSE_SEC = 8         # settle between rounds, letting freed children become deletable
DELETE_DEADLINE_SEC = 180   # per-package convergence ceiling; host budget covers the loop
URLOPEN_TIMEOUT_SEC = 30    # bound every HTTP call — urllib's default (None) hangs a stuck
                            # socket silently until the Cloud Build timeout kills the build


def package_absent(pkg_url, token):
    """The truth: True iff a GET on the package returns 404. An unexpected status (not
    200, not 404) dies loud rather than guess."""
    try:
        gar_fetch(pkg_url, token, JSON_ACCEPT, method="GET")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return True
        die(f"Absence-verify returned unexpected HTTP {e.code}")
    except (urllib.error.URLError, socket.timeout) as e:
        die(f"Absence-verify failed: {e}")
    return False


def list_version_ids(api_base, pkg_url, token):
    """Every version id (the segment after /versions/) for a package, paginated so a
    large web is never silently capped. Empty if the package is gone."""
    ids = []
    page_token = ""
    while True:
        url = f"{pkg_url}/versions?pageSize=1000"
        if page_token:
            url += f"&pageToken={page_token}"
        try:
            data = gar_json(url, token, JSON_ACCEPT)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return ids
            die(f"versions.list failed: HTTP {e.code}")
        except (urllib.error.URLError, socket.timeout) as e:
            die(f"versions.list failed: {e}")
        for v in data.get("versions", []):
            name = v.get("name", "")
            if "/versions/" in name:
                ids.append(name.split("/versions/", 1)[1])
        page_token = data.get("nextPageToken", "")
        if not page_token:
            return ids


def fire_delete(url, token, label):
    """Issue a DELETE and return without blocking on the LRO — the absence poll, not any
    single call, is the arbiter of truth. A 404 is already-gone; any other non-success is
    logged for the build trail (it reconciles next round, or the deadline makes it loud).
    A FAILED_PRECONDITION 'referenced by parent manifests' is the expected per-round skip
    for a child whose parent index has not gone yet. A transport-level failure (connection
    reset, DNS blip, timeout) is morally the same event as a 5xx — logged in the same
    reconciling form, never branched on. The truth-readers above deliberately do NOT share
    this tolerance: a flaky reader misreporting absence is the one failure never absorbed."""
    try:
        gar_fetch(url, token, JSON_ACCEPT, method="DELETE")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print(f"    {label}: HTTP {e.code} (reconciling via absence poll)")
    except (urllib.error.URLError, socket.timeout) as e:
        print(f"    {label}: {e} (reconciling via absence poll)")


def converge_delete(api_base, package_base, pkg, token):
    encoded = pkg.replace("/", "%2F")
    pkg_url = f"{api_base}/{package_base}/packages/{encoded}"
    print(f"--- Deleting package: {pkg} ---")

    start = time.monotonic()
    rounds = 0
    while True:
        if package_absent(pkg_url, token):
            print(f"  Verified absent after {rounds} round(s): {pkg}")
            return
        if time.monotonic() - start >= DELETE_DEADLINE_SEC:
            remaining = len(list_version_ids(api_base, pkg_url, token))
            die(f"{pkg} still present after {DELETE_DEADLINE_SEC}s "
                f"({remaining} version(s) remain) — delete did not converge")
        rounds += 1
        version_ids = list_version_ids(api_base, pkg_url, token)
        print(f"  Round {rounds}: firing delete at {len(version_ids)} version(s) + package shell")
        for ver_id in version_ids:
            fire_delete(f"{pkg_url}/versions/{ver_id}?force=true", token, f"version {ver_id[:19]}")
        fire_delete(pkg_url, token, f"package {pkg}")
        time.sleep(ROUND_PAUSE_SEC)


def main():
    api_base     = require_env("_RBGL_GAR_API_BASE")
    package_base = require_env("_RBGL_GAR_PACKAGE_BASE")
    packages_raw = require_env("_RBGL_DELETE_PACKAGES")

    packages = packages_raw.split()
    if not packages:
        die("_RBGL_DELETE_PACKAGES is empty after split")

    print(f"=== Cloud-dispatched delete of {len(packages)} package(s) ===")

    token = metadata_token()

    for pkg in packages:
        converge_delete(api_base, package_base, pkg, token)

    print(f"=== All {len(packages)} package(s) deleted (verified absent) ===")


if __name__ == "__main__":
    main()
