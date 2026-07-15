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
# RBTIS - Namespace and capability probe
#
# Sortie: ns_capability_escape
# Front: namespace

import os
import subprocess


def _read_proc(path):
    """Read a /proc or /sys file, return content or None."""
    try:
        with open(path) as f:
            return f.read().strip()
    except (FileNotFoundError, PermissionError, OSError):
        return None


def _write_test(path, value):
    """Test if a /proc or /sys path is writable (without actually changing it)."""
    try:
        with open(path, "w") as f:
            # Don't actually write — just test open-for-write
            pass
        return True
    except (PermissionError, OSError):
        return False


def _parse_capabilities(hex_str):
    """Parse capability hex string into list of capability names."""
    cap_names = {
        0: "CAP_CHOWN", 1: "CAP_DAC_OVERRIDE", 2: "CAP_DAC_READ_SEARCH",
        3: "CAP_FOWNER", 5: "CAP_KILL", 6: "CAP_SETGID", 7: "CAP_SETUID",
        8: "CAP_SETPCAP", 10: "CAP_NET_BIND_SERVICE", 12: "CAP_NET_ADMIN",
        13: "CAP_NET_RAW", 14: "CAP_IPC_LOCK", 16: "CAP_SYS_MODULE",
        17: "CAP_SYS_RAWIO", 18: "CAP_SYS_CHROOT", 19: "CAP_SYS_PTRACE",
        21: "CAP_SYS_ADMIN", 22: "CAP_SYS_BOOT", 23: "CAP_SYS_NICE",
        24: "CAP_SYS_RESOURCE", 25: "CAP_SYS_TIME", 29: "CAP_AUDIT_WRITE",
        37: "CAP_MKNOD", 38: "CAP_LEASE", 40: "CAP_BPF",
    }
    try:
        bits = int(hex_str, 16)
    except (ValueError, TypeError):
        return []
    present = []
    for bit, name in sorted(cap_names.items()):
        if bits & (1 << bit):
            present.append(name)
    return present


