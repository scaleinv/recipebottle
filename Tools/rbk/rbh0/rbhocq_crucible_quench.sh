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
# Recipe Bottle Handbook Onboarding - Shared Crucible Quench

set -euo pipefail

test -z "${ZRBHOCQ_SOURCED:-}" || return 0
ZRBHOCQ_SOURCED=1

# Voice-neutral quench step shared by the first crucible explorer and
# the tadmor security evaluator. Surfaces the charge-auto-quench
# pedagogy at its natural moment (alongside the quench teaching).
#
# Args:
#   $1  z_moniker — nameplate identity for the imprint-channel quench

rbhocq_crucible_quench() {
  local -r z_moniker="${1}"

  buh_step1 "${RBYC_QUENCH} the ${RBYC_CRUCIBLE}"
  buh_e
  buh_line "${RBYC_QUENCH} stops and removes all three containers and the"
  buh_line "${RBYC_ENCLAVE} network:"
  buh_e
  buh_tt  "   " "${RBZ_CRUCIBLE_QUENCH}" "${z_moniker}"
  buh_e
  buh_line "Clean shutdown. The images stay cached locally — the next ${RBYC_CHARGE}"
  buh_line "reuses them instantly."
  buh_e
  buh_line "You don't need to ${RBYC_QUENCH} between iterations. ${RBYC_CHARGE} tears"
  buh_line "down any prior state before starting, so repeating ${RBYC_CHARGE}"
  buh_line "picks up a fresh ${RBYC_CRUCIBLE}. ${RBYC_QUENCH} when you are done"
  buh_line "with the ${RBYC_CRUCIBLE} for the session."
  buh_e
}

# eof
