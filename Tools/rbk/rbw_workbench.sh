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
# RBW Workbench - Routes Recipe Bottle commands to CLIs via zipper registry
#
# All commands dispatch via buz_exec_lookup (see rbz_zipper.sh for colophon mapping).
# Qualification gate runs for rbw-cC (crucible charge) and rbw-fO (hallmark ordain) before dispatch.

set -euo pipefail

# Get script directory
RBW_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"

# Source dependencies
source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"
source "${BURD_BUK_DIR}/buv_validation.sh"
source "${BURD_BUK_DIR}/burd_regime.sh"
source "${BURD_BUK_DIR}/buz_zipper.sh"
source "${RBW_SCRIPT_DIR}/rbz_zipper.sh"

# Show filename on each displayed line
buc_context "${0##*/}"

# Kindle dispatch and zipper registry
zbuv_kindle
zburd_kindle
zbuz_kindle
zrbz_kindle

# Verbose output if BURE_VERBOSE is set
rbw_show() {
  test "${BURE_VERBOSE:-0}" != "1" || echo "RBWSHOW: $*"
}

######################################################################
# Routing

rbw_route() {
  local z_command="$1"
  shift

  rbw_show "Routing command: ${z_command} with args: $*"

  zburd_sentinel

  rbw_show "BURD environment verified"

  # Qualification gate for commands that need it
  case "${z_command}" in
    "${RBZ_CRUCIBLE_CHARGE}"|"${RBZ_ORDAIN_HALLMARK}")
      "${RBW_SCRIPT_DIR}/rbq_cli.sh" rbq_qualify_fast || buc_die "Qualification gate failed"
      ;;
  esac

  buz_exec_lookup "${z_command}" "${RBW_SCRIPT_DIR}" "$@"
}

rbw_main() {
  local z_command="${1:-}"
  shift || true

  test -n "${z_command}" || buc_die "No command specified"

  rbw_route "${z_command}" "$@"
}

rbw_main "$@"

# eof
