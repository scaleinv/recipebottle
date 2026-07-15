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
# Recipe Bottle GAR Layout - Implementation
#
# Kindle constants for GAR categorical-namespace path construction.
# Callers interpolate the three root constants with hallmark/date/anchor and
# basename literals at the call site — no subshell, no function call overhead.
#
# Shape:
#   "${z_gar_base}/${RBGL_HALLMARKS_ROOT}/<hallmark>/<basename>:<hallmark>"
#   "${z_gar_base}/${RBGL_DEPOT_FACTS_ROOT}/<filename>:<tag>"
#   "${z_gar_base}/${RBGL_LODES_ROOT}/<kind-letter><stamp>:<member-tag>"

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGL_SOURCED:-}" || buc_die "Module rbgl multiply sourced - check sourcing hierarchy"
ZRBGL_SOURCED=1

######################################################################
# Internal Functions (zrbgl_*)

zrbgl_kindle() {
  test -z "${ZRBGL_KINDLED:-}" || buc_die "Module rbgl already kindled"

  # Category constants come from rbgc.
  zrbgc_sentinel

  # Root segments — category only. Callers append '/<id>/<basename>:<tag>'.
  readonly RBGL_HALLMARKS_ROOT="${RBGC_GAR_CATEGORY_HALLMARKS}"
  readonly RBGL_DEPOT_FACTS_ROOT="${RBGC_GAR_CATEGORY_DEPOT_FACTS}"
  readonly RBGL_LODES_ROOT="${RBGC_GAR_CATEGORY_LODES}"

  readonly ZRBGL_KINDLED=1
}

zrbgl_sentinel() {
  test "${ZRBGL_KINDLED:-}" = "1" || buc_die "Module rbgl not kindled - call zrbgl_kindle first"
}

# eof
