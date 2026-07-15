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
# Recipe Bottle Handbook Onboarding - First Crucible (local builds)

set -euo pipefail

test -z "${ZRBHOFC_SOURCED:-}" || return 0
ZRBHOFC_SOURCED=1

# Explorer-intimate top/tail; mechanical middle delegates to
# rbhoct_crucible_trunk + rbhocq_crucible_quench.

rbho_first_crucible() {
  zrbho_sentinel

  buc_doc_brief "Start a Crucible using local builds — kludge, charge, SSH, verify containment"
  buc_doc_shown || return 0

  local -r z_moniker="ccyolo"
  local -r z_sentry_vessel="rbev-sentry-deb-tether"
  local -r z_bottle_vessel="rbev-bottle-ccyolo"
  local -r z_nameplate_file="${RBCC_moorings_dir}/${z_moniker}/${RBCC_rbrn_file}"
  local -r z_ssh_tabtarget="tt/rbw-cS.SshTo.${z_moniker}.sh"

  buyy_cmd_yawp "${z_ssh_tabtarget}";     local -r z_cmd_ssh="${z_buym_yelp}"

  local -r z_test_domain="www.internic.net"

  local z_has_docker=0
  command -v docker >/dev/null 2>&1 && z_has_docker=1

  buh_section "Start a ${RBYC_CRUCIBLE} Using Local Builds"
  buh_e
  buh_line "A ${RBYC_CRUCIBLE} is a sandboxed container environment with enforced"
  buh_line "network isolation. You are going to build one on your workstation"
  buh_line "and run Claude Code inside it — no cloud account, no credentials"
  buh_line "beyond your own Claude subscription."
  buh_e
  buh_line "This track uses the ${RBYC_CCYOLO} ${RBYC_NAMEPLATE}: a Claude Code sandbox that can"
  buh_line "only reach Anthropic. Everything else is blocked."
  buh_e
  buh_line "Prerequisite: a Claude OAuth subscription (you will authenticate"
  buh_line "inside the container via copy/paste from your browser)."
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

  buh_step1 "Enter the container and run Claude Code"
  buh_e
  buh_line "SSH into the ${RBYC_BOTTLE}:"
  buh_e
  buh_line "   ${z_cmd_ssh}"
  buh_e
  buh_line "You land as the claude user in ~/workspace, which contains"
  buh_line "a small sample project. Run Claude Code:"
  buh_e
  buh_code "   claude"
  buh_e
  buh_line "Claude Code will prompt you to authenticate. It opens a URL —"
  buh_line "copy it to your workstation browser, sign in with your Claude"
  buh_line "subscription, and paste the code back into the terminal."
  buh_e
  buh_warn "The ${RBYC_CCYOLO} ${RBYC_BOTTLE} pins Claude Code to a specific version."
  buh_line "Versions after v2.1.89 have a regression where paste does not"
  buh_line "work in the OAuth input prompt through SSH or docker exec"
  buh_line "(github.com/anthropics/claude-code/issues/47745). If you"
  buh_line "update the pin and paste stops working, type the code manually."
  buh_e
  buh_line "Once authenticated, Claude Code starts in full autonomy mode —"
  buh_line "no permission prompts. Inside a network-contained ${RBYC_CRUCIBLE},"
  buh_line "this is the correct posture: the ${RBYC_SENTRY} enforces the real"
  buh_line "security boundary, not the tool permission system."
  buh_e
  buh_line "Try your first interaction:"
  buh_e
  buh_code "   The count_words.sh script has bugs — can you find and fix them?"
  buh_e
  buh_line "Watch Claude read the files, identify issues, and edit the code."
  buh_line "The workspace is a bind mount — edits inside the ${RBYC_BOTTLE} are"
  buh_line "visible on the host filesystem, and vice versa. Your repo"
  buh_line "working tree gets dirty when you work inside the ${RBYC_BOTTLE},"
  buh_line "and that is the point."
  buh_e
  buh_line "Why SSH instead of docker exec?"
  buh_e
  buh_line "Docker exec is laggy and breaks terminal resize — Claude Code's"
  buh_line "interactive display needs correct dimensions. SSH gives a proper"
  buh_line "login session with full terminal negotiation."
  buh_e
  buh_line "If SSH fails, ${RBYC_RACK} is the diagnostic fallback —"
  buh_line "docker exec into the ${RBYC_BOTTLE} to inspect state:"
  buh_e
  buh_tt  "   " "${RBZ_CRUCIBLE_RACK}" "" " ${z_moniker}"
  buh_e

  buh_step1 "Verify network containment"
  buh_e
  buh_line "From inside the ${RBYC_BOTTLE} (while SSH'd in), you can test what's reachable."
  buh_line "The ${RBYC_CCYOLO} ${RBYC_NAMEPLATE} allows Anthropic and ${z_test_domain} (a test"
  buh_line "target — ICANN-owned, stable). Everything else is blocked."
  buh_e
  buh_line "Run these curl commands inside the ${RBYC_BOTTLE}:"
  buh_e
  buh_code "   curl -s -o /dev/null -w '%{http_code}' https://api.anthropic.com"
  buh_line "   Expected: 404 (API wants auth, not bare GET)"
  buh_e
  buh_code "   curl -s -o /dev/null -w '%{http_code}' https://claude.ai"
  buh_line "   Expected: 403 (web app)"
  buh_e
  buh_code "   curl -s -o /dev/null -w '%{http_code}' http://${z_test_domain}"
  buh_line "   Expected: 200 (test target on allowlist)"
  buh_e
  buh_code "   curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://google.com"
  buh_line "   Expected: 000 or timeout (blocked)"
  buh_e
  buh_code "   curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://registry.npmjs.org"
  buh_line "   Expected: 000 or timeout (blocked)"
  buh_e
  buh_line "The ${RBYC_SENTRY} enforces this with two layers:"
  buh_line "dnsmasq resolves only whitelisted domains; iptables drops"
  buh_line "packets to any IP not in the CIDR allowlist. Both layers"
  buh_line "must agree for traffic to pass."
  buh_e
  buh_line "${z_test_domain} is included in the ${RBYC_CCYOLO} ${RBYC_NAMEPLATE}"
  buh_line "specifically for this verification step — it proves the"
  buh_line "allowlist works for a non-Anthropic domain."
  buh_e

  rbhocq_crucible_quench "${z_moniker}"

  buh_step1 "The pattern"
  buh_e
  buh_line "Four verbs drive the local-${RBYC_CRUCIBLE} iteration loop. Own them"
  buh_line "and you can run any ${RBYC_NAMEPLATE} — ${z_moniker} was just this"
  buh_line "session's example."
  buh_e
  buyy_tt_yawp "${RBZ_CRUCIBLE_KLUDGE_BOTTLE}";          local -r z_tt_kludge="${z_buym_yelp}"
  buyy_tt_yawp "${RBZ_CRUCIBLE_CHARGE}" "${z_moniker}";  local -r z_tt_charge="${z_buym_yelp}"
  buyy_tt_yawp "${RBZ_CRUCIBLE_SSH}"    "${z_moniker}";  local -r z_tt_ssh="${z_buym_yelp}"
  buyy_tt_yawp "${RBZ_CRUCIBLE_QUENCH}" "${z_moniker}";  local -r z_tt_quench="${z_buym_yelp}"
  buh_line "   ${RBYC_KLUDGE}   ${z_tt_kludge}    build the ${RBYC_BOTTLE} image, write ${RBYC_HALLMARK} into ${RBYC_NAMEPLATE}"
  buh_line "   ${RBYC_CHARGE}   ${z_tt_charge}    start the three containers from the ${RBYC_NAMEPLATE}"
  buh_line "   SSH      ${z_tt_ssh}     log into the ${RBYC_BOTTLE} for interactive work"
  buh_line "   ${RBYC_QUENCH}   ${z_tt_quench}    stop and remove the ${RBYC_CRUCIBLE}"
  buh_e
  buh_line "${RBYC_CHARGE} tears down prior state on restart — you rarely ${RBYC_QUENCH}"
  buh_line "between iterations."
  buh_e

  buh_tt  "Return to start: " "${RBZ_ONBOARD_START_HERE}"
  buh_e
}

# eof
