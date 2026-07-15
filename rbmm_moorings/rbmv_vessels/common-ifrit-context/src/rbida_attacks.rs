// Copyright 2026 Scale Invariant, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Author: Brad Hyslop <bhyslop@scaleinvariant.org>
//
// RBIDA — attack definitions and dispatch for ifrit
//
// Each variant of rbida_Attack represents one security boundary probe.
// Exhaustive match in rbida_run ensures adding a variant forces handling.
// Attacks shell out to system commands available in the ifrit vessel image.

use std::process::Command;

use crate::rbida_sorties;

// ── Domain constants (RCG String Boundary Discipline) ──

/// Test connectivity target — ICANN-owned, stable single /20 CIDR (192.0.32.0/20)
pub const RBIDA_CONNECTIVITY_DOMAIN: &str = "www.internic.net";

// ── Selector constants (Single Definition Rule — RCG String Boundary Discipline) ──

const RBIDA_SEL_DNS_ALLOWED_EXAMPLE: &str = "dns-allowed-example";
const RBIDA_SEL_DNS_ALLOWED_EXAMPLE_ORG: &str = "dns-allowed-example-org";
const RBIDA_SEL_DNS_BLOCKED_GOOGLE: &str = "dns-blocked-google";
const RBIDA_SEL_APT_GET_BLOCKED: &str = "apt-get-blocked";
const RBIDA_SEL_DNS_NONEXISTENT: &str = "dns-nonexistent";
const RBIDA_SEL_DNS_TCP: &str = "dns-tcp";
const RBIDA_SEL_DNS_UDP: &str = "dns-udp";
const RBIDA_SEL_DNS_BLOCK_DIRECT: &str = "dns-block-direct";
const RBIDA_SEL_DNS_BLOCK_ALTPORT: &str = "dns-block-altport";
const RBIDA_SEL_DNS_BLOCK_CLOUDFLARE: &str = "dns-block-cloudflare";
const RBIDA_SEL_DNS_BLOCK_QUAD9: &str = "dns-block-quad9";
const RBIDA_SEL_DNS_BLOCK_ZONETRANSFER: &str = "dns-block-zonetransfer";
const RBIDA_SEL_DNS_BLOCK_IPV6: &str = "dns-block-ipv6";
const RBIDA_SEL_DNS_BLOCK_MULTICAST: &str = "dns-block-multicast";
const RBIDA_SEL_DNS_BLOCK_SPOOFING: &str = "dns-block-spoofing";
const RBIDA_SEL_DNS_BLOCK_TUNNELING: &str = "dns-block-tunneling";
const RBIDA_SEL_TCP443_CONNECT: &str = "tcp443-connect";
const RBIDA_SEL_TCP443_BLOCK: &str = "tcp443-block";
const RBIDA_SEL_ICMP_FIRST_HOP: &str = "icmp-first-hop";
const RBIDA_SEL_ICMP_SECOND_HOP_BLOCKED: &str = "icmp-second-hop-blocked";
const RBIDA_SEL_DNS_EXFIL_SUBDOMAIN: &str = "dns-exfil-subdomain";
const RBIDA_SEL_META_CLOUD_ENDPOINT: &str = "meta-cloud-endpoint";
const RBIDA_SEL_NET_FORBIDDEN_CIDR: &str = "net-forbidden-cidr";
const RBIDA_SEL_DIRECT_SENTRY_PROBE: &str = "direct-sentry-probe";
const RBIDA_SEL_ICMP_EXFIL_PAYLOAD: &str = "icmp-exfil-payload";
const RBIDA_SEL_NET_IPV6_ESCAPE: &str = "net-ipv6-escape";
const RBIDA_SEL_NET_SRCIP_SPOOF: &str = "net-srcip-spoof";
const RBIDA_SEL_NET_SRCIP_SPOOF_EXTERNAL: &str = "net-srcip-spoof-external";
const RBIDA_SEL_PROTO_SMUGGLE_RAWSOCK: &str = "proto-smuggle-rawsock";
const RBIDA_SEL_NET_FRAGMENT_EVASION: &str = "net-fragment-evasion";
const RBIDA_SEL_DIRECT_ARP_POISON: &str = "direct-arp-poison";
const RBIDA_SEL_NS_CAPABILITY_ESCAPE: &str = "ns-capability-escape";
const RBIDA_SEL_ARP_SEND_GRATUITOUS: &str = "arp-send-gratuitous";
const RBIDA_SEL_ARP_SEND_GATEWAY_POISON: &str = "arp-send-gateway-poison";
const RBIDA_SEL_DNS_FORGE_RESPONSE: &str = "dns-forge-response";
const RBIDA_SEL_MAC_FLOOD_BRIDGE: &str = "mac-flood-bridge";
const RBIDA_SEL_NET_ROUTE_MANIPULATION: &str = "net-route-manipulation";
const RBIDA_SEL_NET_ENCLAVE_SUBNET_ESCAPE: &str = "net-enclave-subnet-escape";
const RBIDA_SEL_NET_DNAT_ENTRY_REFLECTION: &str = "net-dnat-entry-reflection";
const RBIDA_SEL_UDP_NON_DNS_BLOCKED: &str = "udp-non-dns-blocked";
const RBIDA_SEL_CIDR_ALL_PORTS_ALLOWED: &str = "cidr-all-ports-allowed";
const RBIDA_SEL_DNS_REBINDING: &str = "dns-rebinding";
const RBIDA_SEL_PROC_SYS_WRITE: &str = "proc-sys-write";
const RBIDA_SEL_TCP_RST_HIJACK: &str = "tcp-rst-hijack";
const RBIDA_SEL_HTTP_END_TO_END: &str = "http-end-to-end";
const RBIDA_SEL_CONNTRACK_SPOOFED_ACK: &str = "conntrack-spoofed-ack";
const RBIDA_SEL_OFFPATH_BLOCKED_DEST: &str = "offpath-blocked-dest";
const RBIDA_SEL_CONNTRACK_PIPELINE_SELFCHECK: &str = "conntrack-pipeline-selfcheck";
const RBIDA_SEL_SENTRY_UDP_NON_DNS: &str = "sentry-udp-non-dns";

