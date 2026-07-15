#!/usr/bin/env python3
# RBGJV Step 02: Mode-aware verification and vouch summary composition
# conjure: DSSE envelope signature verification (Python json + openssl)
# bind: digest-pin comparison | graft: GRAFTED stamp
# Writes /workspace/vouch_platforms.txt for step 03.
# Substitutions (GCB anchors — automapSubstitutions provides as env vars):
#   ${_RBGV_GAR_HOST} ${_RBGV_GAR_PATH} ${_RBGV_HALLMARKS_ROOT}
#   ${_RBGV_HALLMARK} ${_RBGV_VESSEL_MODE}
#   ${_RBGV_VESSEL} (content only — written into vouch_summary.vessel)
#   ${_RBGV_ARK_BASENAME_IMAGE} ${_RBGV_ARK_BASENAME_ATTEST}
#   ${_RBGV_IMAGE_1} ${_RBGV_IMAGE_2} ${_RBGV_IMAGE_3}
#   ${_RBGV_IMAGE_1_PROVENANCE} ${_RBGV_IMAGE_2_PROVENANCE} ${_RBGV_IMAGE_3_PROVENANCE}
#   ${_RBGV_BIND_SOURCE} ${_RBGV_GRAFT_SOURCE}

import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

ACCEPT_ALL = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])


def die(msg):
    print(f"FATAL: {msg}", file=sys.stderr)
    sys.exit(1)


def require_env(name):
    val = os.environ.get(name, "")
    if not val:
        die(f"{name} missing")
    return val


def b64url_decode(s):
    """Decode base64url with padding normalization."""
    remainder = len(s) % 4
    if remainder:
        s += "=" * (4 - remainder)
    return base64.urlsafe_b64decode(s)


METADATA_TOKEN_URL = (
    "http://metadata.google.internal/computeMetadata/v1/"
    "instance/service-accounts/default/token"
)


def metadata_token():
    """Fetch OAuth2 access token from GCE metadata server."""
    req = urllib.request.Request(METADATA_TOKEN_URL, headers={"Metadata-Flavor": "Google"})
    resp = urllib.request.urlopen(req)
    return json.loads(resp.read())["access_token"]


def gar_fetch(url, token, accept, method="GET"):
    headers = {"Authorization": f"Bearer {token}", "Accept": accept}
    req = urllib.request.Request(url, headers=headers, method=method)
    return urllib.request.urlopen(req)


def gar_json(url, token, accept):
    resp = gar_fetch(url, token, accept)
    return json.loads(resp.read())


def platform_string(plat_dict):
    """Build os/arch[/variant] string from a platform dict."""
    s = f"{plat_dict['os']}/{plat_dict['architecture']}"
    if plat_dict.get("variant"):
        s += f"/{plat_dict['variant']}"
    return s


def main():
    vessel_mode    = os.environ.get("_RBGV_VESSEL_MODE", "")
    gar_host       = require_env("_RBGV_GAR_HOST")
    gar_path       = require_env("_RBGV_GAR_PATH")
    hallmarks_root = require_env("_RBGV_HALLMARKS_ROOT")
    image_basename = require_env("_RBGV_ARK_BASENAME_IMAGE")
    vessel         = require_env("_RBGV_VESSEL")
    hallmark       = require_env("_RBGV_HALLMARK")

    print(f"=== Mode-aware verification ({vessel_mode}) ===")

    # New layout: image package = <HALLMARKS_ROOT>/<HALLMARK>/<image-basename>, tag = <HALLMARK>
    image_package = f"{hallmarks_root}/{hallmark}/{image_basename}"
    image_registry_base = f"https://{gar_host}/v2/{gar_path}/{image_package}"
    image_full_ref = f"{gar_host}/{gar_path}/{image_package}"

    token = metadata_token()

    try:
        manifest = gar_json(f"{image_registry_base}/manifests/{hallmark}", token, ACCEPT_ALL)
    except Exception as e:
        die(f"Failed to fetch manifest for {image_package}:{hallmark}: {e}")

    media_type = manifest.get("mediaType", "")
    is_index = "manifest.list" in media_type or "image.index" in media_type

    # Discover platforms and write vouch_platforms.txt
    config = None
    if is_index:
        plats = []
        for m in manifest.get("manifests", []):
            p = m.get("platform", {})
            if p.get("os") == "unknown" and p.get("architecture") == "unknown":
                continue
            plats.append(platform_string(p))
        if not plats:
            die("No platforms")
        with open("/workspace/vouch_platforms.txt", "w") as f:
            f.write(",".join(plats))
    else:
        config_digest = manifest.get("config", {}).get("digest", "")
        if not config_digest:
            die("No config digest")
        try:
            config = gar_json(f"{image_registry_base}/blobs/{config_digest}", token, ACCEPT_ALL)
        except Exception as e:
            die(f"Failed to fetch config blob: {e}")
        ps = f"{config['os']}/{config['architecture']}"
        if config.get("variant"):
            ps += f"/{config['variant']}"
        with open("/workspace/vouch_platforms.txt", "w") as f:
            f.write(ps)

    with open("/workspace/vouch_platforms.txt") as f:
        print(f"Platforms: {f.read()}")

    if vessel_mode == "rbnve_conjure":
        _verify_conjure(manifest, is_index, config, token, gar_host, gar_path,
                        hallmarks_root, hallmark, vessel)
    elif vessel_mode == "rbnve_bind":
        _verify_bind(token, image_registry_base, hallmark, vessel)
    elif vessel_mode == "rbnve_graft":
        _verify_graft(hallmark, vessel)
    else:
        die(f"Unknown vessel mode: {vessel_mode}")


