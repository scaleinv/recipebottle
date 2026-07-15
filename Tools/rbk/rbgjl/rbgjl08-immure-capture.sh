#!/bin/bash
# RBGJL Step 08: Copy the selected podvm disk leaves into a Lode via gcrane (capture)
# Builder: gcr.io/go-containerregistry/gcrane:debug (floating bootstrap — podvm is
#          vessel-less like wsl, so its tool-pinning defers to the bootstrap-builder
#          digest-pin itch, RBS0 rbsk_pinning_boundary. gcrane reads the PUBLIC quay
#          source anonymously and auths the GAR push ambiently via google.Keychain
#          -> ADC -> the GCE metadata server as the Mason SA, no explicit login. The
#          :debug variant carries /busybox/sh. Auth canon: RBSCB)
# Substitutions: _RBGL_GAR_HOST, _RBGL_GAR_PATH, _RBGL_LODES_ROOT, _RBGL_LODE_STAMP,
#                _RBGL_PODVM_FAMILY
#
# Step 07 (python3 on the gcloud builder) anon-read the quay family index, selected the
# curated leaves by descriptor platform+disktype, and staged the selection list at
# /workspace/immure_selection.txt (one row: member_tag|leaf_digest|blob_digest|
# blob_size). This step gcrane-cp's each leaf BY DIGEST from the family repo into the
# ONE GAR package rbi_ld/<stamp> under its member tag, then confirms the copy is
# digest-faithful (cheap manifest readback; the blob Content-Length residency guard
# is rbgjl09). The split exists because parsing the structured upstream index belongs
# in python (CBG CBp_ rules), which the gcrane:debug busybox shell cannot host —
# registry copy is gcrane's job, index parsing is python's.
#
# gcrane cp <family>@<leaf-digest> is get-or-error (the loud failure the recorded
# trust grade wants) and preserves the manifest digest byte-for-byte (memo-20260608
# §4). Each selected leaf is a single-platform manifest, so the Lode package stays a
# FLAT package (no parent-index web) — banish stays single-call atomic by
# construction (RBSLB). Do not capture the family index itself; that would web the
# package.

set -euo pipefail
echo "=== Copy selected podvm disk leaves into a Lode (gcrane cp by digest) ==="

STAMP="${_RBGL_LODE_STAMP}"
FAMILY="${_RBGL_PODVM_FAMILY}"
test -n "${STAMP}"  || { echo "FATAL: _RBGL_LODE_STAMP missing"   >&2; exit 1; }
test -n "${FAMILY}" || { echo "FATAL: _RBGL_PODVM_FAMILY missing" >&2; exit 1; }

# Guard the inter-step handoff (CBi_102): step 07 must have selected the leaves.
# An EMPTY selection is legitimate — an all-preserved refresh (every curated leaf
# already held) adds no new leaf, so step 07 writes an empty list and this loop
# no-ops. Only a MISSING file means step 07 never ran; guard on -f, not -s.
test -f /workspace/immure_selection.txt \
  || { echo "FATAL: /workspace/immure_selection.txt missing — step 07 must run first" >&2; exit 1; }

PKG="${_RBGL_GAR_HOST}/${_RBGL_GAR_PATH}/${_RBGL_LODES_ROOT}/${STAMP}"
echo "Lode package: ${PKG}"

while IFS='|' read -r MEMBER_TAG LEAF_DIGEST BLOB_DIGEST BLOB_SIZE; do
  test -n "${MEMBER_TAG}" || continue
  SRC="${FAMILY}@${LEAF_DIGEST}"
  DEST="${PKG}:${MEMBER_TAG}"
  echo "--- ${MEMBER_TAG}: ${SRC} -> ${DEST} ---"

  # Copy registry->registry by digest, daemonless (no docker pull/tag/push). The
  # leaf is a single-platform OCI artifact (empty config + one zstd blob); gcrane cp
  # copies the manifest and its blob and preserves the manifest digest.
  # < /dev/null: keep in-loop tools off the while-read stdin (a child reading
  # stdin would consume the remaining selection rows; busybox sh has no arrays,
  # so the belt beats load-then-iterate).
  gcrane cp "${SRC}" "${DEST}" < /dev/null \
    || { echo "FATAL: gcrane cp failed for ${SRC} -> ${DEST}" >&2; exit 1; }

  # Cheap manifest-level integrity check (free on this builder): the copied tag must
  # resolve to the same digest we selected. The deeper blob Content-Length residency
  # guard is rbgjl09 (needs curl — a Debian step). CBb_101 applies.
  DEST_DIGEST=$(gcrane digest "${DEST}" < /dev/null) \
    || { echo "FATAL: gcrane digest failed for ${DEST}" >&2; exit 1; }
  test "${DEST_DIGEST}" = "${LEAF_DIGEST}" \
    || { echo "FATAL: copied digest mismatch for ${MEMBER_TAG} — ${DEST_DIGEST} != ${LEAF_DIGEST}" >&2; exit 1; }

  echo "${MEMBER_TAG} captured: ${DEST} (${DEST_DIGEST})"
done < /workspace/immure_selection.txt

echo "=== Immure capture step complete ==="
