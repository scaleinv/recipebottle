#!/bin/bash
#
# Copyright 2026 Scale Invariant, Inc.
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
# Recipe Bottle Foundry Ledger - inventory cluster (guard-free, sourced by rbflk_):
# tally hallmark health, rekon a hallmark/reliquary subtree, and audit hallmarks
# and reliquaries (Retriever for tally; Director for the rest).

set -euo pipefail

######################################################################
# Inventory (rbfl_*)

rbfl_tally() {
  zrbfl_sentinel

  buc_doc_brief "Tally hallmarks with health status (vouched / pending / incomplete)"
  buc_doc_shown || return 0

  buc_step "Authenticating as Retriever"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_retriever}") \
    || buc_die "Failed to get Retriever OAuth token"

  buc_step "Enumerating hallmarks under ${RBGL_HALLMARKS_ROOT}/"
  zrbfc_list_packages_capture "${z_token}" "${RBGL_HALLMARKS_ROOT}"

  if ! test -s "${ZRBFC_PACKAGE_LIST_FILE}"; then
    buc_info "No hallmarks found under ${RBGL_HALLMARKS_ROOT}/"
    buc_success "Tally complete — 0 hallmarks"
    return 0
  fi

  # Load-then-iterate. A synthetic sentinel element appended to the array
  # lets the final hallmark flush through the same boundary branch as every
  # intermediate one (single flush site).
  local z_lines=()
  local z_line=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    z_lines+=("${z_line}")
  done < "${ZRBFC_PACKAGE_LIST_FILE}"
  z_lines+=("__SENTINEL__ __SENTINEL__")

  echo ""
  printf "  %-30s  %-11s  %s\n" "HALLMARK" "HEALTH" "BASENAMES"
  printf "  %-30s  %-11s  %s\n" "------------------------------" "-----------" "---------"

  # State machine over <hallmark> <basename> pairs (file was sorted by the
  # capture helper). Vessel is no longer encoded in the GAR path —
  # restoration via about/vouch metadata is AAL territory.
  local z_prev_h="" z_prev_bns=""
  local z_prev_img=0 z_prev_abt=0 z_prev_vch=0
  local z_count=0 z_vouched_n=0 z_pending_n=0 z_incomplete_n=0
  local z_i="" z_h="" z_b="" z_health=""

  for z_i in "${!z_lines[@]}"; do
    z_line="${z_lines[$z_i]}"
    test -n "${z_line}" || continue

    z_h="${z_line%% *}"
    z_b="${z_line#* }"
    test -n "${z_h}" || continue
    test -n "${z_b}" || continue

    if test "${z_h}" != "${z_prev_h}"; then
      if test -n "${z_prev_h}"; then
        if test "${z_prev_img}" = "1" \
          && test "${z_prev_abt}" = "1" \
          && test "${z_prev_vch}" = "1"; then
          z_health="vouched"
          z_vouched_n=$(( z_vouched_n + 1 ))
        elif test "${z_prev_img}" = "1" \
          && test "${z_prev_abt}" = "1"; then
          z_health="pending"
          z_pending_n=$(( z_pending_n + 1 ))
        else
          z_health="incomplete"
          z_incomplete_n=$(( z_incomplete_n + 1 ))
        fi
        printf "  %-30s  %-11s  %s\n" "${z_prev_h}" "${z_health}" "${z_prev_bns}"
        z_count=$(( z_count + 1 ))
      fi

      case "${z_h}" in
        __SENTINEL__) break ;;
      esac

      z_prev_h="${z_h}"
      z_prev_bns=""
      z_prev_img=0
      z_prev_abt=0
      z_prev_vch=0
    fi

    z_prev_bns="${z_prev_bns}${z_prev_bns:+ }${z_b}"
    case "${z_b}" in
      "${RBGC_ARK_BASENAME_IMAGE}") z_prev_img=1 ;;
      "${RBGC_ARK_BASENAME_ABOUT}") z_prev_abt=1 ;;
      "${RBGC_ARK_BASENAME_VOUCH}") z_prev_vch=1 ;;
    esac
  done

  echo ""
  buc_info "Total hallmarks: ${z_count}  (vouched: ${z_vouched_n}, pending: ${z_pending_n}, incomplete: ${z_incomplete_n})"

  case "${z_pending_n}" in
    0) ;;
    *) buc_info "To vouch pending hallmarks:"
       buc_tabtarget "rbw-fV"
       ;;
  esac

  case "${z_incomplete_n}" in
    0) ;;
    *) buc_info "To abjure incomplete hallmarks:"
       buc_tabtarget "rbw-fA"
       ;;
  esac

  buc_success "Tally complete"
}

