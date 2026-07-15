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
# Recipe Bottle Lode - kind-decode cluster (sourced by both rbld0_lode and
# rbfl0_ledger): the single home for decoding a Lode touchmark's kind from its
# kind-letter prefix. Sentinel is zrbfc_sentinel, not zrbld_sentinel — like the
# spine and delete clusters, this hearting binds nothing rbld and must run in the
# rbfl (Foundry Ledger) context where rbld is not kindled.

set -euo pipefail

# Multiple inclusion detection — this cluster is multiply-sourced (rbld0_lode for
# the Lode verbs, rbfl0_ledger for yoke's reliquary kind gate), so it carries its
# own guard (BCG "the single-guard rule, and its one exception"). rbld and rbfl are
# never co-furnished, so the guard is the documented backstop, not a live fire.
test -z "${ZRBLDK_SOURCED:-}" || buc_die "Module rbldk multiply sourced - check sourcing hierarchy"
ZRBLDK_SOURCED=1

######################################################################
# Touchmark kind decode (zrbld_*)

# Decode a Lode touchmark's kind from its kind-letter prefix. A touchmark is
# <kind><YYMMDDHHMMSS> (e.g. r260327172456 -> reliquary, vw260602120000 ->
# podvm-wsl). The kind is the leading letter-run, extracted by stripping from the
# first digit and matched as a WHOLE prefix against the RBGC_LODE_KIND_* enum —
# never char[0], so a 2-letter podvm prefix (vw/vn) is never mis-read as its first
# letter. Emits the matched RBGC_LODE_KIND_* on stdout; returns 1 on an
# unrecognized prefix.
#
# This is the single home for touchmark kind decode — used wherever a consumer
# needs a Lode's kind, on both the express path (a bare touchmark: operator input
# or display) and the chained path (a touchmark handed forward through the depth-1
# fact chain). The touchmark is the sole carrier of kind: its kind-letter prefix
# decodes here, and the chain carries no separate kind-brand fact. The two
# consumers are feoff (its bole gate) and yoke (its reliquary gate).
#
# _capture shape: stdout once or return 1; the caller guards with || buc_die.
# Args: <touchmark>
zrbld_decode_touchmark_kind_capture() {
  zrbfc_sentinel

  local -r z_touchmark="${1:-}"
  local -r z_prefix="${z_touchmark%%[0-9]*}"

  case "${z_prefix}" in
    "${RBGC_LODE_KIND_BOLE}")         printf '%s' "${RBGC_LODE_KIND_BOLE}";         return 0 ;;
    "${RBGC_LODE_KIND_RELIQUARY}")    printf '%s' "${RBGC_LODE_KIND_RELIQUARY}";    return 0 ;;
    "${RBGC_LODE_KIND_WSL}")          printf '%s' "${RBGC_LODE_KIND_WSL}";          return 0 ;;
    "${RBGC_LODE_KIND_PODVM_WSL}")    printf '%s' "${RBGC_LODE_KIND_PODVM_WSL}";    return 0 ;;
    "${RBGC_LODE_KIND_PODVM_NATIVE}") printf '%s' "${RBGC_LODE_KIND_PODVM_NATIVE}"; return 0 ;;
  esac
  return 1
}

# eof
