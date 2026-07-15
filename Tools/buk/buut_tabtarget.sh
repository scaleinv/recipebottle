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
# BUUT - Tabtarget and Launcher creation utilities
#
# Functions for creating tabtargets (tt/*.sh) and launchers (rbmm_moorings/rbml_launchers/launcher.*.sh)
# as part of the BUK dispatch system.

set -euo pipefail

# Multiple inclusion detection
test -z "${ZBUUT_SOURCED:-}" || buc_die "Module buut multiply sourced - check sourcing hierarchy"
ZBUUT_SOURCED=1

######################################################################
# Internal Functions (zbuut_*)

zbuut_kindle() {
  test -z "${ZBUUT_KINDLED:-}" || buc_die "Module buut already kindled"

  # Validate BURD environment
  zburd_sentinel

  # Validate BURC environment (needed for paths)
  test -n "${BURC_TABTARGET_DIR:-}" || buc_die "BURC_TABTARGET_DIR is unset"
  test -n "${BURC_TOOLS_DIR:-}" || buc_die "BURC_TOOLS_DIR is unset"

  # Moorings-layout names (launcher subdir) for launcher list/create.
  source "${BURC_TOOLS_DIR}/buk/bubc_constants.sh" || buc_die "Failed to source bubc_constants.sh"

  readonly ZBUUT_KINDLED=1
}

zbuut_sentinel() {
  test "${ZBUUT_KINDLED:-}" = "1" || buc_die "Module buut not kindled - call zbuut_kindle first"
}

# Verbose output if BURE_VERBOSE is set
zbuut_show() {
  test "${BURE_VERBOSE:-0}" != "1" || echo "BUUTSHOW: $*"
}

# Write a tabtarget file with specified flags
# Usage: zbuut_write_tabtarget <launcher_path> <tabtarget_file> <flag_lines>
zbuut_write_tabtarget() {
  zbuut_sentinel

  local z_launcher_path="${1:-}"
  local z_tabtarget_file="${2:-}"
  local z_flag_lines="${3:-}"

  test -n "${z_launcher_path}" || buc_die "zbuut_write_tabtarget: launcher_path required"
  test -n "${z_tabtarget_file}" || buc_die "zbuut_write_tabtarget: tabtarget_file required"

  zbuut_show "Writing tabtarget: ${z_tabtarget_file}"

  # Build the tabtarget content. The launcher is named in the BURD_LAUNCHER
  # config line as a bare basename (launcher.<id>_workbench.sh); z-launcher.sh
  # reads it from the environment and resolves it directly under the moorings
  # launcher dir. The exec line carries no launcher token and is byte-identical
  # in every tabtarget.
  echo '#!/bin/bash' > "${z_tabtarget_file}"
  echo "export BURD_LAUNCHER=${z_launcher_path##*/}" >> "${z_tabtarget_file}"

  # Add flag lines if provided
  if test -n "${z_flag_lines}"; then
    echo "${z_flag_lines}" >> "${z_tabtarget_file}"
  fi

  echo "exec \"\${BASH_SOURCE[0]%/*}/z-launcher.sh\" \"\${0##*/}\" \"\${@}\"" >> "${z_tabtarget_file}"

  chmod +x "${z_tabtarget_file}" || buc_die "Failed to make tabtarget executable: ${z_tabtarget_file}"
}

# Create tabtargets with specified flags
# Usage: zbuut_create_tabtargets <flag_lines> <launcher_path> <tabtarget_name>...
zbuut_create_tabtargets() {
  zbuut_sentinel

  local z_flag_lines="${1:-}"
  shift || true
  local z_launcher_path="${1:-}"
  shift || true

  test -n "${z_launcher_path}" || buc_die "launcher_path required"
  test "$#" -gt 0 || buc_die "at least one tabtarget_name required"

  # Validate launcher exists
  local z_launcher_file="${PWD}/${z_launcher_path}"
  test -f "${z_launcher_file}" || buc_die "launcher not found: ${z_launcher_file}"

  # Process each tabtarget name
  local z_tabtarget_name
  for z_tabtarget_name in "$@"; do
    local z_tabtarget_file="${PWD}/${BURC_TABTARGET_DIR}/${z_tabtarget_name}.sh"

    # Warn if overwriting
    test ! -f "${z_tabtarget_file}" || buc_warn "overwriting existing tabtarget: ${z_tabtarget_file}"

    zbuut_write_tabtarget "${z_launcher_path}" "${z_tabtarget_file}" "${z_flag_lines}"
    buc_success "Created tabtarget: ${z_tabtarget_file}"
  done
}

######################################################################
# External Functions (buut_*)

# List launchers in the moorings launcher directory
buut_list_launchers() {
  buc_doc_brief "List all launchers in the moorings launcher directory"
  buc_doc_shown || return 0

  zbuut_sentinel
  local z_launcher_dir="${BURD_CONFIG_DIR}/${BUBC_launchers_subdir}"
  zbuut_show "Listing launchers in ${z_launcher_dir}"
  buc_step "Launchers in ${z_launcher_dir}"
  local z_found=0
  local z_launcher
  for z_launcher in "${z_launcher_dir}/launcher."*.sh; do
    test -f "${z_launcher}" || continue
    echo "${z_launcher}"
    z_found=1
  done
  test "${z_found}" = "1" || echo "  (none found)"
}

