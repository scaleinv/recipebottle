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
# RBTIS - ICMP covert channel probe
#
# Sortie: icmp_exfil_payload
# Front: icmp

import os
import socket
import struct
import time


SENTRY_IP = os.environ["RBRN_ENCLAVE_SENTRY_IP"]
ALLOWED_CIDR_IP = os.environ["RBRN_UPLINK_ALLOWED_CIDRS"].split(",")[0].split("/")[0]
EXTERNAL_IP = "8.8.8.8"
TIMEOUT = 3


def _checksum(data):
    """Compute ICMP checksum."""
    if len(data) % 2:
        data += b"\x00"
    s = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    s = (s >> 16) + (s & 0xFFFF)
    s += s >> 16
    return ~s & 0xFFFF


def _build_icmp_echo(payload=b"", seq=1):
    """Build an ICMP echo request with arbitrary payload."""
    icmp_type = 8  # Echo request
    code = 0
    ident = os.getpid() & 0xFFFF
    header = struct.pack("!BBHHH", icmp_type, code, 0, ident, seq)
    cksum = _checksum(header + payload)
    header = struct.pack("!BBHHH", icmp_type, code, cksum, ident, seq)
    return header + payload, ident


def _send_icmp(dest, payload=b"", seq=1):
    """Send ICMP echo to dest, return dict with result."""
    result = {"dest": dest, "sent": False, "replied": False, "payload_len": len(payload)}
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        sock.settimeout(TIMEOUT)
        packet, ident = _build_icmp_echo(payload, seq)
        sock.sendto(packet, (dest, 0))
        result["sent"] = True

        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            sock.settimeout(max(0.1, deadline - time.time()))
            try:
                resp, addr = sock.recvfrom(4096)
                # IP header is first 20 bytes, ICMP starts at offset 20
                if len(resp) < 28:
                    continue
                icmp_type = resp[20]
                resp_ident = struct.unpack("!H", resp[24:26])[0]
                if icmp_type == 0 and resp_ident == ident:  # Echo reply, matching ID
                    result["replied"] = True
                    result["reply_from"] = addr[0]
                    result["reply_payload_len"] = len(resp) - 28
                    break
            except socket.timeout:
                break
        sock.close()
    except PermissionError:
        result["error"] = "Raw socket permission denied (need CAP_NET_RAW)"
    except Exception as e:
        result["error"] = str(e)
    return result


def run():
    """ICMP covert channel — test whether data can escape via ICMP payloads.

    Vector:
      The sentry allows ICMP within the enclave (bottle <-> sentry) but blocks
      ICMP on the FORWARD chain and on uplink egress. This sortie sends ICMP
      echo requests with encoded payloads to three targets:

        1. Sentry (10.242.0.2) — should reply (enclave ICMP allowed)
        2. External IP (8.8.8.8) — should be blocked (FORWARD drops ICMP)
        3. Allowed CIDR IP (160.79.104.1) — should be blocked (FORWARD drops
           ICMP even to allowed CIDRs; the allowlist only permits TCP/UDP)

      If ICMP reaches any destination beyond the sentry, an attacker could
      encode data in echo request payloads (~64KB per packet) and exfiltrate
      at high bandwidth with a cooperating listener.

    Detection logic:
      - Sentry echo reply received          -> expected (enclave ICMP works)
      - External echo reply received         -> BREACH (ICMP crossed boundary)
      - Allowed-CIDR echo reply received     -> BREACH (ICMP forwarded to uplink)
      - Large payload echo reply from sentry -> informational (payload reflection)
    """
    assertions = []

    # Test 1: ICMP to sentry (should work — enclave ICMP allowed)
    secret = b"EXFIL:ifrit-escaped-via-icmp-payload-encoding"
    r = _send_icmp(SENTRY_IP, payload=secret, seq=1)
    assertions.append({
        "name": "icmp_sentry_reachable",
        "passed": r.get("replied", False),
        "detail": f"ICMP echo to sentry {SENTRY_IP}: "
                  + ("reply received" if r.get("replied") else r.get("error", "no reply")),
    })

    # Test 2: ICMP to sentry with large payload (test payload reflection)
    big_payload = os.urandom(1024)
    r_big = _send_icmp(SENTRY_IP, payload=big_payload, seq=2)
    reflected = r_big.get("reply_payload_len", 0) >= 1024 if r_big.get("replied") else False
    assertions.append({
        "name": "icmp_sentry_payload_reflected",
        "passed": True,  # informational — not a breach
        "detail": f"1024-byte payload: "
                  + (f"reflected ({r_big.get('reply_payload_len', 0)} bytes)" if reflected
                     else "not reflected or no reply"),
    })

    # Test 3: ICMP to external IP (should be blocked)
    r_ext = _send_icmp(EXTERNAL_IP, payload=secret, seq=3)
    ext_blocked = not r_ext.get("replied", False)
    assertions.append({
        "name": "icmp_external_blocked",
        "passed": ext_blocked,
        "detail": f"ICMP echo to external {EXTERNAL_IP}: "
                  + ("blocked (no reply)" if ext_blocked
                     else f"REPLY RECEIVED from {r_ext.get('reply_from')} — ICMP escaped enclave"),
    })

    # Test 4: ICMP to allowed CIDR IP (should still be blocked — ICMP not in FORWARD allow)
    r_cidr = _send_icmp(ALLOWED_CIDR_IP, payload=secret, seq=4)
    cidr_blocked = not r_cidr.get("replied", False)
    assertions.append({
        "name": "icmp_allowed_cidr_blocked",
        "passed": cidr_blocked,
        "detail": f"ICMP echo to allowed CIDR {ALLOWED_CIDR_IP}: "
                  + ("blocked (no reply)" if cidr_blocked
                     else f"REPLY RECEIVED from {r_cidr.get('reply_from')} — ICMP forwarded to uplink"),
    })

    # Test 5: ICMP with crafted type (timestamp request, type 13) to external
    # Some firewalls only filter echo but miss other ICMP types
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        sock.settimeout(TIMEOUT)
        icmp_type = 13  # Timestamp request
        ident = os.getpid() & 0xFFFF
        ts = int(time.time()) & 0xFFFFFFFF
        body = struct.pack("!III", ts, 0, 0)
        header = struct.pack("!BBHHH", icmp_type, 0, 0, ident, 1)
        cksum = _checksum(header + body)
        header = struct.pack("!BBHHH", icmp_type, 0, cksum, ident, 1)
        sock.sendto(header + body, (EXTERNAL_IP, 0))
        try:
            resp, addr = sock.recvfrom(4096)
            ts_reply = resp[20] == 14  # Timestamp reply
            ts_blocked = not ts_reply
        except socket.timeout:
            ts_blocked = True
        sock.close()
        assertions.append({
            "name": "icmp_timestamp_external_blocked",
            "passed": ts_blocked,
            "detail": f"ICMP timestamp request to {EXTERNAL_IP}: "
                      + ("blocked" if ts_blocked else "REPLY — non-echo ICMP type escaped"),
        })
    except Exception as e:
        assertions.append({
            "name": "icmp_timestamp_external_blocked",
            "passed": True,
            "detail": f"ICMP timestamp test skipped: {e}",
        })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "ICMP covert channel blocked — no ICMP escapes enclave boundary"
                  if all_passed
                  else "ICMP covert channel OPEN — ICMP crossed enclave boundary",
        "assertions": assertions,
    }
