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
# Recipe Bottle Handbook Onboarding - Tadmor Security Evaluation

set -euo pipefail

test -z "${ZRBHOTS_SOURCED:-}" || return 0
ZRBHOTS_SOURCED=1

# Evaluator-intimate top/tail; mechanical middle delegates to
# rbhoct_crucible_trunk + rbhocq_crucible_quench.
#
# No cloud-build or global-suite references — this handbook teaches
# the local adversarial loop against kludged hallmarks. Airgap/moriah
# coverage belongs in Building for Crucibles, not here.

rbho_tadmor_security() {
  zrbho_sentinel

  buc_doc_brief "Verify Crucible containment under attack — charge tadmor and run the adversarial suite"
  buc_doc_shown || return 0

  local -r z_moniker="tadmor"
  local -r z_sentry_vessel="rbev-sentry-deb-tether"
  local -r z_bottle_vessel="rbev-bottle-ifrit-tether"
  local -r z_nameplate_file="${RBCC_moorings_dir}/${z_moniker}/${RBCC_rbrn_file}"

  local z_has_docker=0
  command -v docker >/dev/null 2>&1 && z_has_docker=1

  buh_section "Verify ${RBYC_CRUCIBLE} Containment Under Attack"
  buh_e
  buh_line "You are evaluating whether ${RBYC_RECIPE_BOTTLE}'s sandbox holds up"
  buh_line "when something inside actively tries to escape. This track walks"
  buh_line "you through building a ${RBYC_CRUCIBLE} locally and running an"
  buh_line "adversarial suite — 34 cases authored against the containment"
  buh_line "primitives — to verify each attack fails as designed."
  buh_e
  buh_line "This track uses the ${z_moniker} ${RBYC_NAMEPLATE}: the same ${RBYC_SENTRY}"
  buh_line "as the explorer track, paired with a ${RBYC_BOTTLE} that carries"
  buh_line "the ${RBYC_IFRIT} attack binary. The ${RBYC_BOTTLE} is a hostile workload"
  buh_line "that attempts escape, not a friendly one."
  buh_e
  buh_line "What you will see: each attack is both an attempt AND the observed"
  buh_line "response. A pass means the attack ran and was contained; the"
  buh_line "output shows you exactly what the ${RBYC_SENTRY} blocked and how."
  buh_e

  buh_line "Configure this handbook session:"
  buh_e
  buh_code "   export ${RBYC_HANDBOOK_NAMEPLATE_NAME}=${z_moniker}"
  buh_e
  buh_line "The kludge and commit commands below reference this ${RBYC_NAMEPLATE}"
  buh_line "by name. Export once and paste freely."
  buh_e

  if test "${z_has_docker}" = "0"; then
    buh_error "Docker is not available on this machine."
    buh_line  "Install Docker Desktop (or dockerd in WSL) and re-run this handbook."
    buh_e
    buh_tt  "Return to start: " "${RBZ_ONBOARD_START_HERE}"
    buh_e
    return 0
  fi

  rbhoct_crucible_trunk "${z_moniker}" "${z_sentry_vessel}" "${z_bottle_vessel}" "${z_nameplate_file}"

  buh_step1 "Tour the containment architecture"
  buh_e
  buh_line "The ${RBYC_CRUCIBLE} is three containers with distinct roles, structured"
  buh_line "for defense-in-depth. An attack that bypasses one layer still has"
  buh_line "to defeat the next."
  buh_e

  buh_step2 "${RBYC_SENTRY} layer — network policy enforcement"
  buh_e
  buh_line "The ${RBYC_SENTRY} runs two enforcement layers:"
  buh_e
  buh_line "  iptables  — packet filter in the kernel. Drops traffic to any IP"
  buh_line "              outside the CIDR allowlist. Applied before any"
  buh_line "              routing decision the workload can make."
  buh_e
  buh_line "  dnsmasq   — DNS resolver. Returns answers only for allowlisted"
  buh_line "              domain names. Non-allowlisted queries fail to"
  buh_line "              resolve, so the workload cannot get an IP to"
  buh_line "              connect to in the first place."
  buh_e
  buh_line "Both layers must agree for traffic to pass. Neither by itself is"
  buh_line "sufficient — iptables alone cannot stop IP-literal exfiltration to"
  buh_line "an allowlisted CIDR; dnsmasq alone cannot stop queries bypassing"
  buh_line "the local resolver. The pair closes both paths."
  buh_e
  buh_line "If either layer fails silently, the other holds the line — the"
  buh_line "adversarial suite exercises this directly."
  buh_e

  buh_step2 "${RBYC_PENTACLE} layer — namespace ownership"
  buh_e
  buh_line "The ${RBYC_PENTACLE} is a dedicated container that owns the network"
  buh_line "namespace shared with the ${RBYC_BOTTLE}. The ${RBYC_BOTTLE} attaches"
  buh_line "to this namespace at ${RBYC_CHARGE} time; it never owns network"
  buh_line "primitives itself."
  buh_e
  buh_line "Why not give the ${RBYC_BOTTLE} its own namespace? If the ${RBYC_BOTTLE}"
  buh_line "could modify its own network state, escape attempts would target"
  buh_line "those primitives directly. Isolating namespace ownership into a"
  buh_line "separate container puts the mutable network state out of reach"
  buh_line "from anything running inside the ${RBYC_BOTTLE}."
  buh_e

  buh_step2 "${RBYC_BOTTLE} layer — unprivileged workload"
  buh_e
  buh_line "The ${RBYC_BOTTLE} itself runs as an unprivileged user with no"
  buh_line "network capabilities. iptables manipulation would need CAP_NET_ADMIN;"
  buh_line "namespace modification would need CAP_SYS_ADMIN; raw sockets would"
  buh_line "need CAP_NET_RAW. None are present."
  buh_e
  buh_line "The three layers compose: ${RBYC_SENTRY} enforces policy, ${RBYC_PENTACLE}"
  buh_line "owns the namespace, ${RBYC_BOTTLE} runs the workload without the"
  buh_line "primitives required to bypass either layer above."
  buh_e

  buh_step1 "Meet ${RBYC_IFRIT} and ${RBYC_THEURGE}"
  buh_e
  buh_line "${RBYC_IFRIT} is the attack binary. It lives inside the bottle-ifrit image"
  buh_line "and carries a catalog of containment-violation attempts — DNS"
  buh_line "tunneling, IP-literal exfiltration, raw socket use, namespace"
  buh_line "escape, filesystem breakout, and similar primitives."
  buh_e
  buh_line "Claude Code sessions with full visibility into ${RBYC_RECIPE_BOTTLE}'s"
  buh_line "internals authored the suite. Each attack was designed against a"
  buh_line "known containment boundary, with the explicit goal of finding a"
  buh_line "gap. The cases preserve the reasoning for each attempt — you can"
  buh_line "read them as an evaluator, not just run them."
  buh_e
  buh_line "${RBYC_THEURGE} coordinates the test. It runs outside the ${RBYC_CRUCIBLE}"
  buh_line "and orchestrates each case: ${RBYC_CHARGE} the ${RBYC_CRUCIBLE},"
  buh_line "dispatch ${RBYC_IFRIT} to attempt one attack, observe the attack's"
  buh_line "behavior inside the ${RBYC_BOTTLE} AND the ${RBYC_SENTRY}'s response"
  buh_line "from outside, compare against expected."
  buh_e
  buh_line "A case passes when the attack ran AND the sandbox responded as"
  buh_line "designed. The output is not 'did the test pass' — it is 'what"
  buh_line "did ${RBYC_IFRIT} try, and what stopped it'."
  buh_e

  buh_step1 "Run the security suite"
  buh_e
  buh_line "The full ${z_moniker} fixture runs all 34 cases against the ${RBYC_CRUCIBLE}"
  buh_line "you just charged:"
  buh_e
  buh_tt  "   " "rbw-tf" "" " ${z_moniker}"
  buh_e
  buh_line "Expect green across the board. A red case surfaces either a"
  buh_line "containment regression or a test that needs updating against a"
  buh_line "primitive that changed — both warrant attention."
  buh_e
  buh_line "For iterative debugging or a deep-dive on a single attack, run"
  buh_line "one case against an already-charged ${RBYC_CRUCIBLE}:"
  buh_e
  buh_tt  "   " "rbw-tc" "" " ${z_moniker} [case-name]"
  buh_e
  buh_line "Omit the case name to list all 34. Useful when investigating a"
  buh_line "specific failure without re-running the full fixture."
  buh_e
  buh_line "Reading results:"
  buh_e
  buh_line "  green    — the attack ran to completion and the sandbox"
  buh_line "             response matched expected containment behavior."
  buh_e
  buh_line "  red      — the attack either succeeded (containment gap) or"
  buh_line "             failed in an unexpected way (test drift)."
  buh_e
  buh_line "  per-case — output shows what ${RBYC_IFRIT} tried, what the ${RBYC_SENTRY}"
  buh_line "             logged, and how the assertion compared the two."
  buh_e

  rbhocq_crucible_quench "${z_moniker}"

  buh_section "What you evaluated"
  buh_e
  buh_line "You exercised the complete containment suite against a local"
  buh_line "${RBYC_CRUCIBLE}. What the results tell you:"
  buh_e
  buh_line "  - Defense-in-depth holds against 34 distinct attack primitives"
  buh_line "  - The ${RBYC_SENTRY}'s dual enforcement closes both IP-literal"
  buh_line "    and DNS-based exfiltration paths"
  buh_line "  - Namespace isolation and unprivileged-user discipline prevent"
  buh_line "    the ${RBYC_BOTTLE} from modifying its own network state"
  buh_e
  buh_line "The adversarial suite is live infrastructure — it must stay green"
  buh_line "as the codebase evolves. Changes that affect containment are"
  buh_line "gated on it passing."
  buh_e
  buh_line "What you ran locally against kludged ${RBYC_HALLMARKS} is the same"
  buh_line "suite that would run against cloud-built ${RBYC_HALLMARKS} on the"
  buh_line "airgap chain. The attack surface is the ${RBYC_CRUCIBLE}; the"
  buh_line "build provenance is evaluated separately."
  buh_e

  buh_tt  "Return to start: " "${RBZ_ONBOARD_START_HERE}"
  buh_e
}

# eof
