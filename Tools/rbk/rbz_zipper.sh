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
# RBW Zipper - Colophon registry for RBW workbench dispatch

set -euo pipefail

# Multiple inclusion guard
test -z "${ZRBZ_SOURCED:-}" || return 0
ZRBZ_SOURCED=1

######################################################################
# Colophon registry initialization

zrbz_kindle() {
  test -z "${ZRBZ_KINDLED:-}" || buc_die "rbz already kindled"

  # Verify buz zipper is kindled (CLI furnish must kindle buz first)
  zbuz_sentinel

  # Open the RB tome: this zipper's run projects to RBTDGC_ consts (RBZ_ stem)
  # and to the "rbz" context scope. Must precede the first enroll so the run
  # begins at the roll's current head.
  buz_tome "rbz" "RBTDGC_" "RBZ_"

  # Access — credential access probes + the sitting lifecycle (rbw-a): payor
  # OAuth, federated avowal, mantle don, and the sitting-lifecycle operator
  # verbs (novate — UPPER: mutates the sitting; espy — lower: reads the cache
  # alone, the group's read-only member).
  buz_group RBZ__GROUP_ACCESS     "rbw-a"   "Access — Credential access probes + sitting lifecycle"
  local z_mod="rbgv_cli.sh"
  buz_enroll RBZ_CHECK_PAYOR             "rbw-ap"  "${z_mod}" "rbgv_check_payor"           ""        "Check the payor credential reaches Google Cloud (OAuth access probe)"
  buz_enroll RBZ_CHECK_AVOWAL       "rbw-aa"  "${z_mod}" "rbgv_check_avowal"     "param1"  "Check federated access — open or reuse a sitting via device flow + STS (Legs 1+2) against the RBRF trust (optional arg: required runway seconds)"
  buz_enroll RBZ_CHECK_MANTLE            "rbw-am"  "${z_mod}" "rbgv_check_mantle"          "param1"  "Check mantle access as the freehold subject — avow, don the named mantle token (rbpa_governor|rbpa_director|rbpa_retriever), reach Artifact Registry, and write the attributed audit entry; or surface the access deficit"
  buz_enroll RBZ_NOVATE_SITTING          "rbw-aN"  "rba_cli.sh" "rba_novate_sitting"       ""        "Novate the sitting — open a fresh full-window sitting, extinguishing any standing one (the runway gate's named remedy)"
  buz_enroll RBZ_ESPY_SITTING            "rbw-as"  "rba_cli.sh" "rba_espy_sitting"         ""        "Espy the sitting — report whether one is live and how much runway remains, from the cache alone (read-only: never opens, never prompts, no network)"

  # Crucible — container runtime (rbw-c)
  buz_group RBZ__GROUP_CRUCIBLE   "rbw-c"   "Crucible — Container runtime"
  z_mod="rbob_cli.sh"
  buz_enroll RBZ_CRUCIBLE_CHARGE  "rbw-cC"  "${z_mod}" "rbob_charge"       "imprint"  "Charge Crucible (Sentry + Pentacle + Bottle containers)"
  buz_enroll RBZ_CRUCIBLE_QUENCH  "rbw-cQ"  "${z_mod}" "rbob_quench"       "imprint"  "Quench Crucible"
  buz_enroll RBZ_CRUCIBLE_SSH     "rbw-cS"  "${z_mod}" "rbob_ssh"          "imprint"  "SSH into the Bottle container"
  buz_enroll RBZ_CRUCIBLE_HAIL    "rbw-ch"  "${z_mod}" "rbob_hail"         "param1"   "Shell into the Sentry container"
  buz_enroll RBZ_CRUCIBLE_RACK    "rbw-cr"  "${z_mod}" "rbob_rack"         "param1"   "Shell into the Bottle container"
  buz_enroll RBZ_CRUCIBLE_SCRY    "rbw-cs"  "${z_mod}" "rbob_scry"         "param1"   "Observe network traffic on Crucible containers"
  buz_enroll RBZ_CRUCIBLE_WRIT    "rbw-cw"  "${z_mod}" "rbob_writ"         "imprint"  "Non-interactive exec in Sentry container"
  buz_enroll RBZ_CRUCIBLE_FIAT    "rbw-cf"  "${z_mod}" "rbob_fiat"         "imprint"  "Non-interactive exec in Pentacle container"
  buz_enroll RBZ_CRUCIBLE_BARK    "rbw-cb"  "${z_mod}" "rbob_bark"         "imprint"  "Non-interactive exec in Bottle container"
  buz_enroll RBZ_CRUCIBLE_ACTIVE  "rbw-cic" "${z_mod}" "rbob_charged"      "param1"   "Check whether the Crucible is charged (compose project has running containers)"
  buz_enroll RBZ_CRUCIBLE_KLUDGE_BOTTLE "rbw-cKB" "${z_mod}" "rbob_kludge_bottle" "param1" "Kludge Bottle vessel and drive hallmark into nameplate"
  buz_enroll RBZ_CRUCIBLE_KLUDGE_SENTRY "rbw-cKS" "${z_mod}" "rbob_kludge_sentry" "param1" "Kludge Sentry vessel and drive hallmark into nameplate"

  # Depot — GCP project infrastructure (rbw-d, UPPER=mutates, lower=read)
  buz_group RBZ__GROUP_DEPOT      "rbw-d"   "Depot — GCP project infrastructure"
  z_mod="rbgp_cli.sh"
  buz_enroll RBZ_LEVY_DEPOT             "rbw-dL"  "${z_mod}" "rbgp_depot_levy"   ""  "Provision GCP depot project"
  buz_enroll RBZ_UNMAKE_DEPOT           "rbw-dU"  "${z_mod}" "rbgp_depot_unmake"  "param1"  "Permanently remove a depot (operator supplies depot project ID)"
  buz_enroll RBZ_LIST_DEPOT             "rbw-dl"  "${z_mod}" "rbgp_depot_list"    ""  "List all active depots"
  buz_enroll RBZ_INFO_DEPOT             "rbw-di"  "${z_mod}" "rbgp_depot_info"    ""  "Run egress posture checks against the live depot's worker pools"
  buz_enroll RBZ_RECOGNOSCE_DEPOT       "rbw-dr"  "${z_mod}" "rbgp_depot_recognosce"  ""  "Recognosce a depot's founding — confirm mantle SAs, capability-sets, and AR audit config against live GCP"
  buz_enroll RBZ_ATTRIBUTION_DEPOT      "rbw-da"  "${z_mod}" "rbgp_attribution_trail" ""  "Print the depot's AR Data-Access attribution trail — recent audit entries naming the acting mantle SA and the human federate subject"

  # Manor — IdP federation founding (rbw-m). The payor founding trio —
  # affiance / jilt / gird (gird seats a fresh depot's first governor, the one
  # admission the payor wields) — plus instaurate, the ensure-exists manor-setup finisher
  # (workforce pool + terrier bucket; the depot-grain polity folder is founded at
  # depot levy), raze, its withheld
  # pool-destroyer inverse (internal release-ladder infra, stripped at delivery),
  # and escheat, the terrier-hygiene sweep (RBSME).
  # The M5 colophon regroup later gathers levy/establish into it.
  buz_group RBZ__GROUP_MANOR      "rbw-m"   "Manor — IdP federation founding"
  z_mod="rbgp_cli.sh"
  buz_enroll RBZ_AFFIANCE_MANOR         "rbw-mA"  "${z_mod}" "rbgp_manor_affiance" "param1"  "Affiance a foedus to its IdP — seat the named foedus's provider and attribute mapping under the standing workforce pool (args: foedus)"
  buz_enroll RBZ_JILT_MANOR             "rbw-mJ"  "${z_mod}" "rbgp_manor_jilt"     "param1"  "Jilt one foedus — delete the named foedus's provider from the manor's standing workforce pool (the pool stands; args: foedus)"
  # instaurate is the ensure-exists manor-setup finisher: idempotently founds the one
  # workforce pool (list-and-match drift guard) and the terrier bucket. The depot-grain
  # polity folder + grain IAM are founded at depot levy, not here. The inverse of raze;
  # ships to consumers (not withheld).
  buz_enroll RBZ_INSTAURATE_MANOR            "rbw-mI"  "${z_mod}" "rbgp_manor_instaurate"    ""  "Instaurate the manor — idempotently ensure payor-project APIs, billing linkage, the workforce pool, and terrier bucket (post-payor-guide manor-setup finisher)"
  # raze force-deletes the whole pool — the deliberate destroyer, distinct from
  # jilt's provider-level break. WITHHELD from delivery (prep-release Step 9c
  # strips the tabtarget); the verb ships in rbgp_payor.sh. Internal release-ladder
  # infra only — consumers never get a one-keystroke pool-destroyer.
  buz_enroll RBZ_RAZE_MANOR             "rbw-mR"  "${z_mod}" "rbgp_manor_raze"     ""  "Raze the manor — force-delete its workforce pool to start clean (internal release-ladder infra; withheld from delivery)"
  # escheat is the manor-hygiene sweep of the terrier (RBSME): plan-then-confirm
  # strike of orphaned polity slices and dead-schema strays; the mutating sibling
  # of the pure read rehearse. Ships to consumers (idempotent, confirm-gated).
  buz_enroll RBZ_ESCHEAT_MANOR          "rbw-mE"  "${z_mod}" "rbgp_manor_escheat"  ""  "Escheat the terrier — sweep orphaned polity slices and dead-schema strays from the manor terrier (plan-then-confirm payor hygiene)"
  # gird keeps its _POLITY demesne stem (it admits a governor to the polity);
  # only its colophon homes here in the payor founding family. Do not rename
  # the constant to match the group — the demesne, not the colophon, names it.
  buz_enroll RBZ_GIRD_POLITY            "rbw-mG"  "${z_mod}" "rbgp_gird"           "param1"  "Gird the first governor — payor seats a citizen as this depot's founding governor (args: subject)"

  # Polity — federation admission (rbw-p, UPPER=mutates, lower=read). The
  # operator-facing admission verbs over the manor terrier + mantle IAM, all
  # governor-wielded: the mutating three (brevet/unseat/attaint) plus rehearse,
  # a manor-wide read. (Gird, the payor-wielded first-governor founding, homes
  # in the rbw-m manor trio.)
  buz_group RBZ__GROUP_POLITY     "rbw-p"   "Polity — federation admission"
  z_mod="rbgp_cli.sh"
  buz_enroll RBZ_BREVET_POLITY          "rbw-pB"  "${z_mod}" "rbgp_brevet"   "param1"  "Brevet a citizen onto a mantle in this depot (governor-wielded admission; args: subject mantle)"
  buz_enroll RBZ_UNSEAT_POLITY          "rbw-pU"  "${z_mod}" "rbgp_unseat"   "param1"  "Unseat a citizen from one mantle (suspension, not erasure; args: subject mantle)"
  buz_enroll RBZ_ATTAINT_POLITY         "rbw-pA"  "${z_mod}" "rbgp_attaint"  "param1"  "Attaint a citizen — whole-person expulsion from this depot (args: subject)"
  buz_enroll RBZ_REHEARSE_POLITY        "rbw-pr"  "${z_mod}" "rbgp_rehearse" ""        "Rehearse the manor terrier — recount every muniment, manor-wide (read-only)"

  # Foedus — test-bed cardinality verbs (rbw-j, UPPER=mutates critical state,
  # lower=read-only). The switch-and-check toothings over the moorings foedera
  # library on a STANDING foedus; founding/dissolving stay the Manor verbs.
  buz_group RBZ__GROUP_FOEDUS     "rbw-j"   "Foedus — test-bed selection and health"
  z_mod="rbof_cli.sh"
  buz_enroll RBZ_INSTATE_FOEDUS         "rbw-jI"  "${z_mod}" "rbof_instate"  "param1"  "Instate a standing foedus as active — re-point the RBRR_ACTIVE_FOEDUS selector in rbrr.env (atomic, uncommitted; operator commits)"
  buz_enroll RBZ_DESCRY_FOEDUS          "rbw-jd"  "${z_mod}" "rbof_descry"   "param1"  "Descry a standing foedus — read its provider's presence under the manor pool (healthy, or a named deficit; read-only)"
  buz_enroll RBZ_CANVASS_FOEDUS         "rbw-jc"  "${z_mod}" "rbof_canvass"  ""        "Canvass the manor's foedera — enumerate every provider under the one workforce pool, emitting per-foedus fact files and marking the regime-selected one (read-only)"

  # Facility — synthetic-federation test-bed lifecycle (rbw-q, test-only utilities;
  # UPPER second-letter=mutates cloud/critical state). The Keycloak orchestrator is
  # one coherent module composing charge/affiance and jilt/quench through their
  # tabtargets — it never reimplements the composed verbs.
  buz_group RBZ__GROUP_FACILITY   "rbw-q"   "Facility — synthetic-federation test-bed lifecycle"
  z_mod="rbxk_cli.sh"
  buz_enroll RBZ_SETUP_KEYCLOAK         "rbw-qjK" "${z_mod}" "rbxk_setup"    ""        "Stand up the Keycloak programmatic test facility — charge fdkyclk, render its ephemeral JWKS into the ignored live regime, affiance rbef_keycloak (mutates cloud via affiance)"
  buz_enroll RBZ_TEARDOWN_KEYCLOAK      "rbw-qjQ" "${z_mod}" "rbxk_teardown" ""        "Tear down the Keycloak test facility — jilt rbef_keycloak, then quench fdkyclk (idempotent)"

  # Lode — fetched-side universal capture (rbw-l, UPPER=mutates GAR/cost, lower=read-only)
  buz_group RBZ__GROUP_LODE       "rbw-l"   "Lode — Fetched-side universal capture"
  z_mod="rbld0_cli.sh"
  buz_enroll RBZ_ENSCONCE_BOLE          "rbw-lE"  "${z_mod}" "rbld_ensconce"      "param1"  "Ensconce an upstream base image into a Lode (capture)"
  buz_enroll RBZ_CONCLAVE_RELIQUARY     "rbw-lC"  "${z_mod}" "rbld_conclave"      ""        "Conclave the build-tool cohort into one Lode (capture)"
  buz_enroll RBZ_UNDERPIN_WSL           "rbw-lU"  "${z_mod}" "rbld_underpin"      "param1"  "Underpin a vendor WSL rootfs into a Lode (capture; args: release point)"
  buz_enroll RBZ_IMMURE_PODVM           "rbw-lI"  "${z_mod}" "rbld_immure"        "param1"  "Immure podman-machine disk leaves of one quay family into a Lode (capture; args: family version)"
  buz_enroll RBZ_DIVINE_LODES           "rbw-ld"  "${z_mod}" "rbld_divine"        ""        "Divine Lodes — enumerate every Lode by touchmark (read-only)"
  buz_enroll RBZ_AUGUR_LODE             "rbw-la"  "${z_mod}" "rbld_augur"         "param1"  "Augur a Lode — inspect member tags and decode its rbi_vouch envelope (read-only)"
  buz_enroll RBZ_PRESAGE_IMMURE         "rbw-lp"  "${z_mod}" "rbld_presage"       "param1"  "Presage an immure — show what it would capture for one quay family (read-only; args: family [version])"
  buz_enroll RBZ_BANISH_LODE            "rbw-lB"  "${z_mod}" "rbld_banish"        "param1"  "Banish a Lode — delete the whole rbi_ld/<touchmark> package"

  # Guide — human-directed procedures (rbw-g)
  buz_group RBZ__GROUP_GUIDE      "rbw-g"   "Guide — Human-directed procedures"
  z_mod="rbgp_cli.sh"
  buz_enroll RBZ_PAYOR_INSTALL          "rbw-gPI" "${z_mod}" "rbgp_payor_install"   "param1"  "Ingest payor OAuth credentials from the downloaded client secret JSON"
  z_mod="rbh0/rbhp0_cli.sh"
  buz_enroll RBZ_PAYOR_ESTABLISH        "rbw-gPE" "${z_mod}" "rbhp_establish"       ""  "Guided Manor establishment — GCP project + OAuth consent screen"
  buz_enroll RBZ_QUOTA_BUILD            "rbw-gPQ" "${z_mod}" "rbhp_quota_build"     ""  "Display Cloud Build capacity review procedure"
  buz_enroll RBZ_FEDERATION_ENTRA       "rbw-gPF" "${z_mod}" "rbhp_federation_entra" ""  "Guided Entra federation setup — IdP-console app registration yielding the foedus core values"
  # Onboarding — handbook tracks (rbw-o terminal + rbw-O* family, see ₣A6 paddock)
  buz_group RBZ__GROUP_ONBOARDING "rbw-o"   "Onboarding — Handbook restart"
  z_mod="rbh0/rbho0_cli.sh"
  buz_enroll RBZ_ONBOARD_START_HERE    "rbw-o"   "${z_mod}" "rbho_start_here"            ""  "Onboarding start — probe-aware menu into handbook tracks"
  buz_enroll RBZ_ONBOARD_CRASH_COURSE  "rbw-Occ" "${z_mod}" "rbho_crash_course"          ""  "Crash Course — universal prerequisite: tabtargets, regimes, diagnostic failure"
  buz_enroll RBZ_ONBOARD_FIRST_CRUCIBLE "rbw-Ofc" "${z_mod}" "rbho_first_crucible"       ""  "Start a Crucible using local builds — kludge, charge, SSH, verify containment"
  buz_enroll RBZ_ONBOARD_TADMOR_SECURITY "rbw-Ots" "${z_mod}" "rbho_tadmor_security"     ""  "Verify Crucible containment under attack — charge tadmor and run the adversarial suite"
  buz_enroll RBZ_ONBOARD_DIR_FIRST_BUILD "rbw-Odf" "${z_mod}" "rbho_director_first_build" "" "Your First Cloud Build — conclave, conjure, tour, summon, abjure"
  buz_enroll RBZ_ONBOARD_DIR_AIRGAP     "rbw-Oda" "${z_mod}" "rbho_director_airgap"      ""  "Airgap Cloud Build — ensconce, conjure base, conjure airgap, charge moriah, compare plumb"
  buz_enroll RBZ_ONBOARD_DIR_BIND       "rbw-Odb" "${z_mod}" "rbho_director_bind"        ""  "Bind Cloud Build — pin upstream image by digest, mode-mixture pluml Crucible"
  buz_enroll RBZ_ONBOARD_DIR_GRAFT      "rbw-Odg" "${z_mod}" "rbho_director_graft"       ""  "Graft Cloud Build — push locally-built image, inspect GRAFTED Vouch verdict"
  buz_enroll RBZ_ONBOARD_PAYOR_HB      "rbw-Op"  "${z_mod}" "rbho_payor_handbook"       ""  "Payor — establish a Manor and provision the Depot"

  # Foundry — registry artifact lifecycle (rbw-f, UPPER=mutates GAR, lower=read/local)
  buz_group RBZ__GROUP_FOUNDRY    "rbw-f"   "Foundry — Registry artifact lifecycle"
  z_mod="rbfd_cli.sh"
  buz_enroll RBZ_ORDAIN_HALLMARK        "rbw-fO"  "${z_mod}" "rbfd_ordain"          "param1"  "Ordain hallmark: conjure, bind, or graft based on vessel mode"
  buz_enroll RBZ_KLUDGE_VESSEL          "rbw-fk"  "rbfk_cli.sh" "rbfk_kludge"       "param1"  "Kludge a vessel image locally for development"
  z_mod="rbfl0_cli.sh"
  buz_enroll RBZ_ABJURE_HALLMARK        "rbw-fA"  "${z_mod}" "rbfl_abjure"          "param1"  "Abjure a hallmark (delete artifacts from GAR)"
  buz_enroll RBZ_TALLY_HALLMARKS        "rbw-ft"  "${z_mod}" "rbfl_tally"           ""  "Tally hallmarks by health state"
  z_mod="rbfv_cli.sh"
  buz_enroll RBZ_VOUCH_HALLMARKS        "rbw-fV"  "${z_mod}" "rbfv_batch_vouch"     ""  "Mode-aware vouch: SLSA (conjure), digest-pin (bind), GRAFTED (graft)"
  z_mod="rbfr_cli.sh"
  buz_enroll RBZ_SUMMON_HALLMARK        "rbw-fs"  "${z_mod}" "rbfr_summon"          "param1"  "Summon vouched hallmark image locally"
  z_mod="rbfc0_cli.sh"
  buz_enroll RBZ_PLUMB_FULL             "rbw-fpf" "${z_mod}" "rbfc_plumb_full"      "param1"  "Full provenance display (SBOM, build info, Dockerfile)"
  buz_enroll RBZ_PLUMB_COMPACT          "rbw-fpc" "${z_mod}" "rbfc_plumb_compact"   "param1"  "Compact provenance summary"
  z_mod="rbfh_cli.sh"
  buz_enroll RBZ_HYGIENE_CHECK_DOCKERFILE "rbw-fhc" "${z_mod}" "rbfh_check"         "param1"  "Check a Dockerfile against the FROM-line hygiene contract"
  buz_enroll RBZ_HYGIENE_CHECK_VESSEL   "rbw-fhv" "${z_mod}" "rbfh_check_vessel"    "param1"  "Check a vessel's conjure Dockerfile against the FROM-line hygiene contract"

  # Ifrit — attack binary (rbw-I)
  buz_group RBZ__GROUP_IFRIT      "rbw-I"   "Ifrit — Attack binary"
  z_mod="rbob_cli.sh"
  buz_enroll RBZ_BOTTLE_SORTIE  "rbw-Is"  "${z_mod}" "rbob_ifrit_sortie"  "imprint"  "Run automated security test scripts inside the Bottle"

  # Image — container image operations (rbw-i, UPPER=mutates, lower=read)
  #
  # Primary layer: the type-blind, path-polymorphic raw trio on bare verb
  # letters — il (list, narrow by raw GAR path), iw (wrest any ref), iJ
  # (jettison a tag/version below package grain). These act on ANY rbi_*
  # namespace; whole-package delete stays with the semantic verbs (banish/
  # abjure). The bare verb letters il/iw/iJ are the FINAL-FORM colophons; iw
  # and iJ deliberately violate terminal exclusivity while their per-domain
  # children survive — a transitional state, resolved when the children retire.
  #
  # Surviving per-domain variants (retire at the made-side retrofit):
  # hallmarks (h) only. Their verbs: rekon (member-list), audit
  # (catalog-list), wrest (pull), Jettison (delete).
  buz_group RBZ__GROUP_IMAGE      "rbw-i"   "Image — Container image operations"
  z_mod="rbfl0_cli.sh"
  buz_enroll RBZ_LIST_IMAGES            "rbw-il"  "${z_mod}" "rbfl_list"                  "param1"  "List GAR contents by raw path (type-blind; omit arg for top namespaces)"
  buz_enroll RBZ_WREST_IMAGE            "rbw-iw"  "${z_mod}" "rbfl_wrest"                 "param1"  "Wrest any image from registry by raw ref (path-polymorphic)"
  buz_enroll RBZ_JETTISON_IMAGE         "rbw-iJ"  "${z_mod}" "rbfl_jettison"             "param1"  "Jettison any image tag/version from registry by raw ref (path-polymorphic)"
  buz_enroll RBZ_REKON_HALLMARK         "rbw-irh" "${z_mod}" "rbfl_rekon_hallmark"        "param1"  "List ark basenames present under a hallmark's GAR subtree"
  buz_enroll RBZ_AUDIT_HALLMARKS        "rbw-iah" "${z_mod}" "rbfl_audit_hallmarks"       ""  "Audit hallmarks — list all hallmark identifiers"
  buz_enroll RBZ_WREST_HALLMARK_IMAGE   "rbw-iwh" "${z_mod}" "rbfl_wrest"                 "param1"  "Wrest a hallmark image from registry"
  buz_enroll RBZ_JETTISON_HALLMARK_IMAGE  "rbw-iJh" "${z_mod}" "rbfl_jettison"            "param1"  "Jettison a hallmark image tag from registry"

  # Marshal — lifecycle (rbw-M)
  buz_group RBZ__GROUP_MARSHAL    "rbw-M"   "Marshal — Lifecycle"
  buz_enroll RBZ_MARSHAL_ZERO           "rbw-MZ"  "rblm_cli.sh" "rblm_zero"      "param1"  "Zero regime to blank template (args: the intended tree's basename)"
  buz_enroll RBZ_MARSHAL_LUSTRATE       "rbw-ML"  "rblm_cli.sh" "rblm_lustrate"  ""  "Lustrate the release clone — erase site identity from every proscribed home"
  buz_enroll RBZ_MARSHAL_FEIGN          "rbw-MF"  "rblm_cli.sh" "rblm_feign"     ""  "Feign a station on the probe branch — write shape-valid stand-ins over the lustrated site fields"
  buz_enroll RBZ_MARSHAL_EXPEDE         "rbw-ME"  "rblm_cli.sh" "rblm_expede"    "param1"  "Expede the delivery candidate — build it by addition in a clone of the public repository"

  # Nameplate — cross-nameplate operations (rbw-n)
  buz_group RBZ__GROUP_NAMEPLATE  "rbw-n"   "Nameplate — Cross-nameplate operations"
  z_mod="rbrn_cli.sh"
  buz_enroll RBZ_LIST_NAMEPLATES        "rbw-rnl" "${z_mod}" "rbrn_list"    ""  "List all nameplates"
  buz_enroll RBZ_SURVEY_NAMEPLATES      "rbw-ni"  "${z_mod}" "rbrn_survey"  ""  "Survey nameplate status"
  buz_enroll RBZ_AUDIT_NAMEPLATES       "rbw-nv"  "${z_mod}" "rbrn_audit"   ""  "Validate all nameplates"
  buz_enroll RBZ_DRIVE_HALLMARK         "rbw-nd"  "${z_mod}" "rbrn_drive"   "param1"  "Drive a freshly-built hallmark into a nameplate's RBRN_*_HALLMARK (express-or-chain; args: field bottle|sentry [hallmark])"

  # Regime — config files (rbw-r)
  buz_group RBZ__GROUP_REGIME     "rbw-r"   "Regime — Config files"
  z_mod="rbrn_cli.sh"
  buz_enroll RBZ_RENDER_NAMEPLATE       "rbw-rnr" "${z_mod}" "rbrn_render"    "param1"  "Render nameplate regime"
  buz_enroll RBZ_VALIDATE_NAMEPLATE     "rbw-rnv" "${z_mod}" "rbrn_validate"  "param1"  "Validate nameplate regime"
  z_mod="rbrv_cli.sh"
  buz_enroll RBZ_LIST_VESSELS           "rbw-rvl" "${z_mod}" "rbrv_list"      ""        "List available vessel sigils"
  buz_enroll RBZ_RENDER_VESSEL          "rbw-rvr" "${z_mod}" "rbrv_render"    "param1"  "Render vessel regime"
  buz_enroll RBZ_VALIDATE_VESSEL        "rbw-rvv" "${z_mod}" "rbrv_validate"  "param1"  "Validate vessel regime"
  z_mod="rbfl0_cli.sh"
  buz_enroll RBZ_YOKE_RELIQUARY         "rbw-rvy" "${z_mod}" "rbfl_yoke"      "param1"  "Yoke a reliquary touchmark into every vessel's rbrv.env (wildcard fan-out)"
  buz_enroll RBZ_ANOINT_GRAFT           "rbw-rva" "${z_mod}" "rbfl_anoint"    "param1"  "Anoint a graft vessel with the previous build's hallmark (rewrites RBRV_GRAFT_IMAGE from chained facts)"
  buz_enroll RBZ_FEOFF_BOLE             "rbw-rvf" "${z_mod}" "rbfl_feoff"     "param1"  "Feoff a conjure vessel - elect its base anchor from a bole Lode touchmark (express-or-chain)"
  z_mod="rbrr_cli.sh"
  buz_enroll RBZ_RENDER_REPO            "rbw-rrr" "${z_mod}" "rbrr_render"    ""  "Render repo regime"
  buz_enroll RBZ_VALIDATE_REPO          "rbw-rrv" "${z_mod}" "rbrr_validate"  ""  "Validate repo regime"
  z_mod="rbrd_cli.sh"
  buz_enroll RBZ_RENDER_DEPOT           "rbw-rdr" "${z_mod}" "rbrd_render"    ""        "Render depot regime"
  buz_enroll RBZ_VALIDATE_DEPOT         "rbw-rdv" "${z_mod}" "rbrd_validate"  ""        "Validate depot regime"
  buz_enroll RBZ_INSCRIBE_DEPOT         "rbw-rdi" "${z_mod}" "rbrd_inscribe"  "param1"  "Inscribe RBRD tripwire image to GAR (bearer token via positional)"
  buz_enroll RBZ_CHECK_DEPOT            "rbw-rdc" "${z_mod}" "rbrd_check"     "param1"  "Check local rbrd.env against inscribed tripwire (bearer token via positional)"
  z_mod="rbrp_cli.sh"
  buz_enroll RBZ_RENDER_PAYOR           "rbw-rpr" "${z_mod}" "rbrp_render"    ""  "Render payor regime"
  buz_enroll RBZ_VALIDATE_PAYOR         "rbw-rpv" "${z_mod}" "rbrp_validate"  ""  "Validate payor regime"
  z_mod="rbrf_cli.sh"
  buz_enroll RBZ_RENDER_FEDERATION      "rbw-rfr" "${z_mod}" "rbrf_render"    ""  "Render federation regime"
  buz_enroll RBZ_VALIDATE_FEDERATION    "rbw-rfv" "${z_mod}" "rbrf_validate"  ""  "Validate federation regime"
  z_mod="rbrw_cli.sh"
  buz_enroll RBZ_RENDER_WORKFORCE       "rbw-rwr" "${z_mod}" "rbrw_render"    ""  "Render workforce regime"
  buz_enroll RBZ_VALIDATE_WORKFORCE     "rbw-rwv" "${z_mod}" "rbrw_validate"  ""  "Validate workforce regime"
  z_mod="rbro_cli.sh"
  buz_enroll RBZ_RENDER_OAUTH           "rbw-ror" "${z_mod}" "rbro_render"    ""  "Render OAuth regime"
  buz_enroll RBZ_VALIDATE_OAUTH         "rbw-rov" "${z_mod}" "rbro_validate"  ""  "Validate OAuth regime"

  # Theurge — test infrastructure (rbw-t). One pipeline: the theurge engine
  # (build/test/run/suite/single) dispatches through rbw_workbench like every
  # other rbw command — no second workbench. Suites fold the former
  # tP/tS/tT into rbw-ts imprints (gauntlet/skirmish/siege).
  buz_group RBZ__GROUP_THEURGE    "rbw-t"   "Theurge — Test infrastructure"
  z_mod="rbtd/rbte_cli.sh"
  # Build/Test carry the imprint channel solely to forward cargo passthrough
  # args ("$@"); the 2-segment filename leaves BURD_TOKEN_3 empty, so no folio
  # is consumed. (Empty channel would drop the args; param1 would eat the first.)
  buz_enroll RBZ_THEURGE_BUILD    "rbw-tb"  "${z_mod}" "rbte_build"   "imprint"  "Build the theurge crate"
  buz_enroll RBZ_THEURGE_TEST     "rbw-tt"  "${z_mod}" "rbte_test"    "imprint"  "Run theurge unit tests"
  buz_enroll RBZ_THEURGE_SUITE    "rbw-ts"  "${z_mod}" "rbte_suite"   "imprint"  "Run a named test suite"
  buz_enroll RBZ_THEURGE_FIXTURE  "rbw-tf"  "${z_mod}" "rbte_run"     "param1"   "Run a single named test fixture"
  buz_enroll RBZ_THEURGE_CASE     "rbw-tc"  "${z_mod}" "rbte_single"  "param1"   "Run one case against a charged Crucible (omit to list fixtures/cases)"
  buz_enroll RBZ_THEURGE_DOWSE    "rbw-td"  "${z_mod}" "rbte_dowse"   ""         "Dowse observed tariff history — per-suite and per-fixture durations from the station's logs-buk self-logs (read-only)"
  # Nihil does nothing by design — theurge-internal, zero cloud/filesystem side
  # effects. Sole consumer: the calibrant-coverage-* fixtures, which need a real
  # colophon to declare and invoke so the census enforcement has a subject.
  buz_enroll RBZ_THEURGE_NIHIL    "rbw-tn"  "${z_mod}" "rbte_nihil"   ""         "Nihil — synthetic colophon that does nothing, for the calibrant census coverage cases (no side effects)"
  z_mod="rbq_cli.sh"
  buz_enroll RBZ_QUALIFY_FAST       "rbw-tq"   "${z_mod}" "rbq_qualify_fast"        ""        "Fast qualify: tabtargets, colophons, nameplate health"
  buz_enroll RBZ_QUALIFY_RELEASE    "rbw-tr"   "${z_mod}" "rbq_qualify_release"     ""        "Release qualify: + shellcheck, full test suite"
  buz_enroll RBZ_QUALIFY_SHELLCHECK "rbw-tl"   "${z_mod}" "rbq_qualify_shellcheck"  ""        "Shellcheck only: BCG-configured static analysis, no test suite"

  readonly ZRBZ_KINDLED=1
}