// ── Attack Enum ─────────────────────────────────────────────────

/// Security boundary attack. Each variant probes one aspect of the
/// sentry's network security posture from inside the bottle.
pub enum rbida_Attack {
    /// DNS resolution of www.internic.net should succeed (allowed domain)
    DnsAllowedExample,
    /// DNS resolution of example.org should succeed (second allowed domain — exercises list treatment)
    DnsAllowedExampleOrg,
    /// DNS resolution of google.com should fail (blocked domain)
    DnsBlockedGoogle,
    /// apt-get update should fail (package repos unreachable)
    AptGetBlocked,
    /// Non-existent domain should fail to resolve
    DnsNonexistent,
    /// DNS over TCP should succeed for allowed domains
    DnsTcp,
    /// DNS over UDP should succeed for allowed domains
    DnsUdp,
    /// Direct external DNS queries should fail (both dig and nc)
    DnsBlockDirect,
    /// Alternate DNS port queries should fail
    DnsBlockAltport,
    /// Cloudflare DNS (1.1.1.1) should be blocked
    DnsBlockCloudflare,
    /// Quad9 DNS (9.9.9.9) should be blocked
    DnsBlockQuad9,
    /// Zone transfer attempts should fail
    DnsBlockZonetransfer,
    /// IPv6 DNS servers should be blocked
    DnsBlockIpv6,
    /// Multicast DNS should be blocked
    DnsBlockMulticast,
    /// DNS spoofing source IP should be blocked
    DnsBlockSpoofing,
    /// DNS tunneling via nc should be blocked
    DnsBlockTunneling,
    /// TCP 443 connection to IP should succeed (pass IP in extra_args[0])
    Tcp443Connect,
    /// TCP 443 connection to IP should fail (pass IP in extra_args[0])
    Tcp443Block,
    /// First traceroute hop should be sentry IP or blocked (* * *)
    IcmpFirstHop,
    /// Second traceroute hop should be blocked (* * *)
    IcmpSecondHopBlocked,
    // ── Ported python sorties (rbtis_*.py) ──
    /// DNS exfiltration via subdomain encoding of allowed domains
    DnsExfilSubdomain,
    /// Cloud metadata endpoint probe (169.254.169.254)
    MetaCloudEndpoint,
    /// TCP/UDP to non-allowed CIDRs
    NetForbiddenCidr,
    /// Sentry service enumeration (port scanning)
    DirectSentryProbe,
    /// ICMP covert channel via payload encoding
    IcmpExfilPayload,
    /// IPv6 unconfigured firewall escape
    NetIpv6Escape,
    /// Source IP spoofing via raw sockets
    NetSrcipSpoof,
    /// Spoof source as arbitrary external-routable IP, target sentry's entry
    /// port — probes whether per-IP RETURN exclusion + rp_filter=2 loose
    /// allows DNAT-reflection back to the bottle
    NetSrcipSpoofExternal,
    /// Protocol smuggling via raw sockets (GRE, SCTP, IP-in-IP)
    ProtoSmuggleRawsock,
    /// IP fragment reassembly bypass
    NetFragmentEvasion,
    /// ARP cache poisoning via AF_PACKET
    DirectArpPoison,
    /// Namespace and capability escape probe
    NsCapabilityEscape,
    // ── Coordinated attack primitives (theurge observes effect) ──
    /// Send gratuitous ARP claiming sentry IP — theurge checks sentry ARP table
    ArpSendGratuitous,
    /// Send targeted ARP reply poisoning gateway entry — theurge checks sentry ARP table
    ArpSendGatewayPoison,
    // ── Coordinated integrity primitives (theurge observes sentry state) ──
    /// Send forged DNS responses to sentry's dnsmasq — theurge checks DNS cache
    DnsForgeResponse,
    /// Flood bridge MAC table with random source MACs — theurge checks connectivity
    MacFloodBridge,
    // ── Novel unilateral attacks ──
    /// Route table manipulation — attempt ip route replace/add to bypass sentry gateway
    NetRouteManipulation,
    /// Enclave subnet escape — probe hosts outside /24 enclave within bridge network range
    NetEnclaveSubnetEscape,
    /// DNAT entry port reflection — TCP connect to sentry entry port from inside bottle
    NetDnatEntryReflection,
    // ── Egress control verification ──
    /// UDP datagram to non-allowed IP on non-DNS port should be blocked
    UdpNonDnsBlocked,
    /// TCP to allowed CIDR on multiple ports should succeed (CIDR is protocol-agnostic)
    CidrAllPortsAllowed,
    // ── Advanced adversarial probes ──
    /// DNS rebinding — re-resolve allowed domain to check dnsmasq cache manipulation
    DnsRebinding,
    /// Kernel tunable writes — attempt to modify /proc/sys network parameters
    ProcSysWrite,
    /// TCP RST connection hijack — forge RST packets targeting sentry DNS connection
    TcpRstHijack,
    // ── Network path verification ──
    /// Full HTTP GET from bottle to www.internic.net — proves NAT masquerade returns actual data
    HttpEndToEnd,
    /// Spoofed ACK without prior SYN — conntrack RELATED,ESTABLISHED should drop it
    ConntrackSpoofedAck,
    /// Lone ACK to a blocked destination — negative control proving the
    /// rbsq_wdd_offpath_reply quirk's "blocked dests are dropped before the
    /// substrate sees them" premise; any reply of any provenance is a BREACH
    OffpathBlockedDest,
    /// Self-check of the conntrack provenance capture/classify pipeline — feeds
    /// inspect_capture_frame synthetic frames and asserts correct classification.
    /// Load-bearing control proving SECURE verdicts are not masking a dead detector.
    ConntrackPipelineSelfcheck,
    // ── Sentry self-protection ──
    /// UDP to sentry on non-53 ports — INPUT DROP should block all non-DNS UDP
    SentryUdpNonDns,
}

