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
# Recipe Bottle Handbook Onboarding - Payor Handbook (establish Manor and Depot)

set -euo pipefail

test -z "${ZRBHOPW_SOURCED:-}" || return 0
ZRBHOPW_SOURCED=1

rbho_payor_handbook() {
  zrbho_sentinel

  buc_doc_brief "Payor — establish a Manor and provision the Depot"
  buc_doc_shown || return 0

  buh_section "Payor — Establish a Manor and Provision the Depot"
  buh_e
  buh_line "The ${RBYC_PAYOR} establishes a ${RBYC_MANOR} — an administrative seat"
  buh_line "holding the billing account, OAuth client, and operator identity."
  buh_line "The ${RBYC_PAYOR} authenticates via OAuth, representing the human"
  buh_line "project owner. Every other role is keyless: a mantle that a"
  buh_line "signed-in citizen dons — no service account keys anywhere."
  buh_e
  buh_line "By the end of this handbook you will have a ${RBYC_MANOR}, a ${RBYC_DEPOT}"
  buh_line "funded under it, its trust affianced to your identity provider,"
  buh_line "and a founding ${RBYC_GOVERNOR} girded to administer it."
  buh_e

  buh_line "This ceremony takes about 30 minutes."
  buh_e

  buh_step_style "Step " " — "

  buh_step1 "Establish the Manor"
  buh_e
  buh_line "The ${RBYC_MANORS} GCP project hosts the OAuth client and billing"
  buh_line "account. It must be created before any infrastructure can be"
  buh_line "provisioned."
  buh_e
  buh_line "Run the guided setup:"
  buh_tt  "  " "${RBZ_PAYOR_ESTABLISH}"
  buh_e
  buh_line "This guides you through creating the ${RBYC_MANORS} GCP project,"
  buh_line "choosing a billing account, and configuring the OAuth consent screen."
  buh_line "The ${RBYC_MANOR} identity is recorded in ${RBYC_RBRP}."
  buh_e

  buh_step1 "Install OAuth credentials"
  buh_e
  buh_line "Step 1 ended with saving a JSON client secret file into its durable"
  buh_line "home - the client_secrets/ subdirectory of your secrets directory"
  buh_line "(RBRR_SECRETS_DIR in rbrr.env). Install it:"
  buh_e
  buh_tt  "  " "${RBZ_PAYOR_INSTALL}" "" " «secrets-dir»/client_secrets/client_secret_*.json"
  buh_e
  buh_line "This walks you through the OAuth authorization flow and stores"
  buh_line "the credential securely."
  buh_e
  buh_line "The glob assumes one client_secret_*.json in the durable home. If"
  buh_line "more than one exists (e.g. after rotating a compromised secret),"
  buh_line "pass its exact path."
  buh_e

  buh_step1 "Instaurate the Manor"
  buh_e
  buh_line "One idempotent command readies the ${RBYC_MANORS} scriptable"
  buh_line "substrate: it enables the payor-project APIs, links billing, seats"
  buh_line "the workforce identity pool, and provisions the terrier bucket."
  buh_line "Set RBRD_DEPOT_MONIKER and RBRD_GCP_REGION in ${RBYC_RBRD} first —"
  buh_line "the depot regime is enforced and the bucket's region rides"
  buh_line "RBRD_GCP_REGION. Safe to re-run at any time (ensure-exists):"
  buh_e
  buh_tt  "  " "${RBZ_INSTAURATE_MANOR}"
  buh_e

  buh_step1 "Affiance a foedus"
  buh_e
  buh_line "Keyless sign-in rides a standing trust between the ${RBYC_MANOR} and"
  buh_line "your identity provider — a foedus. First register the application"
  buh_line "at the IdP's own console (guided walk, Entra shown):"
  buh_e
  buh_tt  "  " "${RBZ_FEDERATION_ENTRA}"
  buh_e
  buh_line "The walk yields the foedus's core trust values, landing in the"
  buh_line "committed federation ${RBYC_REGIME}. Then pledge the trust — seat the"
  buh_line "foedus's provider under the workforce pool:"
  buh_e
  buh_tt  "  " "${RBZ_AFFIANCE_MANOR}" "" " <foedus>"
  buh_e
  buh_line "Once per foedus — every citizen sign-in afterward rides this trust."
  buh_e

  buh_step1 "Provision the Depot"
  buh_e
  buh_line "A ${RBYC_DEPOT} is the facility where container images are built and"
  buh_line "stored — a GCP project with a container repository, storage bucket,"
  buh_line "and build infrastructure, funded under the ${RBYC_MANORS} billing account."
  buh_line "A ${RBYC_GOVERNOR} administers the ${RBYC_DEPOT} — brevetting the"
  buh_line "citizens who build and retrieve container images onto the"
  buh_line "${RBYC_DIRECTOR} and ${RBYC_RETRIEVER} mantles."
  buh_e
  buh_line "${RBYC_PAYOR} creates the Depot — commit anything pending first;"
  buh_line "the tripwire inscribe at the end of ${RBYC_LEVY} refuses on a dirty"
  buh_line "working tree, so the inscribed ${RBYC_RBRD} is a committed state:"
  buh_tt  "  " "${RBZ_LEVY_DEPOT}"
  buh_e
  buh_line "This enables APIs, creates the Artifact Registry repository and"
  buh_line "Cloud Storage bucket, and configures Cloud Build."
  buh_e
  buh_line "${RBYC_PAYOR} can list Depots for verification:"
  buh_tt  "  " "${RBZ_LIST_DEPOT}"
  buh_e

  buh_line "At the end of a successful ${RBYC_LEVY}, the depot-immutable"
  buh_line "settings in ${RBYC_RBRD} (cloud prefix, depot moniker, region, and"
  buh_line "Cloud Build machine type) are inscribed into the Depot as a"
  buh_line "tripwire image. Every later cloud build pulls that image and"
  buh_line "byte-compares it against your local ${RBYC_RBRD} file before"
  buh_line "submitting, so an accidental post-levy edit fails loud instead of"
  buh_line "silently pointing builds at the wrong project or worker pool."
  buh_e
  buh_line "Three failure modes you may meet, and how to recover:"
  buh_e
  buh_warn "Drift — a cloud build dies reporting a ${RBYC_RBRD} mismatch."
  buh_line "  Your local ${RBYC_RBRD} no longer matches what the Depot was"
  buh_line "  levied with. Restore the file to its inscribed contents (the"
  buh_line "  failure prints a diff), or if the change is intentional, unmake"
  buh_line "  and re-levy the Depot — ${RBYC_RBRD} is frozen for its lifetime:"
  buh_tt  "    " "${RBZ_UNMAKE_DEPOT}" "" " <depot-project-id>"
  buh_tt  "    " "${RBZ_LEVY_DEPOT}"
  buh_e
  buh_warn "Missing tripwire — a cloud build dies reporting the image is absent."
  buh_line "  The Depot was levied before the tripwire existed, or the image"
  buh_line "  was removed. Inscribe it once against the current ${RBYC_RBRD}"
  buh_line "  (supply a fresh access token):"
  buh_tt  "    " "${RBZ_INSCRIBE_DEPOT}" "" " \$(gcloud auth print-access-token)"
  buh_e
  buh_warn "Re-inscribe refused — re-running levy on an inscribed Depot dies."
  buh_line "  The tripwire is already present and is never overwritten in"
  buh_line "  place. To refresh it, unmake the Depot and levy fresh:"
  buh_tt  "    " "${RBZ_UNMAKE_DEPOT}" "" " <depot-project-id>"
  buh_tt  "    " "${RBZ_LEVY_DEPOT}"
  buh_e
  buh_line "To verify alignment at any time without submitting a build:"
  buh_tt  "  " "${RBZ_CHECK_DEPOT}" "" " \$(gcloud auth print-access-token)"
  buh_e
  buh_line "${RBYC_PAYOR} girds the first ${RBYC_GOVERNOR} of this ${RBYC_DEPOT} —"
  buh_line "seating the freehold subject as its founding governor:"
  buh_tt  "  " "${RBZ_GIRD_POLITY}" "" " <subject>"
  buh_e
  buh_line "No key file is created or handed over: the ${RBYC_GOVERNOR} signs in"
  buh_line "(avows) and dons the governor mantle to administer this ${RBYC_DEPOT},"
  buh_line "admitting ${RBYC_RETRIEVER} and ${RBYC_DIRECTOR} citizens independently."
  buh_e
  buh_line "The ${RBYC_PAYORS} job for this ${RBYC_DEPOT} is done unless billing or"
  buh_line "project-level changes are needed."
  buh_e

  buh_tt  "Return to start: " "${RBZ_ONBOARD_START_HERE}"
  buh_e
}

# eof
