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
# RBTIS - IPv6 unconfigured firewall escape
#
# Sortie: net_ipv6_escape
# Front: network

import os
import socket
import struct
import subprocess


TIMEOUT = 3

# Well-known IPv6 destinations
IPV6_TARGETS = [
    ("2001:4860:4860::8888", 53, "Google DNS IPv6"),
    ("2606:4700:4700::1111", 443, "Cloudflare IPv6"),
    ("2001:4860:4860::8844", 53, "Google DNS IPv6 secondary"),
]


def _get_ipv6_addrs():
    """Discover IPv6 addresses on non-loopback interfaces."""
    addrs = []
    try:
        result = subprocess.run(
            ["ip", "-6", "addr", "show", "scope", "link"],
            capture_output=True, text=True, timeout=5
        )
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.startswith("inet6 "):
                parts = line.split()
                if len(parts) >= 2:
                    addrs.append(parts[1].split("/")[0])
    except Exception:
        pass
    return addrs


def _get_ipv6_global_addrs():
    """Discover global-scope IPv6 addresses."""
    addrs = []
    try:
        result = subprocess.run(
            ["ip", "-6", "addr", "show", "scope", "global"],
            capture_output=True, text=True, timeout=5
        )
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.startswith("inet6 "):
                parts = line.split()
                if len(parts) >= 2:
                    addrs.append(parts[1].split("/")[0])
    except Exception:
        pass
    return addrs


def _ipv6_tcp_connect(host, port, timeout=TIMEOUT):
    """Attempt IPv6 TCP connect."""
    result = {"host": host, "port": port, "connected": False}
    try:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((host, port, 0, 0))
        result["connected"] = True
        sock.close()
    except (ConnectionRefusedError, ConnectionResetError) as e:
        result["refused"] = True
        result["error"] = type(e).__name__
    except socket.timeout:
        result["error"] = "timeout"
    except OSError as e:
        result["error"] = str(e)
    return result


def _ipv6_udp_probe(host, port, timeout=TIMEOUT):
    """Send an IPv6 UDP DNS probe."""
    result = {"host": host, "port": port, "responded": False}
    try:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        sock.settimeout(timeout)
        # Minimal DNS query for "example.com" A record
        probe = b"\xAA\xBB\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
        probe += b"\x07example\x03com\x00\x00\x01\x00\x01"
        sock.sendto(probe, (host, port, 0, 0))
        try:
            resp, addr = sock.recvfrom(4096)
            result["responded"] = True
            result["reply_from"] = addr[0]
        except socket.timeout:
            result["error"] = "timeout"
        sock.close()
    except OSError as e:
        result["error"] = str(e)
    return result


def _check_ip6tables():
    """Check if ip6tables has any rules configured."""
    result = {"checked": False, "has_rules": False, "policy_drop": False}
    try:
        r = subprocess.run(
            ["ip6tables", "-L", "-n"],
            capture_output=True, text=True, timeout=5
        )
        result["checked"] = True
        output = r.stdout
        result["raw"] = output[:500]
        # Check if default policies are DROP
        for line in output.splitlines():
            if "policy DROP" in line:
                result["policy_drop"] = True
            if line.startswith("-") or (line and not line.startswith("Chain") and "target" not in line.lower() and line.strip()):
                result["has_rules"] = True
    except FileNotFoundError:
        result["error"] = "ip6tables not found"
    except PermissionError:
        result["error"] = "permission denied"
    except Exception as e:
        result["error"] = str(e)
    return result


