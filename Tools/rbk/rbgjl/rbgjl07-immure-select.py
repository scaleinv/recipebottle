#!/usr/bin/env python3
# RBGJL Step 07: Select podvm disk leaves from a quay family index (the immure select)
# Builder: gcr.io/cloud-builders/gcloud:latest (floating bootstrap; python3 + urllib +
#   json — the reliquary-less capture rides this, not a pinned tool). Python, not bash:
#   this step PARSES a structured upstream OCI index (correlate platform.architecture +
#   annotations.disktype within a child descriptor, extract a third field), which the
#   "no jq, author-by-hand with grep+cut" bash GCB discipline does not cover. python's
#   stdlib json/urllib are the native tools — the rbgjl06-package-delete.py precedent,
#   and the .py file is outside the bash command-allowlist (CBG polyglot, CBp_ rules).
# Substitutions (automapSubstitutions provides as env vars):
#   _RBGL_GAR_HOST _RBGL_GAR_PATH _RBGL_LODES_ROOT _RBGL_LODE_STAMP _RBGL_TAG_SPRUE
#   _RBGL_TAG_VOUCH _RBGL_TRUST_GRADE _RBGL_VOUCH_SCHEMA _RBGL_ACQUIRED_BY
#   _RBGL_PODVM_BRAND _RBGL_PODVM_FAMILY _RBGL_PODVM_VERSION _RBGL_PODVM_SELECTION
#   _RBGL_PODVM_PRESERVED (refresh add-only: JSON array of already-captured members)
#
# podvm is recorded-at-acquisition: quay rotates these images out within days and
# publishes no durable checksum, so RB attests only the leaf digest observed at
# capture. There is no checksum to verify (unlike wsl); the integrity guard is the
# downstream blob-residency HEAD (rbgjl09) plus gcrane cp's digest-faithful copy.
#
# Selection list staged at /workspace/immure_selection.txt — one row per selected
# leaf, the contract for rbgjl08 (capture) and rbgjl09 (residency):
#   <member_tag>|<leaf_manifest_digest>|<layer_blob_digest>|<layer_blob_size>
# No field can carry a '|' (tags, sha256: digests, decimal sizes), so busybox
# IFS='|' read splits it cleanly. The envelope (/workspace/lode_<stamp>_vouch.json)
# and the stamp roster (/workspace/lode_stamps.txt) are the contract for rbgjl02.

import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ACCEPT_INDEX = (
    "application/vnd.oci.image.index.v1+json,"
    "application/vnd.docker.distribution.manifest.list.v2+json"
)
ACCEPT_MANIFEST = (
    "application/vnd.oci.image.manifest.v1+json,"
    "application/vnd.docker.distribution.manifest.v2+json"
)


def die(msg):
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def require_env(name):
    val = os.environ.get(name, "")
    if not val:
        die(f"{name} missing")
    return val


def http_get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return resp.read()


def get_pull_token(registry, repo):
    # Registry-v2 anon Bearer: probe /v2/, read the 401 Www-Authenticate challenge
    # for the realm + service, then fetch a pull-scoped token. quay's anonymous
    # rate-limiting is the failure mode — fail loud, never retry-loop.
    probe = f"https://{registry}/v2/"
    try:
        http_get(probe, {})
        return None  # registry needs no auth
    except urllib.error.HTTPError as e:
        if e.code != 401:
            die(f"unexpected {e.code} probing {probe}: {e.reason}")
        challenge = e.headers.get("Www-Authenticate", "")
    realm = re.search(r'realm="([^"]*)"', challenge)
    service = re.search(r'service="([^"]*)"', challenge)
    if not realm:
        die(f"no Bearer realm in Www-Authenticate from {registry}: {challenge!r}")
    params = {"service": (service.group(1) if service else registry),
              "scope": f"repository:{repo}:pull"}
    token_url = realm.group(1) + "?" + urllib.parse.urlencode(params)
    try:
        body = http_get(token_url, {})
    except urllib.error.HTTPError as e:
        die(f"anon token fetch failed ({e.code}) at {token_url}: {e.reason}")
    data = json.loads(body)
    token = data.get("token") or data.get("access_token")
    if not token:
        die("no token in anon auth response")
    return token


