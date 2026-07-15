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
# BURE Regime - Bash Utility Regime Environment Module
#
# BURE is an ambient regime — variables are set in the environment by callers,
# not sourced from a file. Callers export BURE_* variables before invoking.

set -euo pipefail

# Multiple inclusion detection
test -z "${ZBURE_SOURCED:-}" || buc_die "Module bure multiply sourced - check sourcing hierarchy"
ZBURE_SOURCED=1

######################################################################
# Internal Functions (zbure_*)

zbure_kindle() {
  test -z "${ZBURE_KINDLED:-}" || buc_die "Module bure already kindled"

  # No defaults set — buv uses ${!varname:-} for safe indirect expansion under set -u.
  # Unset variables are detected distinctly from empty by zbuv_check_capture.
  # Exception: ambient regime defaults for optional behavioral overrides.
  BURE_VERBOSE="${BURE_VERBOSE:-0}"
  BURE_COLOR="${BURE_COLOR:-auto}"
  BURE_COUNTDOWN="${BURE_COUNTDOWN:-}"
  BURE_TWEAK_NAME="${BURE_TWEAK_NAME:-}"
  BURE_TWEAK_VALUE="${BURE_TWEAK_VALUE:-}"
  BURE_LABEL="${BURE_LABEL:-}"

  # Enroll all BURE variables — single source of truth for validation and rendering

  buv_regime_enroll BURE

  buv_group_enroll "Behavioral Overrides"
  buv_string_enroll  BURE_COUNTDOWN   0  4  "Countdown override (skip to disable)"
  buv_enum_enroll    BURE_VERBOSE     "Verbosity level" 0 1 2 3
  buv_enum_enroll    BURE_COLOR       "Color mode" auto 0 1

  buv_group_enroll "Tweak Mechanism"
  buv_string_enroll  BURE_TWEAK_NAME  0  64   "Tweak name (buo-sprued; consumer-interpreted)"
  buv_string_enroll  BURE_TWEAK_VALUE 0  256  "Tweak value (consumer-interpreted)"

  buv_group_enroll "Exchange Labels"
  buv_string_enroll  BURE_LABEL       0  120  "Correlation label for cross-project exchange (xname format)"

  # Guard against unexpected BURE_ variables not in enrollment
  buv_scope_sentinel BURE BURE_

  # Lock all enrolled BURE_ variables against mutation
  buv_lock BURE

  readonly ZBURE_KINDLED=1
}

zbure_sentinel() {
  test "${ZBURE_KINDLED:-}" = "1" || buc_die "Module bure not kindled - call zbure_kindle first"
}

# Enforce all BURE enrollment validations
zbure_enforce() {
  zbure_sentinel

  buv_vet BURE

  # Custom enforce: BURE_COUNTDOWN must be empty or "skip"
  if test -n "${BURE_COUNTDOWN}"; then
    test "${BURE_COUNTDOWN}" = "skip" \
      || buc_die "BURE_COUNTDOWN must be 'skip' or empty, got '${BURE_COUNTDOWN}'"
  fi

  # Custom enforce: BURE_TWEAK_NAME, when set, must carry the buo tweak sprue —
  # a `buo<segment>_` prefix. BUK validates the SHAPE only (the virtual registry
  # of tweaks is `grep buo`); it never enumerates consumer names, so this stays
  # generic. An unregistered or mistyped tweak name fails loud here rather than
  # silently no-op'ing at the consumer.
  # Doctrine (BUS0 "Tweak Mechanism"): a tweak forces one hard-to-produce
  # condition for a test to observe handled correctly; one tweak at a time per
  # test/fixture/suite, by design; a suite may reserve the slot for a standing guard.
  if test -n "${BURE_TWEAK_NAME}"; then
    case "${BURE_TWEAK_NAME}" in
      buo[a-z]*_*) : ;;
      *) buc_die "BURE_TWEAK_NAME must carry the buo sprue (buo<segment>_<name>), got '${BURE_TWEAK_NAME}'" ;;
    esac
  fi
}

# eof
