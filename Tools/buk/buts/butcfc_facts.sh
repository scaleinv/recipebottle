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
# BUTCFC - Fact-chaining (consume side) test cases for BUK self-test
#
# Exercises buf_relay, buf_read_fact_capture, and buf_elect_fact_capture against
# the live dispatch directories.
# BURD_PREVIOUS_DIR and BURD_OUTPUT_DIR are readonly (locked by the BURD regime),
# so these cases cannot redirect them to scratch — they seed uniquely-named
# (butcfc_*) facts into the real previous/ and current/ dirs and assert on those,
# the same precedent the burx-exchange multi cases use for the output dir. The
# directories are writable even though the path variables are not. The full
# cross-dispatch current/->previous/ promotion is covered by a chaining test
# (deferred). Pure local — no GCP, containers, network.

set -euo pipefail

######################################################################
# Helper

# Seed a fact file under a dir, mirroring the producer's trailing-newline
# format (printf '%s\n'), so the read path exercises newline stripping.
zbutcfc_seed() {
  local -r z_dir="${1}"
  local -r z_name="${2}"
  local -r z_value="${3}"
  printf '%s\n' "${z_value}" > "${z_dir}/${z_name}" || buto_fatal "seed failed: ${z_dir}/${z_name}"
}

# Seed a fact into the previous/ dir, creating the dir first. The five
# seed-into-previous cases share this mkdir+seed prelude; BURD_PREVIOUS_DIR is
# readonly and cannot be redirected, so the mkdir stays inline here rather than
# lifted to a one-time setup.
zbutcfc_seed_previous() {
  local -r z_name="${1}"
  local -r z_value="${2}"
  mkdir -p "${BURD_PREVIOUS_DIR}" || buto_fatal "mkdir previous failed"
  zbutcfc_seed "${BURD_PREVIOUS_DIR}" "${z_name}" "${z_value}"
}

######################################################################
# Test cases — direct assertions inside zbute_tcase subshell

butcfc_relay_forwards_tcase() {
  buto_trace "buf_relay: forwards a previous fact into current"

  zbutcfc_seed_previous "butcfc_fwd" "forwarded-value"

  buf_relay || buto_fatal "buf_relay failed"

  test -f "${BURD_OUTPUT_DIR}/butcfc_fwd" || buto_fatal "buf_relay did not forward butcfc_fwd"
  local -r z_got=$(<"${BURD_OUTPUT_DIR}/butcfc_fwd")
  test "${z_got}" = "forwarded-value" || buto_fatal "forwarded content mismatch: '${z_got}'"
}

butcfc_relay_preserves_current_tcase() {
  buto_trace "buf_relay: never clobbers a file already present in current"

  zbutcfc_seed_previous "butcfc_pres" "from-previous"
  zbutcfc_seed "${BURD_OUTPUT_DIR}"   "butcfc_pres" "from-current"

  buf_relay || buto_fatal "buf_relay failed"

  local -r z_got=$(<"${BURD_OUTPUT_DIR}/butcfc_pres")
  test "${z_got}" = "from-current" \
    || buto_fatal "buf_relay clobbered an existing current file: '${z_got}'"
}

butcfc_relay_idempotent_tcase() {
  buto_trace "buf_relay: a second call is a no-op no-clobber and still succeeds"

  zbutcfc_seed_previous "butcfc_idem" "v1"

  buf_relay || buto_fatal "buf_relay first call failed"
  buf_relay || buto_fatal "buf_relay second call failed"

  local -r z_got=$(<"${BURD_OUTPUT_DIR}/butcfc_idem")
  test "${z_got}" = "v1" || buto_fatal "idempotent relay altered content: '${z_got}'"
}

butcfc_read_fact_tcase() {
  buto_trace "buf_read_fact_capture: emits the bare value (newline stripped) from previous"

  zbutcfc_seed_previous "butcfc_greeting" "hello world"

  local z_value
  z_value=$(buf_read_fact_capture "butcfc_greeting") || buto_fatal "buf_read_fact_capture failed on present fact"
  test "${z_value}" = "hello world" \
    || buto_fatal "buf_read_fact_capture returned '${z_value}' expected 'hello world'"
}

