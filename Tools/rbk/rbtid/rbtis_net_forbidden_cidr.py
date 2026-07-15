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
# RBTIS - TCP/UDP to non-allowed CIDRs
#
# Sortie: net_forbidden_cidr
# Front: network

import os
import socket


TIMEOUT = 3
ALLOWED_CIDR = os.environ["RBRN_UPLINK_ALLOWED_CIDRS"].split(",")[0]
ALLOWED_CIDR_IP = ALLOWED_CIDR.split("/")[0]

# Forbidden destinations — well-known IPs outside the allowed CIDR
FORBIDDEN_TCP_TARGETS = [
    ("8.8.8.8", 53, "Google DNS"),
    ("1.1.1.1", 443, "Cloudflare"),
    ("93.184.216.34", 80, "example.com"),
    ("140.82.121.4", 443, "GitHub"),
]

FORBIDDEN_UDP_TARGETS = [
    ("8.8.8.8", 53, "Google DNS UDP"),
    ("1.1.1.1", 53, "Cloudflare DNS UDP"),
]

# Allowed CIDR destination — should be reachable
ALLOWED_TARGET = (ALLOWED_CIDR_IP, 443, f"Allowed CIDR ({ALLOWED_CIDR})")


def _probe_tcp(host, port, timeout=TIMEOUT):
    """Attempt TCP connect. Return dict with result."""
    result = {"host": host, "port": port, "proto": "tcp", "connected": False}
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((host, port))
        result["connected"] = True
        sock.close()
    except (ConnectionRefusedError, ConnectionResetError) as e:
        # Connection refused means the packet reached the destination —
        # the remote host actively rejected it. That's a BREACH: the sentry
        # forwarded the packet beyond the enclave.
        result["refused"] = True
        result["error"] = type(e).__name__
    except socket.timeout:
        result["error"] = "timeout"
    except OSError as e:
        result["error"] = str(e)
    return result


def _probe_udp(host, port, timeout=TIMEOUT):
    """Send a UDP probe and listen for any response."""
    result = {"host": host, "port": port, "proto": "udp", "responded": False}
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout)
        # Send a DNS query as UDP payload (common probe)
        probe = b"\xAA\xBB\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
        probe += b"\x07example\x03com\x00\x00\x01\x00\x01"
        sock.sendto(probe, (host, port))
        try:
            resp, addr = sock.recvfrom(4096)
            result["responded"] = True
            result["reply_from"] = addr[0]
            result["reply_len"] = len(resp)
        except socket.timeout:
            result["error"] = "timeout"
        sock.close()
    except OSError as e:
        result["error"] = str(e)
    return result


def run():
    """TCP/UDP to non-allowed CIDRs — test CIDR allowlist enforcement.

    Vector:
      The sentry's FORWARD chain in allowlist mode permits traffic only to
      CIDRs listed in RBRN_UPLINK_ALLOWED_CIDRS (160.79.104.0/23). All other
      destinations should be dropped by the default FORWARD DROP policy.

      This sortie systematically probes:
        1. TCP connections to well-known IPs outside the allowed range
        2. UDP to non-allowed destinations (iptables FORWARD rules for allowed
           CIDRs don't distinguish TCP vs UDP — both should be forwarded for
           allowed CIDRs, neither for forbidden ones)
        3. A control connection to the allowed CIDR to confirm positive path

      Note on ConnectionRefused: a RST from the remote host means the packet
      traversed the sentry and reached the destination. That's a BREACH even
      though the connection "failed" — the data left the enclave.

    Detection logic:
      - TCP connect or RST from forbidden IP   -> BREACH
      - UDP response from forbidden IP          -> BREACH
      - Timeout to forbidden IP                 -> SECURE (packet dropped)
      - TCP connect to allowed CIDR             -> expected (control)
    """
    assertions = []

    # Test 1: TCP to forbidden destinations
    for host, port, label in FORBIDDEN_TCP_TARGETS:
        r = _probe_tcp(host, port)
        # Blocked means: timeout and no connection. A refused connection means
        # the packet reached the destination's network.
        escaped = r["connected"] or r.get("refused", False)
        assertions.append({
            "name": f"tcp_forbidden_{host}_{port}",
            "passed": not escaped,
            "detail": f"TCP {host}:{port} ({label}): "
                      + ("CONNECTED" if r["connected"]
                         else "REFUSED (packet reached destination)" if r.get("refused")
                         else f"blocked ({r.get('error', 'no response')})"),
        })

    # Test 2: UDP to forbidden destinations
    for host, port, label in FORBIDDEN_UDP_TARGETS:
        r = _probe_udp(host, port)
        escaped = r["responded"]
        assertions.append({
            "name": f"udp_forbidden_{host}_{port}",
            "passed": not escaped,
            "detail": f"UDP {host}:{port} ({label}): "
                      + (f"RESPONSE from {r.get('reply_from')}" if escaped
                         else f"blocked ({r.get('error', 'no response')})"),
        })

    # Test 3: TCP to allowed CIDR (control — should succeed or at least not timeout)
    host, port, label = ALLOWED_TARGET
    r = _probe_tcp(host, port)
    # For the control, we expect either a connection or a refusal — both mean
    # the packet was forwarded. Only a timeout would indicate blocking.
    reached = r["connected"] or r.get("refused", False)
    assertions.append({
        "name": "tcp_allowed_cidr_reachable",
        "passed": True,  # informational — not a pass/fail for security
        "detail": f"TCP {host}:{port} ({label}): "
                  + ("reachable" if reached
                     else f"unreachable ({r.get('error')}) — allowed CIDR may be down"),
    })

    # Test 4: TCP to forbidden IPs on port 443 (HTTPS — most common egress)
    for host, label in [("52.20.0.1", "AWS us-east-1"), ("35.190.0.1", "GCP frontend")]:
        r = _probe_tcp(host, 443)
        escaped = r["connected"] or r.get("refused", False)
        assertions.append({
            "name": f"tcp_forbidden_{host}_443",
            "passed": not escaped,
            "detail": f"TCP {host}:443 ({label}): "
                      + ("CONNECTED" if r["connected"]
                         else "REFUSED" if r.get("refused")
                         else f"blocked ({r.get('error', 'no response')})"),
        })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "CIDR allowlist enforced — all forbidden destinations blocked"
                  if all_passed
                  else "CIDR allowlist BYPASSED — traffic reached forbidden destinations",
        "assertions": assertions,
    }
