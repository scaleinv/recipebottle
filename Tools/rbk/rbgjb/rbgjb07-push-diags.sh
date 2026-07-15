#!/bin/bash
# RBGJB Step 07: Push diagnostic files as diags registry artifact
# Builder: gcr.io/cloud-builders/docker
# Substitutions: _RBGY_DOCKERFILE,
#                _RBGY_GAR_LOCATION, _RBGY_GAR_PROJECT, _RBGY_GAR_REPOSITORY,
#                _RBGY_GAR_HOST_SUFFIX, _RBGY_HALLMARKS_ROOT, _RBGY_HALLMARK,
#                _RBGY_ARK_BASENAME_DIAGS
#
# Builds a FROM scratch container containing conjure build-time diagnostic files
# and pushes as the diags ark. The about pipeline (rbgja01) pulls this
# artifact and merges its contents into the about container.
#
# Files included:
#   buildkit_metadata.json  - BuildKit resolved base images and build parameters (from step 04)
#   cache_before.json       - Docker daemon state before build (from step 04)
#   cache_after.json        - Docker daemon state after pushes (from step 06)
#   recipe.txt              - Dockerfile content (no size limit, unlike substitution variable)
#
# The diags artifact persists in the registry as a durable record.
# Abjure cleans it up alongside image, about, and vouch.

set -euo pipefail

test -n "${_RBGY_GAR_LOCATION}"        || (echo "_RBGY_GAR_LOCATION missing"        >&2; exit 1)
test -n "${_RBGY_GAR_PROJECT}"         || (echo "_RBGY_GAR_PROJECT missing"         >&2; exit 1)
test -n "${_RBGY_GAR_REPOSITORY}"      || (echo "_RBGY_GAR_REPOSITORY missing"      >&2; exit 1)
test -n "${_RBGY_GAR_HOST_SUFFIX}"     || (echo "_RBGY_GAR_HOST_SUFFIX missing"     >&2; exit 1)
test -n "${_RBGY_HALLMARKS_ROOT}"      || (echo "_RBGY_HALLMARKS_ROOT missing"      >&2; exit 1)
test -n "${_RBGY_HALLMARK}"            || (echo "_RBGY_HALLMARK missing"            >&2; exit 1)
test -n "${_RBGY_DOCKERFILE}"          || (echo "_RBGY_DOCKERFILE missing"          >&2; exit 1)
test -n "${_RBGY_ARK_BASENAME_DIAGS}"  || (echo "_RBGY_ARK_BASENAME_DIAGS missing"  >&2; exit 1)

test -s .hallmark || (echo "hallmark not derived" >&2; exit 1)
HALLMARK="$(cat .hallmark)"

GAR_REPO_BASE="${_RBGY_GAR_LOCATION}${_RBGY_GAR_HOST_SUFFIX}/${_RBGY_GAR_PROJECT}/${_RBGY_GAR_REPOSITORY}"
DIAGS_URI="${GAR_REPO_BASE}/${_RBGY_HALLMARKS_ROOT}/${HALLMARK}/${_RBGY_ARK_BASENAME_DIAGS}:${HALLMARK}"

echo "=== Building diags artifact ==="

# Copy Dockerfile to recipe.txt (full content, no substitution variable size limit)
cp "${_RBGY_DOCKERFILE}" recipe.txt
echo "recipe.txt written ($(wc -c < recipe.txt | tr -d ' ') bytes)"

# Generate Dockerfile for scratch container (include only files that exist)
{
  echo 'FROM scratch'
  test -f buildkit_metadata.json && echo 'COPY buildkit_metadata.json /buildkit_metadata.json'
  test -f cache_before.json      && echo 'COPY cache_before.json /cache_before.json'
  test -f cache_after.json       && echo 'COPY cache_after.json /cache_after.json'
  test -f recipe.txt             && echo 'COPY recipe.txt /recipe.txt'
} > Dockerfile.diags

echo "--- Dockerfile.diags contents ---"
cat Dockerfile.diags
echo "--- end ---"

docker build -t "${DIAGS_URI}" -f Dockerfile.diags .
docker push "${DIAGS_URI}"

echo "Diags pushed: ${DIAGS_URI}"
