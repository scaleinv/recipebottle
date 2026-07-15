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
# Recipe Bottle Lode - wsl body (guard-free cluster, sourced by rbld0_lode):
#   underpin — capture a vendor-published WSL rootfs into a Lode (Director creds)
# The wsl kind rides the capture-assembly spine (rblds_): this body owns only the
# kind-specific data — the underpin recipe (curl+gpg fetch/verify + gcrane-append
# wrap + vouch-push) and the substitutions blob — and composes them through
# zrbld_spine_dispatch / zrbld_spine_extract_single. No build-submission or
# step-composition machinery lives here.
#
# The structural outlier among the Lode kinds: its upstream is an HTTPS rootfs
# tarball + an out-of-band published checksum, NOT an OCI registry image — so it
# cannot reuse the gcrane/docker registry-pull steps. Its fetch step (rbgjl04) fetches
# over curl, GPG-verifies the vendor's published SHA256SUMS against a pinned
# signing-key fingerprint, verifies the rootfs bytes, and stages the tarball; the wrap
# step (rbgjl05) gcrane-appends it as an opaque single-layer OCI member (never
# extracted). Acquisition runs cloud-side; the workstation only assembles the URL from
# the version arguments.

set -euo pipefail

# Underpin is capture-pure: it writes no consumer config. It hands the captured
# touchmark forward through one bare single-form chaining fact
# (RBF_FACT_LODE_TOUCHMARK) via the depth-1 cross-tabtarget chain; a consumer
# decodes the wsl kind from the touchmark prefix. The provenance envelope lives
# only in GAR (:rbi_vouch tag, pushed cloud-side by rbgjl02), never host-side.
# Consumption (wsl --import of the captured seed) is a
# separate, deferred layer that reads these facts — not part of underpin.

######################################################################
# Internal Helpers (zrbld_*)

# Internal: compose the underpin capture recipe (curl+gpg fetch/verify + gcrane-append
# wrap + vouch-push) and its substitutions blob, then ride the capture spine to submit
# and poll. The spine owns the capture-domain build knobs (mason SA, TETHER pool,
# regime timeout); this body chooses only the recipe, the substitutions, and the poll
# ceiling. Three steps across two builders: the fetch/verify rides the Debian Google
# builder (curl + apt-installed gnupg), the wrap and vouch-push ride the floating gcrane
# builder. wsl is evicted but NOT pinned this pace — it is vessel-less with no reliquary
# source, so its tool-pinning defers to the bootstrap-builder digest-pin itch (RBS0
# rbsk_pinning_boundary); both gcrane rows ride the floating bootstrap builder, same tier
# as conclave. The heavy capture poll ceiling gives headroom for the in-step
# apt-get(gnupg) + keyserver fetch + gcrane append.
# Args: token url stamp
zrbld_underpin_submit() {
  zrbld_sentinel

  local -r z_token="${1:?Token required}"
  local -r z_url="${2:?URL required}"
  local -r z_stamp="${3:?Stamp required}"

  buc_step "Constructing underpin capture recipe"
  local -r z_gar_host="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}"
  local -r z_gar_path="${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"

  # Recipe rows: script_path|builder_image|id|entrypoint, pre-resolved for the spine.
  # Fetch/verify on the Debian Google builder (curl + apt-installed gnupg); wrap + vouch
  # on the floating gcrane builder (busybox). No reliquary bootstrap and no pinning —
  # wsl is vessel-less, so its tool-pinning defers to the bootstrap-builder digest-pin
  # itch; both gcrane rows ride the floating bootstrap builder, same tier as conclave.
  local -r z_recipe=(
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl04-underpin-capture.sh|${ZRBLD_GOOGLE_DOCKER_BUILDER}|underpin-fetch|bash"
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl05-underpin-wrap.sh|${ZRBLD_GCRANE_BUILDER}|underpin-wrap|busybox"
    "${ZRBLD_RBGJL_STEPS_DIR}/rbgjl02-assemble-push-vouch.sh|${ZRBLD_GCRANE_BUILDER}|assemble-push-vouch|busybox"
  )

  buc_log_args "Composing underpin substitutions blob"
  local -r z_subs_file="${ZRBLD_UNDERPIN_PREFIX}subs.json"
  jq -n \
    --arg zjq_gar_host     "${z_gar_host}" \
    --arg zjq_gar_path     "${z_gar_path}" \
    --arg zjq_lodes_root   "${RBGL_LODES_ROOT}" \
    --arg zjq_tag_rootfs   "${RBGC_LODE_TAG_ROOTFS}" \
    --arg zjq_tag_vouch    "${RBGC_LODE_TAG_VOUCH}" \
    --arg zjq_trust_grade  "${RBGC_LODE_TRUST_VERIFIED}" \
    --arg zjq_vouch_schema "${RBGC_LODE_VOUCH_SCHEMA}" \
    --arg zjq_acquired_by  "${RBGD_MASON_EMAIL}" \
    --arg zjq_stamp        "${z_stamp}" \
    --arg zjq_wsl_url      "${z_url}" \
    --arg zjq_wsl_key_fpr  "${RBGC_LODE_WSL_SIGNING_FPR}" \
    '{
      _RBGL_GAR_HOST:     $zjq_gar_host,
      _RBGL_GAR_PATH:     $zjq_gar_path,
      _RBGL_LODES_ROOT:   $zjq_lodes_root,
      _RBGL_TAG_ROOTFS:   $zjq_tag_rootfs,
      _RBGL_TAG_VOUCH:    $zjq_tag_vouch,
      _RBGL_TRUST_GRADE:  $zjq_trust_grade,
      _RBGL_VOUCH_SCHEMA: $zjq_vouch_schema,
      _RBGL_ACQUIRED_BY:  $zjq_acquired_by,
      _RBGL_LODE_STAMP:   $zjq_stamp,
      _RBGL_WSL_URL:      $zjq_wsl_url,
      _RBGL_WSL_KEY_FPR:  $zjq_wsl_key_fpr
    }' > "${z_subs_file}" \
    || buc_die "Failed to compose underpin substitutions blob"

  zrbld_spine_dispatch \
    "${z_token}" "${RBGD_MASON_EMAIL}" "Underpin" "${ZRBFC_BUILD_POLL_CEILING_CAPTURE_HEAVY}" \
    "${z_subs_file}" "${ZRBLD_UNDERPIN_PREFIX}" \
    "${z_recipe[@]}"
}

