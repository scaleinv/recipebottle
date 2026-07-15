#!/usr/bin/env python3
#
# Copyright 2026 Scale Invariant, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Brad Hyslop <bhyslop@scaleinvariant.org>
#
# RBTIS - Cloud metadata endpoint probe
#
# Sortie: meta_cloud_endpoint
# Front: metadata

import os
import socket


METADATA_IP = "169.254.169.254"
SENTRY_IP = os.environ["RBRN_ENCLAVE_SENTRY_IP"]
TIMEOUT = 3

# Cloud provider metadata paths
METADATA_PROBES = [
    # GCP
    ("GCP metadata", "/computeMetadata/v1/", {"Metadata-Flavor": "Google"}),
    ("GCP project ID", "/computeMetadata/v1/project/project-id", {"Metadata-Flavor": "Google"}),
    ("GCP service account token", "/computeMetadata/v1/instance/service-accounts/default/token", {"Metadata-Flavor": "Google"}),
    # AWS
    ("AWS metadata", "/latest/meta-data/", {}),
    ("AWS IAM credentials", "/latest/meta-data/iam/security-credentials/", {}),
    # Azure
    ("Azure metadata", "/metadata/instance?api-version=2021-02-01", {"Metadata": "true"}),
]


def _http_get(host, port, path, headers=None, timeout=TIMEOUT):
    """Minimal HTTP GET — no dependencies beyond socket."""
    result = {"host": host, "port": port, "path": path,
              "connected": False, "responded": False, "status": None, "body": None}
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((host, port))
        result["connected"] = True

        req = f"GET {path} HTTP/1.0\r\nHost: {host}\r\n"
        for k, v in (headers or {}).items():
            req += f"{k}: {v}\r\n"
        req += "\r\n"
        sock.sendall(req.encode())

        resp = b""
        while True:
            try:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                resp += chunk
            except socket.timeout:
                break
        sock.close()

        if resp:
            result["responded"] = True
            # Parse status line
            try:
                status_line = resp.split(b"\r\n", 1)[0].decode()
                result["status"] = int(status_line.split(" ", 2)[1])
                # Extract body
                parts = resp.split(b"\r\n\r\n", 1)
                if len(parts) > 1:
                    result["body"] = parts[1][:512]  # cap body for debrief
            except (ValueError, IndexError):
                result["raw_head"] = resp[:256]
    except (ConnectionRefusedError, ConnectionResetError) as e:
        result["error"] = type(e).__name__
    except socket.timeout:
        result["error"] = "timeout"
    except OSError as e:
        result["error"] = str(e)
    return result


def run():
    """Cloud metadata endpoint probe — test access to 169.254.169.254.

    Vector:
      Cloud providers (GCP, AWS, Azure) expose instance metadata at the
      link-local address 169.254.169.254. This address is neither part of the
      enclave subnet (10.242.0.0/24) nor the allowed uplink CIDRs
      (160.79.104.0/23). However, link-local routing behaves differently from
      normal IP routing:

        - The pentacle sets a default route via the sentry (10.242.0.2)
        - Link-local addresses may be handled by the kernel before routing
        - The sentry's MASQUERADE excludes enclave traffic but does not
          explicitly block link-local destinations
        - The host's network namespace may respond to 169.254.169.254

      If the metadata endpoint is reachable, an attacker could extract:
        - Cloud credentials (service account tokens, IAM role credentials)
        - Project/subscription identifiers
        - Network configuration and internal DNS names
        - SSH keys and instance identity documents

      This is a full prison break without touching the network boundary.

    Detection logic:
      - TCP connect to 169.254.169.254:80 succeeds  -> BREACH
      - HTTP response with metadata content           -> BREACH (critical)
      - Connection refused or timeout                  -> SECURE
    """
    assertions = []

    # Test 1: Can we TCP connect to the metadata IP at all?
    r = _http_get(METADATA_IP, 80, "/", timeout=TIMEOUT)
    metadata_reachable = r["connected"]
    assertions.append({
        "name": "metadata_tcp_connect",
        "passed": not metadata_reachable,
        "detail": f"TCP connect to {METADATA_IP}:80: "
                  + (f"CONNECTED (status {r.get('status')})" if metadata_reachable
                     else f"blocked ({r.get('error', 'no connection')})"),
    })

    # Test 2: Probe each cloud provider's metadata paths
    any_metadata_leaked = False
    for label, path, headers in METADATA_PROBES:
        r = _http_get(METADATA_IP, 80, path, headers=headers, timeout=TIMEOUT)
        leaked = r.get("status") in (200, 301, 302, 401, 403)
        if leaked:
            any_metadata_leaked = True
        assertions.append({
            "name": f"metadata_probe_{label.lower().replace(' ', '_')}",
            "passed": not leaked,
            "detail": f"{label}: "
                      + (f"HTTP {r['status']} — metadata endpoint responded"
                         if leaked
                         else r.get("error", "no response")),
        })

    # Test 3: Try alternate metadata ports (some providers use 8080, 8775)
    for port in (8080, 8775):
        r = _http_get(METADATA_IP, port, "/", timeout=2)
        port_open = r["connected"]
        assertions.append({
            "name": f"metadata_port_{port}",
            "passed": not port_open,
            "detail": f"TCP {METADATA_IP}:{port}: "
                      + ("CONNECTED" if port_open else r.get("error", "blocked")),
        })

    # Test 4: Try reaching metadata IP via the sentry as HTTP proxy
    # Some misconfigurations allow proxying through the gateway
    r = _http_get(SENTRY_IP, 80, f"http://{METADATA_IP}/", timeout=2)
    proxy_worked = r.get("status") in (200, 301, 302)
    assertions.append({
        "name": "metadata_via_sentry_proxy",
        "passed": not proxy_worked,
        "detail": f"HTTP proxy via sentry {SENTRY_IP}:80 to metadata: "
                  + (f"PROXIED (status {r['status']})" if proxy_worked
                     else r.get("error", "blocked")),
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "Cloud metadata endpoint unreachable from enclave"
                  if all_passed
                  else "Cloud metadata endpoint REACHABLE — credential leak possible",
        "assertions": assertions,
    }
