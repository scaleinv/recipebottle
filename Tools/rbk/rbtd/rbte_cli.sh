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
# RBTE CLI - Theurge test engine CLI entry point
#
# Enrolled in rbz_zipper, dispatched by rbw_workbench via buz_exec_lookup.
# Public functions (rbte_build/test/run/suite/single) live in rbte_engine.sh;
# fixture/suite folio arrives via BUZ_FOLIO from the colophon channel.

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Furnish and Main

zrbte_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BURD_TABTARGET_DIR    " "Tabtarget directory (dispatch-provided; codegen input)"
  buc_doc_env "BURD_TEMP_DIR         " "Temp directory (dispatch-provided; codegen scratch)"
  buc_doc_env "BURD_STATION_FILE     " "Station regime file (launcher-provided; dowse log-dir source)"
  buc_doc_env_done || return 0

  local z_cli_dir="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/buz_zipper.sh"
  source "${BURD_BUK_DIR}/buwz_zipper.sh"
  source "${z_cli_dir}/../rbcc_constants.sh"
  source "${z_cli_dir}/../rbpc_constants.sh"
  source "${z_cli_dir}/../rbgc_constants.sh"
  source "${z_cli_dir}/../rbz_zipper.sh"
  source "${z_cli_dir}/rbte_engine.sh"

  zbuv_kindle
  zburd_kindle
  zbuz_kindle
  zrbz_kindle
  zbuwz_kindle
  zrbgc_kindle
  zrbte_kindle
}

buc_execute rbte_ "Theurge test engine" zrbte_furnish "$@"

# eof
