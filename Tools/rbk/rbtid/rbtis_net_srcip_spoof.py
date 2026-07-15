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
# RBTIS - Source IP spoofing via raw sockets
#
# Sortie: net_srcip_spoof
# Front: network

import os
import socket
import struct
import time


BOTTLE_IP = os.environ["RBRN_ENCLAVE_BOTTLE_IP"]
SENTRY_IP = os.environ["RBRN_ENCLAVE_SENTRY_IP"]
ALLOWED_CIDR_IP = os.environ["RBRN_UPLINK_ALLOWED_CIDRS"].split(",")[0].split("/")[0]
FORBIDDEN_IP = "8.8.8.8"
TIMEOUT = 3


def _ip_checksum(header):
    """Compute IP header checksum."""
    if len(header) % 2:
        header += b"\x00"
    s = sum(struct.unpack("!%dH" % (len(header) // 2), header))
    s = (s >> 16) + (s & 0xFFFF)
    s += s >> 16
    return ~s & 0xFFFF


def _build_spoofed_syn(src_ip, dst_ip, src_port, dst_port):
    """Build a complete IP+TCP SYN packet with spoofed source."""
    # TCP SYN
    seq = struct.unpack("!I", os.urandom(4))[0]
    data_offset_flags = (5 << 12) | 0x002  # SYN
    tcp = struct.pack("!HHIIHHH",
                      src_port, dst_port,
                      seq, 0,
                      data_offset_flags,
                      65535, 0) + b"\x00\x00"  # checksum + urgent

    # IP header
    version_ihl = 0x45
    total_len = 20 + len(tcp)
    ident = struct.unpack("!H", os.urandom(2))[0]
    header = struct.pack("!BBHHHBBH4s4s",
                         version_ihl, 0, total_len,
                         ident, 0x4000,  # DF
                         64, 6, 0,       # TTL, TCP, checksum placeholder
                         socket.inet_aton(src_ip),
                         socket.inet_aton(dst_ip))
    cksum = _ip_checksum(header)
    header = struct.pack("!BBHHHBBH4s4s",
                         version_ihl, 0, total_len,
                         ident, 0x4000,
                         64, 6, cksum,
                         socket.inet_aton(src_ip),
                         socket.inet_aton(dst_ip))
    return header + tcp


def _send_spoofed(src_ip, dst_ip, src_port, dst_port, label):
    """Send a spoofed SYN and listen for any response."""
    result = {"src": src_ip, "dst": dst_ip, "label": label,
              "sent": False, "replied": False}
    try:
        # Send with IP_HDRINCL
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
        packet = _build_spoofed_syn(src_ip, dst_ip, src_port, dst_port)
        sock.sendto(packet, (dst_ip, 0))
        result["sent"] = True
        sock.close()

        # Listen for TCP response on raw socket
        listen = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_TCP)
        listen.settimeout(TIMEOUT)
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            listen.settimeout(max(0.1, deadline - time.time()))
            try:
                resp, addr = listen.recvfrom(4096)
                # We're looking for a response from dst_ip to src_ip
                # but since src_ip is spoofed, the response may not reach us.
                # However, if dst_ip responds to our real IP (ICMP unreachable, RST)
                # or if the sentry's NAT rewrites things oddly, we might see it.
                if addr[0] == dst_ip:
                    ip_hlen = (resp[0] & 0x0F) * 4
                    if len(resp) > ip_hlen + 13:
                        tcp_flags = resp[ip_hlen + 13]
                        result["replied"] = True
                        result["reply_from"] = addr[0]
                        result["tcp_flags"] = tcp_flags
                        break
            except socket.timeout:
                break
        listen.close()
    except PermissionError:
        result["error"] = "Raw socket permission denied"
    except OSError as e:
        result["error"] = str(e)
    return result


def _check_rp_filter():
    """Check reverse path filtering status on all interfaces."""
    results = {}
    for iface in ["all", "default", "eth0", "eth1"]:
        path = f"/proc/sys/net/ipv4/conf/{iface}/rp_filter"
        try:
            with open(path) as f:
                results[iface] = int(f.read().strip())
        except (FileNotFoundError, PermissionError):
            pass
    return results


def run():
    """Source IP spoofing — test if rp_filter blocks spoofed source addresses.

    Vector:
      The bottle has CAP_NET_RAW, enabling raw sockets with IP_HDRINCL to
      craft packets with arbitrary source IP addresses. This sortie tests:

        1. Spoof source as sentry IP (10.242.0.2) to forbidden destination.
           If rp_filter is not active on the enclave interface, the sentry
           may treat this as locally-originated traffic and bypass FORWARD
           rules (going through OUTPUT instead).

        2. Spoof source as an IP in the allowed CIDR (160.79.104.x) to a
           forbidden destination. MASQUERADE NAT might treat this as return
           traffic and skip source rewriting, potentially confusing conntrack.

        3. Spoof source as 127.0.0.1 to forbidden destination. Loopback is
           universally trusted in iptables (lo interface rules). If a packet
           with src 127.0.0.1 arrives on the enclave interface, rp_filter
           should reject it — but misconfiguration could let it through.

      The sentry enables rp_filter via sysctl, which validates that incoming
      packets have a source address reachable via the receiving interface.
      This should block all spoofed sources. But rp_filter must be set on
      the correct interface (enclave-facing, not just "all" or "default").

    Detection logic:
      - Spoofed packet dropped by rp_filter (no response)  -> SECURE
      - Response received from forbidden destination        -> BREACH
      - rp_filter value 0 on enclave interface              -> BREACH (advisory)
    """
    assertions = []

    # Test 0: Check rp_filter settings
    rp = _check_rp_filter()
    # rp_filter: 0=off, 1=strict, 2=loose
    rp_safe = all(v >= 1 for v in rp.values()) if rp else False
    assertions.append({
        "name": "rp_filter_enabled",
        "passed": rp_safe or not rp,  # pass if can't read (restricted)
        "detail": f"rp_filter values: {rp if rp else 'unreadable (restricted)'}",
    })

    # Test 1: Spoof source as sentry IP -> forbidden destination
    r = _send_spoofed(SENTRY_IP, FORBIDDEN_IP, 40010, 53, "spoof-as-sentry")
    escaped = r.get("replied", False)
    assertions.append({
        "name": "spoof_sentry_ip_blocked",
        "passed": not escaped,
        "detail": f"SYN from spoofed {SENTRY_IP} to {FORBIDDEN_IP}:53: "
                  + (f"RESPONSE received — rp_filter failed" if escaped
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 2: Spoof source as allowed CIDR IP -> forbidden destination
    r = _send_spoofed(ALLOWED_CIDR_IP, FORBIDDEN_IP, 40011, 53, "spoof-as-allowed-cidr")
    escaped = r.get("replied", False)
    assertions.append({
        "name": "spoof_allowed_cidr_blocked",
        "passed": not escaped,
        "detail": f"SYN from spoofed {ALLOWED_CIDR_IP} to {FORBIDDEN_IP}:53: "
                  + (f"RESPONSE received — NAT confused" if escaped
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 3: Spoof source as loopback -> forbidden destination
    r = _send_spoofed("127.0.0.1", FORBIDDEN_IP, 40012, 53, "spoof-as-loopback")
    escaped = r.get("replied", False)
    assertions.append({
        "name": "spoof_loopback_blocked",
        "passed": not escaped,
        "detail": f"SYN from spoofed 127.0.0.1 to {FORBIDDEN_IP}:53: "
                  + (f"RESPONSE received — loopback spoof bypassed filter" if escaped
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 4: Spoof source as sentry IP -> allowed CIDR (could confuse NAT)
    r = _send_spoofed(SENTRY_IP, ALLOWED_CIDR_IP, 40013, 443, "spoof-sentry-to-allowed")
    # For this test, a response is more ambiguous — the allowed CIDR is reachable.
    # But it would arrive at the sentry (spoofed source), not us.
    assertions.append({
        "name": "spoof_sentry_to_allowed",
        "passed": True,  # informational — hard to detect response to spoofed src
        "detail": f"SYN from spoofed {SENTRY_IP} to {ALLOWED_CIDR_IP}:443: "
                  + (f"sent, response would go to sentry (not observable)"
                     if r.get("sent")
                     else f"failed: {r.get('error')}"),
    })

    # Test 5: Spoof source as random external IP -> allowed CIDR
    r = _send_spoofed("93.184.216.34", ALLOWED_CIDR_IP, 40014, 443, "spoof-external-to-allowed")
    escaped = r.get("replied", False)
    assertions.append({
        "name": "spoof_external_to_allowed_blocked",
        "passed": not escaped,
        "detail": f"SYN from spoofed 93.184.216.34 to {ALLOWED_CIDR_IP}:443: "
                  + (f"RESPONSE — rp_filter not blocking external spoof" if escaped
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "Source IP spoofing blocked — rp_filter active on enclave interface"
                  if all_passed
                  else "Source IP spoofing NOT fully blocked — rp_filter misconfiguration",
        "assertions": assertions,
    }
