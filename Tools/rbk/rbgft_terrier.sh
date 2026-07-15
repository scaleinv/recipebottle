#!/bin/bash
#
# Copyright 2025 Scale Invariant, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Brad Hyslop <bhyslop@scaleinvariant.org>
#
# Recipe Bottle Federation Terrier - muniment access sub-operations
#
# The data layer over a provisioned terrier: the atomic sub-operations engross /
# expunge / peruse / peruse_manor that touch the Manor-homed terrier bucket, each
# a single conditioned REST call whose atomicity Cloud Storage adjudicates (no
# external lock, no cloud-build invocation). brevet / unseat / rehearse are the
# civic wrappers that compose these — rehearse over the manor-wide read; this
# module carries no lock logic and no IAM — it is glue over a service.
#
# A muniment is one GCS object per (principal subject, mantle held) pair — the
# settled per-entry granularity, the exact mirror of the pool-scoped IAM grant it
# records. Its object name indexes the pair under the polity managed folder; its
# content is the authoritative record (peruse reconstructs the holding from
# content — only the depot attribution column reads from the key, placement being
# the index's alone to tell). No provider dimension: the grantable principal
# names the pool and subject, never the asserting provider (RBSTN), so two
# foedera admitting the same subject onto the same mantle hold the SAME grant —
# one muniment, not two. Per-entry muniments are immutable: a holding exists or
# it does not, so engross is a create (ifGenerationMatch=0) and expunge a delete —
# the RBSTR generation-conditional update path is unexercised under this
# granularity.
#
# Callers authenticate and pass the bearer token (token-first), like the rbgb_
# bucket primitives: the payor reads/writes as project owner today; a donned
# governor mantle writes own-polity once admission lands. The muniment wire keys
# live under the rbgft_ sprue (rbgft_subject, rbgft_mantle).

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBGFT_SOURCED:-}" || buc_die "Module rbgft multiply sourced - check sourcing hierarchy"
ZRBGFT_SOURCED=1

######################################################################
# Internal Functions (zrbgft_*)

zrbgft_kindle() {
  test -z "${ZRBGFT_KINDLED:-}" || buc_die "Module rbgft already kindled"

  buc_log_args "Ensure dependencies are kindled first"
  zrbgc_sentinel
  zrbuh_sentinel

  readonly ZRBGFT_PREFIX="${BURD_TEMP_DIR}/rbgft_"
  readonly ZRBGFT_MUNIMENT_BODY="${ZRBGFT_PREFIX}muniment.json"

  # Infix values for HTTP operations
  readonly ZRBGFT_INFIX_ENGROSS="terrier_engross"
  readonly ZRBGFT_INFIX_EXPUNGE="terrier_expunge"
  readonly ZRBGFT_INFIX_PERUSE_LIST="terrier_peruse_list"
  readonly ZRBGFT_INFIX_PERUSE_GET="terrier_peruse_get"
  readonly ZRBGFT_INFIX_PERUSE_MANOR_LIST="terrier_peruse_manor_list"
  readonly ZRBGFT_INFIX_PERUSE_MANOR_GET="terrier_peruse_manor_get"
  readonly ZRBGFT_INFIX_ESCHEAT_LIST="terrier_escheat_list"
  readonly ZRBGFT_INFIX_ESCHEAT_GET="terrier_escheat_get"
  readonly ZRBGFT_INFIX_ESCHEAT_EXPUNGE="terrier_escheat_expunge"

  # Escheat survey run counter — mutable kindle state. Each survey invocation
  # takes fresh temp filenames (the verb surveys twice per dispatch: plan, then
  # verify), preserving both runs' forensics.
  z_rbgft_escheat_run=0

  readonly ZRBGFT_KINDLED=1
}

zrbgft_sentinel() {
  test "${ZRBGFT_KINDLED:-}" = "1" || buc_die "Module rbgft not kindled - call zrbgft_kindle first"
}

# Compose the muniment object name: the per-entry index under the polity managed
# folder. Three structural segments — <depot>/<mantle>/<subject> — the depot
# leads (the managed-folder grain) and the raw principal subject trails (it
# alone may carry its own slashes); the whole name is percent-encoded once at
# transit time by the caller (rbuh_urlencode_capture), matching the rbgb_
# object idiom.
zrbgft_muniment_name_capture() {
  zrbgft_sentinel
  local -r z_depot="${1}"
  local -r z_mantle="${2}"
  local -r z_subject="${3}"
  test -n "${z_depot}"    || return 1
  test -n "${z_mantle}"   || return 1
  test -n "${z_subject}"  || return 1
  printf '%s/%s/%s' "${z_depot}" "${z_mantle}" "${z_subject}"
}

