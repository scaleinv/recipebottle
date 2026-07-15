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
# Bash Utility Regime Dispatch - Direct bash dispatch

set -euo pipefail

BURE_VERBOSE=${BURE_VERBOSE:-0}

BURD_REGIME_FILE=${BURD_REGIME_FILE:-"__MISSING_BURD_REGIME_FILE__"}

# Utility function for verbose output
zbud_show() { test "$BURE_VERBOSE" != "1" || echo "BURDSHOW: $*"; }

# Enable trace mode if verbose level is 2
if test "${BURE_VERBOSE}" = "2"; then
  set -x
fi

zbud_die() { echo "FATAL: $*" >&2; exit 1; }

zburd_sentinel() {
  test "${ZBURD_INITIALIZED:-}" = "1" || zbud_die "Dispatch not initialized - zbud_main not complete"
}

# String validator with optional length constraints
zbud_check_string() {
  local -r z_context="${1}"
  local -r z_varname="${2}"
  local z_val="${!z_varname:-}"
  local -r z_min="${3}"
  local -r z_max="${4}"

  test "${z_min}" != "0" -o -n "${z_val}" || return 0
  test -n "${z_val}" || zbud_die "[${z_context}] ${z_varname} must not be empty"

  if test -n "${z_max}"; then
    test ${#z_val} -ge "${z_min}" || zbud_die "[${z_context}] ${z_varname} must be at least ${z_min} chars, got '${z_val}' (${#z_val})"
    test ${#z_val} -le "${z_max}" || zbud_die "[${z_context}] ${z_varname} must be no more than ${z_max} chars, got '${z_val}' (${#z_val})"
  fi
}

# Source configuration and setup environment
zbud_setup() {
  zbud_show "Starting BDU setup"

  source            "${BURD_REGIME_FILE}"

  # Apply BURV (Bash Utility Regime Verification) overrides if set
  BURC_OUTPUT_ROOT_DIR="${BURV_OUTPUT_ROOT_DIR:-${BURC_OUTPUT_ROOT_DIR}}"
  BURC_TEMP_ROOT_DIR="${BURV_TEMP_ROOT_DIR:-${BURC_TEMP_ROOT_DIR}}"

  zbud_check_string "${BURD_REGIME_FILE}" BURC_STATION_FILE        1 256
  zbud_check_string "${BURD_REGIME_FILE}" BURC_LOG_LAST            1 256
  zbud_check_string "${BURD_REGIME_FILE}" BURC_LOG_EXT             1 32
  zbud_check_string "${BURD_REGIME_FILE}" BURC_TABTARGET_DIR       1 256
  zbud_check_string "${BURD_REGIME_FILE}" BURC_TABTARGET_DELIMITER 1 8
  zbud_check_string "${BURD_REGIME_FILE}" BURC_TEMP_ROOT_DIR       1 256
  zbud_check_string "${BURD_REGIME_FILE}" BURC_OUTPUT_ROOT_DIR     1 256
  zbud_check_string "${BURD_REGIME_FILE}" BURC_TOOLS_DIR           1 256

  # Dispatch-provided directory variables (survive exec boundary for CLIs)
  BURD_TOOLS_DIR="${BURC_TOOLS_DIR}"
  BURD_BUK_DIR="${BURC_TOOLS_DIR}/buk"
  BURD_TABTARGET_DIR="${BURC_TABTARGET_DIR}"
  export BURD_TOOLS_DIR BURD_BUK_DIR BURD_TABTARGET_DIR

  # Source station file (skip for no-log handbook tabtargets)
  if test -z "${BURD_NO_LOG:-}"; then
    zbud_show "Sourcing station file: ${BURC_STATION_FILE}"
    source                           "${BURC_STATION_FILE}"

    # Apply BURV (Bash Utility Regime Verification) overrides if set
    BURS_LOG_DIR="${BURV_LOG_DIR:-${BURS_LOG_DIR}}"

    # Validate station variables
    zbud_check_string "${BURC_STATION_FILE}" BURS_LOG_DIR 1 256
  fi

  mkdir -p "${BURC_TEMP_ROOT_DIR}" || zbud_die "Failed to create temp root: ${BURC_TEMP_ROOT_DIR}"
  local -r z_date_file="${BURC_TEMP_ROOT_DIR}/bud_bootstrap_date.txt"
  date +'%Y%m%d-%H%M%S %s' > "${z_date_file}" || zbud_die "Failed to get datetime"
  local z_datetime
  z_datetime=$(<"${z_date_file}")
  test -n "${z_datetime}" || zbud_die "Empty datetime from ${z_date_file}"
  BURD_NOW_STAMP="${z_datetime% *}-$$-$((RANDOM % 1000))"
  BURD_NOW_EPOCH="${z_datetime#* }"
  zbud_show "Generated timestamp: ${BURD_NOW_STAMP} epoch: ${BURD_NOW_EPOCH}"

  BURD_TEMP_DIR="${BURC_TEMP_ROOT_DIR}/temp-${BURD_NOW_STAMP}"
  case "${BURD_TEMP_DIR}" in
    /*) ;;
    *)  BURD_TEMP_DIR="${PWD}/${BURD_TEMP_DIR}" ;;
  esac
  mkdir -p                           "${BURD_TEMP_DIR}" || zbud_die "Failed to create temp directory: ${BURD_TEMP_DIR}"
  zbud_show "Generated temporary dir: ${BURD_TEMP_DIR}"

  # Setup transcript file path
  BURD_TRANSCRIPT="${BURD_TEMP_DIR}/transcript.txt"

  # Setup output directories under the output root (both fixed locations).
  #   current/  = this dispatch's outputs (fresh each run).
  #   previous/ = the prior dispatch's current/, promoted here at dispatch
  #               start. Promotion is EXIT-STATUS-INDEPENDENT — it runs before
  #               this dispatch does any work, so the prior run's outputs are
  #               forwarded regardless of how it exited (fail-after-forward
  #               still passes the baton). The current/+previous/ pair is the
  #               depth-1 cross-tabtarget chain; no deeper history is kept.
  BURD_OUTPUT_DIR="${BURC_OUTPUT_ROOT_DIR}/current"
  BURD_PREVIOUS_DIR="${BURC_OUTPUT_ROOT_DIR}/previous"
  case "${BURD_OUTPUT_DIR}" in
    /*) ;;
    *)  BURD_OUTPUT_DIR="${PWD}/${BURD_OUTPUT_DIR}" ;;
  esac
  case "${BURD_PREVIOUS_DIR}" in
    /*) ;;
    *)  BURD_PREVIOUS_DIR="${PWD}/${BURD_PREVIOUS_DIR}" ;;
  esac

  # Promote prior current/ -> previous/, then create a fresh empty current/.
  # current/ and previous/ are siblings under one root, so mv is always an
  # atomic same-filesystem rename — never a byte copy. It relocates the prior
  # outputs (replacing the old unconditional rm of current/) rather than
  # destroying them. First drop the generation older than one, then promote.
  if test -d "${BURD_PREVIOUS_DIR}"; then
    zbud_show "Dropping stale previous directory: ${BURD_PREVIOUS_DIR}"
    rm -rf "${BURD_PREVIOUS_DIR}" || zbud_die "Failed to remove previous directory: ${BURD_PREVIOUS_DIR}"
  fi
  if test -d "${BURD_OUTPUT_DIR}"; then
    zbud_show "Promoting prior output to previous: ${BURD_OUTPUT_DIR} -> ${BURD_PREVIOUS_DIR}"
    mv "${BURD_OUTPUT_DIR}" "${BURD_PREVIOUS_DIR}" || zbud_die "Failed to promote output directory to previous: ${BURD_OUTPUT_DIR}"
  fi
  mkdir -p "${BURD_OUTPUT_DIR}" || zbud_die "Failed to create output directory: ${BURD_OUTPUT_DIR}"

  zbud_show "Output directory ready: ${BURD_OUTPUT_DIR} (previous: ${BURD_PREVIOUS_DIR})"

  # Get Git context
  local -r z_git_context_file="${BURD_TEMP_DIR}/bud_git_context.txt"
  local -r z_git_context_stderr="${BURD_TEMP_DIR}/bud_git_context_stderr.txt"
  if git describe --always --dirty --tags --long > "${z_git_context_file}" 2>"${z_git_context_stderr}"; then
    BURD_GIT_CONTEXT=$(<"${z_git_context_file}")
  else
    BURD_GIT_CONTEXT="git-unavailable"
  fi
  zbud_show "Git context: ${BURD_GIT_CONTEXT}"

  # Platform fact for native binaries (e.g. theurge) that cannot inherit bash's
  # own $OSTYPE across the process boundary — synthesized live each dispatch and
  # delivered through the exported BURD_ channel. The native bash path is derived
  # inside theurge via cygpath, keeping cygpath out of kit bash.
  BURD_OSTYPE="${OSTYPE}"
  zbud_show "Platform: ${BURD_OSTYPE}"

  # Export for child processes
  export BURD_TEMP_DIR
  export BURD_OUTPUT_DIR
  export BURD_PREVIOUS_DIR
  export BURD_NOW_STAMP
  export BURD_NOW_EPOCH
  export BURD_TRANSCRIPT
  export BURD_GIT_CONTEXT
  export BURD_OSTYPE

  return 0
}

# Process command-line arguments
zbud_process_args() {
  local -r z_target="${1}"
  shift

  zbud_show "Processing target: ${z_target}"

  # Extract tokens from tabtarget
  local -a z_tokens
  IFS="${BURC_TABTARGET_DELIMITER}" read -ra z_tokens <<< "${z_target}"
  zbud_show "Split tokens: ${z_tokens[*]}"

  # Store primary command token (legacy, equivalent to BURD_TOKEN_1)
  BURD_COMMAND="${z_tokens[0]}"

  # Explode tokens into numbered variables for workbench access
  # Pattern matches MBC_TTPARAM__FIRST through MBC_TTPARAM__FIFTH
  BURD_TOKEN_1="${z_tokens[0]:-}"
  BURD_TOKEN_2="${z_tokens[1]:-}"
  BURD_TOKEN_3="${z_tokens[2]:-}"
  BURD_TOKEN_4="${z_tokens[3]:-}"
  BURD_TOKEN_5="${z_tokens[4]:-}"

  export BURD_TOKEN_1 BURD_TOKEN_2 BURD_TOKEN_3 BURD_TOKEN_4 BURD_TOKEN_5

  # Create tag for log files
  local -r z_tag="${z_tokens[0]}-${z_tokens[2]:-unknown}"

  # Setup log paths and files (skip entirely for no-log tabtargets)
  if test -z "${BURD_NO_LOG:-}"; then
    BURD_LOG_LAST="${BURS_LOG_DIR}/${BURC_LOG_LAST}.${BURC_LOG_EXT}"
    BURD_LOG_SAME="${BURS_LOG_DIR}/same-${z_tag}.${BURC_LOG_EXT}"
    BURD_LOG_HIST="${BURS_LOG_DIR}/hist-${z_tag}-${BURD_NOW_STAMP}.${BURC_LOG_EXT}"
    mkdir -p "${BURS_LOG_DIR}"
    : > "${BURD_LOG_LAST}"
    : > "${BURD_LOG_SAME}"
    : > "${BURD_LOG_HIST}"
  fi

  # Store target and extra arguments
  BURD_TARGET="${z_target}"
  BURD_CLI_ARGS=("$@")

  # Export command context for workbench access
  export BURD_COMMAND
  export BURD_TARGET
  export BURD_CLI_ARGS

  return 0
}

# Function to curate logs for the 'same' log file (normalized output)
zbud_curate_same() {
  # Convert to unix line endings, strip colors, normalize temp dir, remove VOLATILE lines
  sed -e 's/\r/\n/g'                             \
      -e '/^$/d'                                 \
      -e 's/\x1b[\[][0-9;]*[a-zA-Z]//g'          \
      -e 's/\x1b[(][A-Z]//g'                     \
      -e "s|${BURD_TEMP_DIR}|BURD_EPHEMERAL_DIR|g" \
      -e '/VOLATILE/d'
}

# Function to curate logs for the historical log file (with timestamps)
zbud_curate_hist() {
  while read -r z_line; do
    printf "[%s] %s\n" "$(date +"%Y-%m-%d %H:%M:%S")" "${z_line}"
  done
}

# Generate and log checksum for a file
zbud_generate_checksum() {
  local -r z_file="${1}"
  local -r z_output_file="${2}"

  local z_checksum
  z_checksum=$(openssl dgst -sha256 -r "${z_file}" 2>/dev/null) || z_checksum="checksum-unavailable"
  read -r z_checksum _ <<< "${z_checksum}"

  echo "Same log checksum: ${z_checksum}" >> "${z_output_file}"
  return 0
}

# Resolve color policy once at dispatch time and export BURE_COLOR (0/1)
zbud_resolve_color() {
  if test -n "${NO_COLOR:-}"; then
    export BURE_COLOR=0
    return 0
  fi
  case "${BURE_COLOR:-auto}" in
    0|1)
      export BURE_COLOR
      ;;
    auto|*)
      if test -t 1 && test "${TERM:-}" != "dumb"; then
          export BURE_COLOR=1
      else
          export BURE_COLOR=0
      fi
      ;;
  esac
}

# Write a fixed-width timestamp (YYYYMMDD-HHMMSS.NNNNNNNNN) to the file at $1.
# Sub-second precision is not load-bearing — the nanosecond field is always
# zero — but the fixed width is preserved for stable downstream BURX parsing.
zbud_nanosecond_timestamp() {
  local -r z_output_file="${1}"
  date +'%Y%m%d-%H%M%S.000000000' > "${z_output_file}" || zbud_die "date failed"
}

zbud_write_burx_initial() {
  local -r z_ts_file="${BURD_TEMP_DIR}/zbud_began_at.txt"
  zbud_nanosecond_timestamp "${z_ts_file}"
  local -r z_began_at=$(<"${z_ts_file}")
  test -n "${z_began_at}" || zbud_die "Empty began_at timestamp"

  local -r z_label="${BURE_LABEL:-}"
  local -r z_content="BURX_PID=$$
BURX_BEGAN_AT=${z_began_at}
BURX_TABTARGET=${BURD_TARGET}
BURX_TEMP_DIR=${BURD_TEMP_DIR}
BURX_TRANSCRIPT=${BURD_TRANSCRIPT}
BURX_LOG_HIST=${BURD_LOG_HIST:-}
BURX_LABEL=${z_label}"
  buf_write_fact_single "${BUF_burx_env}" "${z_content}"
}

zbud_write_burx_completion() {
  local -r z_exit_status="${1}"
  local -r z_ts_file="${BURD_TEMP_DIR}/zbud_ended_at.txt"
  zbud_nanosecond_timestamp "${z_ts_file}"
  local -r z_ended_at=$(<"${z_ts_file}")
  test -n "${z_ended_at}" || zbud_die "Empty ended_at timestamp"

  printf 'BURX_EXIT_STATUS=%s\nBURX_ENDED_AT=%s\n' "${z_exit_status}" "${z_ended_at}" >> "${BURD_OUTPUT_DIR}/${BUF_burx_env}"
  printf 'BURX_EXIT_STATUS=%s\nBURX_ENDED_AT=%s\n' "${z_exit_status}" "${z_ended_at}" >> "${BURD_TEMP_DIR}/${BUF_burx_env}"
}

zbud_main() {
  zbud_show "Starting BDU dispatch"

  # Decide color policy before stdout is piped
  zbud_resolve_color

  # Setup environment
  zbud_setup || { echo "ERROR: Environment setup failed" >&2; exit 1; }
  zbud_show "Environment setup complete"

  # Source fact-file module for BURX writes
  source "${BURC_TOOLS_DIR}/buk/buf_fact.sh"

  # Process arguments
  zbud_process_args "$@" || { echo "ERROR: Argument processing failed" >&2; exit 1; }
  zbud_show "Arguments processed"

  # Write initial BURX exchange state
  zbud_write_burx_initial

  # Detect unexpected BURD_ variables
  local -r z_known="BURD_CONFIG_DIR BURD_MOORINGS_DIR BURD_REGIME_FILE BURD_NO_LOG BURD_INTERACTIVE BURD_COORDINATOR_SCRIPT BURD_LAUNCHER BURD_STATION_FILE BURD_TERM_COLS BURD_NOW_STAMP BURD_NOW_EPOCH BURD_TEMP_DIR BURD_OUTPUT_DIR BURD_PREVIOUS_DIR BURD_TRANSCRIPT BURD_GIT_CONTEXT BURD_LOG_LAST BURD_LOG_SAME BURD_LOG_HIST BURD_COMMAND BURD_TARGET BURD_CLI_ARGS BURD_TOKEN_1 BURD_TOKEN_2 BURD_TOKEN_3 BURD_TOKEN_4 BURD_TOKEN_5 BURD_TOOLS_DIR BURD_BUK_DIR BURD_TABTARGET_DIR BURD_OSTYPE"
  ZBURD_UNEXPECTED=()
  local z_var
  for z_var in $(compgen -v BURD_); do
    case " ${z_known} " in
      *" ${z_var} "*) : ;;
      *) ZBURD_UNEXPECTED+=("${z_var}") ;;
    esac
  done

  # Die on unexpected variables
  if test ${#ZBURD_UNEXPECTED[@]} -gt 0; then
    zbud_die "Unexpected BURD_ variables: ${ZBURD_UNEXPECTED[*]}"
  fi

  ZBURD_INITIALIZED=1

  # Build complete invocation array (always has ≥2 elements, so always safe under set -u)
  local -r z_coordinator_cmd="${BURD_COORDINATOR_SCRIPT}"
  local -a z_invocation=("${z_coordinator_cmd}" "${BURD_COMMAND}")
  if test ${#BURD_CLI_ARGS[@]} -gt 0; then
    z_invocation+=("${BURD_CLI_ARGS[@]}")
  fi
  zbud_show "Coordinator command: ${z_invocation[*]}"

  # Log command to all log files (or suppress all output if BURD_NO_LOG)
  if test -z "${BURD_NO_LOG:-}"; then
    if test -n "${BURD_INTERACTIVE:-}"; then
      echo "log (interactive): ${BURD_LOG_HIST}"
      echo "command: ${z_invocation[*]}" >> "${BURD_LOG_HIST}"
      echo "Git context: ${BURD_GIT_CONTEXT}"  >> "${BURD_LOG_HIST}"
    else
      echo "log files:   ${BURD_LOG_LAST} ${BURD_LOG_SAME} ${BURD_LOG_HIST}"
      echo "command: ${z_invocation[*]}" >> "${BURD_LOG_LAST}"
      echo "command: ${z_invocation[*]}" >> "${BURD_LOG_SAME}"
      echo "command: ${z_invocation[*]}" >> "${BURD_LOG_HIST}"
      echo "Git context: ${BURD_GIT_CONTEXT}"  >> "${BURD_LOG_HIST}"
    fi
    echo "transcript:  ${BURD_TRANSCRIPT}"
    echo "output dir:  ${BURD_OUTPUT_DIR}"
  fi

  zbud_show "Executing coordinator"

  # Execute coordinator with logging
  set +e
  zBURD_STATUS_FILE="${BURD_TEMP_DIR}/status-$$"
  if test -n "${BURD_INTERACTIVE:-}" && test -z "${BURD_NO_LOG:-}"; then
    # Interactive mode with logging: uncurated tee to historical log, preserves line buffering
    "${z_invocation[@]}" 2>&1 | tee -a "${BURD_LOG_HIST}"
    zBURD_EXIT_STATUS=${PIPESTATUS[0]}
    echo "${zBURD_EXIT_STATUS}" > "${zBURD_STATUS_FILE}"
    zbud_show "Coordinator status (interactive): ${zBURD_EXIT_STATUS}"
  elif test -n "${BURD_NO_LOG:-}"; then
    {
      "${z_invocation[@]}"
      echo $? > "${zBURD_STATUS_FILE}"
      zbud_show "Coordinator status: $(cat "${zBURD_STATUS_FILE}")"
    }
  else
    {
      "${z_invocation[@]}" 2>&1
      echo $? > "${zBURD_STATUS_FILE}"
      zbud_show "Coordinator status: $(cat "${zBURD_STATUS_FILE}")"
    } | while IFS= read -r z_line; do
        printf '%s\n' "${z_line}" >> "${BURD_LOG_LAST}"
        printf '%s\n' "${z_line}" | zbud_curate_same >> "${BURD_LOG_SAME}"
        printf '%s\n' "${z_line}" | zbud_curate_hist >> "${BURD_LOG_HIST}"
        printf '%s\n' "${z_line}"  # to stdout
      done
  fi

  zBURD_EXIT_STATUS=$(<"${zBURD_STATUS_FILE}")
  rm                     "${zBURD_STATUS_FILE}"

  # Write BURX completion state
  zbud_write_burx_completion "${zBURD_EXIT_STATUS}"

  set -e

  # Generate checksum for the log files (only when enabled)
  if test -z "${BURD_NO_LOG:-}"; then
    zbud_generate_checksum "${BURD_LOG_SAME}" "${BURD_LOG_HIST}"
    zbud_show "Checksum generated"
  fi

  zbud_show "BDU completed with status: ${zBURD_EXIT_STATUS}"

  exit "${zBURD_EXIT_STATUS}"
}

zbud_main "$@"

# eof
