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
# RBTE Engine - Theurge test engine implementation module
#
# BCG module providing kindle/sentinel/public functions for theurge
# Rust build, test, and orchestration commands.

set -euo pipefail

# Multiple inclusion guard
test -z "${ZRBTE_SOURCED:-}" || return 0
ZRBTE_SOURCED=1

######################################################################
# Kindle

zrbte_kindle() {
  test -z "${ZRBTE_KINDLED:-}" || buc_die "rbte already kindled"

  local z_dir="${BASH_SOURCE[0]%/*}"

  readonly RBTE_MANIFEST="${z_dir}/Cargo.toml"

  # Windows-native cargo (the x86_64-pc-windows-gnu toolchain) cannot open a
  # Cygwin /cygdrive-style path argument — it reads it as a literal Windows path
  # and reports "does not exist". Under Cygwin, hand cargo a Windows-form path
  # (drive-letter root, forward slashes — which Windows accepts). Pure parameter
  # expansion, no subshell and no external cygpath, mirroring RBTDRX's /cygdrive
  # fast path on the Rust side. Same path-argument boundary as the
  # Windows shellcheck.exe, distinct from the .sh process-launch boundary
  # RBTDRX/rbtdri handle Rust-side. Identity off Cygwin; fails fast on an
  # unsurveyed shape.
  # Retire when theurge builds as a true Cygwin binary.
  if test "${OSTYPE:-}" = "cygwin"; then
    case "${RBTE_MANIFEST}" in
      /cygdrive/?/*)
        local -r z_drive_rest="${RBTE_MANIFEST#/cygdrive/}"
        local -r z_drive="${z_drive_rest%%/*}"
        local -r z_drive_tail="${z_drive_rest#"${z_drive}/"}"
        readonly RBTE_MANIFEST_ARG="${z_drive}:/${z_drive_tail}"
        ;;
      *)
        buc_die "rbte: cannot translate manifest path for Windows cargo (expected /cygdrive/X/...): ${RBTE_MANIFEST}"
        ;;
    esac
  else
    readonly RBTE_MANIFEST_ARG="${RBTE_MANIFEST}"
  fi

  readonly ZRBTE_BINARY="${z_dir}/target/debug/rbtd"

  # Suite→fixture composition is owned by theurge (RBTDRC_SUITES in
  # rbtdrc_crucible.rs), not bash. Suite names survive here only as tabtarget
  # imprints passed straight through to the binary's `suite` mode.

  readonly ZRBTE_KINDLED=1
}

######################################################################
# Sentinel

zrbte_sentinel() {
  test "${ZRBTE_KINDLED:-}" = "1" || buc_die "Module rbte not kindled - call zrbte_kindle first"
}

######################################################################
# Internal helpers

# zrbte_codegen() - Refresh all zipper-derived artifacts before compiling.
# Write-on-change, so unchanged files keep their mtime and cargo skips rebuilds.
# The build is the sole producer — there is no standalone generate command.
zrbte_codegen() {
  zrbte_sentinel

  rbz_generate_context "${BURD_TABTARGET_DIR}" "${RBCC_tabtarget_context_file}" \
    || buc_die "Failed to generate tabtarget context"
  rbz_generate_consts "${RBCC_rbtdgc_consts_file}" \
    || buc_die "Failed to generate colophon consts"
}

zrbte_build_binary() {
  zrbte_sentinel

  zrbte_codegen
  buc_step "Building theurge"
  cargo build --manifest-path "${RBTE_MANIFEST_ARG}" || buc_die "cargo build failed"
  test -x "${ZRBTE_BINARY}" || buc_die "Theurge binary not found: ${ZRBTE_BINARY}"
}

######################################################################
# Public functions

rbte_build() {
  zrbte_sentinel

  zrbte_codegen
  buc_step "Building theurge"
  buc_log_args "Manifest: ${RBTE_MANIFEST}"
  cargo build --manifest-path "${RBTE_MANIFEST_ARG}" "$@" || buc_die "cargo build failed"
  buc_success "Theurge built"
}

rbte_test() {
  zrbte_sentinel

  zrbte_codegen
  buc_step "Testing theurge"
  buc_log_args "Manifest: ${RBTE_MANIFEST}"
  cargo test --manifest-path "${RBTE_MANIFEST_ARG}" "$@" || buc_die "cargo test failed"
  buc_success "All theurge tests passed"
}

rbte_run() {
  zrbte_sentinel

  local z_fixture="${BUZ_FOLIO:-}"
  test -n "${z_fixture}" || buc_die "No fixture — pass one as the folio (e.g. rbw-tf.FixtureRun.sh tadmor)"

  zrbte_build_binary

  # Extra CLI args (e.g. --keep-going) pass straight through to the binary,
  # which owns flag parsing and the disposition policy gate.
  buc_step "Running theurge fixture '${z_fixture}'"
  "${ZRBTE_BINARY}" "${z_fixture}" "$@"
}

rbte_suite() {
  zrbte_sentinel

  local z_suite="${BUZ_FOLIO:-}"
  test -n "${z_suite}" || buc_die "No suite imprint — use tabtarget with imprint (e.g. rbw-ts.TestSuite.reveille.sh)"

  zrbte_build_binary

  # Composition is owned by theurge: pass the suite imprint straight through to
  # the binary's `suite` mode, which resolves and runs its fixtures. Extra CLI
  # args (e.g. --keep-going) pass through with it.
  buc_step "Running theurge suite '${z_suite}'"
  "${ZRBTE_BINARY}" suite "${z_suite}" "$@"
}

rbte_single() {
  zrbte_sentinel

  zrbte_build_binary

  local z_fixture="${BUZ_FOLIO:-}"
  local z_case="${1:-}"
  "${ZRBTE_BINARY}" single ${z_fixture:+"${z_fixture}"} ${z_case:+"${z_case}"}
}

rbte_dowse() {
  zrbte_sentinel

  zrbte_build_binary

  # Read-only census over the station's self-logs. The log dir is a station
  # regime value (BURS_LOG_DIR); dispatch does not export it to children, so
  # reach it by sourcing the launcher-exported station file — the burs_cli
  # pattern.
  test -n "${BURD_STATION_FILE:-}" || buc_die "BURD_STATION_FILE not set - launch via tabtarget"
  source "${BURD_STATION_FILE}" || buc_die "Failed to source station file: ${BURD_STATION_FILE}"
  test -n "${BURS_LOG_DIR:-}" || buc_die "BURS_LOG_DIR not set in ${BURD_STATION_FILE}"

  buc_step "Dowsing observed tariff history"
  "${ZRBTE_BINARY}" dowse "${BURS_LOG_DIR}"
}

rbte_nihil() {
  zrbte_sentinel

  buc_step "Nihil: synthetic colophon for the calibrant census coverage cases"
  buc_success "Nihil: complete"
}

# eof
