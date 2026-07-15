#!/bin/bash
# RBGJL Step 05: Wrap the verified WSL rootfs into a Lode member via gcrane append
# Builder: gcr.io/go-containerregistry/gcrane:debug (floating bootstrap — wsl pinning is
#          deferred to the bootstrap-builder digest-pin itch; gcrane auths GAR ambiently
#          via google.Keychain -> ADC -> the GCE metadata server as the Mason SA. The
#          :debug variant carries /busybox/sh. Auth canon: RBSCB)
# Substitutions: _RBGL_GAR_HOST, _RBGL_GAR_PATH, _RBGL_LODES_ROOT, _RBGL_LODE_STAMP,
#                _RBGL_TAG_ROOTFS
#
# Step 04 (Debian builder: curl + gpg) fetched the vendor rootfs, GPG-verified it
# against the published checksum, authored the provenance envelope, and staged the
# opaque tarball at /workspace/underpin_ctx_<stamp>/rootfs.tar (a context dir holding
# ONLY rootfs.tar). This step wraps that tarball as a FROM-scratch single-layer OCI
# member and pushes it under :rbi_rootfs. The split exists because the fetch/verify
# tools (curl, gpg) and the wrap tool (gcrane) live in disjoint builder images —
# gcrane:debug busybox carries neither curl nor gpg.

set -euo pipefail
echo "=== Wrap verified WSL rootfs into a Lode member (gcrane append) ==="

STAMP="${_RBGL_LODE_STAMP}"
test -n "${STAMP}" || { echo "FATAL: _RBGL_LODE_STAMP missing" >&2; exit 1; }
test -n "${_RBGL_TAG_ROOTFS}" || { echo "FATAL: _RBGL_TAG_ROOTFS missing" >&2; exit 1; }

PKG="${_RBGL_GAR_HOST}/${_RBGL_GAR_PATH}/${_RBGL_LODES_ROOT}/${STAMP}"
DEST="${PKG}:${_RBGL_TAG_ROOTFS}"

# Guard the inter-step handoff (CBi_102): step 04 must have fetched, verified, and
# staged the rootfs before this step can wrap it.
CTX="/workspace/underpin_ctx_${STAMP}"
test -f "${CTX}/rootfs.tar" \
  || { echo "FATAL: rootfs not staged at ${CTX}/rootfs.tar — step 04 must run first" >&2; exit 1; }

echo "--- Wrapping rootfs -> ${DEST} ---"
APPEND_CTX="${CTX}"
APPEND_URI="${DEST}"
#@rbgjs_include gcrane-append

echo "Rootfs member pushed: ${DEST}"
echo "=== Wrap step complete ==="