def _verify_conjure(manifest, is_index, config, token, gar_host, gar_path,
                    hallmarks_root, hallmark, vessel):
    builder_id = "https://cloudbuild.googleapis.com/GoogleHostedWorker"
    expected_keyid = ("projects/verified-builder/locations/global/keyRings/"
                      "attestor/cryptoKeys/google-hosted-worker/cryptoKeyVersions/1")

    # New layout: attest package = <HALLMARKS_ROOT>/<HALLMARK>/<attest-basename> with per-platform tags <HALLMARK>-<arch>
    attest_basename = require_env("_RBGV_ARK_BASENAME_ATTEST")
    attest_package = f"{hallmarks_root}/{hallmark}/{attest_basename}"
    attest_registry_base = f"https://{gar_host}/v2/{gar_path}/{attest_package}"
    attest_full_ref = f"{gar_host}/{gar_path}/{attest_package}"

    # Build platform entries: [(digest, arch, variant), ...]
    # Resolve provenance-carrying digests from per-platform attest tags (HEAD request),
    # NOT from the image manifest index (those are buildx-native digests with no GCB provenance).
    entries = []
    if is_index:
        for m in manifest.get("manifests", []):
            p = m.get("platform", {})
            if p.get("os") == "unknown" and p.get("architecture") == "unknown":
                continue
            arch = p["architecture"]
            variant = p.get("variant", "")
            ps = f"{arch}{variant}"
            attest_tag = f"{hallmark}-{ps}"
            try:
                resp = gar_fetch(f"{attest_registry_base}/manifests/{attest_tag}", token, ACCEPT_ALL, method="HEAD")
                ad = resp.headers.get("Docker-Content-Digest", "")
            except Exception:
                die(f"HEAD for {attest_package}:{attest_tag} failed")
            if not ad:
                die(f"No digest for {attest_package}:{attest_tag}")
            entries.append((ad, arch, variant))
    else:
        arch = config["architecture"]
        variant = config.get("variant", "")
        ps = f"{arch}{variant}"
        attest_tag = f"{hallmark}-{ps}"
        try:
            resp = gar_fetch(f"{attest_registry_base}/manifests/{attest_tag}", token, ACCEPT_ALL, method="HEAD")
            ad = resp.headers.get("Docker-Content-Digest", "")
        except Exception:
            die(f"HEAD for {attest_package}:{attest_tag} failed")
        if not ad:
            die(f"No digest for {attest_package}:{attest_tag}")
        entries.append((ad, arch, variant))

    print(f"Verifying {len(entries)} platform(s) via DSSE")
    if not entries:
        die("no platform entries")

    for digest, arch, variant in entries:
        ps = f"{arch}{variant}"
        fr = f"{attest_full_ref}@{digest}"
        print(f"  {ps}: fetching provenance...")

        result = subprocess.run(
            ["gcloud", "artifacts", "docker", "images", "describe",
             fr, "--format", "json", "--show-provenance"],
            capture_output=True, text=True, check=True,
        )
        prov_data = json.loads(result.stdout)

        with open(f"/workspace/prov-{ps}.json", "w") as f:
            f.write(result.stdout)

        # Extract v1.0 DSSE envelope
        envelope = None
        for p in prov_data.get("provenance_summary", {}).get("provenance", []):
            if "intoto_slsa_v1" in p.get("noteName", ""):
                envelope = p.get("envelope")
                break
        if not envelope:
            die(f"No v1.0 envelope for {ps}")

        with open(f"/workspace/env-{ps}.json", "w") as f:
            json.dump(envelope, f, indent=2)
            f.write("\n")

        # Verify keyid
        ak = envelope["signatures"][0]["keyid"]
        if ak != expected_keyid:
            die(f"keyid mismatch: {ak}")

        # Decode payload and signature (base64url)
        payload_raw = b64url_decode(envelope["payload"])
        sig_raw     = b64url_decode(envelope["signatures"][0]["sig"])

        pl_file  = f"/workspace/pl-{ps}.raw"
        sig_file = f"/workspace/sig-{ps}.bin"
        with open(pl_file, "wb") as f:
            f.write(payload_raw)
        with open(sig_file, "wb") as f:
            f.write(sig_raw)

        # Construct PAE (Pre-Authentication Encoding)
        payload_type = "application/vnd.in-toto+json"
        pae_header = f"DSSEv1 {len(payload_type)} {payload_type} {len(payload_raw)} ".encode()
        pae_file = f"/workspace/pae-{ps}.bin"
        with open(pae_file, "wb") as f:
            f.write(pae_header + payload_raw)

        # Verify with openssl
        verify_result = subprocess.run(
            ["openssl", "dgst", "-sha256",
             "-verify", "/workspace/keys/google-hosted-worker.pub",
             "-signature", sig_file, pae_file],
            capture_output=True, text=True,
        )
        if verify_result.returncode != 0:
            die(f"DSSE verify FAILED for {ps}")

        # Extract verification details from payload
        payload_json = json.loads(payload_raw)
        ab = payload_json["predicate"]["runDetails"]["builder"]["id"]
        if ab != builder_id:
            die(f"builder mismatch: {ab}")

        bt = payload_json["predicate"]["buildDefinition"]["buildType"]
        sd = payload_json["subject"][0]["digest"]["sha256"]

        verify_data = {
            "verifier": "dsse-envelope-v1",
            "builder_id": ab,
            "build_type": bt,
            "subject_digest": sd,
            "keyid": ak,
            "verdict": "pass",
        }
        with open(f"/workspace/verify-{ps}.json", "w") as f:
            json.dump(verify_data, f, indent=2)
            f.write("\n")
        print(f"  {ps}: DSSE verified OK")

    print(f"All {len(entries)} platforms verified")

    # Compose vouch summary
    vouch_summary = {
        "hallmark": hallmark,
        "vessel": vessel,
        "vessel_mode": "rbnve_conjure",
        "verify_method": "dsse-envelope",
        "base_images": [],
        "platforms": [],
    }

    for digest, arch, variant in entries:
        ps = f"{arch}{variant}"
        with open(f"/workspace/verify-{ps}.json") as f:
            vdata = json.loads(f.read())
        vdata["platform"] = ps
        vouch_summary["platforms"].append(vdata)

    # Record base image provenance (anchored GAR refs or upstream pass-through)
    for slot in [1, 2, 3]:
        ref  = os.environ.get(f"_RBGV_IMAGE_{slot}", "")
        prov = os.environ.get(f"_RBGV_IMAGE_{slot}_PROVENANCE", "")
        if ref:
            vouch_summary["base_images"].append({"slot": slot, "ref": ref, "provenance": prov})

    with open("/workspace/vouch_summary.json", "w") as f:
        json.dump(vouch_summary, f, indent=2)
        f.write("\n")
    print("Vouch summary composed")