######################################################################
# External Functions (rbgft_*)
#
# engross / expunge echo a one-word disposition on stdout (their only stdout
# output; all human logging routes to stderr); peruse echoes one muniment per
# line. Callers capture the disposition to assert the precondition outcome.

# rbgft_engross <token> <bucket> <depot_project_id> <mantle> <subject>
# Write the muniment for (subject, mantle) into the depot's polity slice.
# ifGenerationMatch=0 create — Cloud Storage writes only if absent. Echoes
# "created" on a fresh write (200/201) or "present" on the 412 precondition
# (RBSTR: a duplicate create is idempotent success, the muniment already holds).
# Any other code rejects in the engross band (BUBC_band_engross).
rbgft_engross() {
  zrbgft_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket="${2:-}"
  local -r z_depot="${3:-}"
  local -r z_mantle="${4:-}"
  local -r z_subject="${5:-}"

  test -n "${z_token}"    || buc_die "Token required"
  test -n "${z_bucket}"   || buc_die "Bucket required"
  test -n "${z_depot}"    || buc_die "Depot project id required"
  test -n "${z_mantle}"   || buc_die "Mantle required"
  test -n "${z_subject}"  || buc_die "Principal subject required"

  buc_step "Engross muniment (${z_mantle}) for ${z_subject}"

  buc_log_args 'Build the authoritative muniment body — the key is only the index'
  jq -n --arg subject "${z_subject}" --arg mantle "${z_mantle}" \
    '{rbgft_subject: $subject, rbgft_mantle: $mantle}' > "${ZRBGFT_MUNIMENT_BODY}" \
    || buc_die "Failed to build muniment JSON"

  local z_objname
  z_objname=$(zrbgft_muniment_name_capture "${z_depot}" "${z_mantle}" "${z_subject}") \
    || buc_die "Failed to compose muniment object name"
  local z_name_enc
  z_name_enc=$(rbuh_urlencode_capture "${z_objname}") || buc_die "Failed to encode object name"

  buc_log_args 'Media upload with ifGenerationMatch=0 — create only if absent; concurrent creators race cleanly (RBSTR)'
  local -r z_url="${RBGC_API_ROOT_STORAGE}${RBGC_STORAGE_JSON_UPLOAD}/b/${z_bucket}/o?uploadType=media&name=${z_name_enc}&ifGenerationMatch=0"
  rbuh_json "POST" "${z_url}" "${z_token}" "${ZRBGFT_INFIX_ENGROSS}" "${ZRBGFT_MUNIMENT_BODY}"

  local z_code
  z_code=$(rbuh_code_capture "${ZRBGFT_INFIX_ENGROSS}") || buc_die "Bad engross HTTP code"
  case "${z_code}" in
    200|201) buc_success "Muniment engrossed (${z_mantle}, ${z_subject})"; echo "created" ;;
    412)     buc_info    "Muniment already present, idempotent (${z_mantle}, ${z_subject})"; echo "present" ;;
    *)       local z_err
             z_err=$(rbuh_json_field_capture "${ZRBGFT_INFIX_ENGROSS}" '.error.message') || z_err="HTTP ${z_code}"
             buc_reject "${BUBC_band_engross}" "Failed to engross muniment (HTTP ${z_code}): ${z_err}" ;;
  esac
}