// ── Verdict ─────────────────────────────────────────────────────

/// Result of running one attack.
pub struct rbida_Verdict {
    pub passed: bool,
    pub detail: String,
}

// ── Selector Mapping ────────────────────────────────────────────

impl rbida_Attack {
    /// Parse a kebab-case selector string into an attack variant.
    pub fn from_selector(s: &str) -> Option<Self> {
        match s {
            RBIDA_SEL_DNS_ALLOWED_EXAMPLE => Some(Self::DnsAllowedExample),
            RBIDA_SEL_DNS_ALLOWED_EXAMPLE_ORG => Some(Self::DnsAllowedExampleOrg),
            RBIDA_SEL_DNS_BLOCKED_GOOGLE => Some(Self::DnsBlockedGoogle),
            RBIDA_SEL_APT_GET_BLOCKED => Some(Self::AptGetBlocked),
            RBIDA_SEL_DNS_NONEXISTENT => Some(Self::DnsNonexistent),
            RBIDA_SEL_DNS_TCP => Some(Self::DnsTcp),
            RBIDA_SEL_DNS_UDP => Some(Self::DnsUdp),
            RBIDA_SEL_DNS_BLOCK_DIRECT => Some(Self::DnsBlockDirect),
            RBIDA_SEL_DNS_BLOCK_ALTPORT => Some(Self::DnsBlockAltport),
            RBIDA_SEL_DNS_BLOCK_CLOUDFLARE => Some(Self::DnsBlockCloudflare),
            RBIDA_SEL_DNS_BLOCK_QUAD9 => Some(Self::DnsBlockQuad9),
            RBIDA_SEL_DNS_BLOCK_ZONETRANSFER => Some(Self::DnsBlockZonetransfer),
            RBIDA_SEL_DNS_BLOCK_IPV6 => Some(Self::DnsBlockIpv6),
            RBIDA_SEL_DNS_BLOCK_MULTICAST => Some(Self::DnsBlockMulticast),
            RBIDA_SEL_DNS_BLOCK_SPOOFING => Some(Self::DnsBlockSpoofing),
            RBIDA_SEL_DNS_BLOCK_TUNNELING => Some(Self::DnsBlockTunneling),
            RBIDA_SEL_TCP443_CONNECT => Some(Self::Tcp443Connect),
            RBIDA_SEL_TCP443_BLOCK => Some(Self::Tcp443Block),
            RBIDA_SEL_ICMP_FIRST_HOP => Some(Self::IcmpFirstHop),
            RBIDA_SEL_ICMP_SECOND_HOP_BLOCKED => Some(Self::IcmpSecondHopBlocked),
            RBIDA_SEL_DNS_EXFIL_SUBDOMAIN => Some(Self::DnsExfilSubdomain),
            RBIDA_SEL_META_CLOUD_ENDPOINT => Some(Self::MetaCloudEndpoint),
            RBIDA_SEL_NET_FORBIDDEN_CIDR => Some(Self::NetForbiddenCidr),
            RBIDA_SEL_DIRECT_SENTRY_PROBE => Some(Self::DirectSentryProbe),
            RBIDA_SEL_ICMP_EXFIL_PAYLOAD => Some(Self::IcmpExfilPayload),
            RBIDA_SEL_NET_IPV6_ESCAPE => Some(Self::NetIpv6Escape),
            RBIDA_SEL_NET_SRCIP_SPOOF => Some(Self::NetSrcipSpoof),
            RBIDA_SEL_NET_SRCIP_SPOOF_EXTERNAL => Some(Self::NetSrcipSpoofExternal),
            RBIDA_SEL_PROTO_SMUGGLE_RAWSOCK => Some(Self::ProtoSmuggleRawsock),
            RBIDA_SEL_NET_FRAGMENT_EVASION => Some(Self::NetFragmentEvasion),
            RBIDA_SEL_DIRECT_ARP_POISON => Some(Self::DirectArpPoison),
            RBIDA_SEL_NS_CAPABILITY_ESCAPE => Some(Self::NsCapabilityEscape),
            RBIDA_SEL_ARP_SEND_GRATUITOUS => Some(Self::ArpSendGratuitous),
            RBIDA_SEL_ARP_SEND_GATEWAY_POISON => Some(Self::ArpSendGatewayPoison),
            RBIDA_SEL_DNS_FORGE_RESPONSE => Some(Self::DnsForgeResponse),
            RBIDA_SEL_MAC_FLOOD_BRIDGE => Some(Self::MacFloodBridge),
            RBIDA_SEL_NET_ROUTE_MANIPULATION => Some(Self::NetRouteManipulation),
            RBIDA_SEL_NET_ENCLAVE_SUBNET_ESCAPE => Some(Self::NetEnclaveSubnetEscape),
            RBIDA_SEL_NET_DNAT_ENTRY_REFLECTION => Some(Self::NetDnatEntryReflection),
            RBIDA_SEL_UDP_NON_DNS_BLOCKED => Some(Self::UdpNonDnsBlocked),
            RBIDA_SEL_CIDR_ALL_PORTS_ALLOWED => Some(Self::CidrAllPortsAllowed),
            RBIDA_SEL_DNS_REBINDING => Some(Self::DnsRebinding),
            RBIDA_SEL_PROC_SYS_WRITE => Some(Self::ProcSysWrite),
            RBIDA_SEL_TCP_RST_HIJACK => Some(Self::TcpRstHijack),
            RBIDA_SEL_HTTP_END_TO_END => Some(Self::HttpEndToEnd),
            RBIDA_SEL_CONNTRACK_SPOOFED_ACK => Some(Self::ConntrackSpoofedAck),
            RBIDA_SEL_OFFPATH_BLOCKED_DEST => Some(Self::OffpathBlockedDest),
            RBIDA_SEL_CONNTRACK_PIPELINE_SELFCHECK => Some(Self::ConntrackPipelineSelfcheck),
            RBIDA_SEL_SENTRY_UDP_NON_DNS => Some(Self::SentryUdpNonDns),
            _ => None,
        }
    }

