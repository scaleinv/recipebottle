#!/bin/bash
# RBGJS gcrane-append — push a prepared directory as a FROM-scratch single-layer OCI
# image via `gcrane append --oci-empty-base`. The Lode-family replacement for the
# buildx-bootstrap + buildx-push pair: gcrane needs no builder bootstrap and no daemon.
# Forked deliberately rather than converting buildx-push in place — that snippet is
# still @rbgjs_include'd by the made-side multi-platform hallmark vouch (rbgjv03),
# outside the Lode family and out of this scope. Single-platform by construction (one
# appended layer over an empty OCI base). Idempotent under retry (CBi_103): re-appending
# identical bytes to the same tag yields an identical digest.
#   requires: APPEND_CTX  dir whose entire contents become the single layer
#                         (files land at image root, matching buildx `COPY x /`)
#             APPEND_URI  full destination image ref including tag
#   provides: the FROM-scratch image pushed to APPEND_URI
APPEND_TAR="${APPEND_CTX%/}.layer.tar"
tar -C "${APPEND_CTX}" -cf "${APPEND_TAR}" . \
  || { echo "FATAL: failed to tar layer from ${APPEND_CTX}" >&2; exit 1; }
gcrane append --oci-empty-base -f "${APPEND_TAR}" -t "${APPEND_URI}" \
  || { echo "FATAL: gcrane append failed for ${APPEND_URI}" >&2; exit 1; }