rbfl_rekon_hallmark() {
  zrbfl_sentinel

  local -r z_express="${BUZ_FOLIO:-}"

  buc_doc_brief "List ark basenames present under a hallmark's GAR subtree"
  buc_doc_param "hallmark" "Hallmark identifier; optional — absent, falls back to the hallmark the prior build chained forward"
  buc_doc_shown || return 0

  # Relay-then-read (RBr_3e7): forward the chain baton before any read or failure point.
  buf_relay || buc_die "Failed to relay chained facts"

  # Resolve the hallmark express-or-chain: an express argument wins; absent, fall
  # back to the hallmark a prior build (ordain or kludge) handed forward through
  # the depth-1 chain — so a no-arg rekon immediately after a build inspects the
  # just-built hallmark.
  local z_hallmark=""
  z_hallmark=$(buf_elect_fact_capture "${z_express}" "${RBF_FACT_HALLMARK}") \
    || buc_reject "${BUBC_band_chain}" "No hallmark — pass one (rbw-irh <hallmark>) or run a build immediately before rekon"

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  buc_step "Enumerating arks under ${RBGL_HALLMARKS_ROOT}/${z_hallmark}/"
  zrbfc_list_packages_capture "${z_token}" "${RBGL_HALLMARKS_ROOT}"

  # Filter the full hallmark enumeration to rows for this hallmark.
  local z_found=""
  local z_line=""
  local z_h=""
  local z_b=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_h="${z_line%% *}"
    z_b="${z_line#* }"
    if test "${z_h}" = "${z_hallmark}"; then
      z_found="${z_found}${z_found:+ }${z_b}"
    fi
  done < "${ZRBFC_PACKAGE_LIST_FILE}"

  test -n "${z_found}" || buc_die "Hallmark not found: ${z_hallmark}"

  echo ""
  printf "  %-10s  %-6s  %s\n" "BASENAME" "EXISTS" "PACKAGE-PATH"
  printf "  %-10s  %-6s  %s\n" "----------" "------" "------------"

  local z_canon=""
  local z_mark=""
  local z_path=""
  for z_canon in \
    "${RBGC_ARK_BASENAME_IMAGE}" \
    "${RBGC_ARK_BASENAME_ABOUT}" \
    "${RBGC_ARK_BASENAME_VOUCH}" \
    "${RBGC_ARK_BASENAME_ATTEST}" \
    "${RBGC_ARK_BASENAME_POUCH}" \
    "${RBGC_ARK_BASENAME_DIAGS}"; do
    z_mark="no"
    case " ${z_found} " in
      *" ${z_canon} "*) z_mark="yes" ;;
    esac
    if test "${z_mark}" = "yes"; then
      z_path="${RBGL_HALLMARKS_ROOT}/${z_hallmark}/${z_canon}"
    else
      z_path="(absent)"
    fi
    printf "  %-10s  %-6s  %s\n" "${z_canon}" "${z_mark}" "${z_path}"
  done

  echo ""
  buc_success "Rekon complete for ${z_hallmark}"
}

