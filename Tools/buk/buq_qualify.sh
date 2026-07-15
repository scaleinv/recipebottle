#!/bin/bash
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
# Bash Qualify Utility Library - Tabtarget structural qualification

set -euo pipefail

# Multiple inclusion guard
test -z "${ZBUQ_INCLUDED:-}" || return 0
ZBUQ_INCLUDED=1

# Source the console utility library + moorings-layout names (launcher subdir)
ZBUQ_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "${ZBUQ_SCRIPT_DIR}/buc_command.sh"
source "${ZBUQ_SCRIPT_DIR}/buym_yelp.sh"
source "${ZBUQ_SCRIPT_DIR}/bubc_constants.sh"

# Pinned shellcheck version. The shellcheck gate hard-fails if the running
# binary differs, locking every station to one version. The pin is exact, not a
# floor, for two reasons:
#   1. --rcfile (used by buq_shellcheck) did not exist before 0.10.0; an older
#      binary silently rejects the flag and runs rule-less — a false pass.
#   2. Check coverage and severity defaults drift across versions, so the same
#      tree can pass on one station and fail on another. The pin converts that
#      silent cross-station divergence into an immediate, actionable failure.
# Bump deliberately and in lockstep across every station platform (Linux,
# macOS): install the matching binary everywhere, then change this constant.
readonly BUQ_SHELLCHECK_VERSION="0.11.0"

######################################################################
# Tabtarget structural qualification

