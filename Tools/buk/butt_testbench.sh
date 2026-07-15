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
# BUTT Testbench - BUK test framework self-test
#
# Exercises the BUK test framework (bute/butr/butd/buto) with kick-tires
# and BURE tweak cases.  Pure local — no GCP, no containers, no network.

set -euo pipefail

BUTT_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
BUTT_BUTS_DIR="${BUTT_SCRIPT_DIR}/buts"

# Source dependencies
source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/burd_regime.sh"
source "${BURD_BUK_DIR}/buv_validation.sh"
source "${BURD_BUK_DIR}/bute_engine.sh"
source "${BURD_BUK_DIR}/butr_registry.sh"
source "${BURD_BUK_DIR}/butd_dispatch.sh"
source "${BURD_BUK_DIR}/bure_regime.sh"
source "${BURD_BUK_DIR}/buf_fact.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"
source "${BURD_BUK_DIR}/buh_handbook.sh"

# Source test case files
source "${BUTT_BUTS_DIR}/butckk_kick.sh"
source "${BUTT_BUTS_DIR}/butcbd_band.sh"
source "${BUTT_BUTS_DIR}/butcbe_bure.sh"
source "${BUTT_BUTS_DIR}/butcbx_burx.sh"
source "${BUTT_BUTS_DIR}/butcfc_facts.sh"
source "${BUTT_BUTS_DIR}/butclc_links.sh"
source "${BUTT_BUTS_DIR}/butcym_yelp.sh"

buc_context "${0##*/}"
zbuv_kindle
zburd_kindle

######################################################################
# Registration

butt_kindle() {
  butr_kindle

  # All fixtures are pure local
  butr_suite_enroll "self-test"

  # kick-tires fixture (2 cases)
  butr_fixture_enroll "kick-tires" "" "zbutt_noop_baste"
  butr_case_enroll "kick-tires" butckk_false_tcase
  butr_case_enroll "kick-tires" butckk_true_tcase

  # band-survival fixture (6 cases)
  butr_fixture_enroll "band-survival" "" "zbutt_noop_baste"
  butr_case_enroll "band-survival" butcbd_die_in_band_tcase
  butr_case_enroll "band-survival" butcbd_die_plain_tcase
  butr_case_enroll "band-survival" butcbd_die_out_of_band_tcase
  butr_case_enroll "band-survival" butcbd_reject_direct_tcase
  butr_case_enroll "band-survival" butcbd_reject_out_of_band_tcase
  butr_case_enroll "band-survival" butcbd_survival_tcase

  # bure-tweak fixture (9 cases)
  butr_fixture_enroll "bure-tweak" "" "zbutt_noop_baste"
  butr_case_enroll "bure-tweak" butcbe_tweak_empty_tcase
  butr_case_enroll "bure-tweak" butcbe_tweak_both_set_tcase
  butr_case_enroll "bure-tweak" butcbe_tweak_name_only_tcase
  butr_case_enroll "bure-tweak" butcbe_tweak_value_only_tcase
  butr_case_enroll "bure-tweak" butcbe_tweak_name_too_long_tcase
  butr_case_enroll "bure-tweak" butcbe_tweak_value_too_long_tcase
  butr_case_enroll "bure-tweak" butcbe_label_valid_tcase
  butr_case_enroll "bure-tweak" butcbe_label_too_long_tcase
  butr_case_enroll "bure-tweak" butcbe_unexpected_var_tcase

  # burx-exchange fixture (7 cases)
  butr_fixture_enroll "burx-exchange" "" "zbutt_noop_baste"
  butr_case_enroll "burx-exchange" butcbx_burx_dual_write_tcase
  butr_case_enroll "burx-exchange" butcbx_burx_fields_tcase
  butr_case_enroll "burx-exchange" butcbx_burx_preexist_tcase
  butr_case_enroll "burx-exchange" butcbx_burx_timestamp_format_tcase
  butr_case_enroll "burx-exchange" butcbx_multi_dual_write_tcase
  butr_case_enroll "burx-exchange" butcbx_multi_preexist_tcase
  butr_case_enroll "burx-exchange" butcbx_multi_empty_content_tcase

  # fact-chaining fixture (9 cases)
  butr_fixture_enroll "fact-chaining" "" "zbutt_noop_baste"
  butr_case_enroll "fact-chaining" butcfc_relay_forwards_tcase
  butr_case_enroll "fact-chaining" butcfc_relay_preserves_current_tcase
  butr_case_enroll "fact-chaining" butcfc_relay_idempotent_tcase
  butr_case_enroll "fact-chaining" butcfc_read_fact_tcase
  butr_case_enroll "fact-chaining" butcfc_read_fact_absent_tcase
  butr_case_enroll "fact-chaining" butcfc_elect_express_tcase
  butr_case_enroll "fact-chaining" butcfc_elect_after_relay_tcase
  butr_case_enroll "fact-chaining" butcfc_chain_survives_consumption_tcase
  butr_case_enroll "fact-chaining" butcfc_elect_chain_tcase

  # buh-link fixture (3 cases)
  butr_fixture_enroll "buh-link" "" "zbutt_noop_baste"
  butr_case_enroll "buh-link" butclc_link_osc8_tcase
  butr_case_enroll "buh-link" butclc_link_fallback_tcase
  butr_case_enroll "buh-link" butclc_link_variants_tcase

  # buym-yelp fixture (15 cases)
  butr_fixture_enroll "buym-yelp" "" "zbutt_noop_baste"
  butr_case_enroll "buym-yelp" butcym_cmd_resolve_tcase
  butr_case_enroll "buym-yelp" butcym_link_osc8_tcase
  butr_case_enroll "buym-yelp" butcym_link_fallback_tcase
  butr_case_enroll "buym-yelp" butcym_ambient_preservation_tcase
  butr_case_enroll "buym-yelp" butcym_fast_path_tcase
  butr_case_enroll "buym-yelp" butcym_multi_markers_tcase
  butr_case_enroll "buym-yelp" butcym_plain_mode_tcase
  butr_case_enroll "buym-yelp" butcym_gray_color_tcase
  butr_case_enroll "buym-yelp" butcym_gray_plain_tcase
  butr_case_enroll "buym-yelp" butcym_strip_cmd_tcase
  butr_case_enroll "buym-yelp" butcym_strip_link_tcase
  butr_case_enroll "buym-yelp" butcym_strip_href_tcase
  butr_case_enroll "buym-yelp" butcym_strip_fast_path_tcase
  butr_case_enroll "buym-yelp" butcym_cold_die_tcase
  butr_case_enroll "buym-yelp" butcym_cold_die_plain_tcase
}

zbutt_noop_baste() {
  buto_trace "Baste (no-op)"
}

######################################################################
# Routing

butt_route() {
  local -r z_command="${1:-}"
  shift || true

  zburd_sentinel

  butt_kindle

  export ZBUTE_ROOT_TEMP_DIR="${BURD_TEMP_DIR}"
  export BUT_VERBOSE="${BUT_VERBOSE:-0}"

  case "${z_command}" in
    buw-st)
      butd_run_suite "self-test"
      ;;
    *)
      buc_die "Unknown command: ${z_command}"
      ;;
  esac
}

butt_main() {
  local -r z_command="${1:-}"
  shift || true
  test -n "${z_command}" || buc_die "No command specified"
  butt_route "${z_command}" "$@"
}

butt_main "$@"

# eof
