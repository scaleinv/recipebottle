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
# Recipe Bottle Handbook Payor - Entra federation setup guide function

set -euo pipefail

test -z "${ZRBHPF_SOURCED:-}" || return 0
ZRBHPF_SOURCED=1

rbhp_federation_entra() {
  zrbhp_sentinel

  buc_doc_brief "Display the Microsoft Entra federation setup procedure yielding the foedus core values"
  buc_doc_shown || return 0

  # Several UI words (Entra ID, Overview) are yawped once and reused across
  # sections below; the readonly captures survive later buyy_*_yawp calls
  # overwriting the shared z_buym_yelp scratch.
  buh_section  "Microsoft Entra Federation Setup Procedure"
  buh_line     "Walks the Entra console work that founds the IdP side of an interactive foedus:"
  buh_line     "one app registration whose values fill the vendor-agnostic core of rbrf.env."
  buh_line     "Everything here is Microsoft-side, human-only console work; no Google resource is"
  buh_line     "touched, and no secret is created anywhere — the registration stays a public client."
  buh_line     "A different OIDC vendor takes a sibling guide converging on the same core values."
  buh_e
  buh_section  "Key:"
  buyy_ui_yawp "precise words you see on the web page."; local -r z_ui_key_words="${z_buym_yelp}"
  buh_line     "   Magenta text refers to ${z_ui_key_words}"
  buyy_cmd_yawp "something you might copy from here."; local -r z_cmd_key_copy="${z_buym_yelp}"
  buh_line     "   Cyan text is ${z_cmd_key_copy}"
  buyy_href_yawp "https://example.com/" "EXAMPLE DOT COM"; local -r z_href_key_example="${z_buym_yelp}"
  buh_line     "   Clickable links look like ${z_href_key_example} (often, ${ZRBHP_CLICK_MOD} + mouse click)"
  buyy_cmd_yawp "«guillemets»"; local -r z_cmd_key_guillemet="${z_buym_yelp}"
  buh_line     "   Values in ${z_cmd_key_guillemet} are yours to substitute — never copy them literally"
  buh_e
  buh_section  "1. Obtain a Microsoft Entra Tenant:"
  buh_line     "   Skip to step 2 if you already administer a tenant."
  buh_line     "   A bare personal Microsoft account cannot register applications, and the"
  buh_line     "   M365 Developer Program requires a qualifying subscription."
  buh_line     "   The working solo path is a free Azure signup — card required, \$0 charge —"
  buh_line     "   which provisions a real default tenant (one-time, roughly 15 minutes):"
  buyy_href_yawp "https://azure.microsoft.com/free" "Azure Free Account Signup"; local -r z_href_azure_free="${z_buym_yelp}"
  buh_line     "   1. Sign up at: ${z_href_azure_free}"
  buh_line     "   2. Complete identity and payment verification"
  buh_line     "   3. The account's default directory is your tenant"
  buh_e
  buh_section  "2. Register the Application:"
  buyy_href_yawp "https://entra.microsoft.com" "Microsoft Entra Admin Center"; local -r z_href_entra_center="${z_buym_yelp}"
  buh_line     "   1. Open: ${z_href_entra_center} and sign in as the tenant administrator"
  buyy_ui_yawp "Entra ID"; local -r z_ui_entra_id="${z_buym_yelp}"
  buyy_ui_yawp "App registrations"; local -r z_ui_app_registrations="${z_buym_yelp}"
  buh_line     "   2. Browse to ${z_ui_entra_id} then ${z_ui_app_registrations}"
  buyy_ui_yawp "New registration"; local -r z_ui_new_registration="${z_buym_yelp}"
  buh_line     "   3. Click ${z_ui_new_registration}"
  buh_line     "   4. Configure the registration:"
  buyy_cmd_yawp "«your-app-name»"; local -r z_cmd_app_name="${z_buym_yelp}"
  buh_line     "      - Name: ${z_cmd_app_name} (display-only; changeable later)"
  buyy_ui_yawp "Supported account types"; local -r z_ui_account_types="${z_buym_yelp}"
  buyy_ui_yawp "Single tenant only"; local -r z_ui_single_tenant="${z_buym_yelp}"
  buh_line     "      - Under ${z_ui_account_types}, choose ${z_ui_single_tenant}"
  buh_line     "        (only users of your tenant may authenticate; older console text reads"
  buyy_ui_yawp "Accounts in this organizational directory only"; local -r z_ui_single_tenant_old="${z_buym_yelp}"
  buh_line     "        ${z_ui_single_tenant_old})"
  buyy_ui_yawp "Redirect URI"; local -r z_ui_redirect_uri="${z_buym_yelp}"
  buh_line     "      - Leave ${z_ui_redirect_uri} EMPTY — the device flow needs none, and this"
  buh_line     "        path never uses Google's browser-console sign-in (whose docs prescribe a"
  buh_line     "        redirect URI and client secret — deliberately not this registration's shape)"
  buyy_ui_yawp "Register"; local -r z_ui_register="${z_buym_yelp}"
  buh_line     "   5. Click ${z_ui_register}"
  buh_e
  buh_section  "3. Allow the Device Flow (public client):"
  buyy_ui_yawp "Manage"; local -r z_ui_manage="${z_buym_yelp}"
  buyy_ui_yawp "Authentication"; local -r z_ui_authentication="${z_buym_yelp}"
  buh_line     "   1. On the new registration's page, open ${z_ui_manage} then ${z_ui_authentication}"
  buyy_ui_yawp "Advanced settings"; local -r z_ui_advanced="${z_buym_yelp}"
  buyy_ui_yawp "Allow public client flows"; local -r z_ui_public_client="${z_buym_yelp}"
  buyy_ui_yawp "Yes"; local -r z_ui_yes="${z_buym_yelp}"
  buh_line     "   2. Under ${z_ui_advanced}, set ${z_ui_public_client} to ${z_ui_yes} (default is No)"
  buyy_ui_yawp "Save"; local -r z_ui_save_auth="${z_buym_yelp}"
  buh_line     "   3. Click ${z_ui_save_auth}"
  buh_line     "   This is the whole credential story: no client secret, no certificate, nothing"
  buh_line     "   to leak — each sitting is opened by a live human sign-in and nothing else."
  buh_e
  buh_section  "4. Record the Identity Values:"
  buyy_ui_yawp "Overview"; local -r z_ui_overview="${z_buym_yelp}"
  buh_line     "   From the registration's ${z_ui_overview} page, record two values:"
  buyy_ui_yawp "Application (client) ID"; local -r z_ui_client_id="${z_buym_yelp}"
  buh_line     "   1. ${z_ui_client_id} — becomes RBRF_IDP_CLIENT_ID below"
  buyy_ui_yawp "Directory (tenant) ID"; local -r z_ui_tenant_id="${z_buym_yelp}"
  buyy_cmd_yawp "«tenant-id»"; local -r z_cmd_tenant_id="${z_buym_yelp}"
  buh_line     "   2. ${z_ui_tenant_id} — the ${z_cmd_tenant_id} composing the three URLs below"
  buh_e
  buh_section  "5. Confirm the Issuer:"
  buh_line     "   Google matches the issuer string exactly, so read it from the tenant's own"
  buh_line     "   metadata rather than assuming its shape:"
  buyy_ui_yawp "Endpoints"; local -r z_ui_endpoints="${z_buym_yelp}"
  buh_line     "   1. From the registration's ${z_ui_overview} page, click ${z_ui_endpoints}"
  buyy_ui_yawp "OpenID Connect metadata document"; local -r z_ui_oidc_metadata="${z_buym_yelp}"
  buh_line     "   2. Open the ${z_ui_oidc_metadata} URL in a browser tab"
  buyy_cmd_yawp "issuer"; local -r z_cmd_issuer_field="${z_buym_yelp}"
  buh_line     "   3. Copy the JSON ${z_cmd_issuer_field} value; expect the shape:"
  buyy_cmd_yawp "https://login.microsoftonline.com/«tenant-id»/v2.0"; local -r z_cmd_issuer_shape="${z_buym_yelp}"
  buh_line     "      ${z_cmd_issuer_shape}"
  buh_e
  buh_section  "6. Author the Foedus Regime Values:"
  local z_entrada_rbrf
  z_entrada_rbrf=$(rbcc_rbrf_file_capture rbef_entrada) || buc_die "Failed to resolve the rbef_entrada federation regime path"
  buyy_cmd_yawp "${z_entrada_rbrf}"; local -r z_cmd_rbrf_file="${z_buym_yelp}"
  buh_line     "   File: ${z_cmd_rbrf_file}"
  buh_line     "   (the standing interactive foedus; a new foedus takes its own rbef_ subdirectory)"
  buh_line     "   Set the core and interactive-mechanism fields from the values above:"
  buyy_cmd_yawp "RBRF_MECHANISM=rbnfe_interactive"; local -r z_cmd_field_mechanism="${z_buym_yelp}"
  buh_line     "   ${z_cmd_field_mechanism}"
  buyy_cmd_yawp "RBRF_IDP_ISSUER=https://login.microsoftonline.com/«tenant-id»/v2.0"; local -r z_cmd_field_issuer="${z_buym_yelp}"
  buh_line     "   ${z_cmd_field_issuer}"
  buh_line     "      (exactly the metadata document's issuer value from step 5)"
  buyy_cmd_yawp "RBRF_IDP_CLIENT_ID=«application-client-id»"; local -r z_cmd_field_client="${z_buym_yelp}"
  buh_line     "   ${z_cmd_field_client}"
  buyy_cmd_yawp "RBRF_IDP_DEVICE_ENDPOINT=https://login.microsoftonline.com/«tenant-id»/oauth2/v2.0/devicecode"; local -r z_cmd_field_device="${z_buym_yelp}"
  buh_line     "   ${z_cmd_field_device}"
  buyy_cmd_yawp "RBRF_IDP_TOKEN_ENDPOINT=https://login.microsoftonline.com/«tenant-id»/oauth2/v2.0/token"; local -r z_cmd_field_token="${z_buym_yelp}"
  buh_line     "   ${z_cmd_field_token}"
  buyy_cmd_yawp "RBRF_IDP_SCOPE=\"openid profile email\""; local -r z_cmd_field_scope="${z_buym_yelp}"
  buh_line     "   ${z_cmd_field_scope}"
  buh_line     "      (must request openid; must NOT request offline_access — a refresh token"
  buh_line     "      would let a run begin outside a live sitting, and the validator refuses it)"
  buyy_cmd_yawp "RBRF_ATTRIBUTE_MAPPING=\"google.subject=assertion.oid\""; local -r z_cmd_field_mapping="${z_buym_yelp}"
  buh_line     "   ${z_cmd_field_mapping}"
  buh_line     "      (oid is the Entra user's immutable object id — stable across rename and"
  buh_line     "      UPN change, and Google's recommended Entra subject mapping)"
  buyy_cmd_yawp "RBRF_PROVIDER_ID=«provider-id»"; local -r z_cmd_field_provider="${z_buym_yelp}"
  buh_line     "   ${z_cmd_field_provider}"
  buh_line     "      (a Google-side choice, not an Entra value: lowercase alphanumeric and"
  buh_line     "      hyphen, 4-32 chars, never starting with gcp-)"
  buh_e
  buh_section  "7. Validate and Commit:"
  buh_line     "   Run:"
  buh_tt       "      " "${RBZ_VALIDATE_FEDERATION}" "" ""
  buh_line     "   Every value is a public identifier, so the file ships committed — commit it"
  buh_line     "   with your usual workflow before founding anything against it."
  buh_e
  buh_section  "8. Citizen Sign-In Identities (admission subjects):"
  buh_line     "   Each human who will authenticate needs a user in this tenant, and admission"
  buh_line     "   (gird, brevet) takes that user's object id as its subject argument:"
  buyy_ui_yawp "Users"; local -r z_ui_users="${z_buym_yelp}"
  buh_line     "   1. Browse to ${z_ui_entra_id} then ${z_ui_users}; create the user if absent"
  buyy_ui_yawp "Object ID"; local -r z_ui_object_id="${z_buym_yelp}"
  buh_line     "   2. Open the user's profile and copy ${z_ui_object_id} exactly"
  buh_line     "   At each user's first sign-in, Entra asks consent for the requested scopes —"
  buh_line     "   expected, accept it. If your tenant restricts user consent, grant admin"
  buyy_ui_yawp "API permissions"; local -r z_ui_api_permissions="${z_buym_yelp}"
  buh_line     "   consent once from the registration's ${z_ui_api_permissions} page."
  buh_e
  buh_section  "9. Found the Google Side:"
  buh_line     "   With the foedus values committed, affiance seats the provider under the"
  buh_line     "   manor's workforce pool (payor work, autonomous from here):"
  buh_tt       "      " "${RBZ_AFFIANCE_MANOR}" "" ""

}

# eof