buq_tabtargets() {
  local z_tt_dir="${1:-}"
  local z_project_root="${2:-}"
  test -n "${z_tt_dir}"       || buc_die "buq_tabtargets: tabtarget directory required"
  test -n "${z_project_root}" || buc_die "buq_tabtargets: project root required"
  test -d "${z_tt_dir}"       || buc_die "buq_tabtargets: directory not found: ${z_tt_dir}"
  shift 2

  # Remaining arguments are glob patterns for exempt tabtargets
  local z_exemptions=("$@")

  buc_step "Qualifying tabtarget structure in ${z_tt_dir}"

  local z_fail_files=()
  local z_fail_reasons=()
  local z_count=0
  local z_exempt_count=0

  # Prescribed tabtarget form (from buut_tabtarget.sh generator):
  #   Line 1:       #!/bin/bash
  #   Line 2:       export BURD_LAUNCHER=launcher.<id>_workbench.sh
  #   Lines 3..N-1: optional export BURD_*=* flag lines
  #   Last line:    exec "${BASH_SOURCE[0]%/*}/z-launcher.sh" "${0##*/}" "${@}"
  # BURD_LAUNCHER names the moorings launcher as a bare basename; z-launcher.sh
  # resolves it directly under the launcher dir. The exec line is a byte-
  # identical constant in every tabtarget.
  local z_prescribed_shebang='#!/bin/bash'
  local z_launcher_prefix='export BURD_LAUNCHER='
  local z_prescribed_exec='exec "${BASH_SOURCE[0]%/*}/z-launcher.sh" "${0##*/}" "${@}"'

  local z_file=""
  for z_file in "${z_tt_dir}"/*.sh; do
    test -e "${z_file}" || continue
    z_count=$((z_count + 1))

    local z_basename="${z_file##*/}"

    # Check exemption patterns
    local z_is_exempt=0
    local z_exempt_pattern=""
    for z_exempt_pattern in "${z_exemptions[@]+"${z_exemptions[@]}"}"; do
      case "${z_basename}" in
        ${z_exempt_pattern}) z_is_exempt=1; break ;;
      esac
    done
    if test "${z_is_exempt}" = "1"; then
      z_exempt_count=$((z_exempt_count + 1))
      continue
    fi

    # Load file lines (load-then-iterate per BCG)
    local z_lines=()
    local z_line=""
    while IFS= read -r z_line || test -n "${z_line}"; do
      z_lines+=("${z_line}")
    done < "${z_file}"

    local z_num_lines=${#z_lines[@]}

    # Must have at least 3 lines: shebang, BURD_LAUNCHER, exec
    test "${z_num_lines}" -ge 3 || {
      z_fail_files+=("${z_basename}")
      z_fail_reasons+=("too few lines: ${z_num_lines} (minimum 3)")
      continue
    }

    # Line 1: prescribed shebang
    test "${z_lines[0]}" = "${z_prescribed_shebang}" || {
      z_fail_files+=("${z_basename}")
      z_fail_reasons+=("line 1: expected '${z_prescribed_shebang}', got '${z_lines[0]}'")
      continue
    }

    # Line 2: export BURD_LAUNCHER=<basename> resolving to a moorings launcher.
    local z_launcher_line="${z_lines[1]}"
    case "${z_launcher_line}" in
      "${z_launcher_prefix}"launcher.*_workbench.sh) ;;
      *)
        z_fail_files+=("${z_basename}")
        z_fail_reasons+=("line 2: expected '${z_launcher_prefix}launcher.<id>_workbench.sh', got '${z_launcher_line}'")
        continue
        ;;
    esac
    local z_launcher_basename="${z_launcher_line#"${z_launcher_prefix}"}"
    local z_launcher_path="${BURD_MOORINGS_DIR}/${BUBC_launchers_subdir}/${z_launcher_basename}"
    test -f "${z_project_root}/${z_launcher_path}" || {
      z_fail_files+=("${z_basename}")
      z_fail_reasons+=("launcher not found: ${z_launcher_path}")
      continue
    }

    # Middle lines (3..N-1): must be export BURD_*=*
    local z_middle_ok=1
    local z_i=2
    local z_last_idx=$((z_num_lines - 1))
    while test "${z_i}" -lt "${z_last_idx}"; do
      case "${z_lines[$z_i]}" in
        'export BURD_'*'='*) ;;
        *)
          z_fail_files+=("${z_basename}")
          z_fail_reasons+=("line $((z_i + 1)): expected 'export BURD_*=*', got '${z_lines[$z_i]}'")
          z_middle_ok=0
          break
          ;;
      esac
      z_i=$((z_i + 1))
    done
    test "${z_middle_ok}" = "1" || continue

    # Last line: the byte-identical constant exec through the z-launcher trampoline.
    test "${z_lines[$z_last_idx]}" = "${z_prescribed_exec}" || {
      z_fail_files+=("${z_basename}")
      z_fail_reasons+=("last line: expected '${z_prescribed_exec}', got '${z_lines[$z_last_idx]}'")
      continue
    }
  done

  local z_checked=$((z_count - z_exempt_count))
  local z_summary="Checked ${z_checked} tabtargets"
  test "${z_exempt_count}" = "0" || z_summary="${z_summary} (${z_exempt_count} exempt)"
  buc_log_args "${z_summary}"

  if (( ${#z_fail_files[@]} )); then
    local z_j=0
    for z_j in "${!z_fail_files[@]}"; do
      buc_warn "${z_fail_files[$z_j]}: ${z_fail_reasons[$z_j]}" || buc_die "Failed to warn"
    done
    buc_die "Tabtarget qualification failed: ${#z_fail_files[@]} of ${z_checked} tabtargets"
  fi

  buc_log_args "All ${z_checked} tabtargets structurally valid"
}

######################################################################
# Shellcheck qualification

buq_shellcheck() {
  local z_tools_dir="${1:-${BURD_TOOLS_DIR:-}}"
  local z_rcfile="${2:-${BURD_BUK_DIR:+${BURD_BUK_DIR}/busc_shellcheckrc}}"
  local z_result_file="${3:-${BURD_TEMP_DIR:+${BURD_TEMP_DIR}/buq_shellcheck_results.txt}}"
  test -n "${z_tools_dir}"   || buc_die "buq_shellcheck: tools directory required"
  test -n "${z_rcfile}"      || buc_die "buq_shellcheck: rcfile path required"
  test -n "${z_result_file}" || buc_die "buq_shellcheck: result file path required"

  # Args beyond the third are explicit extra .sh files to lint alongside the
  # tree under z_tools_dir — a consumer with load-bearing shell scripts outside
  # its tools dir (vessel/jailer context, charge hooks) enumerates them here.
  # Each must exist: a moved or renamed extra fails loud rather than silently
  # dropping out of coverage.
  local z_extra_files=()
  if (( $# > 3 )); then
    z_extra_files=("${@:4}")
  fi

  buc_step "Running shellcheck qualification"

  test -f "${z_rcfile}"    || buc_die "Shellcheck rcfile not found: ${z_rcfile}"
  test -d "${z_tools_dir}" || buc_die "Tools directory not found: ${z_tools_dir}"

  command -v shellcheck >/dev/null 2>&1 || buc_die "shellcheck not found — install from https://www.shellcheck.net"

  # Hard version pin — fail instantly if this station's shellcheck is not the
  # pinned version, before any check runs. Prevents silent cross-station
  # divergence (e.g. a pre-0.10.0 binary that rejects --rcfile). Keep stations
  # in lockstep; bump BUQ_SHELLCHECK_VERSION only after upgrading all of them.
  local z_sc_version=""
  z_sc_version="$(shellcheck --version | awk '/^version:/ {print $2}')"
  test "${z_sc_version}" = "${BUQ_SHELLCHECK_VERSION}" || buc_die \
    "shellcheck version mismatch: found '${z_sc_version}', require '${BUQ_SHELLCHECK_VERSION}'. Install the pinned version ahead of the system binary on PATH — static release: https://github.com/koalaman/shellcheck/releases/tag/v${BUQ_SHELLCHECK_VERSION}"

  # Collect .sh files (load-then-iterate per BCG)
  local z_files=()
  local z_file=""
  while IFS= read -r z_file || test -n "${z_file}"; do
    z_files+=("${z_file}")
  done < <(find "${z_tools_dir}" -name '*.sh' -type f | sort)

  local -r z_tree_count=${#z_files[@]}

  # Append the validated extra files after the tree set
  if (( ${#z_extra_files[@]} > 0 )); then
    local z_extra=""
    for z_extra in "${z_extra_files[@]}"; do
      test -f "${z_extra}" || buc_die "buq_shellcheck: extra file not found: ${z_extra}"
      z_files+=("${z_extra}")
    done
  fi

  local -r z_file_count=${#z_files[@]}
  buc_log_args "Found ${z_tree_count} shell files under ${z_tools_dir}; ${#z_extra_files[@]} explicit extra files"

  test "${z_file_count}" -gt 0 || buc_die "No .sh files found under ${z_tools_dir}"

  # Run shellcheck — capture output to temp file for forensics
  local z_status=0
  shellcheck --rcfile="${z_rcfile}" -S style -f gcc "${z_files[@]}" \
    > "${z_result_file}" 2>&1 \
    || z_status=$?

  if test "${z_status}" = "0"; then
    buc_step "Shellcheck qualification passed: ${z_file_count} files clean"
    return 0
  fi

  # Count and display findings
  local z_finding_count=0
  local z_discard
  while IFS= read -r z_discard || test -n "${z_discard:-}"; do
    z_finding_count=$((z_finding_count + 1))
  done < "${z_result_file}"
  buc_log_args "Shellcheck findings: ${z_finding_count} (see ${z_result_file})"

  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    buc_warn "${z_line}"
  done < "${z_result_file}"

  buc_die "Shellcheck qualification failed: ${z_finding_count} findings across ${z_file_count} files"
}

# eof
