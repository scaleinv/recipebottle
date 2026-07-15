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
# BUG Git - bash git utilities (BUK domain)
#
# Home for the "tools never commit, but gate on a clean tree" convention: a tool
# may presume git and refuse downstream steps on a dirty tree, but never commits
# in the consumer's codebase. Bash-only — Rust git use is outside BUK framing.

set -euo pipefail

# Multiple inclusion guard
test -z "${ZBUG_SOURCED:-}" || buc_die "Module bug multiply sourced - check sourcing hierarchy"
ZBUG_SOURCED=1

# Tinder constant (pure string literal — available at source time). The detailed
# clean-tree error condition, carried as a structured constant rather than an
# inline free string, so the well-formed gate below states one canonical grievance.
# Untracked files are not gated, so the condition names staged-or-unstaged only.
BUG_clean_tree_condition="git working tree carries uncommitted changes (staged or unstaged)"

# Clean-tree gate — the sole clean-tree guard (a deliberate-rejection gate per
# BCG "Precision Exit-Code Band"): it buc_rejects the named clean-tree band
# rather than dying imprecisely, and states the error condition from the
# BUG_clean_tree_condition constant. BUG holds no opinion on WHY a clean tree
# matters — the caller supplies its rationale as a creed, appended to the
# condition, so the opinion stays kit-side and BUG stays kit-agnostic. Untracked
# files are not gated (staged/unstaged only).
# Args: <creed>  (the caller's rationale for demanding a clean tree)
bug_require_clean_tree_creed() {
  local -r z_creed="${1:-}"
  test -n "${z_creed}" || buc_die "bug_require_clean_tree_creed: creed (rationale) required"

  buc_step "Verifying clean working tree"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    buc_reject "${BUBC_band_clean_tree}" "${BUG_clean_tree_condition} — ${z_creed}"
  fi
}

# eof
