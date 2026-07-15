#!/bin/bash
# RBGJL Step 09: Blob-residency guard for the captured podvm leaves (anti-hollow-mirror)
# Builder: gcr.io/cloud-builders/docker (Google-hosted, Debian — carries curl; the
#          gcrane:debug capture builder has no curl, so the registry-v2 HEAD guard
#          lives here, after the cp). The Mason SA token comes from the metadata
#          server (rbgjs token-fetch).
# Substitutions: _RBGL_GAR_HOST, _RBGL_GAR_PATH, _RBGL_LODES_ROOT, _RBGL_LODE_STAMP
#
# Note: this script runs inside a Cloud Build container, not under BCG module
# discipline (CBG governs).
#
# Step 08 gcrane-cp'd each selected leaf into rbi_ld/<stamp> and confirmed the
# MANIFEST digest is faithful. This step confirms the BLOB BYTES actually reside: a
# GAR registry-v2 blob HEAD returns Content-Length; assert it equals the leaf
# manifest's declared layer size (staged by rbgjl07 in the selection list). This is
# the anti-hollow-mirror guard the recorded trust grade demands — a registry can
# hold a manifest whose large layer never fully landed; the digest check alone would
# not catch it (memo-20260608 §1, proven against 1.13 GB / 245 MB / 200 MB / 194 MB
# blobs). curl HEAD, no image tool, no blob download.

set -euo pipefail
echo "=== Blob-residency guard for captured podvm leaves ==="

STAMP="${_RBGL_LODE_STAMP}"
test -n "${STAMP}" || { echo "FATAL: _RBGL_LODE_STAMP missing" >&2; exit 1; }

# Guard the inter-step handoff (CBi_102): the selection list is the residency contract.
# An EMPTY list is legitimate (all-preserved refresh — no new leaf to residency-check),
# so guard on -f (step 07 ran), not -s; the loop below no-ops on an empty file.
test -f /workspace/immure_selection.txt \
  || { echo "FATAL: /workspace/immure_selection.txt missing — step 07 must run first" >&2; exit 1; }

# Mason SA OAuth token from the metadata server (provides TOKEN).
#@rbgjs_include token-fetch

GAR_IMAGE="${_RBGL_GAR_PATH}/${_RBGL_LODES_ROOT}/${STAMP}"
echo "GAR image path: ${GAR_IMAGE}"

while IFS='|' read -r MEMBER_TAG LEAF_DIGEST BLOB_DIGEST BLOB_SIZE; do
  test -n "${MEMBER_TAG}" || continue
  echo "--- Residency: ${MEMBER_TAG} (${BLOB_DIGEST}) expecting ${BLOB_SIZE} bytes ---"

  BLOB_URL="https://${_RBGL_GAR_HOST}/v2/${GAR_IMAGE}/blobs/${BLOB_DIGEST}"
  HEAD_FILE="/workspace/immure_head_${MEMBER_TAG}.txt"
  # < /dev/null: keep curl off the while-read stdin (a child reading stdin
  # would consume the remaining selection rows).
  curl -sfI -H "Authorization: Bearer ${TOKEN}" "${BLOB_URL}" -o "${HEAD_FILE}" < /dev/null \
    || { echo "FATAL: blob HEAD failed for ${MEMBER_TAG} at ${BLOB_URL}" >&2; exit 1; }

  # Content-Length, case-insensitive header, strip CR. awk's END keeps the last
  # match (a redirect chain would append; the registry-v2 endpoint answers HEAD
  # directly per the memo). grep+awk only — tail/tr are outside the GCB allowlist.
  ACTUAL_LEN=$(grep -i 'content-length:' "${HEAD_FILE}" | awk 'END{gsub(/\r/,"",$2); print $2}')
  test -n "${ACTUAL_LEN}" \
    || { echo "FATAL: no Content-Length in HEAD response for ${MEMBER_TAG}" >&2; exit 1; }

  if [ "${ACTUAL_LEN}" != "${BLOB_SIZE}" ]; then
    echo "FATAL: hollow mirror — ${MEMBER_TAG} blob Content-Length ${ACTUAL_LEN} != declared ${BLOB_SIZE}" >&2
    exit 1
  fi
  echo "${MEMBER_TAG}: ${ACTUAL_LEN} bytes resident (matches declared size)"
done < /workspace/immure_selection.txt

echo "=== Immure residency guard complete ==="