def run():
    """IPv6 unconfigured firewall escape — test if IPv6 bypasses iptables.

    Vector:
      The sentry's rbjs_sentry.sh configures only iptables (IPv4). It never
      touches ip6tables. If the enclave network interface has IPv6 enabled
      (even just a link-local address), and ip6tables default policies are
      ACCEPT, then IPv6 traffic flows freely — bypassing the entire firewall.

      This is the classic dual-stack oversight: hardening IPv4 while leaving
      IPv6 wide open. The attack requires:
        1. IPv6 link-local address exists on enclave interface
        2. ip6tables has no DROP policies
        3. An IPv6 route exists (even link-local can reach the host)

      If IPv6 connectivity exists to external hosts, the attacker has an
      unrestricted channel — TCP, UDP, any port, any destination. The entire
      containment model is irrelevant.

    Detection logic:
      - No IPv6 addresses on enclave                -> SECURE (IPv6 disabled)
      - IPv6 exists but ip6tables has DROP policies  -> SECURE (dual-stack hardened)
      - IPv6 TCP/UDP reaches external host           -> BREACH (complete bypass)
    """
    assertions = []

    # Test 1: Check for IPv6 link-local addresses
    link_local = _get_ipv6_addrs()
    assertions.append({
        "name": "ipv6_link_local_exists",
        "passed": True,  # informational
        "detail": f"IPv6 link-local addresses: {link_local if link_local else 'none (IPv6 disabled)'}",
    })

    # Test 2: Check for IPv6 global addresses
    global_addrs = _get_ipv6_global_addrs()
    assertions.append({
        "name": "ipv6_global_exists",
        "passed": len(global_addrs) == 0,
        "detail": f"IPv6 global addresses: {global_addrs if global_addrs else 'none'}",
    })

    # Test 3: Check ip6tables configuration
    ip6t = _check_ip6tables()
    ip6_hardened = ip6t.get("policy_drop", False)
    assertions.append({
        "name": "ip6tables_has_drop_policy",
        "passed": ip6_hardened or not link_local,  # OK if no IPv6 or if hardened
        "detail": f"ip6tables: "
                  + ("DROP policies configured" if ip6_hardened
                     else f"NOT hardened — {ip6t.get('error', 'default ACCEPT policies')}"
                     if link_local
                     else "irrelevant (no IPv6)"),
    })

    # Test 4: IPv6 TCP to external destinations
    ipv6_escaped = False
    for host, port, label in IPV6_TARGETS:
        r = _ipv6_tcp_connect(host, port)
        escaped = r["connected"] or r.get("refused", False)
        if escaped:
            ipv6_escaped = True
        assertions.append({
            "name": f"ipv6_tcp_{host.replace(':', '_')}_{port}",
            "passed": not escaped,
            "detail": f"IPv6 TCP [{host}]:{port} ({label}): "
                      + ("CONNECTED" if r["connected"]
                         else "REFUSED (packet reached dest)" if r.get("refused")
                         else f"blocked ({r.get('error', 'no response')})"),
        })

    # Test 5: IPv6 UDP DNS query to external resolver
    r = _ipv6_udp_probe("2001:4860:4860::8888", 53)
    udp_escaped = r["responded"]
    if udp_escaped:
        ipv6_escaped = True
    assertions.append({
        "name": "ipv6_udp_dns_external",
        "passed": not udp_escaped,
        "detail": f"IPv6 UDP DNS to [2001:4860:4860::8888]:53: "
                  + (f"RESPONSE from {r.get('reply_from')}" if udp_escaped
                     else f"blocked ({r.get('error', 'no response')})"),
    })

    # Test 6: IPv6 ICMPv6 echo (ping6) to external
    icmpv6_escaped = False
    try:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_RAW, socket.IPPROTO_ICMPV6)
        sock.settimeout(TIMEOUT)
        # ICMPv6 echo request: type=128, code=0, checksum=0, id, seq
        ident = os.getpid() & 0xFFFF
        header = struct.pack("!BBHHH", 128, 0, 0, ident, 1)
        # Kernel computes ICMPv6 checksum for us
        sock.sendto(header, ("2001:4860:4860::8888", 0, 0, 0))
        try:
            resp, addr = sock.recvfrom(4096)
            if resp[0] == 129:  # ICMPv6 echo reply
                icmpv6_escaped = True
        except socket.timeout:
            pass
        sock.close()
    except OSError as e:
        pass
    assertions.append({
        "name": "ipv6_icmpv6_external",
        "passed": not icmpv6_escaped,
        "detail": f"ICMPv6 echo to [2001:4860:4860::8888]: "
                  + ("REPLY RECEIVED — IPv6 completely open" if icmpv6_escaped
                     else "blocked"),
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "IPv6 contained — either disabled or ip6tables hardened"
                  if all_passed
                  else "IPv6 ESCAPE — iptables bypassed via unconfigured ip6tables",
        "assertions": assertions,
    }