    /// Kebab-case selector for this attack (inverse of from_selector).
    pub fn selector(&self) -> &'static str {
        match self {
            Self::DnsAllowedExample => RBIDA_SEL_DNS_ALLOWED_EXAMPLE,
            Self::DnsAllowedExampleOrg => RBIDA_SEL_DNS_ALLOWED_EXAMPLE_ORG,
            Self::DnsBlockedGoogle => RBIDA_SEL_DNS_BLOCKED_GOOGLE,
            Self::AptGetBlocked => RBIDA_SEL_APT_GET_BLOCKED,
            Self::DnsNonexistent => RBIDA_SEL_DNS_NONEXISTENT,
            Self::DnsTcp => RBIDA_SEL_DNS_TCP,
            Self::DnsUdp => RBIDA_SEL_DNS_UDP,
            Self::DnsBlockDirect => RBIDA_SEL_DNS_BLOCK_DIRECT,
            Self::DnsBlockAltport => RBIDA_SEL_DNS_BLOCK_ALTPORT,
            Self::DnsBlockCloudflare => RBIDA_SEL_DNS_BLOCK_CLOUDFLARE,
            Self::DnsBlockQuad9 => RBIDA_SEL_DNS_BLOCK_QUAD9,
            Self::DnsBlockZonetransfer => RBIDA_SEL_DNS_BLOCK_ZONETRANSFER,
            Self::DnsBlockIpv6 => RBIDA_SEL_DNS_BLOCK_IPV6,
            Self::DnsBlockMulticast => RBIDA_SEL_DNS_BLOCK_MULTICAST,
            Self::DnsBlockSpoofing => RBIDA_SEL_DNS_BLOCK_SPOOFING,
            Self::DnsBlockTunneling => RBIDA_SEL_DNS_BLOCK_TUNNELING,
            Self::Tcp443Connect => RBIDA_SEL_TCP443_CONNECT,
            Self::Tcp443Block => RBIDA_SEL_TCP443_BLOCK,
            Self::IcmpFirstHop => RBIDA_SEL_ICMP_FIRST_HOP,
            Self::IcmpSecondHopBlocked => RBIDA_SEL_ICMP_SECOND_HOP_BLOCKED,
            Self::DnsExfilSubdomain => RBIDA_SEL_DNS_EXFIL_SUBDOMAIN,
            Self::MetaCloudEndpoint => RBIDA_SEL_META_CLOUD_ENDPOINT,
            Self::NetForbiddenCidr => RBIDA_SEL_NET_FORBIDDEN_CIDR,
            Self::DirectSentryProbe => RBIDA_SEL_DIRECT_SENTRY_PROBE,
            Self::IcmpExfilPayload => RBIDA_SEL_ICMP_EXFIL_PAYLOAD,
            Self::NetIpv6Escape => RBIDA_SEL_NET_IPV6_ESCAPE,
            Self::NetSrcipSpoof => RBIDA_SEL_NET_SRCIP_SPOOF,
            Self::NetSrcipSpoofExternal => RBIDA_SEL_NET_SRCIP_SPOOF_EXTERNAL,
            Self::ProtoSmuggleRawsock => RBIDA_SEL_PROTO_SMUGGLE_RAWSOCK,
            Self::NetFragmentEvasion => RBIDA_SEL_NET_FRAGMENT_EVASION,
            Self::DirectArpPoison => RBIDA_SEL_DIRECT_ARP_POISON,
            Self::NsCapabilityEscape => RBIDA_SEL_NS_CAPABILITY_ESCAPE,
            Self::ArpSendGratuitous => RBIDA_SEL_ARP_SEND_GRATUITOUS,
            Self::ArpSendGatewayPoison => RBIDA_SEL_ARP_SEND_GATEWAY_POISON,
            Self::DnsForgeResponse => RBIDA_SEL_DNS_FORGE_RESPONSE,
            Self::MacFloodBridge => RBIDA_SEL_MAC_FLOOD_BRIDGE,
            Self::NetRouteManipulation => RBIDA_SEL_NET_ROUTE_MANIPULATION,
            Self::NetEnclaveSubnetEscape => RBIDA_SEL_NET_ENCLAVE_SUBNET_ESCAPE,
            Self::NetDnatEntryReflection => RBIDA_SEL_NET_DNAT_ENTRY_REFLECTION,
            Self::UdpNonDnsBlocked => RBIDA_SEL_UDP_NON_DNS_BLOCKED,
            Self::CidrAllPortsAllowed => RBIDA_SEL_CIDR_ALL_PORTS_ALLOWED,
            Self::DnsRebinding => RBIDA_SEL_DNS_REBINDING,
            Self::ProcSysWrite => RBIDA_SEL_PROC_SYS_WRITE,
            Self::TcpRstHijack => RBIDA_SEL_TCP_RST_HIJACK,
            Self::HttpEndToEnd => RBIDA_SEL_HTTP_END_TO_END,
            Self::ConntrackSpoofedAck => RBIDA_SEL_CONNTRACK_SPOOFED_ACK,
            Self::OffpathBlockedDest => RBIDA_SEL_OFFPATH_BLOCKED_DEST,
            Self::ConntrackPipelineSelfcheck => RBIDA_SEL_CONNTRACK_PIPELINE_SELFCHECK,
            Self::SentryUdpNonDns => RBIDA_SEL_SENTRY_UDP_NON_DNS,
        }
    }

    /// All known attack selectors, in definition order.
    pub fn all_selectors() -> &'static [&'static str] {
        &[
            RBIDA_SEL_DNS_ALLOWED_EXAMPLE,
            RBIDA_SEL_DNS_ALLOWED_EXAMPLE_ORG,
            RBIDA_SEL_DNS_BLOCKED_GOOGLE,
            RBIDA_SEL_APT_GET_BLOCKED,
            RBIDA_SEL_DNS_NONEXISTENT,
            RBIDA_SEL_DNS_TCP,
            RBIDA_SEL_DNS_UDP,
            RBIDA_SEL_DNS_BLOCK_DIRECT,
            RBIDA_SEL_DNS_BLOCK_ALTPORT,
            RBIDA_SEL_DNS_BLOCK_CLOUDFLARE,
            RBIDA_SEL_DNS_BLOCK_QUAD9,
            RBIDA_SEL_DNS_BLOCK_ZONETRANSFER,
            RBIDA_SEL_DNS_BLOCK_IPV6,
            RBIDA_SEL_DNS_BLOCK_MULTICAST,
            RBIDA_SEL_DNS_BLOCK_SPOOFING,
            RBIDA_SEL_DNS_BLOCK_TUNNELING,
            RBIDA_SEL_TCP443_CONNECT,
            RBIDA_SEL_TCP443_BLOCK,
            RBIDA_SEL_ICMP_FIRST_HOP,
            RBIDA_SEL_ICMP_SECOND_HOP_BLOCKED,
            RBIDA_SEL_DNS_EXFIL_SUBDOMAIN,
            RBIDA_SEL_META_CLOUD_ENDPOINT,
            RBIDA_SEL_NET_FORBIDDEN_CIDR,
            RBIDA_SEL_DIRECT_SENTRY_PROBE,
            RBIDA_SEL_ICMP_EXFIL_PAYLOAD,
            RBIDA_SEL_NET_IPV6_ESCAPE,
            RBIDA_SEL_NET_SRCIP_SPOOF,
            RBIDA_SEL_NET_SRCIP_SPOOF_EXTERNAL,
            RBIDA_SEL_PROTO_SMUGGLE_RAWSOCK,
            RBIDA_SEL_NET_FRAGMENT_EVASION,
            RBIDA_SEL_DIRECT_ARP_POISON,
            RBIDA_SEL_NS_CAPABILITY_ESCAPE,
            RBIDA_SEL_ARP_SEND_GRATUITOUS,
            RBIDA_SEL_ARP_SEND_GATEWAY_POISON,
            RBIDA_SEL_DNS_FORGE_RESPONSE,
            RBIDA_SEL_MAC_FLOOD_BRIDGE,
            RBIDA_SEL_NET_ROUTE_MANIPULATION,
            RBIDA_SEL_NET_ENCLAVE_SUBNET_ESCAPE,
            RBIDA_SEL_NET_DNAT_ENTRY_REFLECTION,
            RBIDA_SEL_UDP_NON_DNS_BLOCKED,
            RBIDA_SEL_CIDR_ALL_PORTS_ALLOWED,
            RBIDA_SEL_DNS_REBINDING,
            RBIDA_SEL_PROC_SYS_WRITE,
            RBIDA_SEL_TCP_RST_HIJACK,
            RBIDA_SEL_HTTP_END_TO_END,
            RBIDA_SEL_CONNTRACK_SPOOFED_ACK,
            RBIDA_SEL_SENTRY_UDP_NON_DNS,
        ]
    }
}

