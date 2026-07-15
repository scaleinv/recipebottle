#!/bin/bash
# RBGJS buildx-bootstrap — ensure the shared docker-container buildx builder
# exists and is selected. Idempotent under Cloud Build retry: inspect-or-create,
# then use. Run once per step before any push; safe to re-run (a second inspect
# succeeds, create is skipped, use is a no-op).
#   requires: (none)
#   provides: the "rb-builder" buildx builder, created if absent and selected
docker buildx inspect rb-builder >/dev/null 2>&1 \
  || docker buildx create --driver docker-container --name rb-builder
docker buildx use rb-builder
