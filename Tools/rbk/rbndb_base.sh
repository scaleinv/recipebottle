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
# Recipe Bottle Depot Regime Bespoke - Tripwire helpers
#
# Implements the depot-immutable tripwire. At end of successful levy
# the Payor inscribes a FROM-scratch image carrying rbmm_moorings/rbrd.env to
# GAR at rbi_df/rbrd:tripwire. Every cloud-submitting command pulls
# that image and exact-byte-diffs the file before submitting, so any
# post-levy hand-edit of rbrd.env dies loudly instead of silently
# differing from the depot's worker-pool quotas, region, and identity.
#
# Public functions:
#   rbrd_inscribe <bearer_token>   — host-side push at end of levy
#   rbrd_check    <bearer_token>   — pre-submit existence + byte-diff
#
# Module convention: rbn{R}{X}_ where R=d (depot regime) and X=b
# (bespoke implementation). See CLAUDE.md "Prefix Naming Discipline".

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBNDB_SOURCED:-}" || buc_die "Module rbndb multiply sourced - check sourcing hierarchy"
ZRBNDB_SOURCED=1

######################################################################
# Internal Functions (zrbndb_*)

zrbndb_kindle() {
  test -z "${ZRBNDB_KINDLED:-}" || buc_die "Module rbndb already kindled"

  buc_log_args "Ensure dependencies are kindled first"
  zrbgc_sentinel
  zrbgl_sentinel
  zrbrd_sentinel
  zrbdc_sentinel

  # Tripwire image FQN composed once at kindle time from depot's GAR
  # coordinates + the rbi_df depot-facts namespace.
  # Shape: <region>-docker.pkg.dev/<depot-project>/<gar-repo>/rbi_df/rbrd:tripwire
  readonly ZRBNDB_REGISTRY_HOST="${RBRD_GCP_REGION}${RBGC_GAR_HOST_SUFFIX}"
  readonly ZRBNDB_TRIPWIRE_IMAGE="${ZRBNDB_REGISTRY_HOST}/${RBDC_DEPOT_PROJECT_ID}/${RBDC_GAR_REPOSITORY}/${RBGL_DEPOT_FACTS_ROOT}/rbrd:tripwire"

  # Per-command temp prefixes (forensic-preserving — files persist after run)
  readonly ZRBNDB_INSCRIBE_PREFIX="${BURD_TEMP_DIR}/rbndb_inscribe_"
  readonly ZRBNDB_CHECK_PREFIX="${BURD_TEMP_DIR}/rbndb_check_"

  readonly ZRBNDB_KINDLED=1
}

zrbndb_sentinel() {
  test "${ZRBNDB_KINDLED:-}" = "1" || buc_die "Module rbndb not kindled - call zrbndb_kindle first"
}

# Authenticate the host docker client to the depot's GAR registry
# using a bearer token. Idempotent — repeated calls refresh credential.
# Bounded retry on the moby/moby#44350 premature-timeout transient (see
# RBGC_DOCKER_LOGIN_TRANSIENT_SIGNATURE); the rbgo_docker_login twin serves the
# foundry cluster, but the depot-regime cluster does not reach rbgo, so this
# shares only the signature + retry-budget constants out of rbgc. Real auth
# failures do not match the signature and fail fast.
# Args: bearer_token stderr_file
zrbndb_docker_login() {
  zrbndb_sentinel

  local -r z_token="${1}"
  local -r z_stderr_file="${2}"

  local z_attempt=0
  local z_rc=0

  while :; do
    z_attempt=$((z_attempt + 1))

    z_rc=0
    printf '%s' "${z_token}" \
      | docker login -u oauth2accesstoken --password-stdin "${ZRBNDB_REGISTRY_HOST}" \
          > /dev/null 2>"${z_stderr_file}" \
      || z_rc=$?

    test "${z_rc}" -ne 0 || break

    [[ "$(<"${z_stderr_file}")" == *"${RBGC_DOCKER_LOGIN_TRANSIENT_SIGNATURE}"* ]] \
      || buc_die "Docker login to ${ZRBNDB_REGISTRY_HOST} failed — see ${z_stderr_file}"

    test "${z_attempt}" -lt "${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS}" \
      || buc_die "Docker login to ${ZRBNDB_REGISTRY_HOST} failed after ${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS} attempts (transient daemon->registry timeout, moby#44350) — see ${z_stderr_file}"

    buc_warn "Docker login transient (attempt ${z_attempt}/${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS}, moby#44350 timeout) — retrying in ${RBGC_HTTP_TRANSIENT_RETRY_SLEEP_SEC}s"
    sleep "${RBGC_HTTP_TRANSIENT_RETRY_SLEEP_SEC}"
  done
}

