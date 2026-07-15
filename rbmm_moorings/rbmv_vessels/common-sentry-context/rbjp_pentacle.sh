#!/bin/sh
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
# RBJP - Pentacle initialization script
# Configures network routing through sentry for enclave isolation.
# Baked into sentry image at /opt/rbk/rbjp_pentacle.sh.
#
# Requires: RBRN_ENCLAVE_SENTRY_IP in container environment

set -e

echo "RBJP: Beginning pentacle setup"

echo "RBJP: Validate parameters"
: "${RBRN_ENCLAVE_SENTRY_IP:?}" && echo "RBJP: RBRN_ENCLAVE_SENTRY_IP = ${RBRN_ENCLAVE_SENTRY_IP}"

echo "RBJP: Configuring DNS to use sentry"
echo "nameserver ${RBRN_ENCLAVE_SENTRY_IP}" > /etc/resolv.conf || exit 10

echo "RBJP: Discovering enclave interface (single non-loopback interface expected)"
z_temp_file="/tmp/rbjp_iface_discovery.txt"
ip -o -4 addr show scope global > "${z_temp_file}" || exit 11
read -r z_num RBJP_ENCLAVE_IF z_rest < "${z_temp_file}"
rm -f "${z_temp_file}"
test -n "${RBJP_ENCLAVE_IF}" || { echo "RBJP: FATAL - No enclave interface found"; exit 11; }
echo "RBJP: Enclave interface = ${RBJP_ENCLAVE_IF}"

echo "RBJP: Flushing ARP entries"
ip link set "${RBJP_ENCLAVE_IF}" down && ip link set "${RBJP_ENCLAVE_IF}" up && ip -s -s neigh flush all || exit 20

echo "RBJP: Setting default route through sentry"
ip route add default via "${RBRN_ENCLAVE_SENTRY_IP}" || exit 30

echo "RBJP: Verifying default route"
ip route | grep -q "^default via ${RBRN_ENCLAVE_SENTRY_IP}" || { echo "RBJP: FATAL - default route not set"; exit 31; }

echo "RBJP: Signaling health"
touch /tmp/rbjph_healthy || exit 40

echo "RBJP: Pentacle setup complete, entering hold"
exec sleep infinity
