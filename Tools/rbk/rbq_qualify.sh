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
# RBQ Qualify - Qualification orchestrator for tabtarget and colophon health

set -euo pipefail

ZRBQ_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"

source "${BURD_BUK_DIR}/buq_qualify.sh"

# Multiple inclusion detection
test -z "${ZRBQ_SOURCED:-}" || buc_die "Module rbq multiply sourced - check sourcing hierarchy"
ZRBQ_SOURCED=1

######################################################################
# Internal Functions (zrbq_*)

zrbq_kindle() {
  test -z "${ZRBQ_KINDLED:-}" || buc_die "Module rbq already kindled"

  zbuz_sentinel
  zrbz_sentinel
  zrbcc_sentinel

  test -n "${BURC_TABTARGET_DIR:-}" || buc_die "BURC_TABTARGET_DIR not set"
  test -n "${BURC_TOOLS_DIR:-}"     || buc_die "BURC_TOOLS_DIR not set"

  readonly ZRBQ_TT_DIR="${BURC_TABTARGET_DIR}"
  readonly ZRBQ_PROJECT_ROOT="${BURC_TOOLS_DIR}/.."
  readonly ZRBQ_RBW_DIR="${RBCC_KIT_DIR}"
  # Match the bare BURD_LAUNCHER basename the tabtargets carry since the
  # path-indirection migration (BCG "Tabtarget Path Indirection"): the line is
  # `export BURD_LAUNCHER=launcher.rbw_workbench.sh`, a basename, not a path. A
  # moorings/launchers full-path predicate matches none of it — the count goes
  # to zero and the colophon net silently lifts.
  readonly ZRBQ_RBW_LAUNCHER="launcher.rbw_workbench.sh"

  readonly ZRBQ_KINDLED=1
}

zrbq_sentinel() {
  test "${ZRBQ_KINDLED:-}" = "1" || buc_die "Module rbq not kindled - call zrbq_kindle first"
}

######################################################################
# External Functions (rbq_*)