# Run a host-docker registry read (manifest inspect, pull) with bounded
# retry on the same moby#44350 premature-timeout transient login wraps
# above. The docker client's internal retry covers only layer downloads;
# the initial resolve leg (token fetch + manifest HEAD) is one-shot, so a
# single daemon->registry timeout otherwise kills the command. Absorbs
# ONLY the surveyed signature, warning each bend. A non-matching failure
# returns rc to the caller's own error path untouched. An exhausted budget
# dies HERE naming the transient — falling through to the caller would
# misdiagnose a network timeout as the caller's condition (rbrd_check's
# absent-tripwire path prescribes depot re-levy; that must never fire on
# a timeout).
# Args: stdout_file stderr_file command...
zrbndb_registry_read() {
  zrbndb_sentinel

  local -r z_stdout_file="${1}"
  local -r z_stderr_file="${2}"
  shift 2

  local z_attempt=0
  local z_rc=0

  while :; do
    z_attempt=$((z_attempt + 1))

    z_rc=0
    "$@" > "${z_stdout_file}" 2>"${z_stderr_file}" || z_rc=$?

    test "${z_rc}" -ne 0 || return 0

    [[ "$(<"${z_stderr_file}")" == *"${RBGC_DOCKER_LOGIN_TRANSIENT_SIGNATURE}"* ]] \
      || return "${z_rc}"

    test "${z_attempt}" -lt "${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS}" \
      || buc_die "${1} registry read failed after ${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS} attempts (transient daemon->registry timeout, moby#44350) — see ${z_stderr_file}"

    buc_warn "Registry read transient (attempt ${z_attempt}/${RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS}, moby#44350 timeout) — retrying in ${RBGC_HTTP_TRANSIENT_RETRY_SLEEP_SEC}s"
    sleep "${RBGC_HTTP_TRANSIENT_RETRY_SLEEP_SEC}"
  done
}

######################################################################
# External Functions (rbrd_*)

# Inscribe the tripwire image at end of successful levy.
# Pre-push existence guard: image present → fatal (depot already
# inscribed; must be unmade and relevied to refresh).
# Token sources (in order): positional $1, then BUZ_FOLIO (tabtarget
# param1 channel). The former is the consuming-CLI path (caller has a
# token in scope); the latter is the rbw-rdi tabtarget path.
rbrd_inscribe() {
  zrbndb_sentinel

  buc_doc_brief "Inscribe RBRD tripwire image to GAR (host-side, at end of levy)"
  buc_doc_param "bearer_token" "OAuth access token with GAR write (Payor)"
  buc_doc_shown || return 0

  # Dirty-tree guard — the tripwire image ships the tracked rbrd.env bytes, and
  # rbrd_check forever after compares local config against them; the inscribed
  # reference must be a committed state.
  bug_require_clean_tree_creed "${RBCC_creed_clean_inscribe}"

  local -r z_token="${1:-${BUZ_FOLIO:-}}"
  test -n "${z_token}" || buc_die "rbrd_inscribe: bearer token required (positional arg or BUZ_FOLIO)"

  local -r z_login_stderr="${ZRBNDB_INSCRIBE_PREFIX}login_stderr.txt"
  local -r z_manifest_stderr="${ZRBNDB_INSCRIBE_PREFIX}manifest_stderr.txt"
  local -r z_build_dir="${ZRBNDB_INSCRIBE_PREFIX}build"
  local -r z_dockerfile="${z_build_dir}/Dockerfile"
  local -r z_rbrd_copy="${z_build_dir}/${RBCC_rbrd_basename}"
  local -r z_build_stdout="${ZRBNDB_INSCRIBE_PREFIX}build_stdout.txt"
  local -r z_build_stderr="${ZRBNDB_INSCRIBE_PREFIX}build_stderr.txt"
  local -r z_push_stdout="${ZRBNDB_INSCRIBE_PREFIX}push_stdout.txt"
  local -r z_push_stderr="${ZRBNDB_INSCRIBE_PREFIX}push_stderr.txt"

  buc_step "Inscribe RBRD tripwire image to GAR"
  buc_log_args "Target: ${ZRBNDB_TRIPWIRE_IMAGE}"

  zrbndb_docker_login "${z_token}" "${z_login_stderr}"

  buc_log_args "Pre-push existence guard via docker manifest inspect"
  if docker manifest inspect "${ZRBNDB_TRIPWIRE_IMAGE}" > /dev/null 2>"${z_manifest_stderr}"; then
    buc_warn "Tripwire image already inscribed: ${ZRBNDB_TRIPWIRE_IMAGE}"
    buc_info "RBRD is depot-time-immutable. To refresh the tripwire, the depot"
    buc_info "must be unmade and relevied:"
    buc_info "  rbw-dU \$(rbw-dl)        # unmake the depot"
    buc_info "  rbw-dL                  # relevy with new rbrd.env"
    buc_die "Cannot inscribe over existing tripwire (would mask drift)"
  fi

  # Pin the canonical build-runner platform. The image is FROM-scratch data
  # (rbrd.env only, never executed), so its architecture is semantically
  # irrelevant — but docker's manifest selection on pull demands a platform
  # match. Pinning one canonical platform on both inscribe (build) and check
  # (pull/create) makes the tripwire pullable on every host regardless of the
  # levying host's arch, instead of baking the inscriber's native arch.
  buc_log_args "Build FROM-scratch image carrying ${RBCC_rbrd_file}"
  mkdir -p "${z_build_dir}" || buc_die "Failed to create build dir ${z_build_dir}"

  cp "${RBCC_rbrd_file}" "${z_rbrd_copy}" \
    || buc_die "Failed to copy ${RBCC_rbrd_file} into build context"

  printf '%s\n' \
    'FROM scratch' \
    "COPY ${RBCC_rbrd_basename} /${RBCC_rbrd_basename}" \
    > "${z_dockerfile}" \
    || buc_die "Failed to write Dockerfile at ${z_dockerfile}"

  docker build --platform "${RBGC_BUILD_RUNNER_PLATFORM}" -t "${ZRBNDB_TRIPWIRE_IMAGE}" "${z_build_dir}" \
      > "${z_build_stdout}" 2>"${z_build_stderr}" \
    || buc_die "docker build failed for ${ZRBNDB_TRIPWIRE_IMAGE} — see ${z_build_stderr}"

  buc_log_args "Push tripwire image to GAR"
  docker push "${ZRBNDB_TRIPWIRE_IMAGE}" \
      > "${z_push_stdout}" 2>"${z_push_stderr}" \
    || buc_die "docker push failed for ${ZRBNDB_TRIPWIRE_IMAGE} — see ${z_push_stderr}"

  buc_success "Tripwire inscribed: ${ZRBNDB_TRIPWIRE_IMAGE}"
}