# rbgft_expunge <token> <bucket> <depot_project_id> <mantle> <subject>
# Withdraw the muniment for (subject, mantle). Echoes "deleted" (204) or
# "absent" (404 — idempotent, already struck from the record). Any other code
# rejects in the expunge band (BUBC_band_expunge).
rbgft_expunge() {
  zrbgft_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket="${2:-}"
  local -r z_depot="${3:-}"
  local -r z_mantle="${4:-}"
  local -r z_subject="${5:-}"

  test -n "${z_token}"    || buc_die "Token required"
  test -n "${z_bucket}"   || buc_die "Bucket required"
  test -n "${z_depot}"    || buc_die "Depot project id required"
  test -n "${z_mantle}"   || buc_die "Mantle required"
  test -n "${z_subject}"  || buc_die "Principal subject required"

  buc_step "Expunge muniment (${z_mantle}) for ${z_subject}"

  local z_objname
  z_objname=$(zrbgft_muniment_name_capture "${z_depot}" "${z_mantle}" "${z_subject}") \
    || buc_die "Failed to compose muniment object name"
  local z_name_enc
  z_name_enc=$(rbuh_urlencode_capture "${z_objname}") || buc_die "Failed to encode object name"

  local -r z_url="${RBGC_API_BASE_GCS}/b/${z_bucket}/o/${z_name_enc}"
  rbuh_json "DELETE" "${z_url}" "${z_token}" "${ZRBGFT_INFIX_EXPUNGE}"

  local z_code
  z_code=$(rbuh_code_capture "${ZRBGFT_INFIX_EXPUNGE}") || buc_die "Bad expunge HTTP code"
  case "${z_code}" in
    204) buc_success "Muniment expunged (${z_mantle}, ${z_subject})"; echo "deleted" ;;
    404) buc_info    "Muniment already absent, idempotent (${z_mantle}, ${z_subject})"; echo "absent" ;;
    *)   local z_err
         z_err=$(rbuh_json_field_capture "${ZRBGFT_INFIX_EXPUNGE}" '.error.message') || z_err="HTTP ${z_code}"
         buc_reject "${BUBC_band_expunge}" "Failed to expunge muniment (HTTP ${z_code}): ${z_err}" ;;
  esac
}

# Shared list-and-fetch core for the muniment reads. Pages a GCS object listing
# (prefix empty = the whole terrier, manor-wide; "<depot>/" = one polity slice),
# fetches each object's body, and echoes one tab-separated
# "<depot>\t<mantle>\t<subject>" line per muniment. The record
# fields (mantle, subject) read from the rbgft_ content fields — the
# content stays the authoritative record; the depot column reads from the object
# key's first segment, because placement is the index's alone to tell: which
# polity slice holds a muniment is not record content, and identical (mantle,
# subject) records co-reside across polity slices (RBSPO
# depot-attributed emission). A
# read-after-list 404 — an object expunged between the listing and its fetch — is
# a benign vanish and is skipped, not fatal: a pure read must not crash because a
# concurrent unseat withdrew an entry, and the wider the sweep the wider that
# window. Any other list/fetch non-OK, or a body missing the rbgft_ fields,
# rejects in the peruse band (BUBC_band_peruse — one read gate, its deficits
# rules within it). <list_infix> is suffixed with the page number; <get_infix>
# names the per-object fetch capture.
zrbgft_list_fetch_emit() {
  zrbgft_sentinel

  local -r z_token="${1}"
  local -r z_bucket="${2}"
  local -r z_prefix="${3}"   # may be empty — manor-wide read of the whole terrier
  local -r z_list_infix="${4}"
  local -r z_get_infix="${5}"

  local z_prefix_param=""
  if test -n "${z_prefix}"; then
    local z_prefix_enc
    z_prefix_enc=$(rbuh_urlencode_capture "${z_prefix}") || buc_die "Failed to encode list prefix"
    z_prefix_param="prefix=${z_prefix_enc}"
  fi

  buc_log_args 'Page through the muniment listing, fetching each body'
  local z_page_token=""
  local z_page=0
  while :; do
    z_page=$((z_page + 1))
    local z_query="${z_prefix_param}"
    if test -n "${z_page_token}"; then
      local z_tok_enc
      z_tok_enc=$(rbuh_urlencode_capture "${z_page_token}") || buc_die "Failed to encode pageToken"
      test -z "${z_query}" || z_query="${z_query}&"
      z_query="${z_query}pageToken=${z_tok_enc}"
    fi
    local z_url="${RBGC_API_BASE_GCS}/b/${z_bucket}/o"
    test -z "${z_query}" || z_url="${z_url}?${z_query}"

    local z_list_infix_page="${z_list_infix}${z_page}"
    rbuh_json "GET" "${z_url}" "${z_token}" "${z_list_infix_page}"

    local z_list_code
    z_list_code=$(rbuh_code_capture "${z_list_infix_page}") || buc_die "Bad muniment list HTTP code"
    case "${z_list_code}" in
      200) : ;;
      *)   local z_list_err
           z_list_err=$(rbuh_json_field_capture "${z_list_infix_page}" '.error.message') || z_list_err="HTTP ${z_list_code}"
           buc_reject "${BUBC_band_peruse}" "Terrier read: failed to list muniments (HTTP ${z_list_code}): ${z_list_err}" ;;
    esac

    local z_list_file="${ZRBUH_PREFIX}${z_list_infix_page}${ZRBUH_POSTFIX_JSON}"
    local z_names
    z_names=$(jq -r '.items[]?.name // empty' "${z_list_file}") || buc_die "Failed to read muniment listing"

    local z_name=""
    while IFS= read -r z_name; do
      test -n "${z_name}" || continue
      local z_name_enc
      z_name_enc=$(rbuh_urlencode_capture "${z_name}") || buc_die "Failed to encode muniment name"
      rbuh_json "GET" "${RBGC_API_BASE_GCS}/b/${z_bucket}/o/${z_name_enc}?alt=media" \
        "${z_token}" "${z_get_infix}"

      local z_get_code
      z_get_code=$(rbuh_code_capture "${z_get_infix}") || buc_die "Bad muniment fetch HTTP code"
      case "${z_get_code}" in
        200) : ;;
        404) buc_info "Muniment ${z_name} vanished between list and fetch — skipped"; continue ;;
        *)   local z_get_err
             z_get_err=$(rbuh_json_field_capture "${z_get_infix}" '.error.message') || z_get_err="HTTP ${z_get_code}"
             buc_reject "${BUBC_band_peruse}" "Terrier read: failed to fetch muniment ${z_name} (HTTP ${z_get_code}): ${z_get_err}" ;;
      esac

      local z_get_file="${ZRBUH_PREFIX}${z_get_infix}${ZRBUH_POSTFIX_JSON}"
      jq -r --arg depot "${z_name%%/*}" '[$depot, .rbgft_mantle, .rbgft_subject] | @tsv' "${z_get_file}" \
        || buc_reject "${BUBC_band_peruse}" "Terrier read: muniment ${z_name} missing rbgft_ fields"
    done <<< "${z_names}"

    z_page_token=$(jq -r '.nextPageToken // empty' "${z_list_file}") || buc_die "Failed to read nextPageToken"
    test -n "${z_page_token}" || break
  done
}

