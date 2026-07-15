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
# Recipe Bottle Handbook Payor - Base (kindle, sentinel, enforce)

set -euo pipefail

test -z "${ZRBHP_SOURCED:-}" || buc_die "Module rbhp multiply sourced - check sourcing hierarchy"
ZRBHP_SOURCED=1

zrbhp_kindle() {
  test -z "${ZRBHP_KINDLED:-}" || buc_die "Module rbhp already kindled"

  # Kernel discrimination for click-modifier display via the bash $OSTYPE
  # builtin (darwin* on macOS) — no external uname dependency.
  case "${OSTYPE}" in
    darwin*) readonly ZRBHP_CLICK_MOD="Cmd" ;;
    *)       readonly ZRBHP_CLICK_MOD="Ctrl" ;;
  esac

  readonly ZRBHP_RBRP_FILE="${RBCC_rbrp_file}"
  readonly ZRBHP_RBRP_FILE_BASENAME="${ZRBHP_RBRP_FILE##*/}"

  readonly ZRBHP_KINDLED=1
}

zrbhp_sentinel() {
  test "${ZRBHP_KINDLED:-}" = "1" || buc_die "Module rbhp not kindled - call zrbhp_kindle first"
}

zrbhp_enforce() {
  zrbhp_sentinel
  test -n "${RBDC_DEPOT_PROJECT_ID:-}"     || buc_die "RBDC_DEPOT_PROJECT_ID is not set"
  zrbgc_sentinel
}

# eof