# Check local rbmm_moorings/rbrd.env against the inscribed tripwire image
# before submitting cloud work. Exact-byte mismatch, missing image,
# or registry/auth failure all fatal with recovery guidance.
# Token sources mirror rbrd_inscribe: positional $1 then BUZ_FOLIO.
rbrd_check() {
  zrbndb_sentinel

  buc_doc_brief "Check local rbrd.env against inscribed tripwire image (drift detector)"
  buc_doc_param "bearer_token" "OAuth access token with GAR read (any role: Payor, Director, Retriever)"
  buc_doc_shown || return 0

  local -r z_token="${1:-${BUZ_FOLIO:-}}"
  test -n "${z_token}" || buc_die "rbrd_check: bearer token required (positional arg or BUZ_FOLIO)"

  local -r z_login_stderr="${ZRBNDB_CHECK_PREFIX}login_stderr.txt"
  local -r z_manifest_stderr="${ZRBNDB_CHECK_PREFIX}manifest_stderr.txt"
  local -r z_pull_stdout="${ZRBNDB_CHECK_PREFIX}pull_stdout.txt"
  local -r z_pull_stderr="${ZRBNDB_CHECK_PREFIX}pull_stderr.txt"
  local -r z_create_stdout="${ZRBNDB_CHECK_PREFIX}create_stdout.txt"
  local -r z_create_stderr="${ZRBNDB_CHECK_PREFIX}create_stderr.txt"
  local -r z_cp_stderr="${ZRBNDB_CHECK_PREFIX}cp_stderr.txt"
  local -r z_rm_stderr="${ZRBNDB_CHECK_PREFIX}rm_stderr.txt"
  local -r z_inscribed_file="${ZRBNDB_CHECK_PREFIX}${RBCC_rbrd_basename}.inscribed"

  buc_log_args "Tripwire check against: ${ZRBNDB_TRIPWIRE_IMAGE}"

  zrbndb_docker_login "${z_token}" "${z_login_stderr}"

  buc_log_args "Existence check via docker manifest inspect"
  zrbndb_registry_read /dev/null "${z_manifest_stderr}" \
      docker manifest inspect "${ZRBNDB_TRIPWIRE_IMAGE}" \
    || {
      buc_warn "Tripwire image absent or unreachable: ${ZRBNDB_TRIPWIRE_IMAGE}"
      buc_info "Manifest-inspect stderr: ${z_manifest_stderr}"
      buc_info "If depot has not been inscribed, or the tripwire was jettisoned,"
      buc_info "re-levy the depot to mint the tripwire:"
      buc_info "  rbw-dU \$(rbw-dl)        # unmake (if a stale depot exists)"
      buc_info "  rbw-dL                  # levy + inscribe tripwire"
      buc_die "Cannot proceed without tripwire — depot regime drift cannot be detected"
    }

  # Pull the canonical build-runner platform explicitly: the tripwire is
  # inscribed single-platform (see rbrd_inscribe), so a host-default pull would
  # fail on any host whose native arch differs from RBGC_BUILD_RUNNER_PLATFORM.
  buc_log_args "Pull tripwire image"
  zrbndb_registry_read "${z_pull_stdout}" "${z_pull_stderr}" \
      docker pull --platform "${RBGC_BUILD_RUNNER_PLATFORM}" "${ZRBNDB_TRIPWIRE_IMAGE}" \
    || buc_die "docker pull failed for ${ZRBNDB_TRIPWIRE_IMAGE} — see ${z_pull_stderr}"

  buc_log_args "Create temp container to extract /${RBCC_rbrd_basename}"
  # The tripwire is FROM-scratch (no CMD/ENTRYPOINT); the Linux daemon rejects
  # docker create on such an image with "no command specified". The container
  # is never started — only docker cp + docker rm touch it — so a never-executed
  # placeholder command satisfies the create-time requirement harmlessly.
  docker create --platform "${RBGC_BUILD_RUNNER_PLATFORM}" "${ZRBNDB_TRIPWIRE_IMAGE}" "/${RBCC_rbrd_basename}" \
      > "${z_create_stdout}" 2>"${z_create_stderr}" \
    || buc_die "docker create failed for ${ZRBNDB_TRIPWIRE_IMAGE} — see ${z_create_stderr}"

  local -r z_cid=$(<"${z_create_stdout}")
  test -n "${z_cid}" || buc_die "docker create returned empty container ID — see ${z_create_stdout}"

  # docker cp's host-side dest must be Windows-native under Cygwin; the cp source
  # is a container path and stays POSIX. z_inscribed_file itself stays POSIX for
  # the openssl read below — only the cp argument is normalized.
  local z_inscribed_native=""
  z_inscribed_native=$(buc_native_path_capture "${z_inscribed_file}") \
    || buc_die "Cannot normalize inscribed-file path for docker cp: ${z_inscribed_file}"

  docker cp "${z_cid}:/${RBCC_rbrd_basename}" "${z_inscribed_native}" 2>"${z_cp_stderr}" \
    || {
      docker rm "${z_cid}" > /dev/null 2>"${z_rm_stderr}" \
        || buc_warn "Failed to remove temp container ${z_cid} — see ${z_rm_stderr}"
      buc_die "docker cp failed extracting /${RBCC_rbrd_basename} from tripwire image — see ${z_cp_stderr}"
    }

  docker rm "${z_cid}" > /dev/null 2>"${z_rm_stderr}" \
    || buc_warn "Failed to remove temp container ${z_cid} — see ${z_rm_stderr}"

  # Byte-exact match via openssl sha256 digests (declared dependency; replaces
  # cmp). On drift, refuse to proceed and point the operator at both copies for
  # manual inspection — no diff dependency for the drift report.
  local z_inscribed_digest=""
  local z_local_digest=""
  z_inscribed_digest=$(openssl dgst -sha256 -r < "${z_inscribed_file}") \
    || buc_die "Failed to digest inscribed tripwire copy: ${z_inscribed_file}"
  z_local_digest=$(openssl dgst -sha256 -r < "${RBCC_rbrd_file}") \
    || buc_die "Failed to digest local ${RBCC_rbrd_file}"
  if [[ "${z_inscribed_digest}" != "${z_local_digest}" ]]; then
    buc_warn "RBRD drift detected"
    buc_info "Local ${RBCC_rbrd_file} differs from the depot-inscribed copy (sha256 mismatch)."
    buc_info "Inscribed copy: ${z_inscribed_file}"
    buc_info "Local copy:     ${RBCC_rbrd_file}"
    buc_info "Recovery options:"
    buc_info "  (a) Restore ${RBCC_rbrd_file} to match the inscribed copy (preserves depot)."
    buc_info "  (b) Unmake and re-levy the depot if rbrd.env genuinely needs to change:"
    buc_info "        rbw-dU \$(rbw-dl)"
    buc_info "        rbw-dL"
    buc_die "Refusing to submit cloud work against drifted depot regime"
  fi

  buc_log_args "Tripwire match — depot regime aligned"
}

# eof
