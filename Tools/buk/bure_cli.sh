#!/bin/bash
#
# Copyright 2025 Scale Invariant, Inc.
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
# BURE CLI - Command line interface for BURE regime operations
#
# BURE is an ambient regime — variables are read from the current environment.
# No file sourcing is required; callers export BURE_* variables before invoking.

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# Command Functions

bure_validate() {
  buc_doc_brief "Validate BURE environment regime via enrollment report"
  buc_doc_shown || return 0

  buc_step "Validating BURE ambient environment"
  buv_report BURE "Environment Regime"
  buc_step "BURE configuration valid"
}

bure_render() {
  buc_doc_brief "Display diagnostic view of BURE environment regime"
  buc_doc_shown || return 0

  buv_render BURE "BURE - Bash Utility Environment Regime (ambient)" ""
}

######################################################################
# Furnish and Main

zbure_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env_done || return 0

  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/bure_regime.sh"
  source "${BURD_BUK_DIR}/bupr_regime.sh"

  zbuv_kindle
  zburd_kindle
  zburd_enforce

  # BURE is ambient — no env file to source, variables already in environment
  zbure_kindle
  zbure_enforce

  zbupr_kindle
}

buc_execute bure_ "Bash Utility Environment Regime" zbure_furnish "$@"

# eof
