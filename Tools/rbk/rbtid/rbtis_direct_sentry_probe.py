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
# RBTIS - Sentry service enumeration
#
# Sortie: direct_sentry_probe
# Front: direct

import socket
import struct
import os


SENTRY_IP = os.environ["RBRN_ENCLAVE_SENTRY_IP"]
ENTRY_PORT = int(os.environ["RBRN_ENTRY_PORT_WORKSTATION"])
TIMEOUT = 2

# Ports to scan on the sentry — common services + management ports
SCAN_PORTS = [
    21, 22, 23, 25, 80, 111, 135, 139, 443, 445,
    993, 995, 2222, 3306, 3389, 5432, 5900, 6379,
    8080, 8443, 8888, 9090, 9200, 27017,
]


def _tcp_connect(host, port, timeout=TIMEOUT):
    """Attempt TCP connect, return True if port is open."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((host, port))
        sock.close()
        return True
    except (ConnectionRefusedError, socket.timeout, OSError):
        return False


def _dns_version_query(host):
    """Query version.bind CHAOS TXT to fingerprint dnsmasq."""
    # Build DNS query: version.bind, class CHAOS (3), type TXT (16)
    txn_id = struct.unpack("!H", os.urandom(2))[0]
    flags = 0x0100  # Standard query, recursion desired
    header = struct.pack("!HHHHHH", txn_id, flags, 1, 0, 0, 0)

    # version.bind as DNS name
    qname = b"\x07version\x04bind\x00"
    question = qname + struct.pack("!HH", 16, 3)  # TXT, CHAOS class

    packet = header + question
    result = {"queried": False, "version": None}

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(TIMEOUT)
        sock.sendto(packet, (host, 53))
        result["queried"] = True

        resp, _ = sock.recvfrom(4096)
        rcode = struct.unpack("!HH", resp[:4])[1] & 0x0F
        ancount = struct.unpack("!H", resp[6:8])[0]

        if rcode == 0 and ancount > 0:
            # Parse TXT record from answer section
            # Skip question section (variable length)
            offset = 12
            while offset < len(resp) and resp[offset] != 0:
                offset += resp[offset] + 1
            offset += 5  # null terminator + qtype(2) + qclass(2)

            # Answer: name(2 ptr) + type(2) + class(2) + ttl(4) + rdlen(2) + rdata
            if offset + 12 < len(resp):
                offset += 2  # name pointer
                offset += 2 + 2 + 4  # type, class, ttl
                rdlen = struct.unpack("!H", resp[offset:offset+2])[0]
                offset += 2
                if rdlen > 1 and offset + 1 < len(resp):
                    txt_len = resp[offset]
                    txt = resp[offset+1:offset+1+txt_len].decode(errors="replace")
                    result["version"] = txt
        sock.close()
    except Exception as e:
        result["error"] = str(e)
    return result


def _dns_any_query(host, name):
    """Send ANY query to test dnsmasq response to unusual query types."""
    txn_id = struct.unpack("!H", os.urandom(2))[0]
    flags = 0x0100
    header = struct.pack("!HHHHHH", txn_id, flags, 1, 0, 0, 0)

    qname = b""
    for label in name.split("."):
        qname += struct.pack("!B", len(label)) + label.encode()
    qname += b"\x00"
    question = qname + struct.pack("!HH", 255, 1)  # ANY, IN class

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(TIMEOUT)
        sock.sendto(header + question, (host, 53))
        resp, _ = sock.recvfrom(4096)
        rcode = struct.unpack("!HH", resp[:4])[1] & 0x0F
        ancount = struct.unpack("!H", resp[6:8])[0]
        sock.close()
        return {"rcode": rcode, "answers": ancount, "responded": True}
    except Exception as e:
        return {"responded": False, "error": str(e)}


def run():
    """Sentry service enumeration — probe the sentry for exposed services.

    Vector:
      The sentry (10.242.0.2) is the trusted gateway. Its INPUT chain should
      only accept:
        - Loopback traffic
        - RELATED,ESTABLISHED connections
        - ICMP from enclave
        - DNS (TCP/UDP port 53) from enclave

      Any other open port represents an unexpected attack surface. This sortie:
        1. Port-scans the sentry for open TCP ports beyond DNS
        2. Fingerprints dnsmasq via version.bind CHAOS TXT query
        3. Tests unusual DNS query types (ANY) for information leakage
        4. Checks if the entry port DNAT (8888->bottle) is accessible from
           within the enclave (it shouldn't be — DNAT is on the uplink)

      A listening service beyond dnsmasq on port 53 means the sentry has
      unnecessary attack surface. Known dnsmasq CVEs against the discovered
      version would be an advisory finding.

    Detection logic:
      - Only port 53 open on sentry        -> SECURE
      - Additional ports open               -> BREACH (unexpected service)
      - dnsmasq version with known CVEs     -> advisory (not auto-BREACH)
      - ANY query returns unexpected data    -> informational
    """
    assertions = []

    # Test 1: Port scan — only port 53 should be open
    open_ports = []
    for port in SCAN_PORTS:
        if _tcp_connect(SENTRY_IP, port):
            open_ports.append(port)

    # DNS port 53 should be open (expected)
    dns_open = 53 in open_ports
    unexpected_ports = [p for p in open_ports if p != 53]

    assertions.append({
        "name": "sentry_dns_port_open",
        "passed": True,  # informational
        "detail": f"DNS port 53: {'open' if dns_open else 'closed (unexpected)'}",
    })

    assertions.append({
        "name": "sentry_no_unexpected_ports",
        "passed": len(unexpected_ports) == 0,
        "detail": f"Unexpected open ports: {unexpected_ports if unexpected_ports else 'none'}"
                  + (f" — {len(unexpected_ports)} unexpected service(s) exposed" if unexpected_ports else ""),
    })

    # Test 2: dnsmasq version fingerprint
    ver = _dns_version_query(SENTRY_IP)
    assertions.append({
        "name": "dnsmasq_version_query",
        "passed": True,  # informational — version disclosure is not a breach
        "detail": f"version.bind: {ver.get('version', 'not disclosed')}"
                  + (f" — check for CVEs" if ver.get("version") else ""),
    })

    # Test 3: ANY query to allowed domain
    test_domain = os.environ["RBRN_UPLINK_ALLOWED_DOMAINS"].split(",")[0]
    any_result = _dns_any_query(SENTRY_IP, test_domain)
    assertions.append({
        "name": "dns_any_query",
        "passed": True,  # informational
        "detail": f"ANY query for {test_domain}: "
                  + (f"rcode={any_result['rcode']}, {any_result['answers']} answers"
                     if any_result.get("responded")
                     else any_result.get("error", "no response")),
    })

    # Test 4: Check if entry port is accessible from enclave
    # DNAT should only apply to traffic arriving on the uplink interface
    entry_open = _tcp_connect(SENTRY_IP, ENTRY_PORT)
    assertions.append({
        "name": "entry_port_not_accessible_from_enclave",
        "passed": not entry_open,
        "detail": f"Entry port {SENTRY_IP}:{ENTRY_PORT} from enclave: "
                  + ("OPEN — DNAT accessible from inside" if entry_open
                     else "closed (correct — DNAT only on uplink)"),
    })

    # Test 5: Check high ports on sentry (dnsmasq source port range, management)
    high_open = []
    for port in [4096, 5353, 8053, 10000, 10053]:
        if _tcp_connect(SENTRY_IP, port):
            high_open.append(port)
    assertions.append({
        "name": "sentry_no_unexpected_high_ports",
        "passed": len(high_open) == 0,
        "detail": f"High port scan: {high_open if high_open else 'none open'}",
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "Sentry exposes only DNS — minimal attack surface"
                  if all_passed
                  else f"Sentry exposes unexpected services: ports {unexpected_ports + high_open}",
        "assertions": assertions,
    }