rbfl_audit_hallmarks() {
  zrbfl_sentinel

  buc_doc_brief "Audit hallmarks — list all hallmark identifiers in registry"
  buc_doc_shown || return 0

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  buc_step "Enumerating hallmarks under ${RBGL_HALLMARKS_ROOT}/"
  zrbfc_list_packages_capture "${z_token}" "${RBGL_HALLMARKS_ROOT}"

  if ! test -s "${ZRBFC_PACKAGE_LIST_FILE}"; then
    buc_info "No hallmarks found under ${RBGL_HALLMARKS_ROOT}/"
    buc_success "Audit complete — 0 hallmarks"
    return 0
  fi

  echo ""
  printf "  %s\n" "HALLMARK"
  printf "  %s\n" "------------------------------"

  local z_count=0
  local z_prev=""
  local z_line=""
  local z_h=""
  while IFS= read -r z_line || test -n "${z_line}"; do
    test -n "${z_line}" || continue
    z_h="${z_line%% *}"
    test -n "${z_h}" || continue
    if test "${z_h}" != "${z_prev}"; then
      printf "  %s\n" "${z_h}"
      buf_write_fact_multi "${z_h}" "${RBCC_fact_ext_audit_hallmark}" "${z_h}"
      z_count=$(( z_count + 1 ))
      z_prev="${z_h}"
    fi
  done < "${ZRBFC_PACKAGE_LIST_FILE}"

  echo ""
  buc_info "Total hallmarks: ${z_count}"
  buc_success "Audit complete"
}

######################################################################
# Raw-path list (rbfl_*) — the type-blind maintenance backdoor (rbw-il)

# Generic, envelope-independent enumeration of GAR by raw path, narrowing
# iteratively: no path -> top namespaces; a prefix -> its children; a full
# package -> its tags and versions. Makes no subtree or kind assumption — it
# reads the whole registry and narrows in-process — so it tolerates half-
# deleted debris, legacy artifacts, and any future namespace with no new verb.
rbfl_list() {
  zrbfl_sentinel

  local -r z_path="${BUZ_FOLIO:-}"

  buc_doc_brief "List GAR contents by iterative path narrowing — the type-blind raw maintenance layer"
  buc_doc_oparm "path" "Raw GAR path. Omit for the top namespaces; a prefix lists its children; a full package lists its tags and versions. A ref carrying :tag or @sha256: is an image — use rbw-iw / rbw-iJ."
  buc_doc_shown || return 0

  # Disambiguation (total rule — GAR's deletable leaves are exactly tags and
  # versions): a ref carrying :tag or @sha256: is an image, not a path. list
  # walks paths only; acting on an image is wrest (rbw-iw) / jettison (rbw-iJ).
  case "${z_path}" in
    *@*|*:*) buc_die "'${z_path}' is an image ref, not a path — use rbw-iw (wrest) or rbw-iJ (jettison)" ;;
  esac

  buc_step "Authenticating as Director"
  local z_token=""
  z_token=$(rba_token_capture "${RBCC_mantle_director}") \
    || buc_die "Failed to get Director OAuth token"

  # One enumeration of every package (decoded names, slashes restored, sorted).
  buc_step "Enumerating GAR packages"
  local -r z_list_infix="rbfl_list_pkgs"
  local -r z_list_url="${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages?pageSize=1000"
  rbuh_json "GET" "${z_list_url}" "${z_token}" "${z_list_infix}"
  rbuh_require_ok "List GAR packages" "${z_list_infix}"
  local -r z_resp_file="${ZRBUH_PREFIX}${z_list_infix}${ZRBUH_POSTFIX_JSON}"

  local -r z_pkgs_file="${BURD_TEMP_DIR}/rbfl_list_packages.txt"
  jq -r '
    .packages[]?.name
    | sub("^.*/packages/"; "")
    | gsub("%2F"; "/")
  ' "${z_resp_file}" | sort > "${z_pkgs_file}" \
    || buc_die "Failed to extract GAR package list"

  # Leaf grain: the path names a package exactly -> list its tags and versions.
  if test -n "${z_path}"; then
    local z_pl=""
    while IFS= read -r z_pl || test -n "${z_pl}"; do
      if test "${z_pl}" = "${z_path}"; then
        zrbfl_list_leaf "${z_token}" "${z_path}"
        return 0
      fi
    done < "${z_pkgs_file}"
  fi

  # Branch grain: emit the distinct next path-segment beneath the prefix
  # (empty path -> the top namespaces).
  local z_prefix=""
  test -z "${z_path}" || z_prefix="${z_path}/"

  local -r z_kids_file="${BURD_TEMP_DIR}/rbfl_list_children.txt"
  jq -r --arg prefix "${z_prefix}" '
    .packages[]?.name
    | sub("^.*/packages/"; "")
    | gsub("%2F"; "/")
    | select(startswith($prefix))
    | ltrimstr($prefix)
    | split("/")[0]
    | select(length > 0)
  ' "${z_resp_file}" | sort -u > "${z_kids_file}" \
    || buc_die "Failed to derive child path segments"

  if ! test -s "${z_kids_file}"; then
    test -n "${z_path}" || buc_die "No packages found in registry"
    buc_die "No path or package matches: ${z_path}"
  fi

  echo ""
  if test -z "${z_path}"; then
    printf "  %s\n" "TOP NAMESPACES"
  else
    printf "  CHILDREN OF  %s\n" "${z_path}"
  fi
  printf "  %s\n" "------------------------------"
  local z_seg=""
  while IFS= read -r z_seg || test -n "${z_seg}"; do
    test -n "${z_seg}" || continue
    if test -z "${z_path}"; then
      printf "  %s\n" "${z_seg}"
    else
      printf "  %s/%s\n" "${z_path}" "${z_seg}"
    fi
  done < "${z_kids_file}"

  echo ""
  buc_success "List complete"
}

