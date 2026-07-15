#!/bin/bash
# RBGJL Step 03: Conclave the build-tool cohort into a Lode (capture) via gcrane
# Builder: gcr.io/go-containerregistry/gcrane:debug (Google-hosted, always pullable —
#          conclave captures the reliquary tools themselves, so it cannot bootstrap
#          from a reliquary; gcrane authenticates GAR ambiently via its google.Keychain
#          -> ADC -> the GCE metadata server as the Mason SA, no explicit login. The
#          :debug variant carries /busybox/sh for the orchestration. Auth canon: RBSCB)
# Substitutions: _RBGL_GAR_HOST, _RBGL_GAR_PATH, _RBGL_LODES_ROOT, _RBGL_LODE_STAMP,
#                _RBGL_TAG_SPRUE, _RBGL_TRUST_GRADE, _RBGL_VOUCH_SCHEMA,
#                _RBGL_ACQUIRED_BY
#
# Pull each build-tool image from upstream, tag it into ONE GAR package
# rbi_ld/<stamp> under the clean member tag :rbi_<tool>, and push. Author the
# batch provenance envelope (members[] one per tool — the cardinality axis) and
# stage it for step 02 (the :rbi_vouch artifact) and for the host capture-file via
# /builder/outputs/output. Single-platform (linux/amd64) — tool images run as GCB
# steps on amd64 workers; gcrane cp --platform linux/amd64 copies just the amd64
# manifest registry->registry (daemonless — no docker daemon, no pull/tag/push).
#
# Package shape:  <host>/<path>/<LODES_ROOT>/<stamp>     (one package = one Lode)
# Member tags on that package, each a distinct tool manifest:
#   :<TAG_SPRUE><tool>   e.g. rbi_gcloud, rbi_gcrane   (clean scheme — no digest layer)
# The :rbi_vouch tag is a separate manifest pushed by step 02.

set -euo pipefail
echo "=== Conclave build-tool cohort into a Lode ==="

STAMP="${_RBGL_LODE_STAMP}"
test -n "${STAMP}" || { echo "FATAL: _RBGL_LODE_STAMP missing" >&2; exit 1; }

PKG="${_RBGL_GAR_HOST}/${_RBGL_GAR_PATH}/${_RBGL_LODES_ROOT}/${STAMP}"
echo "Lode package: ${PKG}"

# Tool image cohort (short-name|upstream-ref) — the authoritative co-versioned set
# for GCB step execution. gcloud,
# docker, and gcrane are Google-hosted (gcr.io); the rest are third-party. gcrane
# rides the :debug variant so the resolved cohort member keeps the /busybox/sh shell
# its capture steps need.
# The cohort is the heredoc feeding the while-read loop at its `done`, below — this
# step runs under /busybox/sh (gcrane:debug's only shell), which has no bash arrays,
# so the cohort cannot be expressed as a bash `MANIFEST=( … )` array; a while-read
# over a `|`-split heredoc is the POSIX form, matching rbgjl02's stamp loop.

# Acquisition moment, attested once for the whole cohort.
ACQUIRED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Accumulate the envelope members[] as we capture (one element per tool). No jq
# dependency — values are controlled (tool name, upstream ref, hex digest, SA
# email, build id, ISO timestamp); none can carry a literal quote.
MEMBERS=''
MFIRST=true

