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
# Recipe Bottle Handbook Payor - Establish ceremony function

set -euo pipefail

test -z "${ZRBHPE_SOURCED:-}" || return 0
ZRBHPE_SOURCED=1

rbhp_establish() {
  zrbhp_sentinel

  buc_doc_brief "Display the manual Payor Establishment procedure for OAuth authentication"
  buc_doc_shown || return 0

  # Yawped once and reused at every site below; readonly capture survives later
  # buyy_cmd_yawp calls overwriting the shared z_buym_yelp scratch.
  buyy_cmd_yawp "${RBGC_PAYOR_APP_NAME}"; local -r z_cmd_app_name="${z_buym_yelp}"

  buh_section  "Manual Payor OAuth Establishment Procedure"
  buh_line     "${RBGC_PAYOR_APP_NAME} now uses OAuth 2.0 for individual developer accounts."
  buh_line     "This resolves project creation limitations for personal Google accounts."
  buh_e
  buh_section  "Key:"
  buyy_ui_yawp "precise words you see on the web page."; local -r z_ui_key_words="${z_buym_yelp}"
  buh_line     "   Magenta text refers to ${z_ui_key_words}"
  buyy_cmd_yawp "something you might copy from here."; local -r z_cmd_key_copy="${z_buym_yelp}"
  buh_line     "   Cyan text is ${z_cmd_key_copy}"
  buyy_href_yawp "https://example.com/" "EXAMPLE DOT COM"; local -r z_href_key_example="${z_buym_yelp}"
  buh_line     "   Clickable links look like ${z_href_key_example} (often, ${ZRBHP_CLICK_MOD} + mouse click)"
  buh_e
  buh_section  "1. Confirm Payor Regime:"
  buyy_cmd_yawp "${ZRBHP_RBRP_FILE}"; local -r z_cmd_rbrp_file="${z_buym_yelp}"
  buh_line     "   File: ${z_cmd_rbrp_file}"
  buyy_cmd_yawp "${RBRP_PAYOR_PROJECT_ID}"; local -r z_cmd_payor_project_id="${z_buym_yelp}"
  buh_line     "   RBRP_PAYOR_PROJECT_ID: ${z_cmd_payor_project_id}"
  buh_line     "   (You will discover RBRP_BILLING_ACCOUNT_ID later in step 5)"
  buh_e
  buh_line     "   First time setup? Set a timestamped project ID with:"
  buh_code     "   sed -i '' 's/^RBRP_PAYOR_PROJECT_ID=.*/RBRP_PAYOR_PROJECT_ID=${RBGC_GLOBAL_PREFIX}-${RBGC_GLOBAL_TYPE_PAYOR}-$(date "${RBGC_GLOBAL_TIMESTAMP_FORMAT}")/' ${ZRBHP_RBRP_FILE}"
  buh_e
  buh_section  "2. Check if Project Already Exists:"
  buh_line     "   Before creating a new project, verify the configured ID is not already in use:"
  buyy_href_yawp "https://console.cloud.google.com/cloud-resource-manager" "Google Cloud Project List"; local -r z_href_project_list="${z_buym_yelp}"
  buh_line     "   1. Check existing projects: ${z_href_project_list}"
  buyy_ui_yawp "${RBRP_PAYOR_PROJECT_ID}"; local -r z_ui_payor_project_id="${z_buym_yelp}"
  buh_line     "   2. Look for a project with ID ${z_ui_payor_project_id}"
  buh_line     "      - Hover over project IDs to verify the full ID matches your configured value"
  buyy_cmd_yawp "find the project"; local -r z_cmd_find_project="${z_buym_yelp}"
  buyy_ui_yawp "${ZRBHP_RBRP_FILE_BASENAME}"; local -r z_ui_rbrp_file_basename="${z_buym_yelp}"
  buh_line     "   3. If you ${z_cmd_find_project} with matching ID, it already exists - edit ${z_ui_rbrp_file_basename}"
  buh_line     "      and re-run this procedure"
  buh_line     "   4. If you don't find it, proceed to step 3 to create it"
  buh_e
  buh_section  "3. Create Payor Project:"
  buyy_href_yawp "https://console.cloud.google.com/projectcreate" "Google Cloud Project Create"; local -r z_href_project_create="${z_buym_yelp}"
  buh_line     "   1. Open browser to: ${z_href_project_create}"
  buh_line     "   2. Ensure signed in with intended Google account (check top-right avatar)"
  buh_line     "   3. Configure new project:"
  buh_line     "      - Project name: ${z_cmd_app_name}"
  buh_line     "      - Project ID: Google will auto-generate a value"
  buyy_ui_yawp "No organization"; local -r z_ui_no_organization="${z_buym_yelp}"
  buh_line     "      - Location: ${z_ui_no_organization} (the choice this guide describes; organization affiliation also works but is an advanced path)"
  buyy_ui_yawp "Edit"; local -r z_ui_edit="${z_buym_yelp}"
  buh_line     "   4. Click ${z_ui_edit} next to the auto-generated Project ID"
  buyy_cmd_yawp "${RBRP_PAYOR_PROJECT_ID}"; local -r z_cmd_payor_project_id_edit="${z_buym_yelp}"
  buh_line     "   5. Replace it with: ${z_cmd_payor_project_id_edit}"
  buyy_ui_yawp "CREATE"; local -r z_ui_create_project="${z_buym_yelp}"
  buh_line     "   6. Click ${z_ui_create_project}"
  buyy_ui_yawp "Creating project..."; local -r z_ui_creating_project="${z_buym_yelp}"
  buh_line     "   7. Wait for ${z_ui_creating_project} notification to complete"
  buh_e
  buh_section  "4. Verify Project Creation:"
  buh_line     "   Verify that your rbrp.env configuration matches the created project:"
  buyy_href_yawp "https://console.cloud.google.com/apis/dashboard?project=${RBRP_PAYOR_PROJECT_ID}" "Google Cloud APIs Dashboard"; local -r z_href_apis_dashboard_verify="${z_buym_yelp}"
  buh_line     "   1. Test this link: ${z_href_apis_dashboard_verify}"
  buyy_ui_yawp "Project Picker"; local -r z_ui_project_picker="${z_buym_yelp}"
  buh_line     "   2. The page is correct when the ${z_ui_project_picker} button reads ${z_cmd_app_name}"
  buyy_ui_yawp "You need additional access"; local -r z_ui_need_additional_access="${z_buym_yelp}"
  buh_line     "   3. If you see ${z_ui_need_additional_access}, wait a few minutes and refresh the page"
  buyy_href_yawp "https://cloud.google.com/iam/docs/access-change-propagation" "Access Change Propagation"; local -r z_href_access_propagation="${z_buym_yelp}"
  buh_line     "      GCP IAM changes are eventually consistent: ${z_href_access_propagation}"
  buh_e
  buh_section  "5. Configure Billing Account:"
  buyy_href_yawp "https://console.cloud.google.com/billing" "Google Cloud Billing"; local -r z_href_billing="${z_buym_yelp}"
  buh_line     "   1. Go to: ${z_href_billing}"
  buh_line     "      If no billing accounts exist:"
  buyy_ui_yawp "Create account"; local -r z_ui_create_account="${z_buym_yelp}"
  buh_line     "          a. Click ${z_ui_create_account}"
  buh_line     "          b. Configure payment method and submit"
  buyy_ui_yawp "Account ID"; local -r z_ui_account_id_new="${z_buym_yelp}"
  buh_line     "          c. Copy new ${z_ui_account_id_new} from table"
  buh_line     "      else if single Open account exists:"
  buyy_ui_yawp "Account ID"; local -r z_ui_account_id_single="${z_buym_yelp}"
  buh_line     "          a. Copy the ${z_ui_account_id_single} value"
  buh_line     "      else if multiple Open accounts exist:"
  buh_line     "          a. Choose account for Recipe Bottle funding"
  buyy_ui_yawp "Account ID"; local -r z_ui_account_id_chosen="${z_buym_yelp}"
  buh_line     "          b. Copy chosen ${z_ui_account_id_chosen} value"
  buyy_href_yawp "https://console.cloud.google.com/billing/projects" "Google Cloud Billing Projects"; local -r z_href_billing_projects="${z_buym_yelp}"
  buh_line     "   2. Go to: ${z_href_billing_projects}"
  buyy_ui_yawp "${ZRBHP_RBRP_FILE}"; local -r z_ui_rbrp_file_save="${z_buym_yelp}"
  buh_line     "   3. Save the billing account ID to your ${z_ui_rbrp_file_save}"
  buyy_cmd_yawp "RBRP_BILLING_ACCOUNT_ID="; local -r z_cmd_billing_account_id="${z_buym_yelp}"
  buyy_ui_yawp "Value from Account ID column"; local -r z_ui_account_id_value="${z_buym_yelp}"
  buh_line     "      Record as: ${z_cmd_billing_account_id} # ${z_ui_account_id_value}"
  buh_line     "   4. Find project row with ID matching your payor project (not name) and get the Account ID value"
  buyy_ui_yawp "${ZRBHP_RBRP_FILE}"; local -r z_ui_rbrp_file_update="${z_buym_yelp}"
  buh_line     "   5. Update ${z_ui_rbrp_file_update} and re-display this procedure."
  buh_e
  buh_section  "6. Configure OAuth Consent Screen:"
  buyy_href_yawp "https://console.cloud.google.com/apis/credentials/consent?project=${RBRP_PAYOR_PROJECT_ID}" "OAuth consent screen"; local -r z_href_oauth_consent="${z_buym_yelp}"
  buh_line     "   Go to: ${z_href_oauth_consent}"
  buyy_ui_yawp "Google Auth Platform not configured yet"; local -r z_ui_auth_not_configured="${z_buym_yelp}"
  buh_line     "   1. The console displays ${z_ui_auth_not_configured}"
  buyy_ui_yawp "Get started"; local -r z_ui_get_started="${z_buym_yelp}"
  buh_line     "   2. Click ${z_ui_get_started}"
  buh_line     "   3. Complete the Project Configuration wizard:"
  buh_line     "      Step 1 - App Information:"
  buh_line     "        - App name: ${z_cmd_app_name}"
  buh_line     "        - User support email: (your email)"
  buyy_ui_yawp "Next"; local -r z_ui_next_step1="${z_buym_yelp}"
  buh_line     "        - Click ${z_ui_next_step1}"
  buh_line     "      Step 2 - Audience:"
  buyy_ui_yawp "Internal"; local -r z_ui_internal="${z_buym_yelp}"
  buh_line     "        - Select ${z_ui_internal} (the manor-setup finisher gates on it;"
  buh_line     "          your GCP organization makes it available - External leaves"
  buh_line     "          the test-user gate and 7-day token expiry in force)"
  buyy_ui_yawp "Next"; local -r z_ui_next_step2="${z_buym_yelp}"
  buh_line     "        - Click ${z_ui_next_step2}"
  buh_line     "      Step 3 - Contact Information:"
  buh_line     "        - Email addresses: (your email), press Enter"
  buyy_ui_yawp "Next"; local -r z_ui_next_step3="${z_buym_yelp}"
  buh_line     "        - Click ${z_ui_next_step3}"
  buh_line     "      Step 4 - Finish:"
  buyy_ui_yawp "I agree to the Google API Services: User Data Policy"; local -r z_ui_agree_policy="${z_buym_yelp}"
  buh_line     "        - Read the linked terms, then (if you accept) check ${z_ui_agree_policy}"
  buyy_ui_yawp "Continue"; local -r z_ui_continue="${z_buym_yelp}"
  buh_line     "        - Click ${z_ui_continue}"
  buyy_ui_yawp "Create"; local -r z_ui_create_consent="${z_buym_yelp}"
  buh_line     "        - Click ${z_ui_create_consent}"
  buh_e
  buh_section  "7. Create OAuth 2.0 Client ID:"
  buyy_href_yawp "https://console.cloud.google.com/apis/credentials?project=${RBRP_PAYOR_PROJECT_ID}" "Credentials"; local -r z_href_credentials="${z_buym_yelp}"
  buh_line     "   Go to: ${z_href_credentials}"
  buyy_ui_yawp "+ Create credentials"; local -r z_ui_create_credentials="${z_buym_yelp}"
  buh_line     "   1. From top bar, click ${z_ui_create_credentials}"
  buyy_ui_yawp "OAuth client ID"; local -r z_ui_oauth_client_id="${z_buym_yelp}"
  buh_line     "   2. Select ${z_ui_oauth_client_id}"
  buyy_ui_yawp "Desktop app"; local -r z_ui_desktop_app="${z_buym_yelp}"
  buh_line     "   3. Application type: ${z_ui_desktop_app}"
  buh_line     "   4. Name: ${z_cmd_app_name}"
  buyy_ui_yawp "Create"; local -r z_ui_create_client="${z_buym_yelp}"
  buh_line     "   5. Click ${z_ui_create_client}"
  buyy_ui_yawp "OAuth client created"; local -r z_ui_oauth_client_created="${z_buym_yelp}"
  buh_line     "   6. Popup titled ${z_ui_oauth_client_created} displays client ID and secret"
  buyy_ui_yawp "Download JSON"; local -r z_ui_download_json="${z_buym_yelp}"
  buh_line     "   7. Click ${z_ui_download_json}"
  buyy_ui_yawp "OK"; local -r z_ui_ok="${z_buym_yelp}"
  buyy_ui_yawp "client_secret_[id].apps.googleusercontent.com.json"; local -r z_ui_client_secret_filename="${z_buym_yelp}"
  buh_line     "   8. Click ${z_ui_ok} ; browser downloads ${z_ui_client_secret_filename}"
  buyy_warn_yawp "CRITICAL: Save securely - contains client secret"; local -r z_warn_save_securely="${z_buym_yelp}"
  buh_line     "      ${z_warn_save_securely}"
  buh_line     "   9. Move the download to its durable home - the client_secrets/"
  buh_line     "      subdirectory of your secrets directory (RBRR_SECRETS_DIR in"
  buh_line     "      rbrr.env). Install and every future re-install read it there."
  buh_e
  buh_section  "8. Install OAuth Credentials:"
  buh_line     "   Run:"
  buh_tt       "      " "${RBZ_PAYOR_INSTALL}" "" " «secrets-dir»/client_secrets/client_secret_*.json"
  buh_line     "   The glob assumes one client_secret_*.json in the durable home."
  buh_line     "   If more than one exists (e.g. after rotating a compromised"
  buh_line     "   secret), pass its exact path instead."
  buh_line     "   This will guide you through OAuth authorization and complete the setup."
  buh_line     "   Install then points you at the manor-setup finisher, which enables"
  buh_line     "   the payor project's APIs and links billing automatically."

}

# eof
