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
# Recipe Bottle Foundry Kludge - local image build for development (no Cloud Build, no GAR, no credentials)

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBFK_SOURCED:-}" || buc_die "Module rbfk multiply sourced - check sourcing hierarchy"
ZRBFK_SOURCED=1

# Source shared Foundry Core module (registry constants + vessel resolution helpers)
source "${BASH_SOURCE[0]%/*}/rbfc0_core.sh"

######################################################################
# Internal Functions (zrbfk_*)

zrbfk_kindle() {
  test -z "${ZRBFK_KINDLED:-}" || buc_die "Module rbfk already kindled"

  buc_log_args 'Kindle shared Foundry Core infrastructure'
  zrbfc_kindle

  buc_log_args 'Define forensic temp prefix for docker image inspect stderr capture'
  readonly ZRBFK_INSPECT_STDERR_PREFIX="${BURD_TEMP_DIR}/rbfk_inspect_stderr_"

  buc_log_args 'Initialize mutable image-presence inspect counter'
  z_rbfk_inspect_counter=0

  readonly ZRBFK_KINDLED=1
}

zrbfk_sentinel() {
  zrbfc_sentinel
  test "${ZRBFK_KINDLED:-}" = "1" || buc_die "Module rbfk not kindled - call zrbfk_kindle first"
}

# Image-Presence Predicate
#
# Wraps `docker image inspect` so stderr lands in a counter-discriminated
# forensic temp file rather than the terminal. Returns docker's exit
# status; callers consume via `if zrbfk_image_present_predicate ...` or
# `... || ...`. The forensic files persist in BURD_TEMP_DIR for the
# command's lifetime, available for post-mortem inspection.
zrbfk_image_present_predicate() {
  zrbfk_sentinel
  local -r z_ref="${1:-}"
  test -n "${z_ref}" || buc_die "zrbfk_image_present_predicate: image ref required"
  z_rbfk_inspect_counter=$(( z_rbfk_inspect_counter + 1 ))
  docker image inspect "${z_ref}" \
    >/dev/null \
    2>"${ZRBFK_INSPECT_STDERR_PREFIX}${z_rbfk_inspect_counter}"
}

######################################################################
# External Functions (rbfk_*)

######################################################################
# Kludge Build - Local image build for development
#
# Builds a vessel image locally using docker build, tags it with a
# kludge hallmark (k-prefixed timestamp) in the same GAR-style
# format that compose and rbob_charge expect. Also creates a fake
# vouch tag (same image, aliased) so the vouch gate passes.
#
# No Cloud Build, no GAR push, no credentials consumed.
# Host platform only (no multi-arch).

