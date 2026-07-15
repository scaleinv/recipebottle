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
# BUTCLC - Link display test cases for BUK self-test
#
# Exercises buh_link: OSC-8 hyperlink output and
# BURD_NO_HYPERLINKS fallback.  Pure local — no GCP, no containers.

set -euo pipefail

######################################################################
# Helpers

zbutclc_link_osc8() {
  buh_link "A " "hallmark" "https://example.com#hallmark" " is a named artifact."
}

zbutclc_link_fallback() {
  export BURD_NO_HYPERLINKS=1
  buh_link "A " "hallmark" "https://example.com#hallmark" " is a named artifact."
}

zbutclc_link_variants() {
  buh_link "" "click here" "https://example.com" " for details"
  buh_link "See " "docs" "https://example.com/docs" ""
  buh_link "A " "vessel" "https://example.com#vessel" " is a container image."
}

######################################################################
# Test cases

butclc_link_osc8_tcase() {
  buto_trace "buh_link: OSC-8 hyperlink present in output"
  zbuto_invoke zbutclc_link_osc8
  buto_fatal_on_error "${ZBUTO_STATUS}" "buh_link failed" "STDERR: ${ZBUTO_STDERR}"
  local z_osc_marker
  z_osc_marker=$(printf '\033]8;;')
  case "${ZBUTO_STDERR}" in
    *"${z_osc_marker}"*) ;;
    *) buto_fatal "OSC-8 sequence not found in output" "Got: ${ZBUTO_STDERR}" ;;
  esac
}

butclc_link_fallback_tcase() {
  buto_trace "buh_link: BURD_NO_HYPERLINKS falls back to angle-bracket URL"
  zbuto_invoke zbutclc_link_fallback
  buto_fatal_on_error "${ZBUTO_STATUS}" "buh_link fallback failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"<https://example.com#hallmark>"*) ;;
    *) buto_fatal "Fallback URL not found in output" "Got: ${ZBUTO_STDERR}" ;;
  esac
  local z_osc_marker
  z_osc_marker=$(printf '\033]8;;')
  case "${ZBUTO_STDERR}" in
    *"${z_osc_marker}"*) buto_fatal "OSC-8 should not appear in fallback mode" ;;
    *) ;;
  esac
}

butclc_link_variants_tcase() {
  buto_trace "buh_link variants succeed with correct arg counts"
  buto_unit_expect_ok zbutclc_link_variants
}

# eof