# Create batch+logging tabtargets (default)
buut_tabtarget_batch_logging() {
  local z_launcher_path="${1:-}"
  shift || true

  buc_doc_brief "Create batch+logging tabtarget(s) (default mode)"
  buc_doc_param "launcher_path" "Path to launcher (e.g., rbmm_moorings/rbml_launchers/launcher.rbw_workbench.sh)"
  buc_doc_param "tabtarget_name" "One or more tabtarget names (e.g., rbw-ri.RegimeInfo)"
  buc_doc_shown || return 0

  zbuut_sentinel
  test -n "${z_launcher_path}" || buc_usage_die

  buc_step "Creating batch+logging tabtarget(s)"
  zbuut_create_tabtargets "" "${z_launcher_path}" "$@"
}

# Create batch+nolog tabtargets (BURD_NO_LOG=1)
buut_tabtarget_batch_nolog() {
  local z_launcher_path="${1:-}"
  shift || true

  buc_doc_brief "Create batch+nolog tabtarget(s) (BURD_NO_LOG=1)"
  buc_doc_param "launcher_path" "Path to launcher (e.g., rbmm_moorings/rbml_launchers/launcher.rbw_workbench.sh)"
  buc_doc_param "tabtarget_name" "One or more tabtarget names (e.g., rbw-ri.RegimeInfo)"
  buc_doc_shown || return 0

  zbuut_sentinel
  test -n "${z_launcher_path}" || buc_usage_die

  buc_step "Creating batch+nolog tabtarget(s)"
  zbuut_create_tabtargets 'export BURD_NO_LOG=1' "${z_launcher_path}" "$@"
}

# Create interactive+logging tabtargets (BURD_INTERACTIVE=1)
buut_tabtarget_interactive_logging() {
  local z_launcher_path="${1:-}"
  shift || true

  buc_doc_brief "Create interactive+logging tabtarget(s) (BURD_INTERACTIVE=1)"
  buc_doc_param "launcher_path" "Path to launcher (e.g., rbmm_moorings/rbml_launchers/launcher.cccw_workbench.sh)"
  buc_doc_param "tabtarget_name" "One or more tabtarget names (e.g., ccck-s.ConnectShell)"
  buc_doc_shown || return 0

  zbuut_sentinel
  test -n "${z_launcher_path}" || buc_usage_die

  buc_step "Creating interactive+logging tabtarget(s)"
  zbuut_create_tabtargets 'export BURD_INTERACTIVE=1' "${z_launcher_path}" "$@"
}

# Create interactive+nolog tabtargets (both flags)
buut_tabtarget_interactive_nolog() {
  local z_launcher_path="${1:-}"
  shift || true

  buc_doc_brief "Create interactive+nolog tabtarget(s) (BURD_INTERACTIVE=1, BURD_NO_LOG=1)"
  buc_doc_param "launcher_path" "Path to launcher (e.g., rbmm_moorings/rbml_launchers/launcher.rbw_workbench.sh)"
  buc_doc_param "tabtarget_name" "One or more tabtarget names (e.g., rbw-PI.PayorInstall)"
  buc_doc_shown || return 0

  zbuut_sentinel
  test -n "${z_launcher_path}" || buc_usage_die

  buc_step "Creating interactive+nolog tabtarget(s)"
  local z_flags='export BURD_NO_LOG=1
export BURD_INTERACTIVE=1'
  zbuut_create_tabtargets "${z_flags}" "${z_launcher_path}" "$@"
}

# Create a launcher
buut_launcher() {
  local z_workbench_path="${1:-}"
  local z_launcher_name="${2:-}"

  buc_doc_brief "Create a launcher stub in rbmm_moorings/rbml_launchers/"
  buc_doc_param "workbench_path" "Path to workbench script (e.g., Tools/myw/myw_workbench.sh)"
  buc_doc_param "launcher_name" "Launcher name without prefix/suffix (e.g., myw_workbench)"
  buc_doc_shown || return 0

  zbuut_sentinel
  test -n "${z_workbench_path}" || buc_usage_die
  test -n "${z_launcher_name}" || buc_usage_die

  # Validate workbench exists
  local z_workbench_file="${PWD}/${z_workbench_path}"
  test -f "${z_workbench_file}" || buc_die "workbench not found: ${z_workbench_file}"

  # Validate moorings launcher directory exists
  local z_launcher_dir="${BURD_CONFIG_DIR}/${BUBC_launchers_subdir}"
  test -d "${z_launcher_dir}" || buc_die "launcher directory not found: ${z_launcher_dir}"

  local z_launcher_file="${z_launcher_dir}/launcher.${z_launcher_name}.sh"

  # Warn if overwriting
  test ! -f "${z_launcher_file}" || buc_warn "overwriting existing launcher: ${z_launcher_file}"

  buc_step "Creating launcher: ${z_launcher_file}"
  zbuut_show "Workbench path: ${z_workbench_path}"

  # Extract comment description from launcher name (strip common suffixes)
  local z_description="${z_launcher_name}"
  z_description="${z_description%_workbench}"
  z_description="${z_description%_testbench}"
  z_description="${z_description%_Coordinator}"

  # Write the 4-line launcher stub. z-launcher.sh chdirs to repo root before
  # exec'ing the stub, so the bul_launcher source path is repo-root-relative —
  # no directory-depth counting, immune to where the launcher dir sits.
  {
    echo '#!/bin/bash'
    echo "# Launcher stub - delegates to ${z_description} workbench"
    echo 'source "Tools/buk/bul_launcher.sh"'
    echo "bul_launch \"\${BURC_TOOLS_DIR}/${z_workbench_path#Tools/}\" \"\$@\""
  } > "${z_launcher_file}"

  chmod +x "${z_launcher_file}" || buc_die "Failed to make launcher executable: ${z_launcher_file}"
  buc_success "Created launcher: ${z_launcher_file}"
}

# eof