// ── Dispatch ────────────────────────────────────────────────────

/// Run the specified attack and return its verdict.
/// Exhaustive match — adding a variant without handling is a compile error.
/// extra_args: optional additional parameters (e.g. IP address for tcp443 attacks)
pub fn rbida_run(attack: &rbida_Attack, extra_args: &[&str]) -> rbida_Verdict {
    match attack {
        rbida_Attack::DnsAllowedExample => rbida_expect_command_succeeds(
            "getent",
            &["hosts", RBIDA_CONNECTIVITY_DOMAIN],
            &format!("DNS resolution of {} (allowed domain)", RBIDA_CONNECTIVITY_DOMAIN),
        ),
        rbida_Attack::DnsAllowedExampleOrg => rbida_expect_command_succeeds(
            "getent",
            &["hosts", "example.org"],
            "DNS resolution of example.org (second allowed domain)",
        ),
        rbida_Attack::DnsBlockedGoogle => rbida_expect_command_fails(
            "getent",
            &["hosts", "google.com"],
            "DNS resolution of google.com (blocked domain)",
        ),
        rbida_Attack::AptGetBlocked => rbida_expect_command_fails(
            "timeout",
            &["5", "apt-get", "-qq", "update"],
            "apt-get update (package repos unreachable)",
        ),
        rbida_Attack::DnsNonexistent => rbida_expect_command_fails(
            "getent",
            &["hosts", "nonexistentdomain123.test"],
            "DNS resolution of nonexistentdomain123.test (non-existent domain)",
        ),
        rbida_Attack::DnsTcp => rbida_expect_command_succeeds(
            "dig",
            &["+tcp", RBIDA_CONNECTIVITY_DOMAIN],
            &format!("DNS over TCP for {} (allowed domain)", RBIDA_CONNECTIVITY_DOMAIN),
        ),
        rbida_Attack::DnsUdp => rbida_expect_command_succeeds(
            "dig",
            &["+notcp", RBIDA_CONNECTIVITY_DOMAIN],
            &format!("DNS over UDP for {} (allowed domain)", RBIDA_CONNECTIVITY_DOMAIN),
        ),
        rbida_Attack::DnsBlockDirect => rbida_expect_all_fail(
            &[
                ("dig", &["@8.8.8.8", RBIDA_CONNECTIVITY_DOMAIN] as &[&str]),
                ("nc", &["-w", "2", "-zv", "8.8.8.8", "53"]),
            ],
            "direct external DNS query bypass (dig @8.8.8.8 and nc 8.8.8.8:53)",
        ),
        rbida_Attack::DnsBlockAltport => rbida_expect_all_fail(
            &[
                ("dig", &["@8.8.8.8", "-p", "5353", RBIDA_CONNECTIVITY_DOMAIN] as &[&str]),
                ("dig", &["@8.8.8.8", "-p", "443", RBIDA_CONNECTIVITY_DOMAIN]),
            ],
            "alternate DNS port bypass (ports 5353 and 443)",
        ),
        rbida_Attack::DnsBlockCloudflare => rbida_expect_command_fails(
            "dig",
            &["@1.1.1.1", RBIDA_CONNECTIVITY_DOMAIN],
            "Cloudflare DNS bypass (1.1.1.1)",
        ),
        rbida_Attack::DnsBlockQuad9 => rbida_expect_command_fails(
            "dig",
            &["@9.9.9.9", RBIDA_CONNECTIVITY_DOMAIN],
            "Quad9 DNS bypass (9.9.9.9)",
        ),
        rbida_Attack::DnsBlockZonetransfer => rbida_expect_command_fails(
            "dig",
            &["@8.8.8.8", RBIDA_CONNECTIVITY_DOMAIN, "AXFR"],
            "DNS zone transfer attempt",
        ),
        rbida_Attack::DnsBlockIpv6 => rbida_expect_command_fails(
            "dig",
            &["@2001:4860:4860::8888", RBIDA_CONNECTIVITY_DOMAIN],
            "IPv6 DNS server bypass (2001:4860:4860::8888)",
        ),
        rbida_Attack::DnsBlockMulticast => rbida_expect_command_fails(
            "dig",
            &["@224.0.0.251", "-p", "5353", "example.local"],
            "multicast DNS bypass (224.0.0.251:5353)",
        ),
        rbida_Attack::DnsBlockSpoofing => rbida_expect_command_fails(
            "dig",
            &["@8.8.8.8", "+nsid", RBIDA_CONNECTIVITY_DOMAIN, "-b", "192.168.1.2"],
            "DNS spoofing source IP bypass",
        ),
        rbida_Attack::DnsBlockTunneling => rbida_expect_command_fails(
            "nc",
            &["-z", "-w", "1", "8.8.8.8", "53"],
            "DNS tunneling via nc to 8.8.8.8:53",
        ),
        rbida_Attack::Tcp443Connect => {
            let ip = extra_args.first().copied().unwrap_or("");
            if ip.is_empty() {
                return rbida_Verdict {
                    passed: false,
                    detail: "ERROR: tcp443-connect requires IP address as extra arg".to_string(),
                };
            }
            rbida_expect_command_succeeds(
                "nc",
                &["-w", "2", "-zv", ip, "443"],
                &format!("TCP 443 connection to {} (should be allowed)", ip),
            )
        }
        rbida_Attack::Tcp443Block => {
            let ip = extra_args.first().copied().unwrap_or("");
            if ip.is_empty() {
                return rbida_Verdict {
                    passed: false,
                    detail: "ERROR: tcp443-block requires IP address as extra arg".to_string(),
                };
            }
            rbida_expect_command_fails(
                "nc",
                &["-w", "2", "-zv", ip, "443"],
                &format!("TCP 443 connection to {} (should be blocked)", ip),
            )
        }
        rbida_Attack::IcmpFirstHop => rbida_check_icmp_first_hop(),
        rbida_Attack::IcmpSecondHopBlocked => rbida_check_icmp_second_hop_blocked(),
        // Ported python sorties
        rbida_Attack::DnsExfilSubdomain => rbida_sorties::sortie_dns_exfil_subdomain(extra_args),
        rbida_Attack::MetaCloudEndpoint => rbida_sorties::sortie_meta_cloud_endpoint(extra_args),
        rbida_Attack::NetForbiddenCidr => rbida_sorties::sortie_net_forbidden_cidr(extra_args),
        rbida_Attack::DirectSentryProbe => rbida_sorties::sortie_direct_sentry_probe(extra_args),
        rbida_Attack::IcmpExfilPayload => rbida_sorties::sortie_icmp_exfil_payload(extra_args),
        rbida_Attack::NetIpv6Escape => rbida_sorties::sortie_net_ipv6_escape(extra_args),
        rbida_Attack::NetSrcipSpoof => rbida_sorties::sortie_net_srcip_spoof(extra_args),
        rbida_Attack::NetSrcipSpoofExternal => rbida_sorties::sortie_net_srcip_spoof_external(extra_args),
        rbida_Attack::ProtoSmuggleRawsock => rbida_sorties::sortie_proto_smuggle_rawsock(extra_args),
        rbida_Attack::NetFragmentEvasion => rbida_sorties::sortie_net_fragment_evasion(extra_args),
        rbida_Attack::DirectArpPoison => rbida_sorties::sortie_direct_arp_poison(extra_args),
        rbida_Attack::NsCapabilityEscape => rbida_sorties::sortie_ns_capability_escape(extra_args),
        // Coordinated attack primitives — execute action, theurge judges outcome
        rbida_Attack::ArpSendGratuitous => rbida_sorties::sortie_arp_send_gratuitous(extra_args),
        rbida_Attack::ArpSendGatewayPoison => rbida_sorties::sortie_arp_send_gateway_poison(extra_args),
        // Coordinated integrity primitives — execute action, theurge judges state
        rbida_Attack::DnsForgeResponse => rbida_sorties::sortie_dns_forge_response(extra_args),
        rbida_Attack::MacFloodBridge => rbida_sorties::sortie_mac_flood_bridge(extra_args),
        // Novel unilateral attacks
        rbida_Attack::NetRouteManipulation => rbida_sorties::sortie_net_route_manipulation(extra_args),
        rbida_Attack::NetEnclaveSubnetEscape => rbida_sorties::sortie_net_enclave_subnet_escape(extra_args),
        rbida_Attack::NetDnatEntryReflection => rbida_sorties::sortie_net_dnat_entry_reflection(extra_args),
        // Egress control verification
        rbida_Attack::UdpNonDnsBlocked => rbida_sorties::sortie_udp_non_dns_blocked(extra_args),
        rbida_Attack::CidrAllPortsAllowed => rbida_sorties::sortie_cidr_all_ports_allowed(extra_args),
        // Advanced adversarial probes
        rbida_Attack::DnsRebinding => rbida_sorties::sortie_dns_rebinding(extra_args),
        rbida_Attack::ProcSysWrite => rbida_sorties::sortie_proc_sys_write(extra_args),
        rbida_Attack::TcpRstHijack => rbida_sorties::sortie_tcp_rst_hijack(extra_args),
        // Network path verification
        rbida_Attack::HttpEndToEnd => rbida_sorties::sortie_http_end_to_end(extra_args),
        rbida_Attack::ConntrackSpoofedAck => rbida_sorties::sortie_conntrack_spoofed_ack(extra_args),
        rbida_Attack::OffpathBlockedDest => rbida_sorties::sortie_offpath_blocked_dest(extra_args),
        rbida_Attack::ConntrackPipelineSelfcheck => {
            rbida_sorties::sortie_conntrack_pipeline_selfcheck(extra_args)
        }
        rbida_Attack::SentryUdpNonDns => rbida_sorties::sortie_sentry_udp_non_dns(extra_args),
    }
}

