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
# Recipe Bottle Keycloak orchestrator CLI (setup / teardown) — the gateway to
# the rbxk synthetic-federation test facility. Light furnish: the module composes
# the heavy verbs (charge/quench/affiance/jilt) through their own tabtargets, so
# this CLI itself carries no GCP/OAuth stack — only the clean-tree gate, the rbcc
# path literals, and the module.

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"

zrbxk_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BURD_TABTARGET_DIR    " "Tabtarget directory (dispatch-provided) — the facility composes charge/quench/affiance/jilt through their tabtargets"
  buc_doc_env "BURD_TEMP_DIR         " "Dispatch-provided temp directory (JWKS bridge scratch)"
  buc_doc_env_done || return 0

  local z_rbk_kit_dir="${BASH_SOURCE[0]%/*}"

  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/bubc_constants.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bug_git.sh"
  source "${z_rbk_kit_dir}/rbcc_constants.sh"
  source "${z_rbk_kit_dir}/rbxk_keycloak.sh"

  zbuv_kindle
  zburd_kindle
  zrbcc_kindle
  zrbxk_kindle
}

buc_execute rbxk_ "Recipe Bottle Keycloak facility" zrbxk_furnish "$@"

# eof