######################################################################
# External Functions (rbld_*)

rbld_underpin() {
  zrbld_sentinel

  buc_doc_brief "Underpin a vendor-published WSL rootfs into a Lode (wsl kind, rbi_ld capture)"
  buc_doc_param "release" "Ubuntu release series — the cdimage path segment (e.g. 24.04)"
  buc_doc_param "point"   "Point-release number — assembles the full version (e.g. 4 -> 24.04.4)"
  buc_doc_shown || return 0

  # Dirty-tree guard — capture composes its cloud step bodies from the working
  # tree; the Lode's provenance envelope must be the product of committed code.
  bug_require_clean_tree_creed "${RBCC_creed_clean_capture}"

  # Two declarative version arguments (no FQIN — see RBSLU): the param1 channel
  # routes the first to BUZ_FOLIO and forwards the rest, so release is the folio
  # and point the first positional. The host assembles the resolved URL from the
  # path-convention template; the cloud step discovers and verifies the checksum.
  local -r z_release="${BUZ_FOLIO:-}"
  local -r z_point="${1:-}"
  test -n "${z_release}" || buc_die "release argument required (e.g. 24.04)"
  test -n "${z_point}"   || buc_die "point argument required (e.g. 4)"

  local -r z_arch="${RBGC_LODE_WSL_ARCH_DEFAULT}"
  local -r z_fullver="${z_release}.${z_point}"
  local z_url=""
  printf -v z_url "${RBGC_LODE_WSL_URL_TEMPLATE}" "${z_release}" "${z_fullver}" "${z_arch}"
  buc_info "Underpin source: ${z_url}"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  # Mint the Lode stamp on the host: <kind-letter><YYMMDDHHMMSS>. The host owns
  # the stamp so the touchmark is known before the build for the capture-file.
  local -r z_stamp="${RBGC_LODE_KIND_WSL}${BURD_NOW_STAMP:2:6}${BURD_NOW_STAMP:9:6}"

  buc_info "Lode: ${RBGL_LODES_ROOT}/${z_stamp}"

  zrbld_underpin_submit "${z_token}" "${z_url}" "${z_stamp}"
  # Shared single-slot extract (rblds_): the fetch step (step 0) authors the
  # output; the wrap and vouch-push steps write none.
  zrbld_spine_extract_single "${ZRBLD_UNDERPIN_PREFIX}" "${RBGC_LODE_BRAND_WSL}" "Underpin"

  buc_success "Underpin complete: ${z_url} -> ${RBGL_LODES_ROOT}/${z_stamp}"
}

# eof
