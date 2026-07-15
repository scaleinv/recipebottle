#!/bin/bash
# RBGJAM Step 02: Syft SBOM scan for each platform of image
# Builder: gcr.io/cloud-builders/docker
# Substitutions: _RBGA_GAR_HOST, _RBGA_GAR_PATH, _RBGA_HALLMARKS_ROOT,
#                _RBGA_HALLMARK, _RBGA_VESSEL_MODE,
#                _RBGA_ARK_BASENAME_IMAGE
#
# Scans each platform of image via registry: transport, pinned to the
# manifest digest that step 01 always writes to platform_digests.txt
# (single-platform included) — scanning a bare tag risks syft falling back
# to auto-selecting the Cloud Build worker's native platform off an index
# that may carry non-runnable attestation manifests.
# Auth via GCB metadata server OAuth2 token — no Docker daemon coupling.
# Produces one SBOM per platform: sbom-{arch}{variant}.json

set -euo pipefail

SYFT_IMAGE="${ZRBF_TOOL_SYFT}"

test -n "${_RBGA_GAR_HOST}"          || { echo "_RBGA_GAR_HOST missing"          >&2; exit 1; }
test -n "${_RBGA_GAR_PATH}"          || { echo "_RBGA_GAR_PATH missing"          >&2; exit 1; }
test -n "${_RBGA_HALLMARKS_ROOT}"    || { echo "_RBGA_HALLMARKS_ROOT missing"    >&2; exit 1; }
test -n "${_RBGA_HALLMARK}"          || { echo "_RBGA_HALLMARK missing"          >&2; exit 1; }
test -n "${_RBGA_VESSEL_MODE}"       || { echo "_RBGA_VESSEL_MODE missing"       >&2; exit 1; }
test -n "${_RBGA_ARK_BASENAME_IMAGE}" || { echo "_RBGA_ARK_BASENAME_IMAGE missing" >&2; exit 1; }

test -s platforms.txt         || { echo "platforms.txt not found (step 01)" >&2; exit 1; }
test -s platform_suffixes.txt || { echo "platform_suffixes.txt not found (step 01)" >&2; exit 1; }
test -s platform_count.txt    || { echo "platform_count.txt not found (step 01)" >&2; exit 1; }

IMAGE_URI="${_RBGA_GAR_HOST}/${_RBGA_GAR_PATH}/${_RBGA_HALLMARKS_ROOT}/${_RBGA_HALLMARK}/${_RBGA_ARK_BASENAME_IMAGE}:${_RBGA_HALLMARK}"
GAR_AUTHORITY="${_RBGA_GAR_HOST}"

# Fetch OAuth2 token from GCB metadata server (no gcloud/jq dependency)
echo "Fetching OAuth2 token from metadata server"
TOKEN_JSON=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token") \
  || { echo "Failed to fetch OAuth2 token from metadata server" >&2; exit 1; }
TOKEN=$(printf '%s' "${TOKEN_JSON}" | sed 's/.*"access_token":"\([^"]*\)".*/\1/') \
  || { echo "Failed to parse access_token" >&2; exit 1; }
test -n "${TOKEN}" || { echo "OAuth2 token empty" >&2; exit 1; }

# Split platforms and suffixes
IFS=',' read -ra PLATFORMS <<< "$(cat platforms.txt)"
IFS=',' read -ra SUFFIXES <<< "$(cat platform_suffixes.txt)"

test "${#PLATFORMS[@]}" -eq "${#SUFFIXES[@]}" \
  || { echo "Platform/suffix count mismatch" >&2; exit 1; }

# Load per-platform digests (all scans are @digest-pinned; see loop below)
declare -A DIGEST_MAP
if test -f platform_digests.txt; then
  while IFS=' ' read -r D_SUFFIX D_DIGEST; do
    DIGEST_MAP["${D_SUFFIX}"]="${D_DIGEST}"
  done < platform_digests.txt
fi

echo "=== Per-platform SBOM generation (registry transport) ==="
for IDX in "${!PLATFORMS[@]}"; do
  PLAT="${PLATFORMS[${IDX}]}"
  SUFFIX="${SUFFIXES[${IDX}]}"
  SBOM_LABEL="${SUFFIX#-}"
  SBOM_FILE="sbom-${SBOM_LABEL}.json"

  # Scan via @digest pinning — single- and multi-platform alike: OCI indexes
  # may carry attestation manifests (unknown/unknown platform) that cause
  # syft to fail on tag auto-selection, and a single-platform image built via
  # buildx can still be published as an index carrying such an attestation.
  # discover-platforms always writes platform_digests.txt, single-platform
  # included, so the digest is available uniformly.
  DIGEST="${DIGEST_MAP[${SUFFIX}]:-}"
  test -n "${DIGEST}" || { echo "No digest found for suffix ${SUFFIX}" >&2; exit 1; }
  SCAN_TARGET="registry:${IMAGE_URI}@${DIGEST}"

  echo "--- Scanning ${PLAT} (${SCAN_TARGET}) → ${SBOM_FILE} ---"
  docker run --rm \
    -e SYFT_REGISTRY_AUTH_AUTHORITY="${GAR_AUTHORITY}" \
    -e SYFT_REGISTRY_AUTH_USERNAME=oauth2accesstoken \
    -e SYFT_REGISTRY_AUTH_PASSWORD="${TOKEN}" \
    -e SYFT_CHECK_FOR_APP_UPDATE=false \
    "${SYFT_IMAGE}" "${SCAN_TARGET}" -o json > "${SBOM_FILE}" \
    || { echo "Syft JSON generation failed for ${PLAT}" >&2; exit 1; }

  test -s "${SBOM_FILE}" || { echo "SBOM output empty for ${PLAT}" >&2; exit 1; }
  echo "SBOM generated: ${SBOM_FILE}"
done
echo "=== SBOM generation complete ==="