def fetch_manifest(registry, repo, ref, token, accept):
    url = f"https://{registry}/v2/{repo}/manifests/{ref}"
    headers = {"Accept": accept}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        return json.loads(http_get(url, headers))
    except urllib.error.HTTPError as e:
        die(f"failed to fetch manifest {ref} ({e.code}): {e.reason}")


def main():
    gar_host = require_env("_RBGL_GAR_HOST")
    gar_path = require_env("_RBGL_GAR_PATH")
    lodes_root = require_env("_RBGL_LODES_ROOT")
    stamp = require_env("_RBGL_LODE_STAMP")
    sprue = require_env("_RBGL_TAG_SPRUE")
    brand = require_env("_RBGL_PODVM_BRAND")
    family = require_env("_RBGL_PODVM_FAMILY")
    version = require_env("_RBGL_PODVM_VERSION")
    selection = require_env("_RBGL_PODVM_SELECTION")

    # Refresh merge (Architecture H): the host passes the already-captured member set
    # as _RBGL_PODVM_PRESERVED — a compact JSON array of rblv_ member objects (envelope
    # members verbatim + orphan-recovered entries), or "[]" for a fresh capture. Members
    # already present are spliced into the new envelope and never re-resolved upstream.
    preserved = json.loads(os.environ.get("_RBGL_PODVM_PRESERVED", "[]") or "[]")
    preserved_idx = {m["rblv_name"]: m for m in preserved}

    print("=== Select podvm disk leaves from quay family index ===")

    # Decompose the family into the registry-v2 host + repository (quay.io/podman/...).
    if "/" not in family:
        die(f"family '{family}' has no registry/repo split")
    registry, repo = family.split("/", 1)
    print(f"Registry: {registry}  Repo: {repo}  Version: {version}")

    pkg = f"{gar_host}/{gar_path}/{lodes_root}/{stamp}"
    print(f"Lode package: {pkg}")

    token = get_pull_token(registry, repo)

    # The top reference must be a multi-arch index — podvm families publish one index
    # per version since 5.4 (memo-20260608 §3.2). A single image here means the
    # version/family pairing is wrong; fail loud rather than capture a non-leaf.
    index = fetch_manifest(registry, repo, version, token, ACCEPT_INDEX)
    media = index.get("mediaType", "")
    if "image.index" not in media and "manifest.list" not in media:
        die(f"{family}:{version} is not an index (mediaType: {media or 'absent'})")
    descriptors = index.get("manifests", [])

    acquired_at = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    rows = []
    members = []

    # SELECTION is space-separated disktype:arch. Match on the index child DESCRIPTOR
    # (platform.architecture in the alt spelling x86_64/aarch64 + annotations.disktype),
    # never the layer filename — unreliable per memo-20260608 §3.4. Match the curated
    # set LITERALLY; never normalize arch spellings.
    for entry in selection.split():
        if ":" not in entry:
            die(f"malformed selection entry '{entry}' (want disktype:arch)")
        disktype, arch = entry.split(":", 1)
        # Both fields non-empty: an empty disktype would silently match any
        # annotation-less descriptor below (ann.get(...) == ""); fail loud on
        # the malformed curated constant instead.
        if not disktype or not arch:
            die(f"malformed selection entry '{entry}' (empty disktype or arch)")
        member_tag = f"{sprue}{disktype}-{arch}"

        # Add-only / preserve-originals: a member the host reports as already captured
        # (enveloped verbatim, or orphan-recovered from GAR) is spliced in WITHOUT a
        # fresh upstream resolve and WITHOUT a capture row — its held bytes and its true
        # per-member time stand. Only genuinely-absent leaves touch the rotating
        # upstream. Fresh capture is the empty-preserved case (every leaf is absent).
        if member_tag in preserved_idx:
            print(f"--- Preserving {member_tag} (already captured; not re-resolved) ---")
            members.append(preserved_idx[member_tag])
            continue

        print(f"--- Selecting {disktype}/{arch} -> :{member_tag} ---")
        leaf_digest = None
        for m in descriptors:
            plat = m.get("platform") or {}
            ann = m.get("annotations") or {}
            if plat.get("architecture") == arch and ann.get("disktype", "") == disktype:
                leaf_digest = m.get("digest")
                break
        if not leaf_digest:
            # Die listing every available (architecture, disktype) pair, so a quay
            # rotation reads as a clear inventory diff, not a mystery.
            available = sorted({
                ((m.get("platform") or {}).get("architecture", ""),
                 (m.get("annotations") or {}).get("disktype", ""))
                for m in descriptors
            })
            die(f"no leaf for {disktype}/{arch} in {family}:{version}; "
                f"available (architecture, disktype): {available}")

        # Each disk leaf is a single-platform OCI artifact: empty config + exactly ONE
        # zstd blob. More than one layer means the descriptor matched a non-disk
        # manifest — die loud rather than residency-check one blob and ignore the rest.
        leaf = fetch_manifest(registry, repo, leaf_digest, token, ACCEPT_MANIFEST)
        layers = leaf.get("layers") or []
        if len(layers) != 1:
            die(f"leaf {disktype}/{arch} has {len(layers)} layers (expected 1 disk blob)")
        blob_digest = layers[0].get("digest")
        blob_size = layers[0].get("size")
        if not blob_digest or blob_size is None:
            die(f"leaf {disktype}/{arch} missing layer digest/size")
        print(f"  leaf manifest: {leaf_digest}")
        print(f"  disk blob:     {blob_digest} ({blob_size} bytes)")

        rows.append(f"{member_tag}|{leaf_digest}|{blob_digest}|{blob_size}")
        # Recorded grade: the attestation IS the captured leaf digest; origin keeps the
        # declared family:version so the rotating-upstream provenance survives. The
        # per-member rblv_acquired_at / rblv_capture_build are PODVM-ONLY — only podvm
        # refreshes, so only podvm accumulates members across multiple authoring events;
        # in a refreshed Lode the preserved members' times sit EARLIER than the
        # envelope-level rblv_acquired_at, so the artifact self-discloses the
        # authored-vs-captured split (see RBSLI). A uniformity sweep must not graft
        # these onto the single-capture kinds.
        members.append({
            "rblv_name": member_tag,
            "rblv_origin": f"{family}:{version}",
            "rblv_digest": leaf_digest,
            "rblv_verification": "recorded",
            "rblv_tags": [member_tag],
            "rblv_acquired_at": acquired_at,
            "rblv_capture_build": os.environ.get("BUILD_ID", ""),
        })

    if not members:
        die("selection produced no members — nothing to immure")

    envelope = {
        "rblv_schema": require_env("_RBGL_VOUCH_SCHEMA"),
        "rblv_kind": brand,
        "rblv_lode": stamp,
        "rblv_acquired_at": acquired_at,
        "rblv_acquired_by": require_env("_RBGL_ACQUIRED_BY"),
        "rblv_capture_build": os.environ.get("BUILD_ID", ""),
        "rblv_trust_grade": require_env("_RBGL_TRUST_GRADE"),
        "rblv_signature": None,
        "rblv_members": members,
    }

    # Truncate-then-write (idempotent under GCB retry — CBi_103; no append mode).
    # immure_selection.txt carries ONLY the absent leaves (the cp/residency contract);
    # on an all-preserved refresh it is legitimately empty and rbgjl08/09 no-op.
    with open("/workspace/immure_selection.txt", "w") as f:
        f.write("\n".join(rows) + ("\n" if rows else ""))
    with open(f"/workspace/lode_{stamp}_vouch.json", "w") as f:
        json.dump(envelope, f)
    with open("/workspace/lode_stamps.txt", "w") as f:
        f.write(stamp + "\n")

    # Host-facing result (the capture-file carries the same envelope). One slot —
    # immure produces exactly one Lode (the cohort is one package). The spine
    # extracts buildStepOutputs from THIS step (index 0); pin the extract slot to 0.
    result = {"rbls_slot_1": {"rbls_stamp": stamp, "rbls_vouch": envelope}}
    os.makedirs("/builder/outputs", exist_ok=True)
    with open("/builder/outputs/output", "w") as f:
        f.write(json.dumps(result))

    print("=== Writing selection results ===")
    print("\n".join(rows))
    print("=== Immure select step complete ===")


if __name__ == "__main__":
    main()
