#!/bin/bash
# RBGJS token-fetch — OAuth2 access token from the Cloud Build metadata server
# (Mason SA). Sole consumer: the immure residency guard's curl blob-HEAD
# (rbgjl09) — registry steps auth ambiently via gcrane (RBSCB). The token is
# fetched in-memory and never written to /workspace, which carries non-secret
# data only.
#   requires: (none — ambient metadata server)
#   provides: TOKEN
echo "Fetching OAuth2 token from metadata server"
TOKEN_JSON=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token") \
  || { echo "Failed to fetch OAuth2 token from metadata server" >&2; exit 1; }

TOKEN=$(printf '%s' "${TOKEN_JSON}" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
test -n "${TOKEN}" || { echo "Failed to extract access_token from metadata response" >&2; exit 1; }
