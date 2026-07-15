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
# BUL Launcher - Shared launcher logic for BUK workbenches.
# Sourced by individual launcher stubs in rbmm_moorings/rbml_launchers/
# Compatible with Bash 3.2 (e.g., macOS default shell)
#
# NOTE: This is bootstrap infrastructure, not a full BCG module.
# No kindle/sentinel pattern - this runs before BCG modules are loaded.

# Guard against multiple inclusion
test -z "${ZBUL_LAUNCHER_SOURCED:-}" || return 0
ZBUL_LAUNCHER_SOURCED=1

# Establish project root. z-launcher.sh (the universal trampoline that exec's
# every launcher stub) has already chdir'd to repo root, so trust PWD rather
# than counting directory hops back from the stub's location — the latter
# couples to where the launcher dir sits and breaks whenever it moves.
ZBUL_PROJECT_ROOT="${PWD}"

# Config directory is supplied by the project-intimate trampoline (z-launcher),
# the SOLE file that knows this project's moorings/config dir name. The shared
# kit no longer hardcodes the name — it consumes the exported absolute path, so
# one kit serves every consumer (.buk, rbmm_moorings, …). The basename is
# derived below as BURD_MOORINGS_DIR for operator-facing display.
test -n "${BURD_CONFIG_DIR:-}" || {
  echo "bul_launcher: BURD_CONFIG_DIR unset — dispatch must run through z-launcher" >&2
  exit 1
}
export BURD_CONFIG_DIR

# Moorings basename — the repo-root-relative config dir name, derived from the
# absolute path. Operator-facing messages render paths relative to it because
# z-launcher leaves the operator at repo root. A BURD_ dispatch value born here
# in bootstrap (two consumers — this file's SETUP NEEDED block and burs_regime's
# enroll description — run before the BURD kindle), enrolled in burd_regime, and
# allowlisted in bud_dispatch.
export BURD_MOORINGS_DIR="${BURD_CONFIG_DIR##*/}"

# Load BURC configuration
export BURD_REGIME_FILE="${BURD_CONFIG_DIR}/burc.env"
source "${BURD_REGIME_FILE}" || exit 1 # buc_die not available yet

# Apply BURV (Bash Utility Regime Verification) overrides if set
BURC_OUTPUT_ROOT_DIR="${BURV_OUTPUT_ROOT_DIR:-${BURC_OUTPUT_ROOT_DIR}}"
BURC_TEMP_ROOT_DIR="${BURV_TEMP_ROOT_DIR:-${BURC_TEMP_ROOT_DIR}}"

# Source BUK modules
export BURD_STATION_FILE="${ZBUL_PROJECT_ROOT}/${BURC_STATION_FILE}"
source "${BURC_TOOLS_DIR}/buk/buc_command.sh" || exit 1 # buc_die not available yet
source "${BURC_TOOLS_DIR}/buk/buv_validation.sh" || buc_die "Failed to source buv_validation.sh"
source "${BURC_TOOLS_DIR}/buk/bubc_constants.sh" || buc_die "Failed to source bubc_constants.sh"
zbuv_kindle

# Load and kindle BURC
source "${BURC_TOOLS_DIR}/buk/burc_regime.sh" || buc_die "Failed to source burc_regime.sh"
zburc_kindle
zburc_enforce

