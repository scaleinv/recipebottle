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
# Recipe Bottle Handbook Onboarding - Shared Crucible Trunk

set -euo pipefail

test -z "${ZRBHOCT_SOURCED:-}" || return 0
ZRBHOCT_SOURCED=1

# Voice-neutral kludge/commit/charge choreography shared by the first
# crucible explorer (rbhofc) and the tadmor security evaluator (rbhots).
# Intimate voice lives in caller top/tail — the trunk stays mechanical.
#
# Args:
#   $1  z_moniker        — nameplate identity (e.g., ccyolo, tadmor)
#   $2  z_sentry_vessel  — sentry vessel name (for image-exists probe)
#   $3  z_bottle_vessel  — bottle vessel name (for image-exists probe)
#   $4  z_nameplate_file — absolute path to the nameplate rbrn.env

rbhoct_crucible_trunk() {
  local -r z_moniker="${1}"
  local -r z_sentry_vessel="${2}"
  local -r z_bottle_vessel="${3}"
  local -r z_nameplate_file="${4}"

  buyy_cmd_yawp "RBRN_SENTRY_HALLMARK";   local -r z_code_sentry_field="${z_buym_yelp}"
  buyy_cmd_yawp "RBRN_BOTTLE_HALLMARK";   local -r z_code_bottle_field="${z_buym_yelp}"

  local z_nameplate_exists=0
  test -f "${z_nameplate_file}" && z_nameplate_exists=1

  local z_sentry_hallmark=""
  local z_bottle_hallmark=""
  local z_sentry_hallmark_present=0
  local z_bottle_hallmark_present=0
  if test "${z_nameplate_exists}" = "1"; then
    z_sentry_hallmark=$(zrbho_po_extract_capture "${z_nameplate_file}" "RBRN_SENTRY_HALLMARK") || z_sentry_hallmark=""
    z_bottle_hallmark=$(zrbho_po_extract_capture "${z_nameplate_file}" "RBRN_BOTTLE_HALLMARK") || z_bottle_hallmark=""
    test -n "${z_sentry_hallmark}" && z_sentry_hallmark_present=1
    test -n "${z_bottle_hallmark}" && z_bottle_hallmark_present=1
  fi

  local z_sentry_image_exists=0
  local z_bottle_image_exists=0
  local z_line=""
  local -r z_ct_images_out="${ZRBHO_DOCKER_IMAGES_PREFIX}ct1_repotag.txt"
  local -r z_ct_images_err="${ZRBHO_DOCKER_STDERR_PREFIX}ct1_repotag.txt"
  if docker images --format "{{.Repository}}:{{.Tag}}" \
       > "${z_ct_images_out}" 2>"${z_ct_images_err}"; then
    while IFS= read -r z_line || test -n "${z_line}"; do
      case "${z_line}" in
        *"${z_sentry_vessel}:k"[0-9]*) z_sentry_image_exists=1 ;;
        *"${z_bottle_vessel}:k"[0-9]*) z_bottle_image_exists=1 ;;
      esac
    done < "${z_ct_images_out}"
  fi

  local z_crucible_charged=0
  local -r z_ct_ps_out="${ZRBHO_DOCKER_PS_PREFIX}ct2_names.txt"
  local -r z_ct_ps_err="${ZRBHO_DOCKER_STDERR_PREFIX}ct2_ps.txt"
  if docker ps --format "{{.Names}}" > "${z_ct_ps_out}" 2>"${z_ct_ps_err}"; then
    while IFS= read -r z_line || test -n "${z_line}"; do
      case "${z_line}" in "${z_moniker}-bottle") z_crucible_charged=1; break ;; esac
    done < "${z_ct_ps_out}"
  fi

  buh_step_style "Step " " — "

  buh_step1 "Build images locally"
  buh_e
  buh_line "A ${RBYC_VESSEL} is a specification for a container image — a Dockerfile"
  buh_line "and build context. A ${RBYC_HALLMARK} is a specific build instance,"
  buh_line "identified by a timestamp tag."
  buh_e
  buh_line "${RBYC_KLUDGE} builds a ${RBYC_VESSEL} image locally using Docker — no cloud, no"
  buh_line "registry, no credentials. The fastest path from Dockerfile to running"
  buh_line "container without cloud build involvement.  Note this only builds for the"
  buh_line "host platform."
  buh_e
  buh_line "A ${RBYC_NAMEPLATE} is the file that defines a ${RBYC_CRUCIBLE} — it specifies"
  buh_line "which ${RBYC_HALLMARK} to use for the ${RBYC_SENTRY}, ${RBYC_PENTACLE}, and"
  buh_line "${RBYC_BOTTLE} containers. It lives at:"
  buh_e
  buh_code "   ${z_nameplate_file}"
  buh_e
  buh_line "Each ${RBYC_KLUDGE} below builds a ${RBYC_VESSEL} AND drives the resulting"
  buh_line "${RBYC_HALLMARK} into the ${z_moniker} ${RBYC_NAMEPLATE} — no copy/paste."
  buh_e
  buh_warn "${RBYC_KLUDGE} requires a clean git tree."
  buh_line "If you have uncommitted changes, commit them first.  Each ${RBYC_KLUDGE} image"
  buh_line "must correspond to an exact committed state — which is why you will commit"
  buh_line "after each ${RBYC_KLUDGE} below."
  buh_e

  buh_step2 "${RBYC_KLUDGE} the ${RBYC_SENTRY}"
  buh_e
  buh_line "The ${RBYC_SENTRY} is the gatekeeper container. It runs iptables"
  buh_line "and dnsmasq to enforce network policy — only domains on the"
  buh_line "${RBYC_NAMEPLATE}'s allowlist are reachable from inside."
  buh_e
  buh_line "Build it and drive the ${RBYC_HALLMARK} into the ${RBYC_NAMEPLATE}:"
  buh_e
  buh_tt  "   " "${RBZ_CRUCIBLE_KLUDGE_SENTRY}" "" " ${RBYC_HANDBOOK_NAMEPLATE_REF}"
  buh_e

  if test "${z_sentry_image_exists}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${RBYC_KLUDGE}-tagged ${RBYC_SENTRY} image found locally"
  else
    buh_line "${RBYC_PROBE_NO}No ${RBYC_KLUDGE}-tagged ${RBYC_SENTRY} image found"
  fi
  if test "${z_sentry_hallmark_present}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${z_code_sentry_field} = ${z_sentry_hallmark}"
  else
    buh_line "${RBYC_PROBE_NO}${z_code_sentry_field} is empty — run the ${RBYC_SENTRY} ${RBYC_KLUDGE} above"
  fi
  buh_e

  buh_step2 "Commit the ${RBYC_SENTRY} ${RBYC_HALLMARK}"
  buh_e
  buh_line "The ${RBYC_KLUDGE} wrote the new ${RBYC_HALLMARK} into the ${RBYC_NAMEPLATE}"
  buh_line "file.  The tree is now dirty.  The next ${RBYC_KLUDGE} requires a clean"
  buh_line "tree, so commit before proceeding:"
  buh_e
  buh_code "   git add ${z_nameplate_file}"
  buh_code "   git commit -m \"Kludge sentry hallmark into ${RBYC_HANDBOOK_NAMEPLATE_REF} nameplate\""
  buh_e

  buh_step2 "${RBYC_KLUDGE} the ${RBYC_BOTTLE}"
  buh_e
  buh_line "The ${RBYC_BOTTLE} is the workload container — the unprivileged target"
  buh_line "the ${RBYC_SENTRY} protects. Build it and drive the ${RBYC_HALLMARK}"
  buh_line "into the ${RBYC_NAMEPLATE}:"
  buh_e
  buh_tt  "   " "${RBZ_CRUCIBLE_KLUDGE_BOTTLE}" "" " ${RBYC_HANDBOOK_NAMEPLATE_REF}"
  buh_e

  if test "${z_bottle_image_exists}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${RBYC_KLUDGE}-tagged ${RBYC_BOTTLE} image found locally"
  else
    buh_line "${RBYC_PROBE_NO}No ${RBYC_KLUDGE}-tagged ${RBYC_BOTTLE} image found"
  fi
  if test "${z_bottle_hallmark_present}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${z_code_bottle_field} = ${z_bottle_hallmark}"
  else
    buh_line "${RBYC_PROBE_NO}${z_code_bottle_field} is empty — run the ${RBYC_BOTTLE} ${RBYC_KLUDGE} above"
  fi
  buh_e

  buh_step2 "Commit the ${RBYC_BOTTLE} ${RBYC_HALLMARK}"
  buh_e
  buh_line "Same cadence: the ${RBYC_KLUDGE} left the ${RBYC_NAMEPLATE} dirty, and"
  buh_line "${RBYC_CHARGE} requires a clean ${RBYC_NAMEPLATE} before starting.  Commit:"
  buh_e
  buh_code "   git add ${z_nameplate_file}"
  buh_code "   git commit -m \"Kludge bottle hallmark into ${RBYC_HANDBOOK_NAMEPLATE_REF} nameplate\""
  buh_e

  buh_step1 "${RBYC_CHARGE} the ${RBYC_CRUCIBLE}"
  buh_e
  buh_line "${RBYC_CHARGE} starts three containers from the ${RBYC_NAMEPLATE}:"
  buh_e
  buh_line "  ${RBYC_SENTRY}    — runs iptables + dnsmasq, enforces the network allowlist"
  buh_line "  ${RBYC_PENTACLE}  — establishes the network namespace shared with the ${RBYC_BOTTLE}"
  buh_line "  ${RBYC_BOTTLE}    — the unprivileged workload container"
  buh_e
  buh_line "The ${RBYC_SENTRY} mediates all traffic. The ${RBYC_BOTTLE} never touches the"
  buh_line "network directly — everything routes through the ${RBYC_SENTRY_P} rules."
  buh_e
  buh_tt  "   " "${RBZ_CRUCIBLE_CHARGE}" "${z_moniker}"
  buh_e
  buh_line "${RBYC_CHARGE} takes 10-30 seconds. It pulls the images from local"
  buh_line "Docker, creates the ${RBYC_ENCLAVE} network, starts the containers,"
  buh_line "waits for the ${RBYC_SENTRY} to confirm its iptables rules are"
  buh_line "applied, then starts the ${RBYC_BOTTLE}."
  buh_e

  if test "${z_crucible_charged}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${RBYC_CRUCIBLE} ${z_moniker} is charged (${RBYC_BOTTLE} container running)"
  else
    buh_line "${RBYC_PROBE_NO}${RBYC_CRUCIBLE} ${z_moniker} is not charged"
  fi
  buh_e
}

# eof
