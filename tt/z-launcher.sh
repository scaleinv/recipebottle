#!/bin/bash
# z-launcher.sh — universal tabtarget trampoline.
#
# Every tt/*.sh dispatches through here:
#   export BURD_LAUNCHER=launcher.<id>_workbench.sh
#   exec "${BASH_SOURCE[0]%/*}/z-launcher.sh" "${0##*/}" "${@}"
#
# Two responsibilities:
#   1. Normalize cwd to repo root so every workbench starts from a
#      deterministic directory regardless of where the user invoked the
#      tabtarget.
#   2. Resolve the moorings launcher named by BURD_LAUNCHER and exec it,
#      forwarding the tabtarget basename and user args unchanged. The
#      downstream launcher stub / bul_launch / bud_dispatch chain sees exactly
#      the argument shape it saw before this trampoline existed.
#
# BURD_LAUNCHER contract: the tabtarget exports BURD_LAUNCHER as a bare launcher
# basename (launcher.<id>_workbench.sh) ahead of dispatch. Every launcher
# co-locates in the moorings launcher dir, so the basename resolves directly —
# the exec line carries no launcher token and is byte-identical across every
# tabtarget. BURD_LAUNCHER flows downstream unchanged (it is the regime
# variable required by burd_regime and allowlisted by bud_dispatch).
#
# No-log behavior is NOT a launcher selection: it rides the BURD_NO_LOG env
# var the tabtarget exports ahead of dispatch (bul_launcher skips the BURS
# station load under it). The former separate nolog launcher was collapsed.

set -u

# Resolve own directory to an absolute path before any chdir.
z_dir="${BASH_SOURCE[0]%/*}"
case "${z_dir}" in
  /*) ;;
  *)  z_dir="${PWD}/${z_dir}" ;;
esac

test -n "${BURD_LAUNCHER:-}" || { echo "z-launcher: BURD_LAUNCHER unset" >&2; exit 1; }

# Project-intimate config-dir anchor. z-launcher is the SOLE file that knows
# where THIS project keeps its moorings/config dir (.buk, rbmm_moorings, …).
# The shared kit (bul_launcher, bubc) consumes BURD_CONFIG_DIR exported below
# rather than hardcoding a name — so one kit serves every consumer.
z_moorings_dir="rbmm_moorings"

# Resolve the launcher basename directly under the co-located launcher dir.
z_launcher="${z_dir}/../${z_moorings_dir}/rbml_launchers/${BURD_LAUNCHER}"

# Fail loud on a mistyped launcher rather than dispatching silently to nothing.
test -f "${z_launcher}" || {
  echo "z-launcher: no launcher '${BURD_LAUNCHER}' (looked for ${z_launcher})" >&2
  exit 1
}

# Normalize cwd to repo root for the dispatched workbench.
cd -P "${z_dir}/.." || { echo "z-launcher: cannot cd to repo root" >&2; exit 1; }

# Hand the config-dir location to the shared launcher (absolute, cd-proof).
export BURD_CONFIG_DIR="${PWD}/${z_moorings_dir}"

# Forward everything: tabtarget basename + user args.
exec "${z_launcher}" "${@}"
