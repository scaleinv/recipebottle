#!/bin/sh
# RBGJR Step 01: In-pool reliquary preflight — HEAD-check tool images and base anchors
# Builder: alpine (from reliquary)
# Substitutions: _RBGR_GAR_HOST, _RBGR_GAR_PATH, _RBGR_LODES_ROOT, _RBGR_TAG_SPRUE,
#                _RBGR_RELIQUARY,
#                _RBGR_BASE_LOCATOR_1, _RBGR_BASE_LOCATOR_2, _RBGR_BASE_LOCATOR_3
#
# Defense-in-depth: every Cloud Build job validates reliquary GAR-presence
# from the worker pool's vantage before expensive work runs. Catches divergence
# the host-side preflight cannot — airgap pool private-VPC routing, IAM split
# between Director and Mason service accounts, time skew between submission and
# execution.
#
# Coverage:
#   - Reliquary tool images (5 of 6): gcloud, docker, syft, binfmt, gcrane.
#     Alpine (this step's own image) is implicitly validated by Cloud Build
#     pulling it for step execution; failure to pull alpine produces Cloud
#     Build's own "image not pullable" error before this script runs.
#   - Base anchor locators (slots 1/2/3 if non-empty). Conjure populates
#     these; bind and graft pass them through empty.
#
# Failure mode: structured "this pool can't see «TOOL»" message naming each
# missed item. Operator remediation: re-conclave the reliquary, re-yoke the
# vessel, re-ordain the hallmark.
#
# Auth: Mason SA via Cloud Build metadata server. HEAD requests via busybox
# wget (no curl in alpine by default; apk add not viable on airgap pools).
# wget exit code is the binary signal — 0 for HTTP 2xx, non-zero otherwise.

# POSIX sh (busybox ash on alpine): pipefail is non-portable and not load-bearing
# here — the one pipe (token extract) is validated by the test -n guard below.
set -eu

test -n "${_RBGR_GAR_HOST}"   || { echo "FATAL: _RBGR_GAR_HOST missing"   >&2; exit 1; }
test -n "${_RBGR_GAR_PATH}"   || { echo "FATAL: _RBGR_GAR_PATH missing"   >&2; exit 1; }
test -n "${_RBGR_LODES_ROOT}" || { echo "FATAL: _RBGR_LODES_ROOT missing" >&2; exit 1; }
test -n "${_RBGR_TAG_SPRUE}"  || { echo "FATAL: _RBGR_TAG_SPRUE missing"  >&2; exit 1; }
test -n "${_RBGR_RELIQUARY}"  || { echo "FATAL: _RBGR_RELIQUARY missing"  >&2; exit 1; }

echo "=== In-pool reliquary preflight ==="
echo "Reliquary: ${_RBGR_RELIQUARY}"
echo "GAR base:  ${_RBGR_GAR_HOST}/${_RBGR_GAR_PATH}"

echo "Fetching OAuth2 token from metadata server"
TOKEN_JSON=$(wget -q -O - \
  --header="Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token") \
  || { echo "FATAL: Failed to fetch OAuth2 token from metadata server" >&2; exit 1; }

TOKEN=$(printf '%s' "${TOKEN_JSON}" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
test -n "${TOKEN}" || { echo "FATAL: Failed to extract access_token from metadata response" >&2; exit 1; }

ACCEPT_MTYPES="application/vnd.docker.distribution.manifest.v2+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json"

REGISTRY_API_BASE="https://${_RBGR_GAR_HOST}/v2/${_RBGR_GAR_PATH}"

MISSES=""

# Tool list mirrors the conclave cohort manifest (rbgjl03) minus alpine.
for TOOL in gcloud docker syft binfmt gcrane; do
  PKG_PATH="${_RBGR_LODES_ROOT}/${_RBGR_RELIQUARY}"
  MEMBER_TAG="${_RBGR_TAG_SPRUE}${TOOL}"
  URL="${REGISTRY_API_BASE}/${PKG_PATH}/manifests/${MEMBER_TAG}"

  echo "--- HEAD ${PKG_PATH}:${MEMBER_TAG} ---"
  if wget -q -O /dev/null \
       --header="Authorization: Bearer ${TOKEN}" \
       --header="Accept: ${ACCEPT_MTYPES}" \
       "${URL}"; then
    echo "  PRESENT: reliquary-tool ${TOOL}"
  else
    echo "  MISSING: reliquary-tool ${TOOL}"
    MISSES="${MISSES} reliquary-tool:${TOOL}"
  fi
done

# Base slots — empty for non-conjure modes; conjure populates from RBRV_IMAGE_n_ANCHOR.
# Locator format: <package-path>:<tag>; package path is itself prefixed by the
# Lode namespace already (e.g. rbi_ld/<touchmark>:rbi_bole).
for SLOT in 1 2 3; do
  case "${SLOT}" in
    1) LOCATOR="${_RBGR_BASE_LOCATOR_1}" ;;
    2) LOCATOR="${_RBGR_BASE_LOCATOR_2}" ;;
    3) LOCATOR="${_RBGR_BASE_LOCATOR_3}" ;;
  esac
  test -n "${LOCATOR}" || continue

  case "${LOCATOR}" in
    *:*) : ;;
    *)   echo "FATAL: invalid base locator format (expected package-path:tag) slot ${SLOT}: ${LOCATOR}" >&2; exit 1 ;;
  esac
  PKG_PATH="${LOCATOR%:*}"
  TAG="${LOCATOR##*:}"
  test -n "${PKG_PATH}" || { echo "FATAL: empty package path in locator slot ${SLOT}: ${LOCATOR}" >&2; exit 1; }
  test -n "${TAG}"      || { echo "FATAL: empty tag in locator slot ${SLOT}: ${LOCATOR}" >&2; exit 1; }
  URL="${REGISTRY_API_BASE}/${PKG_PATH}/manifests/${TAG}"

  echo "--- HEAD ${PKG_PATH}:${TAG} (base slot ${SLOT}) ---"
  if wget -q -O /dev/null \
       --header="Authorization: Bearer ${TOKEN}" \
       --header="Accept: ${ACCEPT_MTYPES}" \
       "${URL}"; then
    echo "  PRESENT: base-anchor slot ${SLOT}"
  else
    echo "  MISSING: base-anchor slot ${SLOT}"
    MISSES="${MISSES} base-anchor:${LOCATOR}"
  fi
done

if [ -z "${MISSES}" ]; then
  echo "=== Reliquary preflight passed — pool sees all tools and base anchors ==="
  exit 0
fi

echo "" >&2
echo "=== Reliquary preflight FAILED — this pool can't see: ===" >&2
for MISS in ${MISSES}; do
  echo "  «${MISS}»" >&2
done
echo "" >&2
echo "Defense-in-depth: every Cloud Build verifies reliquary GAR-presence from" >&2
echo "the worker pool's vantage. The Director's host-side preflight passed, but" >&2
echo "the Mason pool cannot reach one or more required artifacts. Likely causes:" >&2
echo "  - airgap pool private-VPC routing missing for these artifacts" >&2
echo "  - IAM split between Director and Mason service accounts" >&2
echo "  - time skew between host-side preflight and pool-side build execution" >&2
echo "" >&2
echo "Remediation: re-conclave reliquary, re-yoke vessel, re-ordain hallmark." >&2
exit 1