######################################################################
# Rust const projection (colophons → RBTDGC_)

# The tomes rbtdgc_consts.rs is DEFINED OVER. Not a description of what some
# caller happened to kindle — the artifact's own roster, and the reason it is a
# constant here rather than an accident of each caller's furnish.
#
# The emitter walks the tomes open in the calling process. That made the generated
# file a function of its CALLER'S MEMORY: three processes produce it (the theurge
# build, rbq's freshness gate, and the release sterilizer), each sourcing its own
# modules, and a caller that forgot a tome emitted a SMALLER FILE with no
# complaint. The omission then surfaced as a stale-file verdict in a delivery
# candidate — a whole ceremony away from the missing source line that caused it.
# The assertion below converts that silence into a death at the point of the
# mistake. A tome minted tomorrow is added HERE, and every caller that has not
# kindled it dies naming it.
ZRBZ_CONSTS_TOME_ROLL=("rbz" "buwz")

# rbz_emit_consts() - Emit the complete generated colophon consts file to stdout.
# The single producer of rbtdgc_consts.rs content, shared by the theurge build
# (rbz_generate_consts), rbq's freshness gate, and the release sterilizer, so no
# two of them can ever diverge. Four sections under one banner: the colophon block
# (buz_emit_colophon_consts walks each rostered tome under its own add/strip
# prefixes — RB's RBTDGC_ run and the BUK zipper's BUWGC_ run), the rbcc
# single-homed set, the rbpc freehold test-rig set, and the rbgc propagation
# budget. rbcc_emit_consts is reachable here because every caller sources rbcc
# alongside rbz; rbpc_emit_consts and rbgc_emit_consts by the same arrangement.
rbz_emit_consts() {
  zrbz_sentinel

  local z_tome=""
  for z_tome in "${ZRBZ_CONSTS_TOME_ROLL[@]}"; do
    buz_tome_declared_predicate "${z_tome}" \
      || buc_die "rbz_emit_consts: tome '${z_tome}' is not kindled — the generated consts file is defined over ${ZRBZ_CONSTS_TOME_ROLL[*]}, and emitting without one would silently produce a smaller file. Source and kindle that zipper in this caller's furnish."
  done

  printf '%s\n' "// Generated by the theurge build — rbz + buwz colophons + rbcc + rbpc + rbgc constants. Do not edit."
  printf '%s\n' "// Regenerate: tt/rbw-tb.Build.sh"
  printf '%s\n' ""
  buz_emit_colophon_consts || buc_die "rbz_emit_consts: colophon emit failed"
  printf '%s\n' ""
  rbcc_emit_consts || buc_die "rbz_emit_consts: rbcc emit failed"
  printf '%s\n' ""
  rbpc_emit_consts || buc_die "rbz_emit_consts: rbpc emit failed"
  printf '%s\n' ""
  rbgc_emit_consts || buc_die "rbz_emit_consts: rbgc emit failed"
}

