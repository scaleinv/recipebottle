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
# BUW Zipper - Colophon registry for BUK workbench dispatch

set -euo pipefail

# Multiple inclusion guard
test -z "${ZBUWZ_SOURCED:-}" || return 0
ZBUWZ_SOURCED=1

######################################################################
# Colophon registry initialization

zbuwz_kindle() {
  test -z "${ZBUWZ_KINDLED:-}" || buc_die "buwz already kindled"

  # Verify buz zipper is kindled (CLI furnish must kindle buz first)
  zbuz_sentinel

  # Open the BUK tome: this zipper's run projects to BUWGC_ consts (BUWZ_ stem).
  # Must precede the first enroll so the run begins at the roll's current head —
  # which, when RB is kindled first (the theurge build and rbq), lands the BUK
  # run after the RB run, keeping the RBTDGC_ block byte-stable.
  buz_tome "buwz" "BUWGC_" "BUWZ_"

  # TabTarget subsystem (buut_cli.sh)
  local z_mod="buut_cli.sh"
  buz_enroll BUWZ_TT_LIST_LAUNCHERS      "buw-tt-ll"  "${z_mod}" "buut_list_launchers"               ""  "List all registered launchers"
  buz_enroll BUWZ_TT_BATCH_LOGGING       "buw-tt-cbl" "${z_mod}" "buut_tabtarget_batch_logging"      ""  "Create batch tabtarget with logging"
  buz_enroll BUWZ_TT_BATCH_NOLOG         "buw-tt-cbn" "${z_mod}" "buut_tabtarget_batch_nolog"        ""  "Create batch tabtarget without logging"
  buz_enroll BUWZ_TT_INTERACTIVE_LOGGING "buw-tt-cil" "${z_mod}" "buut_tabtarget_interactive_logging" ""  "Create interactive tabtarget with logging"
  buz_enroll BUWZ_TT_INTERACTIVE_NOLOG   "buw-tt-cin" "${z_mod}" "buut_tabtarget_interactive_nolog"  ""  "Create interactive tabtarget without logging"
  buz_enroll BUWZ_TT_LAUNCHER            "buw-tt-cl"  "${z_mod}" "buut_launcher"                     ""  "Create launcher script"

  # Config Regime subsystem (burc_cli.sh)
  z_mod="burc_cli.sh"
  buz_enroll BUWZ_RC_VALIDATE "buw-rcv" "${z_mod}" "burc_validate"  ""  "Validate BURC regime"
  buz_enroll BUWZ_RC_RENDER   "buw-rcr" "${z_mod}" "burc_render"    ""  "Render BURC regime"

  # Station Regime subsystem (burs_cli.sh)
  z_mod="burs_cli.sh"
  buz_enroll BUWZ_RS_VALIDATE "buw-rsv" "${z_mod}" "burs_validate"  ""  "Validate BURS regime"
  buz_enroll BUWZ_RS_RENDER   "buw-rsr" "${z_mod}" "burs_render"    ""  "Render BURS regime"

  # Environment Regime subsystem (bure_cli.sh)
  z_mod="bure_cli.sh"
  buz_enroll BUWZ_RE_VALIDATE "buw-rev" "${z_mod}" "bure_validate"  ""  "Validate BURE regime"
  buz_enroll BUWZ_RE_RENDER   "buw-rer" "${z_mod}" "bure_render"    ""  "Render BURE regime"

  # Test fixtures (bux_cli.sh)
  z_mod="bux_cli.sh"
  buz_enroll BUWZ_DELAY      "buw-xd" "${z_mod}" "bux_delay"       ""  "Sleep 20 seconds (timing fixture)"
  buz_enroll BUWZ_BAND_CHAIN "buw-xb" "${z_mod}" "bux_band_chain"  ""  "Raise a band rejection beneath a die chain (self-test survival fixture)"

  # Self-test (butt_testbench.sh)
  z_mod="butt_testbench.sh"
  buz_enroll BUWZ_SELF_TEST "buw-st" "${z_mod}" "buw-st"  ""  "BUK self-test (kick-tires + bure-tweak)"

  readonly ZBUWZ_KINDLED=1
}

######################################################################
# Internal sentinel

zbuwz_sentinel() {
  test "${ZBUWZ_KINDLED:-}" = "1" || buc_die "Module buwz not kindled - call zbuwz_kindle first"
}

# eof