# BURS station load is skipped under BURD_NO_LOG. No-log tabtargets (e.g.
# handbooks) need only BURC and must run on a fresh clone before any station
# file exists. The flag is exported by the tabtarget ahead of dispatch, so it
# is visible here. This collapses the former separate nolog launcher.
if test -z "${BURD_NO_LOG:-}"; then
  # bud_dispatch is the canonical exporter of BURD_TABTARGET_DIR, but the
  # SETUP NEEDED block below uses buyy_tt_yawp which requires it earlier.
  BURD_TABTARGET_DIR="${BURC_TABTARGET_DIR}"

  # Load yelp + handbook so the SETUP NEEDED block can yawp paths, tabtarget
  # references, and recommended file contents, and print them via buh_*.
  source "${BURC_TOOLS_DIR}/buk/buym_yelp.sh"    || buc_die "Failed to source buym_yelp.sh"
  source "${BURC_TOOLS_DIR}/buk/buh_handbook.sh" || buc_die "Failed to source buh_handbook.sh"

  # Load BURS configuration and kindle
  z_station_file="${ZBUL_PROJECT_ROOT}/${BURC_STATION_FILE}"
  if ! test -f "${z_station_file}"; then
    buyy_ui_yawp  "${z_station_file}";              z_path_yp="${z_buym_yelp}"
    buyy_ui_yawp  "${BURC_STATION_FILE}";           z_rel_yp="${z_buym_yelp}"
    buyy_ui_yawp  "${BURD_REGIME_FILE}";            z_burc_yp="${z_buym_yelp}"
    buyy_cmd_yawp "BURS_LOG_DIR=../logs-buk";       z_var_log_yp="${z_buym_yelp}"
    buyy_cmd_yawp "BURS_USER=<your-username>";      z_var_usr_yp="${z_buym_yelp}"
    buyy_cmd_yawp "BURS_TINCTURE=a";                z_var_tin_yp="${z_buym_yelp}"

    buh_e
    buh_section "SETUP NEEDED: Station Regime file not found"
    buh_e
    buh_line    "  Missing: ${z_path_yp}"
    buh_e
    buh_line    "  The Bash Utility Kit (BUK) launcher uses two regime files:"
    buh_e
    buh_line    "    Config Regime (BURC) - checked into the repo at ${z_burc_yp}"
    buh_line    "      Project-level settings: tool paths, tabtarget layout, and the"
    buh_line    "      location of the Station Regime file."
    buh_tt      "      Inspect: " "buw-rcr"
    buh_e
    buh_line    "    Station Regime (BURS) - developer-specific, NOT in git"
    buh_line    "      Machine-level settings that vary per developer or workstation."
    buh_line    "      The Config Regime says to look for it at: ${z_rel_yp}"
    buh_tt      "      Inspect: " "buw-rsr"
    buh_e
    buh_line    "  Other toolkits in the project may define additional regime files."
    buh_e
    buh_line    "  To get started, create the Station Regime file with this content:"
    buh_e
    buh_line    "    ${z_var_log_yp}"
    buh_line    "    ${z_var_usr_yp}"
    buh_line    "    ${z_var_tin_yp}"
    buh_e
    buh_line    "  All three variables are required."
    buh_e
    buh_line    "  BURS_LOG_DIR names the directory for operation logs. All tabtargets"
    buh_line    "  run from the project root, so relative paths resolve from there. The"
    buh_line    "  example above places logs in the parent directory of the repo. You"
    buh_line    "  may also use an absolute path, or a path inside the repo itself"
    buh_line    "  (.gitignored) — the Config Regime's choice of BURC_STATION_FILE path"
    buh_line    "  often signals which convention a project prefers."
    buh_e
    buh_line    "  BURS_USER is your local developer username (1-32 chars). Per-user"
    buh_line    "  profile lookups under ${BURD_MOORINGS_DIR}/${BUBC_rbmu_users_subdir}/<BURS_USER>/ key on this name."
    buh_e
    buh_line    "  BURS_TINCTURE is a 1-3 char tag (lowercase alphanumeric, leading"
    buh_line    "  letter, no hyphen). Use 'a' until you have a reason to change it;"
    buh_line    "  downstream tooling may compose it into per-station resource names"
    buh_line    "  so concurrent stations sharing an upstream account stay disjoint."
    buh_e
    exit 1
  fi
  source "${z_station_file}" || buc_die "Failed to source: ${z_station_file}"

  # Apply BURV (Bash Utility Regime Verification) overrides if set
  BURS_LOG_DIR="${BURV_LOG_DIR:-${BURS_LOG_DIR}}"

  source "${BURC_TOOLS_DIR}/buk/burs_regime.sh" || buc_die "Failed to source burs_regime.sh"
  zburs_kindle
  zburs_enforce
fi

# Helper function to delegate to BURD
# Usage: bul_launch "path/to/workbench.sh" "$@"
bul_launch() {
  local z_coordinator="$1"
  shift

  # Detect terminal width via /dev/tty (survives exec chain and dispatch pipes)
  # Subshell probe: /dev/tty may exist but not be openable (CI, sandbox)
  BURD_TERM_COLS=80
  if (exec </dev/tty) 2>/dev/null; then
    read -r _ BURD_TERM_COLS < <(stty size </dev/tty 2>/dev/null)
    test -n "${BURD_TERM_COLS}" || BURD_TERM_COLS=80
  fi
  export BURD_TERM_COLS

  export BURD_COORDINATOR_SCRIPT="${z_coordinator}"
  exec "${BURC_TOOLS_DIR}/buk/bud_dispatch.sh" "${1##*/}" "${@:2}"
}