// ── Attack Helpers ──────────────────────────────────────────────

/// Run a command and expect it to succeed (exit 0).
/// PASS when the security boundary correctly allows the operation.
fn rbida_expect_command_succeeds(cmd: &str, args: &[&str], description: &str) -> rbida_Verdict {
    match Command::new(cmd).args(args).output() {
        Ok(output) => {
            if output.status.success() {
                rbida_Verdict {
                    passed: true,
                    detail: format!("SECURE: {}", description),
                }
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                rbida_Verdict {
                    passed: false,
                    detail: format!(
                        "BREACH: {} — command failed (exit {}): {}",
                        description,
                        output.status.code().unwrap_or(-1),
                        stderr.trim()
                    ),
                }
            }
        }
        Err(e) => rbida_Verdict {
            passed: false,
            detail: format!("ERROR: {} — failed to execute '{}': {}", description, cmd, e),
        },
    }
}

/// Run a command and expect it to fail (nonzero exit).
/// PASS when the security boundary correctly blocks the operation.
fn rbida_expect_command_fails(cmd: &str, args: &[&str], description: &str) -> rbida_Verdict {
    match Command::new(cmd).args(args).output() {
        Ok(output) => {
            if output.status.success() {
                rbida_Verdict {
                    passed: false,
                    detail: format!("BREACH: {} — command succeeded unexpectedly", description),
                }
            } else {
                rbida_Verdict {
                    passed: true,
                    detail: format!("SECURE: {}", description),
                }
            }
        }
        Err(e) => rbida_Verdict {
            passed: false,
            detail: format!("ERROR: {} — failed to execute '{}': {}", description, cmd, e),
        },
    }
}