def run():
    """Namespace and capability probe — test container escape via kernel interfaces.

    Vector:
      The bottle runs inside a Docker container. Network firewalls are
      irrelevant if the container can break out of its namespace. This sortie
      checks:

        1. Linux capabilities: CAP_SYS_ADMIN enables namespace creation,
           mount operations, and BPF program loading. CAP_NET_ADMIN enables
           iptables manipulation from inside the bottle (add rules, flush
           the sentry's firewall if in the same network namespace).

        2. Writable /proc/sys/net paths: If ip_forward is writable, the
           bottle could become a router. If other sysctl knobs are writable,
           the attacker can modify kernel network behavior.

        3. Docker socket: /var/run/docker.sock would allow full container
           escape via the Docker API (create a privileged container, mount
           host filesystem).

        4. Host PID namespace: If /proc shows host processes (PID 1 is
           systemd/init, not the bottle's entrypoint), the container shares
           the host PID namespace — enabling ptrace attacks.

        5. Namespace files: If /proc/1/ns/* is readable and points to the
           same namespaces as the bottle, namespace isolation may be absent.

      This is the "go around the wall" approach — ignore the firewall
      entirely and escape the container.

    Detection logic:
      - CAP_SYS_ADMIN or CAP_NET_ADMIN present    -> BREACH
      - Writable network sysctl paths              -> BREACH
      - Docker socket accessible                   -> BREACH
      - Host PID namespace visible                  -> BREACH
      - All restricted                              -> SECURE
    """
    assertions = []

    # Test 1: Parse effective capabilities
    status = _read_proc("/proc/self/status")
    cap_eff_hex = None
    if status:
        for line in status.splitlines():
            if line.startswith("CapEff:"):
                cap_eff_hex = line.split(":")[1].strip()
                break

    caps = _parse_capabilities(cap_eff_hex) if cap_eff_hex else []
    dangerous_caps = [c for c in caps if c in (
        "CAP_SYS_ADMIN", "CAP_NET_ADMIN", "CAP_SYS_PTRACE",
        "CAP_SYS_MODULE", "CAP_SYS_RAWIO", "CAP_BPF"
    )]

    assertions.append({
        "name": "no_dangerous_capabilities",
        "passed": len(dangerous_caps) == 0,
        "detail": f"Effective capabilities: {', '.join(caps) if caps else 'none'}"
                  + (f" — DANGEROUS: {', '.join(dangerous_caps)}" if dangerous_caps else ""),
    })

    # Note: CAP_NET_RAW is expected (scapy needs it) — only flag the admin/escape caps
    has_net_raw = "CAP_NET_RAW" in caps
    assertions.append({
        "name": "cap_net_raw_present",
        "passed": True,  # informational — expected for ifrit bottle
        "detail": f"CAP_NET_RAW: {'present (expected for scapy)' if has_net_raw else 'absent'}",
    })

    # Test 2: Writable network sysctl paths
    writable_sysctls = []
    sysctl_paths = [
        "/proc/sys/net/ipv4/ip_forward",
        "/proc/sys/net/ipv4/conf/all/forwarding",
        "/proc/sys/net/ipv4/conf/all/rp_filter",
        "/proc/sys/net/ipv4/conf/all/accept_redirects",
        "/proc/sys/net/ipv4/conf/all/send_redirects",
        "/proc/sys/net/ipv4/ip_local_port_range",
        "/proc/sys/net/ipv6/conf/all/disable_ipv6",
        "/proc/sys/net/ipv6/conf/all/forwarding",
    ]
    for path in sysctl_paths:
        current = _read_proc(path)
        if current is not None and _write_test(path, current):
            writable_sysctls.append(path)

    assertions.append({
        "name": "no_writable_net_sysctls",
        "passed": len(writable_sysctls) == 0,
        "detail": f"Writable network sysctls: {writable_sysctls if writable_sysctls else 'none'}"
                  + (" — could modify kernel network behavior" if writable_sysctls else ""),
    })

    # Test 3: Docker socket
    docker_paths = [
        "/var/run/docker.sock",
        "/run/docker.sock",
        "/var/run/containerd/containerd.sock",
    ]
    socket_found = []
    for path in docker_paths:
        if os.path.exists(path):
            socket_found.append(path)

    assertions.append({
        "name": "no_docker_socket",
        "passed": len(socket_found) == 0,
        "detail": f"Container runtime sockets: {socket_found if socket_found else 'none found'}"
                  + (" — FULL CONTAINER ESCAPE POSSIBLE" if socket_found else ""),
    })

    # Test 4: Host PID namespace check
    # Read /proc/1/cmdline — if it's systemd/init, we're in host PID namespace
    pid1_cmd = _read_proc("/proc/1/cmdline")
    if pid1_cmd:
        # cmdline is null-separated
        pid1_name = pid1_cmd.split("\x00")[0]
        is_host_pid = any(x in pid1_name for x in ["systemd", "init", "launchd"])
    else:
        pid1_name = "unreadable"
        is_host_pid = False

    assertions.append({
        "name": "isolated_pid_namespace",
        "passed": not is_host_pid,
        "detail": f"PID 1 command: {pid1_name}"
                  + (" — HOST PID NAMESPACE (not isolated)" if is_host_pid
                     else " — container PID namespace (isolated)" if pid1_cmd
                     else " — unreadable (likely isolated)"),
    })

    # Test 5: Namespace isolation check
    # In a container, PID 1 is the container init (e.g. socat), so sharing
    # namespaces with PID 1 is expected. The real question is whether we can
    # see host processes (high PIDs for systemd, sshd, dockerd) or access
    # host-level namespace files.
    host_processes_visible = False
    host_indicators = ["systemd", "sshd", "dockerd", "containerd", "kubelet"]
    try:
        for pid_dir in os.listdir("/proc"):
            if not pid_dir.isdigit():
                continue
            try:
                cmdline = _read_proc(f"/proc/{pid_dir}/cmdline")
                if cmdline:
                    for indicator in host_indicators:
                        if indicator in cmdline:
                            host_processes_visible = True
                            break
            except (OSError, PermissionError):
                pass
            if host_processes_visible:
                break
    except OSError:
        pass

    assertions.append({
        "name": "namespace_isolation",
        "passed": not host_processes_visible,
        "detail": f"Host processes visible: {'YES — host PID namespace shared' if host_processes_visible else 'no (container isolated)'}",
    })

    # Test 6: Can we manipulate iptables from inside the bottle?
    iptables_works = False
    try:
        result = subprocess.run(
            ["iptables", "-L", "-n"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            iptables_works = True
    except (FileNotFoundError, PermissionError):
        pass

    assertions.append({
        "name": "iptables_not_accessible",
        "passed": not iptables_works,
        "detail": f"iptables from bottle: "
                  + ("ACCESSIBLE — could flush sentry rules" if iptables_works
                     else "not accessible (correct)"),
    })

    # Test 7: /sys/class/net — can we see host interfaces?
    try:
        interfaces = os.listdir("/sys/class/net")
    except (OSError, PermissionError):
        interfaces = []
    # In a properly isolated container, we should only see lo + enclave iface
    extra_ifaces = [i for i in interfaces if i not in ("lo",) and not i.startswith("eth")]
    assertions.append({
        "name": "no_host_interfaces_visible",
        "passed": len(extra_ifaces) == 0,
        "detail": f"Network interfaces: {interfaces}"
                  + (f" — unexpected: {extra_ifaces}" if extra_ifaces else ""),
    })

    all_passed = all(a["passed"] for a in assertions)
    return {
        "verdict": "SECURE" if all_passed else "BREACH",
        "detail": "Container isolation intact — no namespace or capability escape"
                  if all_passed
                  else "Container isolation BROKEN — escape vectors available",
        "assertions": assertions,
    }