# Leaf display for rbfl_list: a full package's tags and versions, each annotated
# with the ref form that wrest/jettison consume (tag -> :tag, version -> @digest).
zrbfl_list_leaf() {
  zrbfl_sentinel

  local -r z_token="${1:?Token required}"
  local -r z_pkg="${2:?Package path required}"
  local -r z_encoded="${z_pkg//\//%2F}"

  buc_step "Listing tags and versions of ${z_pkg}"

  local -r z_tags_infix="rbfl_list_tags"
  rbuh_json "GET" \
    "${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages/${z_encoded}/tags?pageSize=1000" \
    "${z_token}" "${z_tags_infix}"
  rbuh_require_ok "List tags for ${z_pkg}" "${z_tags_infix}"
  local -r z_tags_file="${BURD_TEMP_DIR}/rbfl_leaf_tags.txt"
  jq -r '.tags[]?.name | sub("^.*/tags/"; "")' \
    "${ZRBUH_PREFIX}${z_tags_infix}${ZRBUH_POSTFIX_JSON}" | sort > "${z_tags_file}" \
    || buc_die "Failed to extract tags for ${z_pkg}"

  local -r z_vers_infix="rbfl_list_vers"
  rbuh_json "GET" \
    "${ZRBFC_GAR_API_BASE}/${ZRBFC_GAR_PACKAGE_BASE}/packages/${z_encoded}/versions?pageSize=1000" \
    "${z_token}" "${z_vers_infix}"
  rbuh_require_ok "List versions for ${z_pkg}" "${z_vers_infix}"
  local -r z_vers_file="${BURD_TEMP_DIR}/rbfl_leaf_vers.txt"
  jq -r '.versions[]?.name | sub("^.*/versions/"; "")' \
    "${ZRBUH_PREFIX}${z_vers_infix}${ZRBUH_POSTFIX_JSON}" | sort > "${z_vers_file}" \
    || buc_die "Failed to extract versions for ${z_pkg}"

  echo ""
  printf "  PACKAGE  %s\n" "${z_pkg}"
  echo ""
  printf "  %s\n" "TAGS  (act:  rbw-iw ${z_pkg}:<tag>   rbw-iJ ${z_pkg}:<tag>)"
  printf "  %s\n" "------------------------------"
  if test -s "${z_tags_file}"; then
    local z_tag=""
    while IFS= read -r z_tag || test -n "${z_tag}"; do
      test -n "${z_tag}" || continue
      printf "    %s\n" "${z_tag}"
    done < "${z_tags_file}"
  else
    printf "    (none)\n"
  fi

  echo ""
  printf "  %s\n" "VERSIONS  (act:  rbw-iJ ${z_pkg}@<version>)"
  printf "  %s\n" "------------------------------"
  if test -s "${z_vers_file}"; then
    local z_ver=""
    while IFS= read -r z_ver || test -n "${z_ver}"; do
      test -n "${z_ver}" || continue
      printf "    %s\n" "${z_ver}"
    done < "${z_vers_file}"
  else
    printf "    (none)\n"
  fi

  echo ""
  buc_success "List complete — ${z_pkg}"
}

# eof