def _verify_bind(token, image_registry_base, hallmark, vessel):
    try:
        resp = gar_fetch(f"{image_registry_base}/manifests/{hallmark}", token, ACCEPT_ALL, method="HEAD")
        actual_digest = resp.headers.get("Docker-Content-Digest", "")
    except Exception:
        die("HEAD failed")
    if not actual_digest:
        die("No Docker-Content-Digest")

    bind_source = os.environ.get("_RBGV_BIND_SOURCE", "")
    if "@" not in bind_source:
        die("no @ in BIND_SOURCE")
    pinned_digest = bind_source.split("@", 1)[1]
    if not pinned_digest:
        die("no digest in BIND_SOURCE")
    if actual_digest != pinned_digest:
        die(f"Digest mismatch — GAR: {actual_digest}  Pin: {pinned_digest}")
    print(f"Digest pin verified: {actual_digest}")

    vouch_summary = {
        "hallmark": hallmark,
        "vessel": vessel,
        "vessel_mode": "rbnve_bind",
        "verification": {
            "method": "digest-pin",
            "bind_source": bind_source,
            "actual_digest": actual_digest,
            "pinned_digest": pinned_digest,
            "verdict": "DIGEST_PIN_VERIFIED",
        },
    }
    with open("/workspace/vouch_summary.json", "w") as f:
        json.dump(vouch_summary, f, indent=2)
        f.write("\n")
    print("Vouch summary composed")


def _verify_graft(hallmark, vessel):
    print("Graft mode — stamping GRAFTED")
    graft_source = os.environ.get("_RBGV_GRAFT_SOURCE", "")
    vouch_summary = {
        "hallmark": hallmark,
        "vessel": vessel,
        "vessel_mode": "rbnve_graft",
        "verification": {
            "method": "none",
            "graft_source": graft_source,
            "verdict": "GRAFTED",
        },
    }
    with open("/workspace/vouch_summary.json", "w") as f:
        json.dump(vouch_summary, f, indent=2)
        f.write("\n")
    print("Vouch summary composed")


if __name__ == "__main__":
    main()