# rbgft_peruse <token> <bucket> <depot_project_id>
# The pure list-and-fetch read of one polity's muniments — no precondition. Lists
# every object under the polity folder prefix, fetches each, and echoes one
# tab-separated "<depot>\t<mantle>\t<subject>" line per muniment
# (the shared lister's uniform emit — the depot column is constant here, by
# construction the polity asked for; record fields from content, never the key).
# The per-polity slice of the roll, and the read side of the reconciliation diff.
rbgft_peruse() {
  zrbgft_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket="${2:-}"
  local -r z_depot="${3:-}"

  test -n "${z_token}"  || buc_die "Token required"
  test -n "${z_bucket}" || buc_die "Bucket required"
  test -n "${z_depot}"  || buc_die "Depot project id required"

  buc_step "Peruse muniments for polity ${z_depot}"

  zrbgft_list_fetch_emit "${z_token}" "${z_bucket}" "${z_depot}/" \
    "${ZRBGFT_INFIX_PERUSE_LIST}" "${ZRBGFT_INFIX_PERUSE_GET}"
}

# rbgft_peruse_manor <token> <bucket>
# The manor-wide read — every muniment in the terrier across all polities, no
# prefix filter (read is bucket-level per RBS0). Echoes the same tab-separated
# "<depot>\t<mantle>\t<subject>" line per muniment as the per-polity
# peruse. The depot attribution column is what makes a manor-wide roll readable:
# it ties each holding to its polity slice — identical (mantle, subject) records
# co-reside across slices (including orphans a freehold churn
# leaves behind, since unmaking a depot project never sweeps the payor-grain
# terrier), so a depot-blind roll cannot witness a depot-scoped admission churn
# (RBSPO depot-attributed emission). The read rehearse composes manor-wide.
rbgft_peruse_manor() {
  zrbgft_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket="${2:-}"

  test -n "${z_token}"  || buc_die "Token required"
  test -n "${z_bucket}" || buc_die "Bucket required"

  buc_step "Peruse muniments manor-wide"

  zrbgft_list_fetch_emit "${z_token}" "${z_bucket}" "" \
    "${ZRBGFT_INFIX_PERUSE_MANOR_LIST}" "${ZRBGFT_INFIX_PERUSE_MANOR_GET}"
}

