#!/bin/bash
#
# Copyright 2025 Scale Invariant, Inc.
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
# RBOO - Recipe Bottle Orchestration Observe
# Network observation (tcpdump) for crucibles
#
# Requires: buc_command.sh sourced
# Requires: rbob_bottle.sh sourced and kindled

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBOO_SOURCED:-}" || buc_die "Module rboo multiply sourced - check sourcing hierarchy"
ZRBOO_SOURCED=1

######################################################################
# Kindle and Sentinel

zrboo_kindle() {
  test -z "${ZRBOO_KINDLED:-}" || buc_die "Module rboo already kindled"

  # Verify RBOB is kindled (provides container names, runtime)
  zrbob_sentinel

  # Terminal control sequences for colored output (ANSI literals, matching BUC constants)
  readonly ZRBOO_BOLD=$'\033[1m'
  readonly ZRBOO_YELLOW=$'\033[33m'
  readonly ZRBOO_BLUE=$'\033[34m'
  readonly ZRBOO_WHITE=$'\033[37m'
  readonly ZRBOO_CYAN=$'\033[36m'
  readonly ZRBOO_RESET=$'\033[0m'

  # Common tcpdump options: unbuffered, line-buffered, no name resolution,
  # verbose, and -e to show L2 source MACs (off-path delivery is otherwise
  # only inferable from absence, not demonstrable).
  ZRBOO_TCPDUMP_OPTS=(-U -l -nn -vvv -e)
  readonly ZRBOO_TCPDUMP_OPTS

  # Scry interface-discovery captures land here (BCG temp-file capture pattern).
  readonly ZRBOO_SCRY_PREFIX="${BURD_TEMP_DIR}/rboo_scry_"

  # Bridge interface (only for podman, discovered at observe time)
  z_rboo_bridge_interface=""

  readonly ZRBOO_KINDLED=1
}

zrboo_sentinel() {
  test "${ZRBOO_KINDLED:-}" = "1" || buc_die "Module rboo not kindled - call zrboo_kindle first"
}

######################################################################
# Output Prefixing

# Tag every captured line with a colored leg label.
#   $1  ANSI color sequence (a ZRBOO_* constant)
#   $2  leg label shown in brackets
zrboo_prefix() {
  local z_color="$1"
  local z_label="$2"
  local line
  while IFS= read -r line; do
    echo "${z_color}${ZRBOO_BOLD}[${z_label}]${ZRBOO_RESET} ${line}"
  done
}

######################################################################
# Public API

