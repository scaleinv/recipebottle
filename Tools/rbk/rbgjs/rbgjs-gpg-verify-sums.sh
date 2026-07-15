#!/bin/bash
# RBGJS gpg-verify-sums — establish a vendor's published checksum under a pinned
# GPG signing key, the verified-against-published gate for vendor-tarball Lode
# kinds (wsl underpin). Fetch the published SHA256SUMS and its detached
# SHA256SUMS.gpg, fetch the signing key BY its pinned fingerprint into a clean
# throwaway keyring (the keyserver is NOT trusted — the pinned fingerprint is the
# trust anchor, so only a signature from exactly that key can pass), verify the
# detached signature, then extract the expected SHA-256 for one target filename.
# gpg is ensured present (apt-get on the Debian-based builder if absent) so a
# missing tool fails the signature check loud, never silently skips it.
#
# Runs cloud-side on purpose: the signature check is security-critical, so it
# belongs in the trusted GCP environment, never on the maybe-compromised
# workstation (RBSLU; paddock acquisition premise). The workstation only ever
# assembles the URL.
#   requires: SUMS_URL         URL of the published SHA256SUMS
#             SIG_URL          URL of the detached SHA256SUMS.gpg
#             TARGET_BASENAME  filename whose checksum line to extract
#             KEY_FPR          pinned 40-hex signing-key fingerprint (trust anchor)
#   provides: EXPECTED_SHA     verified-published 64-hex digest for TARGET_BASENAME
if ! command -v gpg >/dev/null 2>&1; then
  echo "gpg absent on builder — installing gnupg + dirmngr"
  if ! { apt-get update >/dev/null 2>&1 && apt-get install -y gnupg dirmngr >/dev/null 2>&1; }; then
    echo "FATAL: could not install gnupg for signature verification" >&2
    exit 1
  fi
fi

echo "Fetching published SHA256SUMS + detached signature"
curl -fSL --retry 3 -o /workspace/SHA256SUMS     "${SUMS_URL}" \
  || { echo "FATAL: failed to fetch SHA256SUMS: ${SUMS_URL}" >&2; exit 1; }
curl -fSL --retry 3 -o /workspace/SHA256SUMS.gpg "${SIG_URL}" \
  || { echo "FATAL: failed to fetch SHA256SUMS.gpg: ${SIG_URL}" >&2; exit 1; }

echo "Receiving signing key ${KEY_FPR} into a clean keyring"
GNUPGHOME=$(mktemp -d)
export GNUPGHOME
gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${KEY_FPR}" \
  || { echo "FATAL: failed to receive signing key ${KEY_FPR}" >&2; exit 1; }

# A clean keyring holding only the pinned key + a [GNUPG:] VALIDSIG status line is
# proof the sums were signed by exactly that key. --status-fd 1 makes the verdict
# machine-checkable instead of trusting gpg's exit code alone.
echo "Verifying SHA256SUMS signature against pinned fingerprint"
gpg --batch --status-fd 1 --verify /workspace/SHA256SUMS.gpg /workspace/SHA256SUMS 2>/dev/null \
  | grep -q "^\[GNUPG:\] VALIDSIG" \
  || { echo "FATAL: SHA256SUMS signature did not verify against ${KEY_FPR}" >&2; exit 1; }

# Exact-match the filename field (SHA256SUMS uses "<hash> *<file>" binary form, or
# "<hash>  <file>" text form) — awk field compare avoids regex pitfalls on the
# dots in the version string.
EXPECTED_SHA=$(awk -v f="${TARGET_BASENAME}" '$2 == f || $2 == "*" f {print $1}' /workspace/SHA256SUMS | head -n1)
test -n "${EXPECTED_SHA}" \
  || { echo "FATAL: no checksum line for ${TARGET_BASENAME} in SHA256SUMS" >&2; exit 1; }
echo "Published checksum (GPG-verified) for ${TARGET_BASENAME}: ${EXPECTED_SHA}"
