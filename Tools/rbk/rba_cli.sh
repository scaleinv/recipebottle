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
# RBA CLI - Recipe Bottle Auth command-line interface
#
# Surfaces the sitting-lifecycle operator verbs as tabtargets — where avow
# itself never is: novate, the one mutating surface (RBS0 rbtf_novate), and
# espy, the read-only probe (RBS0 rbtf_espy). Thin arm over the rba library:
# the furnish carries only the avowal-path stack (trust + manor pool + OAuth
# transport), none of the depot/don machinery the probe CLI (rbgv_cli.sh) pulls.

set -euo pipefail

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"

######################################################################
# CLI Commands

# Novate the sitting — force-fresh renewal: bypass the sitting-reuse branch
# and atomically overwrite any standing sitting with a freshly-opened,
# full-window one. The remedy the avow runway gate names when it turns a
# short sitting away. Mechanism-gated exactly as avowal is: device-flow
# interactive or RFC 7523 programmatic per the trust's RBRF_MECHANISM.
# Depot-agnostic like the avowal probe: needs only the RBRF trust + manor pool.
rba_novate_sitting() {
  zrba_sentinel
  buc_doc_brief "Novate the sitting — open a fresh full-window sitting, extinguishing any standing one (the runway gate's named remedy)"
  buc_doc_shown || return 0

  buc_step "Novation — force-fresh sitting against the RBRF trust"
  rbcc_source_active_rbrf
  source "${RBCC_rbrw_file}" || buc_die "Failed to source RBRW: ${RBCC_rbrw_file}"
  zrbrf_kindle
  zrbrw_kindle
  zrbrf_enforce
  zrbrw_enforce

  rba_novate

  local z_token
  z_token=$(zrba_sitting_read_capture) || buc_die "Sitting not readable after novation"
  test -n "${z_token}" || buc_die "Sitting holds an empty federated token"
  buc_success "Sitting novated — fresh full-window federated token obtained (${#z_token} chars)"
}

# Espy the sitting — the read-only probe (RBS0 rbtf_espy): report whether a
# sitting is live and how much runway remains, from the cache alone — never
# opening one, never prompting, no network. An absent or lapsed sitting is a
# reported verdict, exit 0 (the descry precedent, RBSFD); only a broken read
# dies. Liveness and sufficiency judgments belong to the callers: the verdict
# rides a fact file keyed by the active foedus, the branch point for the
# theurge gate arc's fail-fast before its may-prompt baseline avow.
rba_espy_sitting() {
  zrba_sentinel
  buc_doc_brief "Espy the sitting — report liveness and remaining runway from the cache alone (read-only: never opens, never prompts, no network)"
  buc_doc_shown || return 0

  buc_step "Espy — sitting state against the RBRF trust"
  rbcc_source_active_rbrf
  source "${RBCC_rbrw_file}" || buc_die "Failed to source RBRW: ${RBCC_rbrw_file}"
  zrbrf_kindle
  zrbrw_kindle
  zrbrf_enforce
  zrbrw_enforce

  local z_path
  z_path=$(zrba_sitting_path_capture) || buc_die "Failed to resolve the sitting cache path"

  # Verdict: absent (no cache), else live/lapsed by the skew-gated predicate.
  # Runway is reported raw (a lapsed sitting inside the skew window may still
  # show a few seconds) — the probe reports, it never judges sufficiency.
  local z_verdict=""
  local z_runway=""
  if test ! -f "${z_path}"; then
    z_verdict="absent"
  else
    z_runway=$(zrba_sitting_runway_capture) || buc_die "Sitting cache present but unreadable: ${z_path}"
    if zrba_sitting_live_predicate; then
      z_verdict="live"
    else
      z_verdict="lapsed"
    fi
  fi

  local z_value="verdict=${z_verdict}"
  test -z "${z_runway}" || z_value="${z_value}
runway=${z_runway}"
  buf_write_fact_multi "${RBRR_ACTIVE_FOEDUS}" "${RBCC_fact_ext_sitting}" "${z_value}" \
    || buc_die "Failed to write the sitting fact"

  if test "${z_verdict}" = "live"; then
    buc_success "Sitting LIVE — runway ${z_runway}s (~$(( z_runway / 3600 ))h$(( (z_runway % 3600) / 60 ))m remaining)"
  else
    buc_warn "No live sitting — verdict '${z_verdict}'; open one with any federated command or rbw-aN (fresh full window)"
  fi
}

######################################################################
# Furnish and Main

zrba_furnish() {
  buc_doc_env "BURD_BUK_DIR          " "BUK module directory (dispatch-provided)"
  buc_doc_env "BURD_TEMP_DIR         " "Bash Dispatch Utility provided temporary directory, empty at start of command"
  buc_doc_env_done || return 0

  local z_rbk="${BASH_SOURCE[0]%/*}"
  source "${BURD_BUK_DIR}/buv_validation.sh"
  source "${BURD_BUK_DIR}/burd_regime.sh"
  source "${BURD_BUK_DIR}/buf_fact.sh"
  source "${z_rbk}/rbrr_regime.sh"
  source "${z_rbk}/rbrf_regime.sh"
  source "${z_rbk}/rbrw_regime.sh"
  source "${z_rbk}/rbcc_constants.sh"
  source "${z_rbk}/rbgc_constants.sh"
  source "${z_rbk}/rbgo_oauth.sh"
  source "${z_rbk}/rba_auth.sh"

  zbuv_kindle
  zburd_kindle

  # RBRR is sourced for the RBRR_ACTIVE_FOEDUS selector alone (the trust
  # resolve in rbcc_source_active_rbrf); depot-agnostic, so no RBRR
  # enforcement — mirroring the avowal probe's furnish posture.
  source "${RBCC_rbrr_file}" || buc_die "Failed to source ${RBCC_rbrr_file}"
  zrbrr_kindle
  zrbcc_kindle
  zrbgc_kindle
  zrbgo_kindle
  zrba_kindle
}

buc_execute rba_ "Recipe Bottle Auth" zrba_furnish "$@"

# eof
