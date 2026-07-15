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
# Recipe Bottle GCP Constants - Implementation (no printf required)

set -euo pipefail

# Multiple inclusion detection
# (Module state remains ZRBGC_* per BCG; external constants use RBGC_*)
test -z "${ZRBGC_SOURCED:-}" || buc_die "Module rbgc multiply sourced - check sourcing hierarchy"
ZRBGC_SOURCED=1

# Tinder constants (pure string literals, no variable expansion — available at source time)
# Depot project ID infix between RBRD_CLOUD_PREFIX and RBRD_DEPOT_MONIKER, consumed
# by rbdc_derived.sh's RBDC_DEPOT_PROJECT_ID derivation.
RBGC_depot_project_infix="d-"

######################################################################
# Internal Functions (zrbgc_*)

zrbgc_kindle() {
  test -z "${ZRBGC_KINDLED:-}" || buc_die "Module rbgc already kindled"

  # Global Resource Naming (Google Cloud global namespace)
  # These resources compete in globally-unique namespaces across all of GCP
  # Pattern: {prefix}-{type}-{name}-{timestamp} where timestamp is YYMMDDHHMMSS
  readonly RBGC_GLOBAL_PREFIX="rbwg"
  readonly RBGC_GLOBAL_TYPE_PAYOR="p"
  readonly RBGC_GLOBAL_TYPE_DEPOT="d"
  readonly RBGC_GLOBAL_TYPE_BUCKET="b"
  readonly RBGC_GLOBAL_TIMESTAMP_FORMAT="+%y%m%d%H%M%S"
  readonly RBGC_GLOBAL_TIMESTAMP_LEN=12
  readonly RBGC_GLOBAL_TIMESTAMP_REGEX="[0-9]{${RBGC_GLOBAL_TIMESTAMP_LEN}}"

  # Global resource validation patterns
  # Payor:  rbwg-p-YYMMDDHHMMSS  (timestamp survives — payor is installation-scoped, not depot-scoped)
  readonly RBGC_GLOBAL_PAYOR_REGEX="^${RBGC_GLOBAL_PREFIX}-${RBGC_GLOBAL_TYPE_PAYOR}-${RBGC_GLOBAL_TIMESTAMP_REGEX}$"

  # Basic Configuration
  readonly RBGC_ADMIN_ROLE="rbw-admin"
  readonly RBGC_PAYOR_ROLE="rbw-payor"
  readonly RBGC_PAYOR_APP_NAME="Recipe Bottle Payor"

  # Timeouts
  readonly RBGC_MAX_CONSISTENCY_SEC=90
  readonly RBGC_EVENTUAL_CONSISTENCY_SEC=3
  # The confirmation streak rbuh_poll_until_gone counts (RBr_c81).
  readonly RBGC_GONE_CONFIRM_STREAK=3
  readonly RBGC_SA_KEY_CREATE_RETRY_MAX=7
  readonly RBGC_SA_KEY_CREATE_RETRY_DELAY_SEC=10

  # IAM-grant propagation retry — exponential-backoff budget shared by every
  # get-modify-set IAM grant site in rbgi_iam.sh, the capabilities GAR IAM
  # loops in rbgw_capabilities.sh, and the theurge's post-admission
  # invocations (projected to Rust via rbgc_emit_consts). RBSCIP locks the
  # profile and homes the rationale (the propagation classes; why the 403
  # wait is blind).
  readonly RBGC_PROPAGATION_INITIAL_DELAY_SEC=3
  readonly RBGC_PROPAGATION_MAX_DELAY_SEC=20
  readonly RBGC_PROPAGATION_DEADLINE_SEC=420

  # HTTP transient-failure retry — bounded retry on curl-network blips
  # (connection refused 7, timeout 28, TLS handshake 35, recv failure 56).
  # Shared by rbuh_json and the OAuth token-mint POST. Other curl exits
  # are configuration-deterministic and fail fast.
  readonly RBGC_HTTP_TRANSIENT_RETRY_ATTEMPTS=3
  readonly RBGC_HTTP_TRANSIENT_RETRY_SLEEP_SEC=3

  # serviceusage enable INTERNAL flake — whole-attempt retry budget for
  # rbge_api_enable on the fresh-project enable race. Signature and membrane:
  # rivets RBr_4e7 / RBr_d21 at RBS0 rbtoe_api_enable.
  readonly RBGC_API_ENABLE_RETRY_ATTEMPTS=3
  readonly RBGC_API_ENABLE_RETRY_PAUSE_SEC=15

  # docker daemon->registry premature-timeout transient — the moby/moby#44350
  # signature. docker's registry-auth client carries a hardcoded,
  # non-configurable 15s timeout (moby/registry/auth.go); against a
  # healthy-but-slow GAR auth backend it fires prematurely, emitting this Go
  # net/http stdlib string. Neither login nor the initial resolve leg of
  # pull / manifest inspect (token fetch + manifest HEAD) carries an internal
  # retry — the docker client retries only layer downloads, after resolve —
  # so callers wrap them (rbgo_docker_login, zrbndb_docker_login,
  # zrbndb_registry_read) reusing the HTTP retry budget above. The string is
  # a Go standard-library invariant, stable across docker versions; this is a
  # surveyed-signature allowlist, NOT a catch-all — real auth failures emit
  # "unauthorized" and fail fast.
  readonly RBGC_DOCKER_LOGIN_TRANSIENT_SIGNATURE='Client.Timeout exceeded while awaiting headers'

  # docker login credential-persist failure under headless Cygwin. Docker
  # Desktop's docker-credential-wincred backend cannot reach the Windows
  # Credential Manager from an sshd session that owns no interactive logon
  # (cmdkey /list is empty over SSH), emitting this Win32 string (rc=1) AFTER
  # auth has already succeeded — the token mint and the push path are sound;
  # only the credential STORE fails. Windows docker also ignores an empty
  # credsStore (the CLI still detects wincred), so config alone cannot divert
  # the store to the file store. At this Palisade (docker's own credential store,
  # source we cannot edit) rbgo_docker_login bends ONCE on this exact signature:
  # since auth already succeeded it writes the credential into the base64 file
  # store itself (the config.json `auths` map docker push reads directly — the
  # form WSL uses natively) and treats login as done. A real auth failure emits
  # "unauthorized" and never matches. Stable Win32 system-error message;
  # corroborated by docker/cli#4353 and #1263. REMOVE the bend when the
  # uncontrolled-Cygwin host gains an interactive Windows logon / working vault.
  readonly RBGC_DOCKER_WINCRED_HEADLESS_SIGNATURE='A specified logon session does not exist'

  # URL Roots & Well-known Endpoints
  readonly RBGC_OAUTH_TOKEN_URL="https://oauth2.googleapis.com/token"
  readonly RBGC_OAUTH_AUTHORIZE_URL="https://accounts.google.com/o/oauth2/v2/auth"
  readonly RBGC_OAUTH_USERINFO_URL="https://www.googleapis.com/oauth2/v3/userinfo"
  readonly RBGC_API_ROOT_IAM="https://iam.googleapis.com"
  # Distinct service from iam.googleapis.com — iamcredentials hosts the
  # short-lived-credential mints (generateAccessToken, the Leg-3 don). The IAM
  # policy ops (get/setIamPolicy, serviceAccounts CRUD) stay on RBGC_API_ROOT_IAM.
  readonly RBGC_API_ROOT_IAMCREDENTIALS="https://iamcredentials.googleapis.com"
  readonly RBGC_API_ROOT_CRM="https://cloudresourcemanager.googleapis.com"
  readonly RBGC_API_ROOT_SERVICEUSAGE="https://serviceusage.googleapis.com"
  readonly RBGC_API_ROOT_ARTIFACTREGISTRY="https://artifactregistry.googleapis.com"
  readonly RBGC_API_ROOT_CLOUDBUILD="https://cloudbuild.googleapis.com"
  readonly RBGC_API_ROOT_CLOUDBILLING="https://cloudbilling.googleapis.com"
  readonly RBGC_API_ROOT_STORAGE="https://storage.googleapis.com"
  readonly RBGC_API_ROOT_SECRETMANAGER="https://secretmanager.googleapis.com"
  readonly RBGC_API_ROOT_LOGGING="https://logging.googleapis.com"
  # IAP hosts the only API surface over the project's OAuth brand (the consent
  # screen); RB uses it solely to read orgInternalOnly — the audience gate.
  readonly RBGC_API_ROOT_IAP="https://iap.googleapis.com"
  readonly RBGC_CONSOLE_URL="https://console.cloud.google.com/"
  readonly RBGC_SIGNUP_URL="https://cloud.google.com/free"

  # OAuth Scopes
  readonly RBGC_SCOPE_CLOUD_PLATFORM="https://www.googleapis.com/auth/cloud-platform"

  # Service Usage Service Identifiers
  readonly RBGC_SERVICE_IAM="iam.googleapis.com"
  readonly RBGC_SERVICE_CRM="cloudresourcemanager.googleapis.com"
  readonly RBGC_SERVICE_ARTIFACTREGISTRY="artifactregistry.googleapis.com"

  # Email/Domain Assembly
  readonly RBGC_SA_EMAIL_DOMAIN="iam.gserviceaccount.com"

  # API Version Paths
  readonly RBGC_IAM_V1="/v1"
  readonly RBGC_IAMCREDENTIALS_V1="/v1"
  readonly RBGC_CRM_V1="/v1"
  readonly RBGC_CRM_V3="/v3"
  readonly RBGC_SERVICEUSAGE_V1="/v1"
  readonly RBGC_SERVICEUSAGE_V1BETA1="/v1beta1"
  readonly RBGC_ARTIFACTREGISTRY_V1="/v1"
  readonly RBGC_CLOUDBUILD_V1="/v1"
  readonly RBGC_CLOUDBILLING_V1="/v1"
  readonly RBGC_STORAGE_JSON_V1="/storage/v1"
  readonly RBGC_STORAGE_JSON_UPLOAD="/upload/storage/v1"
  readonly RBGC_SECRETMANAGER_V1="/v1"
  readonly RBGC_LOGGING_V2="/v2"
  readonly RBGC_IAP_V1="/v1"

  # REST Path Fragments
  readonly RBGC_PATH_PROJECTS="/projects"
  readonly RBGC_PATH_LOCATIONS="/locations"
  readonly RBGC_PATH_REPOSITORIES="/repositories"
  readonly RBGC_PATH_SERVICE_ACCOUNTS="/serviceAccounts"
  readonly RBGC_PATH_KEYS="/keys"

  # REST Operation Suffixes
  readonly RBGC_CRM_GET_IAM_POLICY_SUFFIX=":getIamPolicy"
  readonly RBGC_CRM_SET_IAM_POLICY_SUFFIX=":setIamPolicy"
  readonly RBGC_IAMCREDENTIALS_GENERATE_ACCESS_TOKEN_SUFFIX=":generateAccessToken"
  readonly RBGC_SERVICEUSAGE_ENABLE_SUFFIX=":enable"
  readonly RBGC_SERVICEUSAGE_PATH_SERVICES="/services"

  # Operation Prefixes
  readonly RBGC_OP_PREFIX_GLOBAL="operations/"

  # Cloud Logging (audit-trail reads — see rbgp_attribution_trail, spike V3)
  readonly RBGC_LOGGING_ENTRIES_LIST_SUFFIX="/entries:list"
  # The always-on Data-Access audit log id (the slash is %2F-encoded per the
  # Cloud Logging logName format). Enabled per-service at depot levy by
  # zrbgp_enable_ar_audit_logs; both the iamcredentials mint hop and the
  # artifactregistry use hop land in this one log.
  readonly RBGC_AUDIT_LOG_DATA_ACCESS="cloudaudit.googleapis.com%2Fdata_access"

  # Ark Artifact Basenames (₢A_AAK layout)
  # Each ark type is a plain basename sibling under rbi_hm/<hallmark>/.
  readonly RBGC_ARK_BASENAME_IMAGE="image"
  readonly RBGC_ARK_BASENAME_ABOUT="about"
  readonly RBGC_ARK_BASENAME_VOUCH="vouch"
  readonly RBGC_ARK_BASENAME_DIAGS="diags"
  readonly RBGC_ARK_BASENAME_ATTEST="attest"
  readonly RBGC_ARK_BASENAME_POUCH="pouch"

  # Hallmark Prefix Letters
  # Encode artifact provenance in the leading character of a hallmark stamp.
  # Kludge hallmarks are local-only; the other three originate in GAR.
  readonly RBGC_HALLMARK_PREFIX_CONJURE="c"
  readonly RBGC_HALLMARK_PREFIX_KLUDGE="k"
  readonly RBGC_HALLMARK_PREFIX_BIND="b"
  readonly RBGC_HALLMARK_PREFIX_GRAFT="g"

  # GAR Categorical Namespaces (₢A_AAK layout)
  # Top-level namespaces under which arks are stored. Consumed by rbgl_layout.sh.
  # rbi_hm holds Director-authored image families; rbi_df holds
  # Payor-authored depot-scoped OCI artifacts produced during depot lifetime.
  readonly RBGC_GAR_CATEGORY_HALLMARKS="rbi_hm"
  readonly RBGC_GAR_CATEGORY_DEPOT_FACTS="rbi_df"
  readonly RBGC_GAR_CATEGORY_LODES="rbi_ld"

  # Lode kind letters — the leading segment of a touchmark.
  readonly RBGC_LODE_KIND_BOLE="b"
  readonly RBGC_LODE_KIND_RELIQUARY="r"
  readonly RBGC_LODE_KIND_WSL="w"
  readonly RBGC_LODE_KIND_PODVM_WSL="vw"
  readonly RBGC_LODE_KIND_PODVM_NATIVE="vn"

  # Kind-brand enum — the kind's spelled name: the vouch envelope's `kind` field,
  # the display label, and — for podvm — the operator-typed `immure` family
  # argument. Not a chaining fact; nothing reads a brand off the chain.
  readonly RBGC_LODE_BRAND_BOLE="bole"
  readonly RBGC_LODE_BRAND_RELIQUARY="reliquary"
  readonly RBGC_LODE_BRAND_WSL="wsl"
  readonly RBGC_LODE_BRAND_PODVM_WSL="podvm-wsl"
  readonly RBGC_LODE_BRAND_PODVM_NATIVE="podvm-native"

  # Member/provenance tags. The rbi_ sprue marks strings from RB's domain:
  # RB's authored lexicon (bole, vouch) and RB-measured-from-content values
  # (the digest). It does NOT mark foreign-cued strings — the sanitized-origin
  # tag is UNSPRUED (origin is a vessel cue), computed at capture, not a constant.
  readonly RBGC_LODE_TAG_SPRUE="rbi_"               # RB reserved tag prefix; member tags compose as <sprue><name>
  readonly RBGC_LODE_TAG_BOLE="rbi_bole"            # uniform greppable handle (bole singleton)
  readonly RBGC_LODE_TAG_VOUCH="rbi_vouch"          # one-per-Lode provenance envelope
  readonly RBGC_LODE_TAG_DIGEST_PREFIX="rbi_sha256-"  # canonical OCI digest tag: rbi_sha256-<full-hex>
  # reliquary cohort members carry the clean scheme :<sprue><tool> (e.g. rbi_gcrane)
  # — no digest/fingerprint layer; the tool name is RB-authored lexicon, so sprued.
  readonly RBGC_LODE_TAG_ROOTFS="rbi_rootfs"        # wsl singleton: the opaque rootfs blob member (RB-authored, sprued)

  # Provenance envelope (:rbi_vouch) — two honest trust grades, declared per Lode.
  # bole captures the durable-upstream grade; podvm-* carries the recorded grade.
  readonly RBGC_LODE_TRUST_VERIFIED="verified-against-published"
  readonly RBGC_LODE_TRUST_RECORDED="recorded-at-acquisition"
  # rbld-vouch-2: the rblv_ sprue migration (ACGm_108, first application).
  # rbld-vouch-3: rblv_git_commit added — the dispatching HEAD commit, stamped at
  #   the shared vouch-push step (rbgjl02) from the spine-injected substitution.
  # Pre-MVP: no back-compat; every author writes rblv_ keys, augur reads rblv_ ONLY.
  readonly RBGC_LODE_VOUCH_SCHEMA="rbld-vouch-3"    # unsigned, schema-versioned, rblv_ sprue

  # Conjure resolved-base image label — the sprued key prefix for the per-slot base
  # digest pins rbgjb03/rbgjb04 emit onto the consumer image (and which survive the
  # pullback into the signed attest image; read back by plumb). Composes as
  # <prefix>_<n> → rbi_resolved_base_1..3, one per populated RBF_IMAGE_n slot. This
  # is an image-config LABEL, not a registry tag — but shares the rbi_ image-domain
  # sprue. Its neighbor build labels (hallmark, git.commit, git.branch) stay UNSPRUED
  # by deliberate divergence. The cloud step that writes the label sources no
  # constants, so the key is a literal there; this constant is the host home (plumb
  # reads it) and the repo-wide grep gate keeps the two in sync.
  readonly RBGC_IMAGE_LABEL_RESOLVED_BASE="rbi_resolved_base"

  # The wsl capture source (RBr_6f2). printf args: (release, release.point, arch).
  readonly RBGC_LODE_WSL_URL_TEMPLATE="https://cdimage.ubuntu.com/ubuntu-base/releases/%s/release/ubuntu-base-%s-base-%s.tar.gz"
  readonly RBGC_LODE_WSL_ARCH_DEFAULT="amd64"
  # Ubuntu CD Image Automatic Signing Key (2012, RSA4096), cdimage@ubuntu.com —
  # signs the SHA256SUMS.gpg published beside the tarball above (RBr_6f2).
  readonly RBGC_LODE_WSL_SIGNING_FPR="843938DF228D22F7B3742BC0D94AA3F0EFE21092"

  # The two quay families immure spans, selected by its family argument.
  readonly RBGC_LODE_PODVM_FAMILY_WSL="quay.io/podman/machine-os-wsl"
  readonly RBGC_LODE_PODVM_FAMILY_NATIVE="quay.io/podman/machine-os"
  # Curated leaf selection per family — `disktype:arch` rows the select step matches
  # against the index child descriptors. Arch carries the ALT spelling (x86_64 /
  # aarch64) the disktype leaves declare, not the OCI amd64 / arm64.
  readonly RBGC_LODE_PODVM_WSL_SELECTION="wsl:x86_64 wsl:aarch64"
  readonly RBGC_LODE_PODVM_NATIVE_SELECTION="applehv:x86_64 applehv:aarch64 hyperv:x86_64 hyperv:aarch64 qemu:x86_64 qemu:aarch64 wsl:x86_64 wsl:aarch64"

  # Reliquary Tool Basenames (cohort seeds for the conclave Lode)
  # Canonical tool names; the resolver composes RBGC_LODE_TAG_SPRUE onto each to
  # address the :rbi_<tool> member tags on the one rbi_ld/<touchmark> package.
  # Authoritative cohort manifest lives in rbgjl/rbgjl03-conclave-capture.sh.
  readonly RBGC_RELIQUARY_TOOL_GCLOUD="gcloud"
  readonly RBGC_RELIQUARY_TOOL_DOCKER="docker"
  readonly RBGC_RELIQUARY_TOOL_ALPINE="alpine"
  readonly RBGC_RELIQUARY_TOOL_SYFT="syft"
  readonly RBGC_RELIQUARY_TOOL_BINFMT="binfmt"
  readonly RBGC_RELIQUARY_TOOL_GCRANE="gcrane"

  # Fact-file filenames (written to BURD_OUTPUT_DIR by producers)
  readonly RBF_FACT_HALLMARK="rbf_fact_hallmark"
  readonly RBF_FACT_GAR_ROOT="rbf_fact_gar_root"
  readonly RBF_FACT_ARK_STEM="rbf_fact_ark_stem"
  readonly RBF_FACT_ARK_YIELD="rbf_fact_ark_yield"

  # Lode capture chaining fact (single-form, fixed filename). A capture is
  # capture-pure and writes no consumer config; it hands the captured touchmark to
  # a later election (feoff for the conjure ANCHOR, yoke for the reliquary) through
  # this one bare fact via the depth-1 cross-tabtarget chain. The provenance
  # envelope lives only in GAR (:rbi_vouch), never host-side. TOUCHMARK carries the
  # Lode stamp (e.g. b260602120000); its kind-letter prefix decodes to the kind, so
  # no separate kind-brand fact rides the chain (RBGC_LODE_BRAND_* are display
  # labels / immure's family vocabulary, not a chaining fact).
  readonly RBF_FACT_LODE_TOUCHMARK="rbf_fact_lode_touchmark"

  # Payor fact-file filenames (governor identifying values)
  readonly RBGP_FACT_GOVERNOR_SA_EMAIL="rbgp_fact_governor_sa_email"

  # Depot lifecycle-state vocabulary. Fact-file extensions live in RBCC.
  # rbgp_depot_list emits one fact file per known depot at
  # "<cloud_prefix>/<moniker>.${RBCC_fact_ext_depot}" with content equal to
  # one of the values below. The cloud_prefix subdir prevents collisions
  # between same-moniker depots under different cloud_prefixes.
  readonly RBGP_DEPOT_STATE_COMPLETE="COMPLETE"
  readonly RBGP_DEPOT_STATE_DELETE_REQUESTED="DELETE_REQUESTED"

  # GCP resource-lifecycle state enum — the raw `state` field values read from
  # CRM projects and IAM workforce pools. ACTIVE and STATE_UNSPECIFIED are shared
  # across both resource kinds; DELETED is the workforce-pool soft-delete terminal
  # (a project's distinct DELETE_REQUESTED is homed as RBGP_DEPOT_STATE_* above).
  readonly RBGC_STATE_ACTIVE="ACTIVE"
  readonly RBGC_STATE_DELETED="DELETED"
  readonly RBGC_STATE_UNSPECIFIED="STATE_UNSPECIFIED"

  # Recipe Bottle marker written into the manor workforce pool's `description` at
  # founding. The manor-setup finisher (rbgp_manor_instaurate) filters workforcePools.list
  # on this exact string to isolate RB-marked pools under the org for its list-and-match
  # drift guard, and affiance writes it at pool creation — both MUST reference this one
  # home, or the finisher's filter and affiance's marker silently diverge.
  readonly RBGC_WORKFORCE_POOL_MARKER="Recipe Bottle manor federation pool"

  # DisplayName anchor used across depot-creation sites (depot project,
  # Mason SA, Governor SA). Search backend filters CRM v3 projects:search
  # by displayName starting with this anchor. Distinct, unmistakable string
  # ensures no collision with non-depot projects in the operator's account.
  readonly RBGC_DEPOT_DISPLAY_PREFIX="RBGC-DEPOT"

  # Artifact Registry (GAR) Composition
  readonly RBGC_GAR_HOST_SUFFIX="-docker.pkg.dev"

  # GAR Cleanup Policy (applied at depot levy — see RBSMF "Create Container Repository").
  # Reaps untagged manifests on GAR's daily cleanup cadence; underwrites the V2-DELETE-by-tag
  # contract documented in RBSIJ for multi-platform orphan children.
  readonly RBGC_GAR_CLEANUP_POLICY_ID="rb-delete-untagged"
  readonly RBGC_GAR_CLEANUP_OLDER_THAN_SEC="86400s"


  # Canonical Role IDs
  readonly RBGC_ROLE_ARTIFACTREGISTRY_READER="roles/artifactregistry.reader"
  readonly RBGC_ROLE_ARTIFACTREGISTRY_WRITER="roles/artifactregistry.writer"
  readonly RBGC_ROLE_ARTIFACTREGISTRY_ADMIN="roles/artifactregistry.admin"
  readonly RBGC_ROLE_CONTAINERANALYSIS_OCCURRENCES_VIEWER="roles/containeranalysis.occurrences.viewer"
  readonly RBGC_ROLE_CLOUDBUILD_BUILDS_EDITOR="roles/cloudbuild.builds.editor"
  readonly RBGC_ROLE_STORAGE_OBJECT_ADMIN="roles/storage.objectAdmin"
  readonly RBGC_ROLE_STORAGE_OBJECT_VIEWER="roles/storage.objectViewer"
  readonly RBGC_ROLE_IAM_SERVICE_ACCOUNT_TOKEN_CREATOR="roles/iam.serviceAccountTokenCreator"
  readonly RBGC_ROLE_SERVICEUSAGE_SERVICE_USAGE_CONSUMER="roles/serviceusage.serviceUsageConsumer"

  # Common API Base Paths (project-independent)
  readonly RBGC_API_BASE_GCS="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_V1}"

  # Cloud Resource Manager - Liens API
  readonly RBGC_API_CRM_LIST_LIENS="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/liens"
  readonly RBGC_API_CRM_DELETE_LIEN="${RBGC_API_ROOT_CRM}${RBGC_CRM_V1}/liens"

  # Google Cloud Storage (GCS) APIs (project-independent)
  readonly RBGC_API_GCS_BUCKETS="${RBGC_API_BASE_GCS}/b"

  readonly RBGC_BUILD_RUNNER_PLATFORM="linux/amd64"


  # Worker pool infrastructure (dual pools: tether + airgap)
  readonly RBGC_POOL_SUFFIX_TETHER="-tether"
  readonly RBGC_POOL_SUFFIX_AIRGAP="-airgap"
  readonly RBGC_WORKER_POOL_SUFFIX="-pool"
  readonly RBGC_PATH_WORKER_POOLS="/workerPools"

  readonly ZRBGC_KINDLED=1
}

