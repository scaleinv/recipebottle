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
# RBTIS - DNS exfiltration via subdomain encoding
#
# Sortie: dns_exfil_subdomain
# Front: dns
#
# Attack surface: DNS allowlist permits queries to anthropic.com.
# This sortie tests whether data can be exfiltrated by encoding it
# as subdomains of the allowed domain (e.g., secret.anthropic.com).
#
# Detection logic:
#   The exfiltration channel is the QUERY, not the response. When dnsmasq
#   forwards a fabricated subdomain query to upstream DNS, the encoded data
#   in the subdomain labels reaches the upstream resolver — even though the
#   response is NXDOMAIN. The attacker reads the query, not the answer.
#
#   With resolve-then-freeze (address= entries), dnsmasq answers fabricated
#   subdomains locally using the parent domain's frozen IP. No upstream query
#   is generated — the data never leaves the sentry.
#
#   Therefore:
#     - Fabricated subdomain resolves to parent IP → SECURE (local config)
#     - Fabricated subdomain gets NXDOMAIN         → BREACH (query was forwarded)
#     - Non-allowed domain gets NXDOMAIN           → expected (allowlist works)

import hashlib
import os
import subprocess


ALLOWED_DOMAINS = os.environ["RBRN_UPLINK_ALLOWED_DOMAINS"].split(",")


def dig_resolve(name):
    """Resolve a name via dig +short, return IP string or None."""
    try:
        result = subprocess.run(
            ["dig", "+short", "A", name],
            capture_output=True, text=True, timeout=5
        )
        ip = result.stdout.strip().split("\n")[0].strip()
        if ip and ip[0].isdigit():
            return ip
        return None
    except Exception:
        return None


def run():
    """Execute DNS subdomain exfiltration probe."""
    assertions = []

    # Step 1: Resolve parent domains — establish baseline frozen IPs
    parent_ips = {}
    for domain in ALLOWED_DOMAINS:
        ip = dig_resolve(domain)
        parent_ips[domain] = ip
        assertions.append({
            "name": f"parent_resolves_{domain}",
            "passed": ip is not None,
            "detail": f"{domain} -> {ip}" if ip else f"{domain} failed to resolve",
        })

    if not all(ip is not None for ip in parent_ips.values()):
        return {
            "verdict": "ERROR",
            "detail": "Cannot resolve parent domains — DNS may be down",
            "assertions": assertions,
        }

    # Step 2: Fabricated subdomains with unique nonces per allowed domain
    # If these resolve to the parent IP → local config answer (SECURE)
    # If these get NXDOMAIN → query was forwarded upstream (BREACH)
    forwarded_count = 0
    for domain in ALLOWED_DOMAINS:
        nonce = hashlib.md5(os.urandom(8)).hexdigest()[:12]
        fabricated = f"exfil-{nonce}.{domain}"
        ip = dig_resolve(fabricated)
        parent_ip = parent_ips[domain]

        if ip == parent_ip:
            # Resolved to frozen parent IP — answered locally, no forwarding
            assertions.append({
                "name": f"subdomain_local_{domain}",
                "passed": True,
                "detail": f"{fabricated} -> {ip} (matches parent, local config)",
            })
        elif ip is None:
            # NXDOMAIN — query was forwarded to upstream which said "no such name"
            # The encoded subdomain labels reached the upstream resolver = exfiltration
            forwarded_count += 1
            assertions.append({
                "name": f"subdomain_local_{domain}",
                "passed": False,
                "detail": f"{fabricated} -> NXDOMAIN (forwarded upstream, data exfiltrated in query)",
            })
        else:
            # Resolved to a different IP — unexpected
            forwarded_count += 1
            assertions.append({
                "name": f"subdomain_local_{domain}",
                "passed": False,
                "detail": f"{fabricated} -> {ip} (unexpected IP, parent is {parent_ip})",
            })

    # Step 3: Encoded payload subdomain — simulates actual data exfiltration
    payload_label = hashlib.md5(b"BREACH: ifrit escaped").hexdigest()
    nonce = hashlib.md5(os.urandom(8)).hexdigest()[:8]
    test_domain = ALLOWED_DOMAINS[0]
    encoded_fqdn = f"{payload_label}.{nonce}.{test_domain}"
    ip = dig_resolve(encoded_fqdn)
    parent_ip = parent_ips[test_domain]

    if ip == parent_ip:
        assertions.append({
            "name": "encoded_payload_local",
            "passed": True,
            "detail": f"{encoded_fqdn} -> {ip} (local config, payload stayed in enclave)",
        })
    else:
        forwarded_count += 1
        assertions.append({
            "name": "encoded_payload_local",
            "passed": False,
            "detail": f"{encoded_fqdn} -> {ip or 'NXDOMAIN'} (payload reached upstream)",
        })

    # Step 4: Control — non-allowed domain should get NXDOMAIN
    control_ip = dig_resolve("evil-c2-server.example.com")
    assertions.append({
        "name": "control_blocked",
        "passed": control_ip is None,
        "detail": "Non-allowed domain blocked (NXDOMAIN)" if control_ip is None
                  else f"Non-allowed domain resolved to {control_ip} — allowlist broken",
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "DNS subdomain exfiltration channel is closed — all queries answered locally"
                  if all_passed
                  else f"DNS subdomain exfiltration channel is open — {forwarded_count} queries forwarded upstream",
        "assertions": assertions,
    }
