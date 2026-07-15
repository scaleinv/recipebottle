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
# Recipe Bottle Foundry - beckon cluster (guard-free): the per-fact "next
# tabtargets" signpost — after a fact is written, the emitter for that fact
# announces the tabtargets that CONSUME it. One emitter per fact type owns its
# consumer roster; today only the hallmark fact (RBF_FACT_HALLMARK) has one.
# Composes the BUK buc_tabtarget primitive — no BUK change. Sourced by the
# hallmark-fact producers (rbfd director ordain, rbfk kludge).

set -euo pipefail

######################################################################
# Beckon (rbfb_*)

# Announce the consumers of the hallmark fact just written (ordain or kludge).
#
# The roster is exactly the RBF_FACT_HALLMARK chain consumers enumerated in
# RBS0 "Chaining-Fact Roles": the rbch_palpate readers (summon, plumb, rekon)
# and the rbch_enchase writers that resolve THIS fact (anoint, drive). It MUST
# agree with that enumeration — a consumer added there without a line here (or
# vice versa) is the drift this single home exists to prevent.
#
# Light context filtering, never a predicate farm: a consumer whose folio IS
# the hallmark gets it filled; a consumer taking a different folio prints a
# placeholder. No per-mode branching — every consumer is listed uniformly.
#
# Args: hallmark (the tag the HEAD just wrote)
rbfb_beckon_hallmark() {
  local -r z_hallmark="${1:-}"
  test -n "${z_hallmark}" || buc_die "rbfb_beckon_hallmark: hallmark required"

  buc_bare ""
  buc_bare "  This hallmark feeds:"

  # rbch_palpate readers of RBF_FACT_HALLMARK — folio IS the hallmark, fill it
  buc_tabtarget "${RBZ_SUMMON_HALLMARK}" "${z_hallmark}"
  buc_tabtarget "${RBZ_PLUMB_COMPACT}"   "${z_hallmark}"
  buc_tabtarget "${RBZ_PLUMB_FULL}"      "${z_hallmark}"
  buc_tabtarget "${RBZ_REKON_HALLMARK}"  "${z_hallmark}"

  # rbch_enchase writers of RBF_FACT_HALLMARK — folio is a different target,
  # so show a placeholder (anoint reads the hallmark with an empty express;
  # drive's folio is the nameplate to receive it)
  buc_tabtarget "${RBZ_ANOINT_GRAFT}"    "<graft-vessel>"
  buc_tabtarget "${RBZ_DRIVE_HALLMARK}"  "<nameplate> bottle"
}

# eof