/// Run multiple commands and require ALL to fail (nonzero exit).
/// PASS only when the security boundary blocks every attempted bypass.
fn rbida_expect_all_fail(checks: &[(&str, &[&str])], description: &str) -> rbida_Verdict {
    for (cmd, args) in checks {
        match Command::new(cmd).args(*args).output() {
            Ok(output) => {
                if output.status.success() {
                    return rbida_Verdict {
                        passed: false,
                        detail: format!(
                            "BREACH: {} — '{}' succeeded unexpectedly",
                            description, cmd
                        ),
                    };
                }
                // This command failed as expected; continue checking the rest
            }
            Err(e) => {
                return rbida_Verdict {
                    passed: false,
                    detail: format!(
                        "ERROR: {} — failed to execute '{}': {}",
                        description, cmd, e
                    ),
                };
            }
        }
    }
    rbida_Verdict {
        passed: true,
        detail: format!("SECURE: {}", description),
    }
}

/// Run traceroute -I -m 1 and verify first hop is sentry IP or * * *.
/// Reads sentry IP from /etc/resolv.conf nameserver line.
fn rbida_check_icmp_first_hop() -> rbida_Verdict {
    // Discover sentry IP from resolv.conf
    let sentry_ip = match rbida_read_nameserver() {
        Ok(ip) => ip,
        Err(e) => {
            return rbida_Verdict {
                passed: false,
                detail: format!("ERROR: icmp-first-hop — cannot read sentry IP: {}", e),
            }
        }
    };

    let output = match Command::new("traceroute")
        .args(["-I", "-m", "1", "8.8.8.8"])
        .output()
    {
        Ok(o) => o,
        Err(e) => {
            return rbida_Verdict {
                passed: false,
                detail: format!("ERROR: icmp-first-hop — failed to execute traceroute: {}", e),
            }
        }
    };

    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    // Accept sentry IP visible OR fully blocked (* * *)
    if combined.contains(&sentry_ip) {
        return rbida_Verdict {
            passed: true,
            detail: format!(
                "SECURE: icmp-first-hop — sentry IP {} visible in traceroute",
                sentry_ip
            ),
        };
    }

    // Check for "1  * * *" pattern (blocked at first hop)
    for line in combined.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("1 ") || trimmed.starts_with("1\t") {
            if trimmed.contains("* * *") {
                return rbida_Verdict {
                    passed: true,
                    detail: "SECURE: icmp-first-hop — first hop blocked (* * *)".to_string(),
                };
            }
        }
    }

    rbida_Verdict {
        passed: false,
        detail: format!(
            "BREACH: icmp-first-hop — unexpected traceroute output (expected sentry IP {} or * * *):\n{}",
            sentry_ip, combined
        ),
    }
}

