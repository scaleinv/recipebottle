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
# Recipe Bottle Handbook Onboarding - Director Airgap Cloud Build
#
# Sequel to Your First Cloud Build (rbhodf). Teaches the airgap
# supply chain: ensconce upstream, conjure base tethered, conjure
# airgap ifrit from the forge base, install into moriah, run the
# same 34-case security suite, compare plumb against tadmor baseline.

set -euo pipefail

test -z "${ZRBHODA_SOURCED:-}" || return 0
ZRBHODA_SOURCED=1

rbho_director_airgap() {
  zrbho_sentinel

  buc_doc_brief "${RBHO_TRACK_AIRGAP} — ensconce, conjure base, conjure airgap, charge moriah, compare plumb"
  buc_doc_shown || return 0

  local -r z_moniker="moriah"
  local -r z_tether_moniker="tadmor"
  local -r z_forge_vessel="rbev-bottle-ifrit-forge"
  local -r z_airgap_vessel="rbev-bottle-ifrit-airgap"
  local -r z_tether_vessel="rbev-bottle-ifrit-tether"
  local -r z_airgap_rbrv="${RBRR_VESSEL_DIR}/${z_airgap_vessel}/${RBCC_rbrv_file}"
  local -r z_moriah_rbrn="${RBCC_moorings_dir}/${z_moniker}/${RBCC_rbrn_file}"
  local -r z_tether_rbrn="${RBCC_moorings_dir}/${z_tether_moniker}/${RBCC_rbrn_file}"

  local z_has_depot=0
  if test -f "${RBCC_rbrd_file}"; then
    local z_line=""
    while IFS= read -r z_line; do
      case "${z_line}" in RBRD_DEPOT_MONIKER=?*) z_has_depot=1; break ;; esac
    done < "${RBCC_rbrd_file}"
  fi

  local z_airgap_base_anchored=0
  if test -f "${z_airgap_rbrv}"; then
    local z_anchor=""
    z_anchor=$(zrbho_po_extract_capture "${z_airgap_rbrv}" "RBRV_IMAGE_1_ANCHOR") || z_anchor=""
    test -n "${z_anchor}" && z_airgap_base_anchored=1
  fi

  local z_airgap_ordained=0
  if test -f "${z_moriah_rbrn}"; then
    local z_moriah_hallmark=""
    z_moriah_hallmark=$(zrbho_po_extract_capture "${z_moriah_rbrn}" "RBRN_BOTTLE_HALLMARK") || z_moriah_hallmark=""
    case "${z_moriah_hallmark}" in
      ""|PENDING-*) ;;
      *) z_airgap_ordained=1 ;;
    esac
  fi

  local z_tether_ready=0
  local z_tether_hallmark=""
  if test -f "${z_tether_rbrn}"; then
    z_tether_hallmark=$(zrbho_po_extract_capture "${z_tether_rbrn}" "RBRN_BOTTLE_HALLMARK") || z_tether_hallmark=""
    case "${z_tether_hallmark}" in
      ""|PENDING-*) z_tether_hallmark="" ;;
      *) z_tether_ready=1 ;;
    esac
  fi

  buyy_link_yawp "${RBRR_PUBLIC_DOCS_URL}" "Vessel"    "${z_forge_vessel}";   local -r z_lk_forge="${z_buym_yelp}"
  buyy_link_yawp "${RBRR_PUBLIC_DOCS_URL}" "Vessel"    "${z_airgap_vessel}";  local -r z_lk_airgap="${z_buym_yelp}"
  buyy_link_yawp "${RBRR_PUBLIC_DOCS_URL}" "Nameplate" "${z_moniker}";        local -r z_lk_moriah="${z_buym_yelp}"
  buyy_link_yawp "${RBRR_PUBLIC_DOCS_URL}" "Nameplate" "${z_tether_moniker}"; local -r z_lk_tadmor="${z_buym_yelp}"

  buh_section "${RBHO_TRACK_AIRGAP} — Your Own Supply Chain"
  buh_e
  buh_line "In ${RBHO_TRACK_FIRST_BUILD} you ${RBYC_ORDAIN}ed a ${RBYC_VESSEL} on the"
  buh_line "${RBYC_TETHERED} pool — Cloud Build pulled base images from the"
  buh_line "public internet during the build. ${RBYC_AIRGAP} removes that"
  buh_line "dependency: zero network during the build, every input pre-staged"
  buh_line "in your ${RBYC_DEPOT}."
  buh_e
  buh_line "This track builds ${z_lk_airgap} — the ${RBYC_BOTTLE} variant that"
  buh_line "matches the ifrit you met in the ${z_lk_tadmor} adversarial suite,"
  buh_line "now with full supply-chain discipline. The chain has three links:"
  buh_e
  buh_line "  1. Capture the rust base from upstream into your ${RBYC_DEPOT} (ensconce into a bole Lode)"
  buh_line "  2. Build a project-authored toolchain ${RBYC_VESSEL} ${RBYC_TETHERED}"
  buh_line "  3. Build the airgap ${RBYC_BOTTLE} ${RBYC_AIRGAP} from the ${z_lk_forge} ${RBYC_HALLMARK}"
  buh_e
  buh_line "Then drive the resulting ${RBYC_HALLMARK} into the ${z_lk_moriah}"
  buh_line "${RBYC_NAMEPLATE} and run the same 34 containment attacks against"
  buh_line "it that you ran against ${z_lk_tadmor}."
  buh_e

  buh_line "Prerequisites:"
  buh_e
  if test "${z_has_depot}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${RBYC_DEPOT} configured (RBRD_DEPOT_MONIKER populated)"
  else
    buh_line "${RBYC_PROBE_NO}${RBYC_DEPOT} not configured — the ${RBYC_PAYOR} must establish the ${RBYC_DEPOT}:"
    buh_tt "      " "${RBZ_ONBOARD_PAYOR_HB}"
  fi
  buh_e
  buh_line "This track assumes you have completed ${RBHO_TRACK_FIRST_BUILD} —"
  buh_line "the ${RBYC_RELIQUARY} is conclaved and you have ${RBYC_ORDAIN}ed at least"
  buh_line "one ${RBYC_VESSEL} on the ${RBYC_TETHERED} pool."
  buh_e

  if test "${z_has_depot}" = "0"; then
    buh_error "Complete the prerequisites above before continuing."
    buh_e
    buh_tt "Return to start: " "${RBZ_ONBOARD_START_HERE}"
    buh_e
    return 0
  fi

  buh_line "Configure this handbook session:"
  buh_e
  buh_code "   export ${RBYC_HANDBOOK_NAMEPLATE_NAME}=${z_moniker}"
  buh_e
  buh_line "The ${RBYC_CHARGE} and suite commands below reference the ${RBYC_NAMEPLATE}"
  buh_line "by name. The two ${RBYC_VESSEL} names shift mid-track (forge →"
  buh_line "airgap), so vessels appear as literals in commands."
  buh_e

  buh_step_style "Step " " — "

  buh_step1 "Ensconce the upstream base into a Lode"
  buh_e
  buh_line "The airgap chain starts with ownership. Ensconce captures an"
  buh_line "upstream image — here rust:slim-bookworm — into a bole Lode in your"
  buh_line "${RBYC_DEPOT} under a content-addressed touchmark. Once captured,"
  buh_line "builds pull the base from your ${RBYC_DEPOT} without touching the"
  buh_line "public internet."
  buh_e
  buh_line "The ${z_lk_forge} ${RBYC_VESSEL} declares its upstream base in"
  buh_line "its ${RBYC_RBRV} file:"
  buh_e
  buh_code "   RBRV_IMAGE_1_ORIGIN=rust:slim-bookworm"
  buh_e
  buh_line "ORIGIN names where the image comes from. Run ensconce on ${z_lk_forge}:"
  buh_e
  buh_tt "   " "${RBZ_ENSCONCE_BOLE}" "" " ${z_forge_vessel}"
  buh_e
  buh_line "Ensconce inspects the current upstream image, computes a"
  buh_line "content-addressed digest from the live manifest, and captures the"
  buh_line "image into a bole Lode in your ${RBYC_DEPOT}. The vessel's ANCHOR is"
  buh_line "filled in when you ordain ${z_lk_forge} below. Re-ensconcing captures"
  buh_line "current upstream — if upstream rotates, the next capture records a"
  buh_line "different touchmark and that is the operation surfacing the change."
  buh_e

  buh_step1 "${RBYC_CONJURE} ${z_lk_forge} ${RBYC_TETHERED}, then point the airgap ${RBYC_BOTTLE} at it"
  buh_e
  buh_line "It is a project-authored toolchain image that pre-stages"
  buh_line "apt packages and warms the cargo cache so the airgap build"
  buh_line "downstream has nothing to fetch."
  buh_e
  buh_line "Build it on the ${RBYC_TETHERED} pool — its ${RBYC_RBRV} declares:"
  buh_e
  buh_code "   RBRV_EGRESS_MODE=rbnve_tether"
  buh_e
  buh_line "${RBYC_ORDAIN} reads this and routes to the ${RBYC_TETHERED} pool:"
  buh_e
  buh_tt "   " "${RBZ_ORDAIN_HALLMARK}" "" " ${z_forge_vessel}"
  buh_e
  buh_line "Wall-clock ~15-20 minutes across the declared platforms. This"
  buh_line "${RBYC_VESSEL} is toolchain plumbing that your customer code will be"
  buh_line "built against — it is not itself customer code, which is why"
  buh_line "${RBYC_TETHERED} build is acceptable at this layer."
  buh_e
  buh_line "Both ensconce and ${RBYC_ORDAIN} refuse on a dirty working tree, so"
  buh_line "commit anything pending before this pair. During this run ${RBYC_ORDAIN}"
  buh_line "elects the ensconced touchmark into ${z_lk_forge}'s ANCHOR slot —"
  buh_line "an rbrv.env edit it leaves for you to commit when the build finishes."
  buh_e
  buh_line "Now bridge: the airgap ${RBYC_VESSEL} ${z_lk_airgap} declares"
  buh_line "${z_lk_forge} as its base:"
  buh_e
  buh_code "   RBRV_IMAGE_1_ORIGIN=rbev-bottle-ifrit-forge"
  buh_code "   RBRV_IMAGE_1_ANCHOR="
  buh_e
  buh_line "ORIGIN names the producer ${RBYC_VESSEL} (lineage); ANCHOR will hold"
  buh_line "the locator pointing at the just-built ${RBYC_HALLMARK} inside"
  buh_line "your ${RBYC_DEPOT}'s hallmark namespace. ${RBYC_ORDAIN} wrote that"
  buh_line "${RBYC_HALLMARK} to the fact file — capture it:"
  buh_e
  buh_code "   export FORGE_HALLMARK=\$(cat ${BURD_OUTPUT_DIR}/${RBF_FACT_HALLMARK})"
  buh_e
  buh_line "Open the airgap ${RBYC_RBRV} and set ANCHOR to that ${RBYC_HALLMARK}'s locator:"
  buh_e
  buh_code "   RBRV_IMAGE_1_ANCHOR=rbi_hm/\${FORGE_HALLMARK}/image:\${FORGE_HALLMARK}"
  buh_e
  buh_line "Substitute the captured hallmark into the locator. Commit the change"
  buh_line "together with the elected forge ANCHOR from the previous step —"
  buh_line "the airgap ${RBYC_ORDAIN} below refuses on an uncommitted tree."
  buh_e
  buh_line "Ensconce is not invoked on the airgap ${RBYC_VESSEL} — its"
  buh_line "${RBYC_RBRV}'s ANCHOR points at ${z_lk_forge}'s ${RBYC_HALLMARK}"
  buh_line "subtree, and the hallmark's existence in your ${RBYC_DEPOT} is"
  buh_line "established by ${z_lk_forge}'s ${RBYC_ORDAIN} success above. Conjure"
  buh_line "resolves the locator at airgap-bottle build time."
  buh_e
  if test "${z_airgap_base_anchored}" = "1"; then
    buh_line "${RBYC_PROBE_YES}Airgap base anchor populated — base ${RBYC_HALLMARK} ready"
  else
    buh_line "${RBYC_PROBE_NO}Airgap base anchor empty — ${RBYC_CONJURE} ${z_lk_forge}, then write the locator into the airgap ${RBYC_RBRV}"
  fi
  buh_e

  buh_step1 "${RBYC_CONJURE} the airgap ${RBYC_BOTTLE} ${RBYC_AIRGAP}"
  buh_e
  buh_line "Now the airgap build has everything it needs inside your"
  buh_line "${RBYC_DEPOT} — rust toolchain, apt packages, cargo cache, all"
  buh_line "pre-staged in the ${z_lk_forge} base ${RBYC_HALLMARK}."
  buh_e
  buh_line "The airgap ${RBYC_VESSEL}'s Dockerfile starts FROM that ${RBYC_HALLMARK}:"
  buh_e
  buh_code "   ARG RBF_IMAGE_1"
  buh_code "   FROM \${RBF_IMAGE_1}"
  buh_e
  buh_line "RBF_IMAGE_1 is resolved from RBRV_IMAGE_1_ANCHOR at build time."
  buh_line "The airgap pool has zero external network — Cloud Build reaches"
  buh_line "your ${RBYC_DEPOT} and nothing else."
  buh_e
  buh_line "${RBYC_ORDAIN}:"
  buh_e
  buh_tt "   " "${RBZ_ORDAIN_HALLMARK}" "" " ${z_airgap_vessel}"
  buh_e
  buh_line "Another ~15-20 minutes. The ${RBYC_VOUCH} at the end attests both"
  buh_line "the SLSA ${RBYC_PROVENANCE} chain and the airgap condition — that"
  buh_line "the build saw no public internet."
  buh_e
  buh_line "Your customer code was compiled against a supply chain you"
  buh_line "controlled end-to-end."
  buh_e

  buh_step1 "Install the ${RBYC_HALLMARK} into ${z_lk_moriah} and run the security suite"
  buh_e
  buh_line "The cloud-built ${RBYC_HALLMARK} is now in your ${RBYC_DEPOT}. The"
  buh_line "${z_lk_moriah} ${RBYC_NAMEPLATE} names how that ${RBYC_HALLMARK} runs as"
  buh_line "a ${RBYC_CRUCIBLE}. ${RBYC_HALLMARK} and ${RBYC_NAMEPLATE} are separate"
  buh_line "artifacts — one is the build product, the other is the deployment"
  buh_line "config."
  buh_e
  buh_line "Read the ${RBYC_HALLMARK} from the fact file ${RBYC_ORDAIN} wrote:"
  buh_e
  buh_code "   export ${RBYC_HANDBOOK_HALLMARK_NAME}=\$(cat ${BURD_OUTPUT_DIR}/${RBF_FACT_HALLMARK})"
  buh_e
  buh_line "Drive it into ${z_lk_moriah}'s ${RBYC_BOTTLE} hallmark, replacing the"
  buh_line "PENDING-ordination placeholder — the drive writes the ${RBYC_RBRN} for you:"
  buh_e
  buh_tt "   " "${RBZ_DRIVE_HALLMARK}" "" " ${z_moniker} bottle ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_e
  buh_line "Commit the change."
  buh_e
  if test "${z_airgap_ordained}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${z_lk_moriah} ${RBYC_BOTTLE} hallmark installed"
  else
    buh_line "${RBYC_PROBE_NO}${z_lk_moriah} ${RBYC_BOTTLE} hallmark is PENDING-ordination — install it above"
  fi
  buh_e
  buh_line "${RBYC_CHARGE} ${z_lk_moriah} with the airgap-built image:"
  buh_e
  buh_tt "   " "${RBZ_CRUCIBLE_CHARGE}" "${z_moniker}"
  buh_e
  buh_line "Run the full 34-case security suite — the same suite you ran"
  buh_line "against ${z_lk_tadmor} with kludged ${RBYC_HALLMARKS}:"
  buh_e
  buh_tt "   " "rbw-tf" "" " ${z_moniker}"
  buh_e
  buh_line "Expect green across the board. Same attacks, same containment"
  buh_line "boundaries, same expected responses — now against a ${RBYC_BOTTLE}"
  buh_line "built with full airgap supply-chain discipline."
  buh_e
  buh_line "This closes the loop: you built the validated airgap security"
  buh_line "infrastructure yourself. Containment holds regardless of how the"
  buh_line "${RBYC_HALLMARK} was produced."
  buh_e

  buh_step1 "Compare ${RBYC_PLUMB} output — ${RBYC_TETHERED} vs ${RBYC_AIRGAP}"
  buh_e
  buh_line "${RBYC_PLUMB} displays the ${RBYC_PROVENANCE} evidence attached to a"
  buh_line "${RBYC_HALLMARK}. Run it against ${z_lk_moriah}'s airgap ${RBYC_BOTTLE}"
  buh_line "alongside ${z_lk_tadmor}'s ${RBYC_TETHERED} ${RBYC_BOTTLE} to see what"
  buh_line "airgap adds to the record."
  buh_e
  if test "${z_tether_ready}" = "1"; then
    buh_line "${RBYC_PROBE_YES}${z_lk_tadmor} bottle hallmark available for comparison"
  else
    buh_line "${RBYC_PROBE_NO}${z_lk_tadmor} has no bottle hallmark — run the ${z_lk_tadmor} track first for the full comparison"
  fi
  buh_e
  buh_line "Airgap ${RBYC_BOTTLE} full ${RBYC_PROVENANCE}:"
  buh_e
  buh_tt "   " "${RBZ_PLUMB_FULL}" "" " ${z_airgap_vessel} ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_e
  if test "${z_tether_ready}" = "1"; then
    buyy_cmd_yawp "${z_tether_hallmark}"; local -r z_lk_tether_hallmark="${z_buym_yelp}"
    buh_line "Tethered ${RBYC_BOTTLE} — ${z_lk_tadmor}'s current bottle ${RBYC_HALLMARK} is ${z_lk_tether_hallmark}:"
    buh_e
    buh_tt "   " "${RBZ_PLUMB_FULL}" "" " ${z_tether_vessel} ${z_tether_hallmark}"
    buh_e
  else
    buyy_cmd_yawp "${z_tether_rbrn}"; local -r z_lk_tether_file="${z_buym_yelp}"
    buh_line "Tethered ${RBYC_BOTTLE} — once ${z_lk_tadmor} is ${RBYC_CHARGE}d, read RBRN_BOTTLE_HALLMARK"
    buh_line "from ${z_lk_tether_file} and plumb it:"
    buh_e
    buh_tt "   " "${RBZ_PLUMB_FULL}" "" " ${z_tether_vessel} <tadmor-hallmark>"
    buh_e
  fi
  buh_line "What to look for, side by side:"
  buh_e
  buh_line "  ${RBYC_SBOM}       Same rust/cargo package set if both ${RBYC_HALLMARKS}"
  buh_line "              were ${RBYC_CONJURED}. The ifrit binary is functionally"
  buh_line "              equivalent either way."
  buh_e
  buh_line "  Build info  The airgap ${RBYC_HALLMARK} records a sealed supply"
  buh_line "              chain — base digests resolved to your ${RBYC_DEPOT},"
  buh_line "              no upstream resolution during the build. A ${RBYC_TETHERED}"
  buh_line "              ${RBYC_HALLMARK} shows upstream resolution within the build"
  buh_line "              window. A kludged ${RBYC_HALLMARK} carries no Cloud Build"
  buh_line "              record at all."
  buh_e
  buh_line "  ${RBYC_PROVENANCE}  The airgap ${RBYC_VOUCH} attests the airgap condition"
  buh_line "              in addition to the standard SLSA chain. ${RBYC_TETHERED}"
  buh_line "              ${RBYC_VOUCHED} ${RBYC_HALLMARKS} carry SLSA without that"
  buh_line "              extra attestation."
  buh_e
  buh_line "For a compact summary:"
  buh_e
  buh_tt "   " "${RBZ_PLUMB_COMPACT}" "" " ${z_airgap_vessel} ${RBYC_HANDBOOK_HALLMARK_REF}"
  buh_e

  buh_step1 "The pattern"
  buh_e
  buh_line "An airgap supply chain has three links. Any future airgap build"
  buh_line "follows the same shape:"
  buh_e
  buh_line "   1. Ensconce the upstream base into a bole Lode in your ${RBYC_DEPOT}"
  buh_line "   2. ${RBYC_CONJURE} ${z_lk_forge} ${RBYC_TETHERED}, write its ${RBYC_HALLMARK} locator"
  buh_line "      into the consumer's ${RBYC_RBRV} ANCHOR"
  buh_line "   3. ${RBYC_CONJURE} the final ${RBYC_BOTTLE} ${RBYC_AIRGAP} from the ${z_lk_forge} ${RBYC_HALLMARK}"
  buh_e
  buh_line "${RBYC_PLUMB} distinguishes three build-info signatures:"
  buh_e
  buh_line "   ${RBYC_AIRGAP}     sealed chain — base digests resolved to your ${RBYC_DEPOT}"
  buh_line "   ${RBYC_TETHERED}   upstream resolution during the build window"
  buh_line "   ${RBYC_KLUDGE_D}    no Cloud Build record — local provenance only"
  buh_e

  buh_tt "Return to start: " "${RBZ_ONBOARD_START_HERE}"
  buh_e
}

# eof