# rbz_generate_consts() - Write the colophon const file, only on difference.
# Args: target_path
# Emits to a temp file, diffs against the target, and copies only when changed
# (stable timestamps). The single producer for the generated file — rblm and
# the theurge build wrapper both call this; rbq's gate verifies via rbz_emit_consts.
rbz_generate_consts() {
  zrbz_sentinel

  local -r z_target="${1:-}"
  test -n "${z_target}" || buc_die "rbz_generate_consts: target path required"

  local -r z_tmp="${BURD_TEMP_DIR}/rbz_generate_consts.rs"
  rbz_emit_consts > "${z_tmp}" || buc_die "rbz_generate_consts: emit failed"

  if test -f "${z_target}" && [[ "$(<"${z_tmp}")" == "$(<"${z_target}")" ]]; then
    buc_log_args "Colophon consts already up to date: ${z_target}"
  else
    cp "${z_tmp}" "${z_target}" || buc_die "rbz_generate_consts: failed to write ${z_target}"
    buc_log_args "Generated: ${z_target}"
  fi
}

# rbz_generate_context() - Write the markdown tabtarget context, only on difference.
# Args: tt_dir, target_path
# Emits via buz_emit_context (which resolves frontispieces from tt_dir filenames),
# diffs against the target, and copies only when changed. Companion producer to
# rbz_generate_consts; the theurge build calls both, rbq's gate verifies via buz_emit_context.
rbz_generate_context() {
  zrbz_sentinel

  local -r z_tt_dir="${1:-}"
  local -r z_target="${2:-}"
  test -n "${z_tt_dir}" || buc_die "rbz_generate_context: tabtarget dir required"
  test -n "${z_target}" || buc_die "rbz_generate_context: target path required"

  local -r z_tmp="${BURD_TEMP_DIR}/rbz_generate_context.md"
  buz_emit_context "rbz" "${z_tt_dir}" > "${z_tmp}" || buc_die "rbz_generate_context: emit failed"

  if test -f "${z_target}" && [[ "$(<"${z_tmp}")" == "$(<"${z_target}")" ]]; then
    buc_log_args "Tabtarget context already up to date: ${z_target}"
  else
    cp "${z_tmp}" "${z_target}" || buc_die "rbz_generate_context: failed to write ${z_target}"
    buc_log_args "Generated: ${z_target}"
  fi
}

######################################################################
# Internal sentinel

zrbz_sentinel() {
  test "${ZRBZ_KINDLED:-}" = "1" || buc_die "Module rbz not kindled - call zrbz_kindle first"
}

# eof