/// Run traceroute -I -m 2 and verify second hop is * * * (blocked).
fn rbida_check_icmp_second_hop_blocked() -> rbida_Verdict {
    let output = match Command::new("traceroute")
        .args(["-I", "-m", "2", "8.8.8.8"])
        .output()
    {
        Ok(o) => o,
        Err(e) => {
            return rbida_Verdict {
                passed: false,
                detail: format!(
                    "ERROR: icmp-second-hop-blocked — failed to execute traceroute: {}",
                    e
                ),
            }
        }
    };

    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    // Check for "2  * * *" pattern
    for line in combined.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("2 ") || trimmed.starts_with("2\t") {
            if trimmed.contains("* * *") {
                return rbida_Verdict {
                    passed: true,
                    detail: "SECURE: icmp-second-hop-blocked — second hop blocked (* * *)".to_string(),
                };
            }
        }
    }

    rbida_Verdict {
        passed: false,
        detail: format!(
            "BREACH: icmp-second-hop-blocked — expected blocked second hop (* * *) in traceroute:\n{}",
            combined
        ),
    }
}

/// Read the nameserver IP from /etc/resolv.conf.
/// Returns the first nameserver entry found.
fn rbida_read_nameserver() -> Result<String, String> {
    let content = std::fs::read_to_string("/etc/resolv.conf")
        .map_err(|e| format!("cannot read /etc/resolv.conf: {}", e))?;

    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("nameserver") {
            let ip = rest.trim();
            if !ip.is_empty() {
                return Ok(ip.to_string());
            }
        }
    }

    Err("no nameserver entry found in /etc/resolv.conf".to_string())
}