# Observe network traffic on crucible containers; all captures run in parallel.
#
# Usage: rboo_observe [duration] [filter]
#   duration  optional bounded window (e.g. 10, 30s, 1m). When supplied, every
#             capture runs under `timeout` and the function returns 0 once the
#             window elapses — a scriptable primitive a fixture or operator
#             one-liner can drive. Omitted: run until Ctrl+C, as before.
#   filter    optional tcpdump filter expression applied to every leg, so a
#             scoped capture (e.g. one host) stays legible.
rboo_observe() {
  zrboo_sentinel

  local z_duration="${1:-}"
  local z_filter="${2:-}"

  buc_step "Starting network observation: ${RBRN_MONIKER}"

  # Discover sentry interface roles by IP inside the container — Docker does
  # not guarantee eth0/eth1 ordering (on the WSL native-docker host the two are
  # reversed), so resolve by role the way rbjs_sentry.sh does, never by name.
  # BCG: external command output goes to temp files, never command substitution.
  local z_enclave_file="${ZRBOO_SCRY_PREFIX}enclave_addr.txt"
  local z_enclave_stderr="${ZRBOO_SCRY_PREFIX}enclave_stderr.txt"
  "${ZRBOB_RUNTIME}" exec "${ZRBOB_SENTRY}" \
    ip -o addr show to "${RBRN_ENCLAVE_SENTRY_IP}" \
    > "${z_enclave_file}" 2>"${z_enclave_stderr}" \
    || buc_die "scry: cannot query Sentry interfaces (is the Crucible charged?) — see ${z_enclave_stderr}"

  # ip -o emits "<idx>: <ifname> ..."; the first line's second field is the leg.
  local z_if_idx=""
  local z_if_rest=""
  local z_sentry_enclave_if=""
  read -r z_if_idx z_sentry_enclave_if z_if_rest < "${z_enclave_file}" || true
  test -n "${z_sentry_enclave_if}" \
    || buc_die "scry: no Sentry interface holds enclave IP ${RBRN_ENCLAVE_SENTRY_IP} (is the Crucible charged?)"

  local z_uplink_file="${ZRBOO_SCRY_PREFIX}uplink_addr.txt"
  local z_uplink_stderr="${ZRBOO_SCRY_PREFIX}uplink_stderr.txt"
  "${ZRBOB_RUNTIME}" exec "${ZRBOB_SENTRY}" \
    ip -o -4 addr show scope global \
    > "${z_uplink_file}" 2>"${z_uplink_stderr}" \
    || buc_die "scry: cannot query Sentry uplink interfaces — see ${z_uplink_stderr}"

  # First global interface whose name differs from the enclave leg is the uplink.
  local z_ifname=""
  local z_sentry_uplink_if=""
  while read -r z_if_idx z_ifname z_if_rest || test -n "${z_if_idx}"; do
    test -n "${z_ifname}" || continue
    if test "${z_ifname}" != "${z_sentry_enclave_if}"; then
      z_sentry_uplink_if="${z_ifname}"
      break
    fi
  done < "${z_uplink_file}"
  test -n "${z_sentry_uplink_if}" \
    || buc_die "scry: no Sentry uplink interface found (enclave=${z_sentry_enclave_if})"

  buc_info "Network topology:"
  buc_info "  SENTRY:          enclave=${z_sentry_enclave_if} uplink=${z_sentry_uplink_if}"
  buc_info "  PENTACLE/BOTTLE: shared namespace on enclave (eth0)"
  test -z "${z_duration}" || buc_info "  Bounded capture: ${z_duration}"
  test -z "${z_filter}"   || buc_info "  Filter:          ${z_filter}"

  # tcpdump reads the filter from its trailing args; include it only when
  # non-empty so an empty expression never reaches tcpdump.
  local -a z_filter_args=()
  test -z "${z_filter}" || z_filter_args=("${z_filter}")

  # Bounded mode wraps each in-container capture in `timeout`; interactive mode
  # runs until Ctrl+C via the cleanup trap.
  local -a z_timeout=()
  if test -n "${z_duration}"; then
    z_timeout=(timeout "${z_duration}")
  else
    trap 'buc_info "Stopping captures..."; kill 0 2>/dev/null; exit 0' SIGINT SIGTERM
  fi

  # Pentacle/bottle leg — shared namespace with the bottle, enclave-only.
  buc_info "Starting Pentacle/Bottle capture (eth0)"
  "${ZRBOB_RUNTIME}" exec "${ZRBOB_PENTACLE}" ${z_timeout[@]+"${z_timeout[@]}"} \
    tcpdump "${ZRBOO_TCPDUMP_OPTS[@]}" -i eth0 ${z_filter_args[@]+"${z_filter_args[@]}"} \
    2>&1 | zrboo_prefix "${ZRBOO_YELLOW}" "PENTACLE/BOTTLE" &

  # Both sentry legs — enclave and uplink — so the full enclave<->uplink path
  # is visible in one run (previously enclave-only).
  buc_info "Starting Sentry enclave capture (${z_sentry_enclave_if})"
  "${ZRBOB_RUNTIME}" exec "${ZRBOB_SENTRY}" ${z_timeout[@]+"${z_timeout[@]}"} \
    tcpdump "${ZRBOO_TCPDUMP_OPTS[@]}" -i "${z_sentry_enclave_if}" ${z_filter_args[@]+"${z_filter_args[@]}"} \
    2>&1 | zrboo_prefix "${ZRBOO_WHITE}" "SENTRY/ENCLAVE" &

  buc_info "Starting Sentry uplink capture (${z_sentry_uplink_if})"
  "${ZRBOB_RUNTIME}" exec "${ZRBOB_SENTRY}" ${z_timeout[@]+"${z_timeout[@]}"} \
    tcpdump "${ZRBOO_TCPDUMP_OPTS[@]}" -i "${z_sentry_uplink_if}" ${z_filter_args[@]+"${z_filter_args[@]}"} \
    2>&1 | zrboo_prefix "${ZRBOO_CYAN}" "SENTRY/UPLINK" &

  # Bridge capture: only for podman (requires podman machine ssh). Built as a
  # single ssh command string, so timeout/opts/filter are spliced in textually.
  if test "${RBRN_RUNTIME}" = "podman"; then
    # BCG: capture network-inspect output to a temp file, never command substitution.
    local z_bridge_if_file="${ZRBOO_SCRY_PREFIX}bridge_if.txt"
    local z_bridge_if_stderr="${ZRBOO_SCRY_PREFIX}bridge_if_stderr.txt"
    "${ZRBOB_RUNTIME}" network inspect "${ZRBOB_NETWORK}" --format '{{.NetworkInterface}}' \
      > "${z_bridge_if_file}" 2>"${z_bridge_if_stderr}" \
      || buc_die "scry: cannot inspect network ${ZRBOB_NETWORK} — see ${z_bridge_if_stderr}"
    read -r z_rboo_bridge_interface < "${z_bridge_if_file}" || true
    test -n "${z_rboo_bridge_interface}" \
      || buc_die "scry: network ${ZRBOB_NETWORK} reports no bridge interface"
    buc_info "Starting bridge capture (${z_rboo_bridge_interface}) via podman machine ssh"
    local z_bridge_cmd="sudo -n"
    test -z "${z_duration}" || z_bridge_cmd="${z_bridge_cmd} timeout ${z_duration}"
    z_bridge_cmd="${z_bridge_cmd} tcpdump ${ZRBOO_TCPDUMP_OPTS[*]} -i ${z_rboo_bridge_interface}"
    test -z "${z_filter}" || z_bridge_cmd="${z_bridge_cmd} ${z_filter}"
    "${ZRBOB_RUNTIME}" machine ssh "${z_bridge_cmd}" 2>&1 | zrboo_prefix "${ZRBOO_BLUE}" "BRIDGE" &
  else
    buc_info "Bridge capture not available for Docker runtime (requires podman machine ssh)"
  fi

  # Wait for all background captures. Bounded mode returns when the windows
  # elapse; interactive mode parks here until the SIGINT trap exits.
  if test -n "${z_duration}"; then
    buc_info "Capturing for ${z_duration}..."
    wait
    buc_info "Capture complete"
    return 0
  fi

  buc_info "Press Ctrl+C to stop captures"
  wait
}

# eof