# rbgft_escheat_survey <token> <bucket>
# The classifying hygiene read (RBSME): list every object in the terrier bucket
# and judge each against the current muniment contract (RBSTN), emitting one
# tab-separated "<verdict>\t<detail>\t<name>" line per object — verdict "sound"
# with the depot key segment as detail, or verdict "stray" with the deficit word
# (key-shape | mantle | body-json | body-fields | mismatch). Deliberately reads
# at the raw object grain, beneath the muniment sub-operations: its subjects are
# precisely the objects that fail or predate the contract, so a malformed body
# CLASSIFIES rather than rejects (contrast the strict zrbgft_list_fetch_emit,
# whose whole read dies on one bad body). A read-after-list 404 is the benign
# vanish, skipped. List/fetch deficits reject in the escheat band
# (BUBC_band_escheat); an absent bucket rejects there naming the manor finisher.
rbgft_escheat_survey() {
  zrbgft_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket="${2:-}"

  test -n "${z_token}"  || buc_die "Token required"
  test -n "${z_bucket}" || buc_die "Bucket required"

  buc_step "Survey the terrier for escheat (classify every object)"

  z_rbgft_escheat_run=$((z_rbgft_escheat_run + 1))
  local -r z_names_file="${ZRBGFT_PREFIX}escheat_${z_rbgft_escheat_run}_names.txt"
  local -r z_fields_file="${ZRBGFT_PREFIX}escheat_${z_rbgft_escheat_run}_fields.txt"
  local -r z_jq_err_file="${ZRBGFT_PREFIX}escheat_${z_rbgft_escheat_run}_jq_err.txt"

  buc_log_args 'Page the raw object listing into the names file'
  : > "${z_names_file}"
  local z_page_token=""
  local z_page=0
  local z_tok_enc=""
  local z_url=""
  local z_list_infix_page=""
  local z_list_code=""
  local z_list_err=""
  local z_list_file=""
  while :; do
    z_page=$((z_page + 1))
    z_url="${RBGC_API_BASE_GCS}/b/${z_bucket}/o"
    if test -n "${z_page_token}"; then
      z_tok_enc=$(rbuh_urlencode_capture "${z_page_token}") || buc_die "Failed to encode pageToken"
      z_url="${z_url}?pageToken=${z_tok_enc}"
    fi

    z_list_infix_page="${ZRBGFT_INFIX_ESCHEAT_LIST}${z_page}"
    rbuh_json "GET" "${z_url}" "${z_token}" "${z_list_infix_page}"

    z_list_code=$(rbuh_code_capture "${z_list_infix_page}") || buc_die "Bad escheat list HTTP code"
    case "${z_list_code}" in
      200) : ;;
      404) buc_reject "${BUBC_band_escheat}" "Escheat survey: terrier bucket ${z_bucket} absent — instaurate the manor first" ;;
      *)   z_list_err=$(rbuh_json_field_capture "${z_list_infix_page}" '.error.message') || z_list_err="HTTP ${z_list_code}"
           buc_reject "${BUBC_band_escheat}" "Escheat survey: failed to list terrier objects (HTTP ${z_list_code}): ${z_list_err}" ;;
    esac

    z_list_file="${ZRBUH_PREFIX}${z_list_infix_page}${ZRBUH_POSTFIX_JSON}"
    jq -r '.items[]?.name // empty' "${z_list_file}" >> "${z_names_file}" \
      || buc_die "Failed to read escheat listing page ${z_page}"

    z_page_token=$(jq -r '.nextPageToken // empty' "${z_list_file}") || buc_die "Failed to read nextPageToken"
    test -n "${z_page_token}" || break
  done

  buc_log_args 'Load the names, then classify each (load-then-iterate)'
  local z_names=()
  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_names+=("${z_line}")
  done < "${z_names_file}"

  local z_i=0
  local z_name=""
  local z_depot=""
  local z_rest=""
  local z_mantle=""
  local z_subject=""
  local z_name_enc=""
  local z_get_code=""
  local z_get_err=""
  local z_get_file=""
  local z_body_mantle=""
  local z_body_subject=""
  for z_i in "${!z_names[@]}"; do
    z_name="${z_names[$z_i]}"

    case "${z_name}" in
      */*/*) : ;;
      *) printf 'stray\tkey-shape\t%s\n' "${z_name}" || buc_die "Failed to emit survey line"
         continue ;;
    esac
    z_depot="${z_name%%/*}"
    z_rest="${z_name#*/}"
    z_mantle="${z_rest%%/*}"
    z_subject="${z_rest#*/}"
    if test -z "${z_depot}" || test -z "${z_mantle}" || test -z "${z_subject}"; then
      printf 'stray\tkey-shape\t%s\n' "${z_name}" || buc_die "Failed to emit survey line"
      continue
    fi

    case "${z_mantle}" in
      governor|director|retriever) : ;;
      *) printf 'stray\tmantle\t%s\n' "${z_name}" || buc_die "Failed to emit survey line"
         continue ;;
    esac

    z_name_enc=$(rbuh_urlencode_capture "${z_name}") || buc_die "Failed to encode object name"
    rbuh_json "GET" "${RBGC_API_BASE_GCS}/b/${z_bucket}/o/${z_name_enc}?alt=media" \
      "${z_token}" "${ZRBGFT_INFIX_ESCHEAT_GET}"

    z_get_code=$(rbuh_code_capture "${ZRBGFT_INFIX_ESCHEAT_GET}") || buc_die "Bad escheat fetch HTTP code"
    case "${z_get_code}" in
      200) : ;;
      404) buc_info "Object ${z_name} vanished between list and fetch — skipped"; continue ;;
      *)   z_get_err=$(rbuh_json_field_capture "${ZRBGFT_INFIX_ESCHEAT_GET}" '.error.message') || z_get_err="HTTP ${z_get_code}"
           buc_reject "${BUBC_band_escheat}" "Escheat survey: failed to fetch object ${z_name} (HTTP ${z_get_code}): ${z_get_err}" ;;
    esac

    z_get_file="${ZRBUH_PREFIX}${ZRBGFT_INFIX_ESCHEAT_GET}${ZRBUH_POSTFIX_JSON}"
    jq -r '[(.rbgft_mantle? // ""), (.rbgft_subject? // "")] | @tsv' \
      "${z_get_file}" > "${z_fields_file}" 2>"${z_jq_err_file}" \
      || { printf 'stray\tbody-json\t%s\n' "${z_name}" || buc_die "Failed to emit survey line"; continue; }

    z_body_mantle=""
    z_body_subject=""
    IFS=$'\t' read -r z_body_mantle z_body_subject < "${z_fields_file}" \
      || { printf 'stray\tbody-fields\t%s\n' "${z_name}" || buc_die "Failed to emit survey line"; continue; }

    if test -z "${z_body_mantle}" || test -z "${z_body_subject}"; then
      printf 'stray\tbody-fields\t%s\n' "${z_name}" || buc_die "Failed to emit survey line"
      continue
    fi

    if test "${z_body_mantle}" != "${z_mantle}" || test "${z_body_subject}" != "${z_subject}"; then
      printf 'stray\tmismatch\t%s\n' "${z_name}" || buc_die "Failed to emit survey line"
      continue
    fi

    printf 'sound\t%s\t%s\n' "${z_depot}" "${z_name}" || buc_die "Failed to emit survey line"
  done
}

