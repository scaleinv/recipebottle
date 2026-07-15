#!/bin/bash
# RBGJAM Step 04: Build and push multi-platform metadata (about) container
# Builder: gcr.io/cloud-builders/docker
# Substitutions: _RBGA_GAR_HOST, _RBGA_GAR_PATH, _RBGA_HALLMARKS_ROOT,
#                _RBGA_HALLMARK, _RBGA_ARK_BASENAME_ABOUT
#
# Builds a FROM scratch container where TARGETARCH/TARGETVARIANT
# auto-args select the per-platform SBOM and build_info files.
# For single-platform images, builds a single-platform container.
# For multi-platform images, uses buildx --push.
#
# File naming convention (matches step 02/03 outputs):
#   sbom-{arch}{variant}.json       -> /sbom.json
#   build_info-{arch}{variant}.json -> /build_info.json
#   recipe.txt                      -> /recipe.txt (optional, from step 03)
#
# No QEMU needed: scratch images have no executables — just file copies
# with platform annotations.

set -euo pipefail

test -n "${_RBGA_GAR_HOST}"          || { echo "_RBGA_GAR_HOST missing"          >&2; exit 1; }
test -n "${_RBGA_GAR_PATH}"          || { echo "_RBGA_GAR_PATH missing"          >&2; exit 1; }
test -n "${_RBGA_HALLMARKS_ROOT}"    || { echo "_RBGA_HALLMARKS_ROOT missing"    >&2; exit 1; }
test -n "${_RBGA_HALLMARK}"          || { echo "_RBGA_HALLMARK missing"          >&2; exit 1; }
test -n "${_RBGA_ARK_BASENAME_ABOUT}" || { echo "_RBGA_ARK_BASENAME_ABOUT missing" >&2; exit 1; }

test -s platforms.txt         || { echo "platforms.txt not found (step 01)" >&2; exit 1; }
test -s platform_suffixes.txt || { echo "platform_suffixes.txt not found (step 01)" >&2; exit 1; }
test -s platform_count.txt    || { echo "platform_count.txt not found (step 01)" >&2; exit 1; }

META_URI="${_RBGA_GAR_HOST}/${_RBGA_GAR_PATH}/${_RBGA_HALLMARKS_ROOT}/${_RBGA_HALLMARK}/${_RBGA_ARK_BASENAME_ABOUT}:${_RBGA_HALLMARK}"
PLATFORMS=$(cat platforms.txt)
PLATFORM_COUNT=$(cat platform_count.txt)

# Generate Dockerfile.meta
# TARGETARCH and TARGETVARIANT are automatic buildx args
{
  echo 'FROM scratch'
  echo 'ARG TARGETARCH'
  echo 'ARG TARGETVARIANT'
  echo 'LABEL org.opencontainers.image.title="rbia-metadata"'
  echo 'COPY sbom-${TARGETARCH}${TARGETVARIANT}.json /sbom.json'
  echo 'COPY build_info-${TARGETARCH}${TARGETVARIANT}.json /build_info.json'
  if test -f recipe.txt; then
    echo 'COPY recipe.txt /recipe.txt'
  fi
  if test -f buildkit_metadata.json; then
    echo 'COPY buildkit_metadata.json /buildkit_metadata.json'
  fi
  if test -f cache_before.json; then
    echo 'COPY cache_before.json /cache_before.json'
  fi
  if test -f cache_after.json; then
    echo 'COPY cache_after.json /cache_after.json'
  fi
} > Dockerfile.meta

echo "=== Building about container ==="
echo "Platforms: ${PLATFORMS}"
echo "Target: ${META_URI}"

# Create buildx builder (inspect-or-create pattern)
docker buildx inspect rb-about-builder >/dev/null 2>&1 \
  || docker buildx create --driver docker-container --name rb-about-builder
docker buildx use rb-about-builder

docker buildx build \
  --push \
  --platform="${PLATFORMS}" \
  --tag "${META_URI}" \
  -f Dockerfile.meta \
  .

echo "About pushed: ${META_URI}"