rbq_qualify_colophons() {
  zrbq_sentinel

  buc_step "Qualifying RBW colophon registrations"

  local z_fail_files=()
  local z_fail_reasons=()
  local z_checked=0

  local z_file=""
  for z_file in "${ZRBQ_TT_DIR}"/*.sh; do
    test -e "${z_file}" || continue

    local z_basename="${z_file##*/}"

    # Load file lines (load-then-iterate)
    local z_lines=()
    local z_line=""
    while IFS= read -r z_line || test -n "${z_line}"; do
      z_lines+=("${z_line}")
    done < "${z_file}"

    # Only check tabtargets using the RBW workbench launcher
    local z_is_rbw=0
    if (( ${#z_lines[@]} > 1 )); then
      case "${z_lines[1]}" in
        *"${ZRBQ_RBW_LAUNCHER}"*) z_is_rbw=1 ;;
      esac
    fi
    test "${z_is_rbw}" = "1" || continue

    z_checked=$((z_checked + 1))

    # Extract colophon from filename (everything before first delimiter)
    local z_colophon="${z_basename%%.*}"

    # Check colophon exists in z_buz_colophon_roll registry
    local z_found=0
    local z_i=0
    for z_i in "${!z_buz_colophon_roll[@]}"; do
      test "${z_buz_colophon_roll[$z_i]}" = "${z_colophon}" || continue
      z_found=1

      # Verify module file exists
      local z_module="${z_buz_module_roll[$z_i]}"
      test -f "${ZRBQ_RBW_DIR}/${z_module}" || {
        z_fail_files+=("${z_basename}")
        z_fail_reasons+=("module not found: ${z_module}")
      }
      break
    done

    test "${z_found}" = "1" || {
      z_fail_files+=("${z_basename}")
      z_fail_reasons+=("colophon '${z_colophon}' not registered in rbz_zipper")
    }
  done

  buc_log_args "Checked ${z_checked} RBW tabtargets"

  if (( ${#z_fail_files[@]} )); then
    local z_j=0
    for z_j in "${!z_fail_files[@]}"; do
      buc_warn "${z_fail_files[$z_j]}: ${z_fail_reasons[$z_j]}"
    done
    buc_die "Colophon qualification failed: ${#z_fail_files[@]} of ${z_checked} tabtargets"
  fi

  buc_log_args "All ${z_checked} RBW colophons registered"
}

# rbq_qualify_completeness() - The forward completeness sweep: every enrolled
# colophon (RBW and BUW — zrbq_furnish kindles both zippers into the shared roll)
# must have a tabtarget on disk. Homed as an rblm_zero (rbw-MZ) precondition,
# never the per-dispatch path: rbw-MZ is withheld from delivery, so this proves
# the source repo complete while a stripped consumer never runs it. The forward
# sibling of rbq_qualify_colophons above (which sweeps tabtarget -> registered).
rbq_qualify_completeness() {
  zrbq_sentinel

  buc_step "Qualifying colophon completeness (every enrolled colophon has a tabtarget)"

  buz_healthcheck

  buc_log_args "All enrolled colophons have tabtargets"
}

rbq_qualify_context() {
  zrbq_sentinel

  buc_step "Qualifying generated context freshness"

  local -r z_committed="${RBCC_tabtarget_context_file}"
  local -r z_fresh="${BURD_TEMP_DIR}/rbq_context_check.md"

  buz_emit_context "rbz" "${ZRBQ_TT_DIR}" > "${z_fresh}" || buc_die "Failed to generate context for comparison"

  if ! test -f "${z_committed}"; then
    buc_die "Generated context file missing: ${z_committed} — run tt/rbw-tb.Build.sh"
  fi

  if [[ "$(<"${z_fresh}")" != "$(<"${z_committed}")" ]]; then
    buc_die "Generated context file is stale: ${z_committed} — run tt/rbw-tb.Build.sh"
  fi

  buc_log_args "Context file is fresh"
}

rbq_qualify_rust_consts() {
  zrbq_sentinel

  buc_step "Qualifying generated Rust consts freshness"

  local -r z_committed="${RBCC_rbtdgc_consts_file}"
  local -r z_fresh="${BURD_TEMP_DIR}/rbq_rust_consts_check.rs"

  rbz_emit_consts > "${z_fresh}" || buc_die "Failed to generate Rust consts for comparison"

  if ! test -f "${z_committed}"; then
    buc_die "Generated Rust consts file missing: ${z_committed} — run tt/rbw-tb.Build.sh"
  fi

  if [[ "$(<"${z_fresh}")" != "$(<"${z_committed}")" ]]; then
    buc_die "Generated Rust consts file is stale: ${z_committed} — run tt/rbw-tb.Build.sh"
  fi

  buc_log_args "Rust consts file is fresh"
}

rbq_qualify_fast() {
  zrbq_sentinel

  buc_step "Running fast qualification"

  buq_tabtargets "${ZRBQ_TT_DIR}" "${ZRBQ_PROJECT_ROOT}" \
    "butctt.*.sh" \
    "buw-SI.*.sh" \
    "z-launcher.sh" \
    # End of exempt list
  rbq_qualify_colophons
  rbq_qualify_context
  rbq_qualify_rust_consts
  rbrn_preflight

  buc_step "Fast qualification passed"
}

# Shellcheck is surfaced standalone as rbw-tl (lint without the test suite), and
# also runs inside the release-prep tier (rbw-tr) and the marshal-zero gate
# (rbw-MZ). It is deliberately absent from fast qualify and the charge/ordain
# workbench gate: routine development and container operations run already-linted,
# shipped code and do not require the shellcheck binary.
rbq_qualify_shellcheck() {
  zrbq_sentinel

  buc_step "Running shellcheck"

  # Load-bearing bash lives outside Tools/ too: the vessel security-boundary
  # jailers (sentry + pentacle, shipped in every vessel build context) and the
  # per-nameplate charge hooks. Enumerate them as explicit extras so the gate
  # covers them by construction — a directory-root widening would sweep in the
  # deliberately-excluded launcher shims, Study/ scratch, POC drivers, and
  # example-vessel scripts that share those parents. The charge hooks are
  # globbed (per-nameplate, recurring by construction); the jailers are singletons.
  local z_extras=(
    "${ZRBQ_PROJECT_ROOT}/rbmm_moorings/rbmv_vessels/common-sentry-context/rbjs_sentry.sh"
    "${ZRBQ_PROJECT_ROOT}/rbmm_moorings/rbmv_vessels/common-sentry-context/rbjp_pentacle.sh"
  )
  local z_hook=""
  for z_hook in "${ZRBQ_PROJECT_ROOT}"/rbmm_moorings/*/rbnnh_post_charge.sh; do
    test -e "${z_hook}" || continue
    z_extras+=("${z_hook}")
  done

  buq_shellcheck "${BURC_TOOLS_DIR}" \
    "${BURD_BUK_DIR}/busc_shellcheckrc" \
    "${BURD_TEMP_DIR}/buq_shellcheck_results.txt" \
    "${z_extras[@]}"

  buc_step "Shellcheck qualification passed"
}

rbq_qualify_release() {
  zrbq_sentinel

  buc_step "Running release qualification"

  rbq_qualify_fast
  rbq_qualify_shellcheck

  buc_step "Running echelon test suite"
  "${ZRBQ_PROJECT_ROOT}/tt/rbw-ts.TestSuite.echelon.sh"

  buc_step "Release qualification passed"
}

# Pristine/skirmish/tadmor qualification collapsed into rbw-ts suite imprints
# (gauntlet/skirmish/siege) — see the suite registry RBTDRC_SUITES in
# rbtdrc_crucible.rs. The siege suite preserves the deliberate two-fixture
# (kludge-tadmor, tadmor) sequence; its rationale lives on that registry entry.

# eof
