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
# Recipe Bottle Foundry Hygiene - Dockerfile FROM-line constraint shared by kludge and conjure

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBFH_SOURCED:-}" || buc_die "Module rbfh multiply sourced - check sourcing hierarchy"
ZRBFH_SOURCED=1

######################################################################
# Internal Functions (zrbfh_*)

zrbfh_kindle() {
  test -z "${ZRBFH_KINDLED:-}" || buc_die "Module rbfh already kindled"
  readonly ZRBFH_KINDLED=1
}

zrbfh_sentinel() {
  test "${ZRBFH_KINDLED:-}" = "1" || buc_die "Module rbfh not kindled - call zrbfh_kindle first"
}

######################################################################
# External Functions (rbfh_*)

# Dockerfile Hygiene Check
#
# Enforces project-wide constraints on Dockerfile FROM lines so that the
# ARG/${RBF_IMAGE_n} parameterization stays the sole source of base
# image origin. Hygiene violations short-circuit before any build, in
# both the local kludge and the Cloud Build conjure paths.
#
# Rules apply to every line at column 0 starting with FROM followed by
# whitespace, after column-0 `#` comments are filtered out. Violation
# emits {path}:{lineno}: {rule} — {offending line} precision via buc_die.
# Multi-stage `AS <name>` codas after token 2 are admissible. Empty
# Dockerfile or one with no column-0 FROM line passes silently.
rbfh_dockerfile_check() {
  zrbfh_sentinel

  local -r z_path="${1:-}"
  test -n "${z_path}" || buc_die "rbfh_dockerfile_check: Dockerfile path required"
  test -f "${z_path}" || buc_die "rbfh_dockerfile_check: Dockerfile not found: ${z_path}"

  local z_line=""
  local z_lineno=0
  local z_token2=""
  local z_pre=""
  local z_post=""

  while IFS= read -r z_line || test -n "${z_line}"; do
    z_lineno=$(( z_lineno + 1 ))

    # Docker treats only column-0 `#` as a comment
    case "${z_line}" in
      '#'*) continue ;;
    esac

    # Constrain only column-0 FROM lines followed by whitespace
    [[ "${z_line}" =~ ^FROM[[:space:]] ]] || continue

    # Rule 1: no tab character anywhere on the FROM line
    case "${z_line}" in
      *$'\t'*) buc_reject "${BUBC_band_hygiene}" "${z_path}:${z_lineno}: FROM line contains tab character — ${z_line}" ;;
    esac

    # Rule 3: line does not end with `\`
    case "${z_line}" in
      *'\') buc_reject "${BUBC_band_hygiene}" "${z_path}:${z_lineno}: FROM line ends with backslash continuation — ${z_line}" ;;
    esac

    # Rule 2: second whitespace-delimited token must be approved
    read -r z_pre z_token2 z_post <<<"${z_line}"
    case "${z_token2}" in
      '${RBF_IMAGE_1}'|'${RBF_IMAGE_2}'|'${RBF_IMAGE_3}'|'scratch') : ;;
      *) buc_reject "${BUBC_band_hygiene}" "${z_path}:${z_lineno}: FROM image token must be \${RBF_IMAGE_1..3} or scratch — ${z_line}" ;;
    esac
  done < "${z_path}"
}

# eof
