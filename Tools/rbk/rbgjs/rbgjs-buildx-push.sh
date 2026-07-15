#!/bin/bash
# RBGJS buildx-push — push a prepared FROM-scratch build context as an image via
# the shared buildx builder (see buildx-bootstrap). The irreducible push shared
# by the FROM-scratch vouch-push callers (Lode rbgjl02, hallmark-verify rbgjv03):
# push cardinality, the destination URI, the platform set, and the context
# assembly (which JSON, conditional Dockerfile) are all done by the kind.
#   requires: PUSH_URI        full destination image ref including tag
#             PUSH_PLATFORMS  buildx --platform value (e.g. linux/amd64)
#             PUSH_CTX        build context dir holding the Dockerfile
#   provides: the image pushed to PUSH_URI
docker buildx build \
  --push \
  --platform="${PUSH_PLATFORMS}" \
  --tag "${PUSH_URI}" \
  "${PUSH_CTX}" \
  || { echo "FATAL: buildx push failed for ${PUSH_URI}" >&2; exit 1; }
