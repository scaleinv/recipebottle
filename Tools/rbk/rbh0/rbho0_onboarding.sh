#!/bin/bash
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
# Recipe Bottle Handbook Onboarding - Base (kindle, sentinel, probes, shared helpers)

set -euo pipefail

test -z "${ZRBHO_SOURCED:-}" || buc_die "Module rbho multiply sourced - check sourcing hierarchy"
ZRBHO_SOURCED=1

# rbho walkthroughs do not require rbho-local state (they probe the
# filesystem directly and render via buh_*). The kindle exists to assert
# the dependency ordering is correct at furnish time.

zrbho_kindle() {
  test -z "${ZRBHO_KINDLED:-}" || buc_die "Module rbho already kindled"
  zrbgc_sentinel
  zbuz_sentinel
  zrbz_sentinel

  # BCG stderr-capture prefixes for docker probes — discriminator appended at use site.
  # BURD_TEMP_DIR is dispatcher-provided (rbho is thin furnish — does not kindle burd).
  readonly ZRBHO_DOCKER_IMAGES_PREFIX="${BURD_TEMP_DIR}/zrbho_docker_images_"
  readonly ZRBHO_DOCKER_PS_PREFIX="${BURD_TEMP_DIR}/zrbho_docker_ps_"
  readonly ZRBHO_DOCKER_STDERR_PREFIX="${BURD_TEMP_DIR}/zrbho_docker_stderr_"

  # Handbook track display names — plain strings, not linked-term yelps.
  # Used where tracks cross-reference each other and in the start-here menu.
  readonly RBHO_TRACK_CRASH_COURSE="Crash Course"
  readonly RBHO_TRACK_FIRST_CRUCIBLE="Your First Crucible"
  readonly RBHO_TRACK_TADMOR="Tadmor Security"
  readonly RBHO_TRACK_FIRST_BUILD="Your First Cloud Build"
  readonly RBHO_TRACK_AIRGAP="Airgap Cloud Build"
  readonly RBHO_TRACK_BIND="Bind Cloud Build"
  readonly RBHO_TRACK_GRAFT="Graft Cloud Build"

  readonly ZRBHO_KINDLED=1
}

zrbho_sentinel() {
  test "${ZRBHO_KINDLED:-}" = "1" || buc_die "Module rbho not kindled - call zrbho_kindle first"
}

# Probe utilities — no sentinels, all work pre-kindle. Filesystem probes
# for onboarding status; callers declare caller-scope variables locally.

zrbho_po_status() {
  local -r z_flag="${1:-}"
  local -r z_text="${2:-}"
  if test "${z_flag}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${z_text}"
  else
    buh_line "${RBYC_PROBE_NO}${z_text}"
  fi
}

# Extract a KEY=VALUE from a file; stdout empty if missing.  No sourcing.
zrbho_po_extract_capture() {
  local -r z_file="${1:-}"
  local -r z_key="${2:-}"
  test -n "${z_key}"  || return 1
  test -f "${z_file}" || return 1
  local z_line=""
  while IFS= read -r z_line; do
    case "${z_line}" in "${z_key}="*) echo "${z_line#"${z_key}="}"; return 0 ;; esac
  done < "${z_file}"
  return 1
}

# eof