# rbgft_escheat_expunge_raw <token> <bucket> <object_name>
# The raw hygiene delete (RBSME): strike one bucket object by its listed name,
# unconditioned — no muniment-name composition, because an escheat subject's key
# may be exactly what fails the contract. Echoes "deleted" (204) or "absent"
# (404 — already vanished, clean). Any other code rejects in the escheat band
# (BUBC_band_escheat). Logged, not stepped: the sweep loop is one verb step.
rbgft_escheat_expunge_raw() {
  zrbgft_sentinel

  local -r z_token="${1:-}"
  local -r z_bucket="${2:-}"
  local -r z_name="${3:-}"

  test -n "${z_token}"  || buc_die "Token required"
  test -n "${z_bucket}" || buc_die "Bucket required"
  test -n "${z_name}"   || buc_die "Object name required"

  buc_log_args "Escheat raw expunge: ${z_name}"

  local z_name_enc
  z_name_enc=$(rbuh_urlencode_capture "${z_name}") || buc_die "Failed to encode object name"

  rbuh_json "DELETE" "${RBGC_API_BASE_GCS}/b/${z_bucket}/o/${z_name_enc}" \
    "${z_token}" "${ZRBGFT_INFIX_ESCHEAT_EXPUNGE}"

  local z_code
  z_code=$(rbuh_code_capture "${ZRBGFT_INFIX_ESCHEAT_EXPUNGE}") || buc_die "Bad escheat expunge HTTP code"
  case "${z_code}" in
    204) buc_info "Escheated ${z_name}"; echo "deleted" ;;
    404) buc_info "Object ${z_name} already absent (benign vanish)"; echo "absent" ;;
    *)   local z_err
         z_err=$(rbuh_json_field_capture "${ZRBGFT_INFIX_ESCHEAT_EXPUNGE}" '.error.message') || z_err="HTTP ${z_code}"
         buc_reject "${BUBC_band_escheat}" "Failed to escheat object ${z_name} (HTTP ${z_code}): ${z_err}" ;;
  esac
}

# eof
