#!/bin/bash
# RBGJB Step 05: Per-platform pullback from consumer image manifest list
# Builder: gcr.io/cloud-builders/docker
# Substitutions: _RBGY_PLATFORMS, _RBGY_PLATFORM_SUFFIXES,
#                _RBGY_GAR_LOCATION, _RBGY_GAR_PROJECT, _RBGY_GAR_REPOSITORY,
#                _RBGY_GAR_HOST_SUFFIX, _RBGY_HALLMARKS_ROOT, _RBGY_HALLMARK,
#                _RBGY_ARK_BASENAME_IMAGE, _RBGY_ARK_BASENAME_ATTEST
#
# For each platform: docker pull --platform <plat> from the image manifest,
# then docker tag to the attest package with tag <hallmark>-<arch>
# (per-platform tags on a single attest package — multi-platform attestation
# scaffolding for CB images: field SLSA provenance generation).

set -euo pipefail

test -n "${_RBGY_PLATFORMS}"           || (echo "_RBGY_PLATFORMS missing"           >&2; exit 1)
test -n "${_RBGY_PLATFORM_SUFFIXES}"   || (echo "_RBGY_PLATFORM_SUFFIXES missing"   >&2; exit 1)
test -n "${_RBGY_GAR_LOCATION}"        || (echo "_RBGY_GAR_LOCATION missing"        >&2; exit 1)
test -n "${_RBGY_GAR_PROJECT}"         || (echo "_RBGY_GAR_PROJECT missing"         >&2; exit 1)
test -n "${_RBGY_GAR_REPOSITORY}"      || (echo "_RBGY_GAR_REPOSITORY missing"      >&2; exit 1)
test -n "${_RBGY_HALLMARKS_ROOT}"      || (echo "_RBGY_HALLMARKS_ROOT missing"      >&2; exit 1)
test -n "${_RBGY_HALLMARK}"            || (echo "_RBGY_HALLMARK missing"            >&2; exit 1)
test -n "${_RBGY_ARK_BASENAME_IMAGE}"  || (echo "_RBGY_ARK_BASENAME_IMAGE missing"  >&2; exit 1)
test -n "${_RBGY_ARK_BASENAME_ATTEST}" || (echo "_RBGY_ARK_BASENAME_ATTEST missing" >&2; exit 1)

test -s .hallmark || (echo "hallmark not derived" >&2; exit 1)
HALLMARK="$(cat .hallmark)"

GAR_REPO_BASE="${_RBGY_GAR_LOCATION}${_RBGY_GAR_HOST_SUFFIX}/${_RBGY_GAR_PROJECT}/${_RBGY_GAR_REPOSITORY}"
HALLMARK_BASE="${GAR_REPO_BASE}/${_RBGY_HALLMARKS_ROOT}/${HALLMARK}"
IMAGE_URI="${HALLMARK_BASE}/${_RBGY_ARK_BASENAME_IMAGE}:${HALLMARK}"
ATTEST_BASE="${HALLMARK_BASE}/${_RBGY_ARK_BASENAME_ATTEST}"

# Split platforms and suffixes into parallel arrays
# _RBGY_PLATFORMS is comma-separated: linux/amd64,linux/arm64,linux/arm/v7
# _RBGY_PLATFORM_SUFFIXES is comma-separated: -amd64,-arm64,-armv7
IFS=',' read -ra PLATFORMS <<< "${_RBGY_PLATFORMS}"
IFS=',' read -ra SUFFIXES <<< "${_RBGY_PLATFORM_SUFFIXES}"

test "${#PLATFORMS[@]}" -eq "${#SUFFIXES[@]}" \
  || (echo "Platform/suffix count mismatch: ${#PLATFORMS[@]} vs ${#SUFFIXES[@]}" >&2; exit 1)

echo "=== Per-platform pullback from ${IMAGE_URI} ==="
for IDX in "${!PLATFORMS[@]}"; do
  PLAT="${PLATFORMS[${IDX}]}"
  SUFFIX="${SUFFIXES[${IDX}]}"
  ATTEST_URI="${ATTEST_BASE}:${HALLMARK}${SUFFIX}"

  echo "--- Pulling ${PLAT} ---"
  docker pull --platform "${PLAT}" "${IMAGE_URI}"
  docker tag "${IMAGE_URI}" "${ATTEST_URI}"
  echo "Tagged: ${ATTEST_URI}"
done

echo "=== Pullback complete ==="
