#!/bin/bash
# RBGJS gcrane-fingerprint — read an upstream image's raw manifest, take its
# canonical sha256 digest, and derive the sanitized-origin glance fingerprint.
# The canonical digest is the sha256 of the RAW manifest bytes (what every tool
# reports); the fingerprint is the sanitized origin (`:` and `/` become `-`) plus
# the first 10 hex of that digest — the ANCHOR tag form. `gcrane
# manifest` streams the registry's stored manifest bytes verbatim (no
# re-serialization), so the digest is byte-identical to the canonical OCI
# digest. The first GAR copy is kind-specific (its
# destination tag is itself digest-derived) and stays in the step.
#   requires: ORIGIN    upstream image ref (e.g. docker.io/library/x:tag)
#             RAW_FILE  /workspace path to write the raw manifest into
#   provides: SHA          64-hex canonical digest (no algorithm prefix)
#             FINGERPRINT  "<sanitized-origin>-<first-10-hex>"
gcrane manifest "${ORIGIN}" > "${RAW_FILE}" \
  || { echo "FATAL: Failed to read upstream manifest: ${ORIGIN}" >&2; exit 1; }

# sha256sum (busybox coreutils, not openssl) — runs inside the gcrane:debug builder.
SHA=$(sha256sum "${RAW_FILE}" | cut -d' ' -f1)
test -n "${SHA}" || { echo "FATAL: Empty digest for ${ORIGIN}" >&2; exit 1; }

# Sanitize origin (: and / become -), append first 10 hex chars (legacy anchor form).
FINGERPRINT="$(printf '%s' "${ORIGIN}" | tr ':/' '--')-${SHA:0:10}"
