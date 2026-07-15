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
# BUTCBD - Precision exit-code band test cases for BUK self-test
#
# Proves the band membrane in buc_die: an in-band $? beneath a
# `cmd || buc_die` chain re-exits unchanged, everything else stays
# imprecise death (1), and a band code survives the full
# tabtarget/launcher/dispatch exec path to the caller's captured status.

set -euo pipefail

######################################################################
# Helpers — each runs inside zbuto_invoke's isolation subshell

zbutcbd_die_in_band() {
  ( exit "${BUBC_band_selftest}" ) || buc_die "wrapped in-band failure"
}

zbutcbd_die_plain() {
  false || buc_die "wrapped plain failure"
}

zbutcbd_die_out_of_band() {
  ( exit 42 ) || buc_die "wrapped out-of-band failure"
}

zbutcbd_reject_direct() {
  buc_reject "${BUBC_band_selftest}" "direct deliberate rejection"
}

zbutcbd_reject_out_of_band() {
  buc_reject 42 "out-of-band code is a programming error"
}

######################################################################
# Membrane cases

butcbd_die_in_band_tcase() {
  buto_trace "Band: in-band status beneath cmd || buc_die re-exits unchanged"
  buto_unit_expect_code "${BUBC_band_selftest}" zbutcbd_die_in_band
}

butcbd_die_plain_tcase() {
  buto_trace "Band: ordinary failure beneath buc_die stays imprecise death (1)"
  buto_unit_expect_code 1 zbutcbd_die_plain
}

butcbd_die_out_of_band_tcase() {
  buto_trace "Band: out-of-band nonzero beneath buc_die launders to 1"
  buto_unit_expect_code 1 zbutcbd_die_out_of_band
}

######################################################################
# Origin helper cases

butcbd_reject_direct_tcase() {
  buto_trace "Band: buc_reject exits with its in-band code"
  buto_unit_expect_code "${BUBC_band_selftest}" zbutcbd_reject_direct
}

butcbd_reject_out_of_band_tcase() {
  buto_trace "Band: buc_reject refuses an out-of-band code with imprecise death"
  buto_unit_expect_code 1 zbutcbd_reject_out_of_band
}

######################################################################
# End-to-end survival case

butcbd_survival_tcase() {
  buto_trace "Band: rejection survives the tabtarget/launcher/dispatch exec path"
  buto_tt_expect_code "${BUBC_band_selftest}" "buw-xb"
}

# eof