rbfk_kludge() {
  zrbfk_sentinel

  buc_doc_brief "Kludge a vessel image locally for development (no Cloud Build, no GAR push)"
  buc_doc_param "vessel" "Vessel sigil or path to vessel directory"
  buc_doc_shown || return 0

  # Dirty-tree guard — kludge images must correspond to a committed state
  bug_require_clean_tree_creed "${RBCC_creed_clean_build}"

  # Resolve vessel argument (sigil or path)
  zrbfc_resolve_vessel "${BUZ_FOLIO:-}"
  local -r z_vessel_dir=$(<"${ZRBFC_VESSEL_RESOLVED_DIR_FILE}")
  test -n "${z_vessel_dir}" || buc_die "Empty resolved vessel path"

  # Load vessel configuration
  zrbfc_load_vessel "${z_vessel_dir}"

  # Validate conjure mode (bind and graft don't have local Dockerfiles)
  test "${RBRV_VESSEL_MODE}" = "rbnve_conjure" \
    || buc_die "Kludge only supports conjure vessels (got: ${RBRV_VESSEL_MODE})"
  test -n "${RBRV_CONJURE_DOCKERFILE:-}" \
    || buc_die "Vessel '${RBRV_SIGIL}' has no RBRV_CONJURE_DOCKERFILE"
  test -n "${RBRV_CONJURE_BLDCONTEXT:-}" \
    || buc_die "Vessel '${RBRV_SIGIL}' has no RBRV_CONJURE_BLDCONTEXT"
  test -f "${RBRV_CONJURE_DOCKERFILE}" \
    || buc_die "Dockerfile not found: ${RBRV_CONJURE_DOCKERFILE}"
  test -d "${RBRV_CONJURE_BLDCONTEXT}" \
    || buc_die "Build context not found: ${RBRV_CONJURE_BLDCONTEXT}"

  # Resolve base images — mirror conjure's anchor-aware resolution so an anchored
  # vessel built via kludge resolves the same GAR-anchored layers as conjure.
  # Slot types diverge by credential need: anchored refs point into GAR and need
  # GCP auth, so misses refuse with a wrest remediation (credentialed-out-of-band).
  # Origin refs are public upstream and need no credentials, so misses auto-pull
  # inline. The presence guard's local-cache assertion is the tag-drift defense:
  # docker build (buildx default: no re-pull) runs against the cached image.
  local -r z_gar_repo_base="${RBGD_GAR_LOCATION}${RBGC_GAR_HOST_SUFFIX}/${RBGD_GAR_PROJECT_ID}/${RBDC_GAR_REPOSITORY}"
  local z_build_args=()
  local z_slot=""
  local z_origin_var=""
  local z_anchor_var=""
  local z_origin=""
  local z_anchor=""
  local z_slot_ref=""
  local z_pkg_path=""
  local z_tag=""
  local z_miss=""
  local z_anchored_misses=()
  for z_slot in 1 2 3; do
    z_origin_var="RBRV_IMAGE_${z_slot}_ORIGIN"
    z_anchor_var="RBRV_IMAGE_${z_slot}_ANCHOR"
    z_origin="${!z_origin_var:-}"
    z_anchor="${!z_anchor_var:-}"

    if test -z "${z_origin}" && test -n "${z_anchor}"; then
      buc_die "Malformed regime: ${z_anchor_var}=${z_anchor} set but ${z_origin_var} is empty"
    fi
    test -n "${z_origin}" || continue

    if test -n "${z_anchor}"; then
      case "${z_anchor}" in
        *:*) : ;;
        *)   buc_die "Invalid ${z_anchor_var} locator format (expected package-path:tag): ${z_anchor}" ;;
      esac
      z_pkg_path="${z_anchor%:*}"
      z_tag="${z_anchor##*:}"
      test -n "${z_pkg_path}" || buc_die "Package path is empty in ${z_anchor_var}: ${z_anchor}"
      test -n "${z_tag}"      || buc_die "Tag is empty in ${z_anchor_var}: ${z_anchor}"
      z_slot_ref="${z_gar_repo_base}/${z_pkg_path}:${z_tag}"
      buc_info "Image slot ${z_slot} (anchored): ${z_slot_ref}"
      zrbfk_image_present_predicate "${z_slot_ref}" \
        || z_anchored_misses+=("${z_anchor}")
    else
      z_slot_ref="${z_origin}"
      buc_info "Image slot ${z_slot} (pass-through): ${z_slot_ref}"
      if ! zrbfk_image_present_predicate "${z_slot_ref}"; then
        buc_info "Origin image not cached — pulling from upstream: ${z_slot_ref}"
        docker pull "${z_slot_ref}" \
          || buc_die "docker pull failed for origin slot ${z_slot}: ${z_slot_ref}"
        zrbfk_image_present_predicate "${z_slot_ref}" \
          || buc_die "Origin image still absent from local cache after pull: ${z_slot_ref}"
      fi
    fi

    z_build_args+=("--build-arg" "RBF_IMAGE_${z_slot}=${z_slot_ref}")
  done
  (( ${#z_build_args[@]} )) || buc_die "No RBRV_IMAGE_n_ORIGIN found in vessel config"

  if (( ${#z_anchored_misses[@]} )); then
    buc_warn "Kludge cannot proceed — anchored base image(s) not cached locally"
    buc_bare "  Anchored slots point into GAR and require credentials. Kludge runs"
    buc_bare "  uncredentialed, so anchored images must be wrested into the local"
    buc_bare "  docker cache out-of-band before kludge runs."
    buc_bare ""
    buc_bare "  Anchored slots (wrest from GAR):"
    for z_miss in "${z_anchored_misses[@]}"; do
      buc_tabtarget "${RBZ_WREST_IMAGE}" "${z_miss}"
    done
    buc_bare ""
    buc_die "Local image cache incomplete — see remediation above"
  fi

  buc_step "Validating Dockerfile hygiene"
  rbfh_dockerfile_check "${RBRV_CONJURE_DOCKERFILE}"

  # Timestamp for chronological sorting, git describe for commit provenance
  # BURD_GIT_CONTEXT is exported by bud_dispatch; dirty-tree guard above ensures clean tree
  local -r z_hallmark="${RBGC_HALLMARK_PREFIX_KLUDGE}${BURD_NOW_STAMP:2:6}${BURD_NOW_STAMP:9:6}-${BURD_GIT_CONTEXT}"

  # Construct image refs matching compose/vouch-gate format (new layout — hallmark-as-tag).
  local -r z_image_ref="${ZRBFC_REGISTRY_HOST}/${ZRBFC_REGISTRY_PATH}/${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_IMAGE}:${z_hallmark}"
  local -r z_vouch_ref="${ZRBFC_REGISTRY_HOST}/${ZRBFC_REGISTRY_PATH}/${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${RBGC_ARK_BASENAME_VOUCH}:${z_hallmark}"

  buc_step "Kludge build: ${RBRV_SIGIL}"
  buc_info "Hallmark: ${z_hallmark}"
  buc_info "Image tag: ${z_image_ref}"

  # Build locally (host platform only — no multi-arch for dev builds).
  # Buildx defaults to not re-pulling base images; the presence guard above has
  # already verified every slot is in the local cache, so the build never networks.
  buc_step "Building image locally"
  # docker is Windows-native under Cygwin; hand it Windows-form paths (no-op when
  # a path is already relative or native, and off Cygwin).
  local z_norm_dockerfile=""
  z_norm_dockerfile=$(buc_native_path_capture "${RBRV_CONJURE_DOCKERFILE}") \
    || buc_die "Cannot normalize conjure Dockerfile path for docker: ${RBRV_CONJURE_DOCKERFILE}"
  local z_norm_context=""
  z_norm_context=$(buc_native_path_capture "${RBRV_CONJURE_BLDCONTEXT}") \
    || buc_die "Cannot normalize conjure build-context path for docker: ${RBRV_CONJURE_BLDCONTEXT}"
  docker build \
    "${z_build_args[@]}" \
    -f "${z_norm_dockerfile}" \
    -t "${z_image_ref}" \
    "${z_norm_context}" \
    || buc_die "Local build failed for ${RBRV_SIGIL}"

  # Create fake vouch tag (same image, aliased — satisfies rbob_charge vouch gate)
  buc_step "Creating vouch tag"
  docker tag "${z_image_ref}" "${z_vouch_ref}" \
    || buc_die "Failed to create vouch tag"

  # Persist facts — mirror conjure/bind/graft so downstream consumers (theurge)
  # can build full refs uniformly regardless of mode.
  buf_write_fact_single "${RBF_FACT_HALLMARK}" "${z_hallmark}"
  buf_write_fact_single "${RBF_FACT_GAR_ROOT}" "${ZRBFC_REGISTRY_HOST}/${ZRBFC_REGISTRY_PATH}"
  buf_write_fact_single "${RBF_FACT_ARK_STEM}" "${RBGL_HALLMARKS_ROOT}/${z_hallmark}"

  buc_success "Kludge build complete: ${RBRV_SIGIL}"
  buc_bare ""
  buc_bare "  Hallmark: ${z_hallmark}"
  buc_bare "  Image:        ${z_image_ref}"
  buc_bare "  Vouch:        ${z_vouch_ref}"
  buc_bare ""
  buc_bare "  Auto-install via:"
  buc_bare "    tt/rbw-cKB.KludgeBottle.sh <moniker>   (bottle vessel)"
  buc_bare "    tt/rbw-cKS.KludgeSentry.sh <moniker>   (sentry vessel)"

  # Beckon the consumers of the hallmark this kludge just wrote
  rbfb_beckon_hallmark "${z_hallmark}"
}

# eof
