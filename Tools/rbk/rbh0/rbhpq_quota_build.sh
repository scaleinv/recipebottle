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
# Recipe Bottle Handbook Payor - Quota build ceremony function

set -euo pipefail

test -z "${ZRBHPQ_SOURCED:-}" || return 0
ZRBHPQ_SOURCED=1

rbhp_quota_build() {
  zrbhp_sentinel

  buc_doc_brief "Display the Cloud Build capacity review procedure to verify machine type and quota settings"
  buc_doc_shown || return 0

  buh_section  "Cloud Build Concurrent Build Capacity"
  buh_line     "Review your build capacity settings to ensure sufficient concurrent build execution."
  buh_line     "Recipe Bottle uses a private worker pool — quota is tracked per private pool host project."
  buh_e
  buh_line     "   Private pool machine types vs concurrency at 10-CPU quota:"
  buyy_cmd_yawp "(2 vCPU)   → 5 concurrent builds"; local -r z_cmd_concur_2vcpu="${z_buym_yelp}"
  buh_line     "     e2-standard-2  ${z_cmd_concur_2vcpu}"
  buyy_cmd_yawp "(8 vCPU)   → 1 concurrent build"; local -r z_cmd_concur_8vcpu="${z_buym_yelp}"
  buh_line     "     e2-standard-8  ${z_cmd_concur_8vcpu}"
  buyy_cmd_yawp "(32 vCPU)  → needs 32+ CPU quota"; local -r z_cmd_concur_32vcpu="${z_buym_yelp}"
  buh_line     "     e2-standard-32 ${z_cmd_concur_32vcpu}"
  buh_e
  buh_section  "Key:"
  buyy_ui_yawp "precise words you see on the web page."; local -r z_ui_key_magenta="${z_buym_yelp}"
  buh_line     "   Magenta text refers to ${z_ui_key_magenta}"
  buyy_cmd_yawp "something you might copy from here."; local -r z_cmd_key_cyan="${z_buym_yelp}"
  buh_line     "   Cyan text is ${z_cmd_key_cyan}"
  buyy_href_yawp "https://example.com/" "EXAMPLE DOT COM"; local -r z_href_key_example="${z_buym_yelp}"
  buh_line     "   Clickable links look like ${z_href_key_example} (often, ${ZRBHP_CLICK_MOD} + mouse click)"
  buh_e
  buh_section  "1. Current Regime Configuration:"
  buyy_cmd_yawp "${RBDC_DEPOT_PROJECT_ID}"; local -r z_cmd_regime_depot_project="${z_buym_yelp}"
  buh_line     "   RBDC_DEPOT_PROJECT_ID:          ${z_cmd_regime_depot_project}"
  buyy_cmd_yawp "${RBRD_GCP_REGION}"; local -r z_cmd_regime_gcp_region="${z_buym_yelp}"
  buh_line     "   RBRD_GCP_REGION:                ${z_cmd_regime_gcp_region}"
  buyy_cmd_yawp "${RBRD_GCB_MACHINE_TYPE}"; local -r z_cmd_regime_machine_type="${z_buym_yelp}"
  buh_line     "   RBRD_GCB_MACHINE_TYPE:          ${z_cmd_regime_machine_type}"
  buyy_cmd_yawp "${RBDC_GCB_POOL_STEM}"; local -r z_cmd_regime_pool_stem="${z_buym_yelp}"
  buh_line     "   RBDC_GCB_POOL_STEM:             ${z_cmd_regime_pool_stem}"
  buyy_cmd_yawp "${RBRR_GCB_MIN_CONCURRENT_BUILDS}"; local -r z_cmd_regime_min_concurrent="${z_buym_yelp}"
  buh_line     "   RBRR_GCB_MIN_CONCURRENT_BUILDS: ${z_cmd_regime_min_concurrent}"
  buh_e
  buh_line     "   The build preflight gate checks quota automatically before each build."
  buh_line     "   It computes: quota_vCPUs / machine_vCPUs >= RBRR_GCB_MIN_CONCURRENT_BUILDS"
  buh_e
  buh_section  "2. Check CPU Quota:"
  buh_line     "   Private pool quota is tracked under the depot project."
  buh_e
  buyy_href_yawp "https://console.cloud.google.com/iam-admin/quotas?project=${RBDC_DEPOT_PROJECT_ID}" "Quotas and System Limits (opens to depot project)"; local -r z_href_check_quotas="${z_buym_yelp}"
  buh_line     "   Go to: ${z_href_check_quotas}"
  buyy_ui_yawp "${RBDC_DEPOT_PROJECT_ID}"; local -r z_ui_check_project="${z_buym_yelp}"
  buh_line     "   1. Verify project ${z_ui_check_project} is selected in the project picker"
  buyy_ui_yawp "Enter property name or value"; local -r z_ui_check_filter_bar="${z_buym_yelp}"
  buh_line     "   2. In the ${z_ui_check_filter_bar} filter bar, type:"
  buyy_cmd_yawp "concurrent_private"; local -r z_cmd_check_filter_text="${z_buym_yelp}"
  buh_line     "      ${z_cmd_check_filter_text}"
  buyy_ui_yawp "cloudbuild.googleapis.com/concurrent_private_pool_build_cpus"; local -r z_ui_check_autocomplete="${z_buym_yelp}"
  buh_line     "   3. Select ${z_ui_check_autocomplete} from the autocomplete"
  buh_line     "   4. Multiple rows appear. Look for the row with Type column showing"
  buyy_ui_yawp "Quota"; local -r z_ui_check_type_quota="${z_buym_yelp}"
  buh_line     "      ${z_ui_check_type_quota} (not System limit) and your region in the Dimensions column"
  buh_line     "   5. Note the quota value and current usage percentage"
  buh_line     "      If usage is near 100% with one build, the machine type is too large for the quota"
  buh_e
  buh_section  "3. Request a Quota Increase (if needed):"
  buyy_ui_yawp "Quota"; local -r z_ui_request_row_quota="${z_buym_yelp}"
  buh_line     "   On the ${z_ui_request_row_quota} row identified above:"
  buyy_ui_yawp "⋮"; local -r z_ui_request_menu_dots="${z_buym_yelp}"
  buh_line     "   1. Click the three-dot menu ${z_ui_request_menu_dots} at the right end of the row"
  buyy_ui_yawp "Edit quota"; local -r z_ui_request_edit_quota="${z_buym_yelp}"
  buh_line     "   2. Select ${z_ui_request_edit_quota}"
  buyy_ui_yawp "New value"; local -r z_ui_request_new_value="${z_buym_yelp}"
  buh_line     "   3. In the side panel, enter the new value in the ${z_ui_request_new_value} field"
  buh_line     "      Recommended: 10 (allows 5 concurrent e2-standard-2 builds across both pools)"
  buyy_ui_yawp "Request description"; local -r z_ui_request_description="${z_buym_yelp}"
  buh_line     "   4. A ${z_ui_request_description} field appears. Enter:"
  buyy_cmd_yawp "Need parallel builds on private worker pool for CI/CD pipeline testing."; local -r z_cmd_request_description_text="${z_buym_yelp}"
  buh_line     "      ${z_cmd_request_description_text}"
  buyy_ui_yawp "Next"; local -r z_ui_request_next="${z_buym_yelp}"
  buh_line     "   5. Click ${z_ui_request_next}"
  buh_line     "   6. Step 2/2 shows contact details (pre-filled from your Google account)"
  buyy_ui_yawp "Submit request"; local -r z_ui_request_submit="${z_buym_yelp}"
  buh_line     "   7. Click ${z_ui_request_submit}"
  buh_line     "      Increases are typically approved within minutes."
  buh_e
  buh_section  "4. Confirm Quota Increase:"
  buh_line     "   After approval, quotas can take up to 15 minutes to propagate."
  buyy_href_yawp "https://console.cloud.google.com/iam-admin/quotas?project=${RBDC_DEPOT_PROJECT_ID}" "Quotas and System Limits (opens to depot project)"; local -r z_href_confirm_quotas="${z_buym_yelp}"
  buh_line     "   Return to: ${z_href_confirm_quotas}"
  buyy_ui_yawp "concurrent_private"; local -r z_ui_confirm_filter_text="${z_buym_yelp}"
  buh_line     "   Filter for ${z_ui_confirm_filter_text} again and verify the new value"
  buh_line     "   Verify: quota / vCPUs per machine type >= RBRR_GCB_MIN_CONCURRENT_BUILDS"
  buyy_cmd_yawp "${RBRR_GCB_MIN_CONCURRENT_BUILDS} concurrent builds"; local -r z_cmd_confirm_target="${z_buym_yelp}"
  buh_line     "     Current target: ${z_cmd_confirm_target}"
  buh_e

}

# eof