zrbgc_sentinel() {
  test "${ZRBGC_KINDLED:-}" = "1" || buc_die "Module rbgc not kindled - call zrbgc_kindle first"
}

# rbgc_emit_consts() - Emit the RBGC-owned propagation budget as Rust i32
# consts to stdout via buz_emit_const_i32 (BUK zipper must be kindled).
# Same arrangement as rbcc_emit_consts/rbpc_emit_consts: rbz_emit_consts
# calls this because every emit caller sources and kindles rbgc alongside
# rbz. RBSCIP locks the profile; the theurge's post-admission invocations
# consume it (RBr_3f4).
rbgc_emit_consts() {
  zrbgc_sentinel

  printf '%s\n' "// RBGC propagation budget (rbgc_constants.sh; profile locked by RBSCIP)"

  local z_name=""
  local z_stem=""
  for z_name in \
    RBGC_PROPAGATION_INITIAL_DELAY_SEC \
    RBGC_PROPAGATION_MAX_DELAY_SEC     \
    RBGC_PROPAGATION_DEADLINE_SEC      \
  ; do
    z_stem="${z_name#RBGC_}"
    buz_emit_const_i32 "RBTDGC_${z_stem}" "${!z_name}" \
      || buc_die "rbgc_emit_consts: emit failed for ${z_name}"
  done
}

# eof

