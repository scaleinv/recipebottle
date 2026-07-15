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
# Recipe Bottle Lode - kindle entry: the single rbld inclusion-guard and kindle,
# sourcing the guard-free body clusters (rbldl_ lifecycle, rblds_ capture spine,
# rbldb_ bole). The readonly ZRBLD_* constants the kindle sets are read globally
# by the clusters.

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBLD_SOURCED:-}" || buc_die "Module rbld multiply sourced - check sourcing hierarchy"
ZRBLD_SOURCED=1

# Source shared Foundry Core module
source "${BASH_SOURCE[0]%/*}/rbfc0_core.sh"

# Lode body clusters, sourced once here at the single rbld entry. Most are
# guard-free; rblds_ (build-assembly spine) and rbldd_ (cloud delete) are
# multiply-sourced — rbfl0_ledger cross-sources them for made-side abjure
# — so they carry their own inclusion guards (BCG single-guard exception).
source "${BASH_SOURCE[0]%/*}/rbldk_kind.sh"
source "${BASH_SOURCE[0]%/*}/rbldl_lifecycle.sh"
source "${BASH_SOURCE[0]%/*}/rblds_spine.sh"
source "${BASH_SOURCE[0]%/*}/rbldd_delete.sh"
source "${BASH_SOURCE[0]%/*}/rbldb_bole.sh"
source "${BASH_SOURCE[0]%/*}/rbldr_reliquary.sh"
source "${BASH_SOURCE[0]%/*}/rbldw_underpin.sh"
source "${BASH_SOURCE[0]%/*}/rbldv_immure.sh"

######################################################################
# Internal Functions (zrbld_*)

zrbld_kindle() {
  test -z "${ZRBLD_KINDLED:-}" || buc_die "Module rbld already kindled"

  buc_log_args 'Validate Foundry Core is kindled'
  zrbfc_sentinel

  buc_log_args 'RBGJL ensconce step scripts (same Tools directory)'
  local z_self_dir="${BASH_SOURCE[0]%/*}"
  readonly ZRBLD_RBGJL_STEPS_DIR="${z_self_dir}/rbgjl"
  test -d "${ZRBLD_RBGJL_STEPS_DIR}" || buc_die "RBGJL steps directory not found: ${ZRBLD_RBGJL_STEPS_DIR}"

  buc_log_args 'Define ensconce operation file prefix'
  readonly ZRBLD_ENSCONCE_PREFIX="${BURD_TEMP_DIR}/rbld_ensconce_"

  buc_log_args 'Define conclave operation file prefix'
  readonly ZRBLD_CONCLAVE_PREFIX="${BURD_TEMP_DIR}/rbld_conclave_"

  buc_log_args 'Define underpin operation file prefix'
  readonly ZRBLD_UNDERPIN_PREFIX="${BURD_TEMP_DIR}/rbld_underpin_"

  buc_log_args 'Define immure operation file prefix'
  readonly ZRBLD_IMMURE_PREFIX="${BURD_TEMP_DIR}/rbld_immure_"

  # Google-hosted docker builder — always pullable even under NO_PUBLIC_EGRESS.
  # Conclave captures the reliquary tool cohort itself, so it cannot resolve its
  # builders from a reliquary (the bootstrap it would be creating); both conclave
  # steps ride this Google-hosted builder instead of the reliquary-resolved docker.
  buc_log_args 'Define Google-hosted docker builder image'
  readonly ZRBLD_GOOGLE_DOCKER_BUILDER="gcr.io/cloud-builders/docker"

  # gcrane builder — crane's Google-auth sibling (same cp/manifest/tag engine).
  # The bole capture step rides this: gcrane authenticates GAR (*.pkg.dev)
  # ambiently through google.Keychain -> ADC -> the GCE metadata server as the
  # Mason SA, so the step needs no token fetch, no crane auth login, and no
  # credential-helper image. The :debug variant carries /busybox/sh and busybox
  # sha256sum for the orchestration (the non-debug image is distroless — no
  # shell). Floating Google-hosted name, like ZRBLD_GOOGLE_DOCKER_BUILDER above:
  # gcr.io is always-pullable under Private Google Access, and the persistent
  # :debug tag is the name we ride — version-freezing belongs to the reliquary
  # gather, not a bash-frozen digest in this constant. Auth canon: RBSCB.
  buc_log_args 'Define Google-hosted gcrane builder image'
  readonly ZRBLD_GCRANE_BUILDER="gcr.io/go-containerregistry/gcrane:debug"

  # gcloud builder — python3 + stdlib urllib/json, Google-hosted and always pullable.
  # The immure select step (rbgjl07) rides this to PARSE the upstream OCI index, which
  # the no-jq bash GCB discipline does not cover; python is the native tool, the
  # rbgjl06-package-delete.py precedent. Floating bootstrap (same itch as the gcrane
  # builder above) — bounded: capture runs as the writer-only Mason SA.
  buc_log_args 'Define Google-hosted gcloud (python3) builder image'
  readonly ZRBLD_GCLOUD_BUILDER="gcr.io/cloud-builders/gcloud:latest"

  buc_log_args 'Define divine operation file prefix'
  readonly ZRBLD_DIVINE_PREFIX="${BURD_TEMP_DIR}/rbld_divine_"

  buc_log_args 'Define augur operation file prefix'
  readonly ZRBLD_AUGUR_PREFIX="${BURD_TEMP_DIR}/rbld_augur_"

  buc_log_args 'Define banish operation file prefix'
  readonly ZRBLD_BANISH_PREFIX="${BURD_TEMP_DIR}/rbld_banish_"

  readonly ZRBLD_KINDLED=1
}

zrbld_sentinel() {
  zrbfc_sentinel
  test "${ZRBLD_KINDLED:-}" = "1" || buc_die "Module rbld not kindled - call zrbld_kindle first"
}

# eof
