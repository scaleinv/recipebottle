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
# Recipe Bottle Foundry Ledger - kindle entry: the single rbfl inclusion-guard and
# kindle/sentinel, sourcing the Foundry Core entry (rbfck_) and the guard-free body
# clusters (rbfla_ anoint, rbfly_ yoke, rbfld_ delete, rbfln_ inventory, rbflw_ wrest).
# The readonly ZRBFL_* constants the kindle sets are read globally.

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBFL_SOURCED:-}" || buc_die "Module rbfl multiply sourced - check sourcing hierarchy"
ZRBFL_SOURCED=1

# Source shared Foundry Core entry and the guard-free body clusters
source "${BASH_SOURCE[0]%/*}/rbfc0_core.sh"
source "${BASH_SOURCE[0]%/*}/rbfla_anoint.sh"
source "${BASH_SOURCE[0]%/*}/rbfly_yoke.sh"
source "${BASH_SOURCE[0]%/*}/rbflf_feoff.sh"
source "${BASH_SOURCE[0]%/*}/rbfld_delete.sh"
source "${BASH_SOURCE[0]%/*}/rbfln_inventory.sh"
source "${BASH_SOURCE[0]%/*}/rbflw_wrest.sh"

# Cross-source from the rbld (Lode) family: abjure dispatches its GAR package
# delete cloud-side through the build-assembly spine and the shared cloud-delete
# body, exactly as banish does (the cinch-blessed narrow cross into made-side
# delete); yoke reaches the touchmark kind-decode for its reliquary kind gate.
# All three carry their own inclusion guards, so this single-source-per-process
# reach raises no double-source; they read only rbfc-level state (zrbfc_sentinel),
# which this process kindles.
source "${BASH_SOURCE[0]%/*}/rbldk_kind.sh"
source "${BASH_SOURCE[0]%/*}/rblds_spine.sh"
source "${BASH_SOURCE[0]%/*}/rbldd_delete.sh"

######################################################################
# Internal Functions (zrbfl_*)

zrbfl_kindle() {
  test -z "${ZRBFL_KINDLED:-}" || buc_die "Module rbfl already kindled"

  buc_log_args 'Validate Foundry Core is kindled'
  zrbfc_sentinel

  buc_log_args 'Define delete operation file prefix'
  readonly ZRBFL_DELETE_PREFIX="${BURD_TEMP_DIR}/rbfl_delete_"

  readonly ZRBFL_KINDLED=1
}

zrbfl_sentinel() {
  zrbfc_sentinel
  test "${ZRBFL_KINDLED:-}" = "1" || buc_die "Module rbfl not kindled - call zrbfl_kindle first"
}

# eof