while IFS='|' read -r NAME UPSTREAM; do
  test -n "${NAME}" || continue
  MEMBER_TAG="${_RBGL_TAG_SPRUE}${NAME}"
  DEST="${PKG}:${MEMBER_TAG}"

  echo "--- ${NAME}: ${UPSTREAM} -> ${DEST} ---"

  # gcrane cp copies registry->registry by digest, daemonless (no docker pull/tag/push).
  # --platform linux/amd64 flattens a multi-arch upstream to the SINGLE amd64 manifest.
  # This is conclave-ONLY and must not leak to other Lode kinds (bole/wsl keep full-
  # fidelity capture): the reliquary cohort is consumed solely as GCB step images on
  # amd64 workers, so the other platforms are dead bytes — and a full multi-arch index
  # makes the Lode package a parent-index/child-manifest web, where GAR refuses to
  # delete a child while its parent index exists (FAILED_PRECONDITION, "referenced by
  # parent manifests") and a single packages.delete removes nothing — banish then
  # needs multiple convergence rounds instead of one. References: RBSLC, RBSLB, RBSCB.
  gcrane --platform linux/amd64 cp "${UPSTREAM}" "${DEST}" \
    || { echo "FATAL: gcrane cp failed for ${UPSTREAM} -> ${DEST}" >&2; exit 1; }

  # Record the upstream manifest-list digest for the envelope. gcrane digest (no
  # --platform) streams the tag's stored index digest (sha256:...) — the same canonical
  # value docker's RepoDigests reported, unchanged by the single-platform copy above, so
  # recorded digests stay identical to the pre-eviction docker path. CBb_101 applies.
  DIGEST=$(gcrane digest "${UPSTREAM}") \
    || { echo "FATAL: gcrane digest failed for ${UPSTREAM}" >&2; exit 1; }
  test -n "${DIGEST}" || { echo "FATAL: empty digest for ${UPSTREAM}" >&2; exit 1; }

  echo "${NAME} captured: ${DEST} (${DIGEST})"

  if [ "${MFIRST}" = "true" ]; then MFIRST=false; else MEMBERS="${MEMBERS},"; fi
  MEMBERS="${MEMBERS}{"
  MEMBERS="${MEMBERS}\"rblv_name\":\"${MEMBER_TAG}\","
  MEMBERS="${MEMBERS}\"rblv_origin\":\"${UPSTREAM}\","
  MEMBERS="${MEMBERS}\"rblv_digest\":\"${DIGEST}\","
  MEMBERS="${MEMBERS}\"rblv_verification\":\"oci-digest\","
  MEMBERS="${MEMBERS}\"rblv_tags\":[\"${MEMBER_TAG}\"]"
  MEMBERS="${MEMBERS}}"
done <<'MANIFEST'
gcloud|gcr.io/cloud-builders/gcloud:latest
docker|gcr.io/cloud-builders/docker:latest
alpine|docker.io/library/alpine:latest
syft|docker.io/anchore/syft:latest
binfmt|docker.io/tonistiigi/binfmt:latest
gcrane|gcr.io/go-containerregistry/gcrane:debug
MANIFEST

# Author the batch provenance envelope (identical content lands in :rbi_vouch and
# the host capture-file). rblv_members[] is the cardinality axis — N for the reliquary
# cohort, where bole carries 1.
ENVELOPE='{'
ENVELOPE="${ENVELOPE}\"rblv_schema\":\"${_RBGL_VOUCH_SCHEMA}\","
ENVELOPE="${ENVELOPE}\"rblv_kind\":\"reliquary\","
ENVELOPE="${ENVELOPE}\"rblv_lode\":\"${STAMP}\","
ENVELOPE="${ENVELOPE}\"rblv_acquired_at\":\"${ACQUIRED_AT}\","
ENVELOPE="${ENVELOPE}\"rblv_acquired_by\":\"${_RBGL_ACQUIRED_BY}\","
ENVELOPE="${ENVELOPE}\"rblv_capture_build\":\"${BUILD_ID:-}\","
ENVELOPE="${ENVELOPE}\"rblv_trust_grade\":\"${_RBGL_TRUST_GRADE}\","
ENVELOPE="${ENVELOPE}\"rblv_signature\":null,"
ENVELOPE="${ENVELOPE}\"rblv_members\":[${MEMBERS}]}"

# Stage the envelope for step 02 (pushes it as the :rbi_vouch artifact). The
# stamps file is the step-02 contract; conclave produces exactly one Lode.
printf '%s' "${ENVELOPE}" > "/workspace/lode_${STAMP}_vouch.json"
: > /workspace/lode_stamps.txt
echo "${STAMP}" >> /workspace/lode_stamps.txt

# Host-facing result (the capture-file carries the same envelope). One slot —
# conclave produces exactly one Lode (the cohort is one package).
RESULT="{\"rbls_slot_1\":{\"rbls_stamp\":\"${STAMP}\",\"rbls_vouch\":${ENVELOPE}}}"

echo "=== Writing capture results ==="
echo "${RESULT}"

# Write to buildStepOutputs channel (host extracts the touchmark -> capture-file).
mkdir -p /builder/outputs
printf '%s' "${RESULT}" > /builder/outputs/output

echo "=== Conclave capture step complete ==="