butcfc_read_fact_absent_tcase() {
  buto_trace "buf_read_fact_capture: fails hard when the named fact is absent"

  local -r z_stderr="${BUT_TEMP_DIR}/read_absent_stderr.txt"

  local z_status=0
  buf_read_fact_capture "butcfc_definitely_absent_fact" 2>"${z_stderr}" || z_status=$?
  test "${z_status}" -ne 0 \
    || buto_fatal "buf_read_fact_capture should fail on an absent fact"
}

butcfc_elect_express_tcase() {
  buto_trace "buf_elect_fact_capture: a non-empty express value wins; the chained fact is not read"

  # No previous fact seeded — if elect read the (absent) fact it would fail.
  local z_value
  z_value=$(buf_elect_fact_capture "express-wins" "butcfc_definitely_absent_fact") \
    || buto_fatal "buf_elect_fact_capture failed with a non-empty express value"
  test "${z_value}" = "express-wins" \
    || buto_fatal "buf_elect_fact_capture returned '${z_value}' expected 'express-wins'"
}

butcfc_elect_after_relay_tcase() {
  buto_trace "buf_elect_fact_capture: relay-then-read — the elect still reads previous/ after buf_relay, and the baton sits forwarded in current/"

  zbutcfc_seed_previous "butcfc_baton" "baton-value"

  buf_relay || buto_fatal "buf_relay failed"

  local z_value
  z_value=$(buf_elect_fact_capture "" "butcfc_baton") \
    || buto_fatal "buf_elect_fact_capture failed after a relay"
  test "${z_value}" = "baton-value" \
    || buto_fatal "elect after relay returned '${z_value}' expected 'baton-value'"

  # The relay forwarded the baton into current/, ready for the next promotion.
  test -f "${BURD_OUTPUT_DIR}/butcfc_baton" \
    || buto_fatal "relay left no forwarded copy in current/"
  local -r z_fwd=$(<"${BURD_OUTPUT_DIR}/butcfc_baton")
  test "${z_fwd}" = "baton-value" || buto_fatal "forwarded baton mismatch: '${z_fwd}'"
}

butcfc_chain_survives_consumption_tcase() {
  buto_trace "consumption is non-destructive: reads delete nothing — previous/ and the relayed current/ copy both survive repeated reads"

  zbutcfc_seed_previous "butcfc_survive" "immortal"

  buf_relay || buto_fatal "buf_relay failed"

  local z_value
  z_value=$(buf_read_fact_capture "butcfc_survive") || buto_fatal "first read failed"
  test "${z_value}" = "immortal" || buto_fatal "first read returned '${z_value}'"

  # A second read succeeds identically — the first read consumed nothing.
  z_value=$(buf_read_fact_capture "butcfc_survive") || buto_fatal "second read failed"
  test "${z_value}" = "immortal" || buto_fatal "second read returned '${z_value}'"

  # Both generations still hold the fact: the previous/ source and the
  # relayed current/ copy that outlives this dispatch.
  test -f "${BURD_PREVIOUS_DIR}/butcfc_survive" \
    || buto_fatal "previous/ fact vanished under consumption"
  local -r z_fwd=$(<"${BURD_OUTPUT_DIR}/butcfc_survive")
  test "${z_fwd}" = "immortal" || buto_fatal "relayed current/ copy mismatch: '${z_fwd}'"
}

butcfc_elect_chain_tcase() {
  buto_trace "buf_elect_fact_capture: an empty express value falls back to the chained fact"

  zbutcfc_seed_previous "butcfc_chained" "from-chain"

  local z_value
  z_value=$(buf_elect_fact_capture "" "butcfc_chained") \
    || buto_fatal "buf_elect_fact_capture failed falling back to a present chained fact"
  test "${z_value}" = "from-chain" \
    || buto_fatal "buf_elect_fact_capture returned '${z_value}' expected 'from-chain'"

  # Empty express AND absent fact is the broken-chain failure path.
  local z_status=0
  buf_elect_fact_capture "" "butcfc_definitely_absent_fact" 2>/dev/null || z_status=$?
  test "${z_status}" -ne 0 \
    || buto_fatal "buf_elect_fact_capture should fail when express is empty and the fact is absent"
}

# eof
