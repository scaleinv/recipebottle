#!/busybox/sh
# RBGJB Step 03: Resolve each populated base image slot's tag -> @sha256: digest
# Builder: gcrane (from reliquary — :debug variant carries /busybox/sh)
# Substitutions: _RBGY_IMAGE_1, _RBGY_IMAGE_2, _RBGY_IMAGE_3 (optional base refs)
#
# For each populated base slot, resolve the ref to its canonical manifest digest
# (gcrane manifest -> sha256 of the raw manifest bytes, the gcrane-fingerprint
# shape) and write the PINNED ref "<ref-without-tag>@sha256:<digest>" to the
# workspace file .resolved_base_n, consumed by the buildx step (rbgjb04).
#
# gcrane authenticates GAR ambiently via its google.Keychain (Mason SA, GCE
# metadata server); a public upstream base needs no auth. The resolve runs on the
# same worker pool as the build, so an airgap vessel resolves its anchored GAR
# base in-pool and a tether vessel resolves its pass-through upstream over egress.
# A scratch / unpopulated slot produces no file (and gets no build-arg, no label).

set -eu

# Resolve one base slot. Args: ref slot-number. Empty ref -> no-op (no file).
zrbgjb_resolve_slot() {
  z_ref="$1"
  z_n="$2"
  test -n "${z_ref}" || return 0

  # Already digest-pinned (an origin pinned upstream) — pass through unchanged.
  case "${z_ref}" in
    *@sha256:*)
      printf '%s' "${z_ref}" > ".resolved_base_${z_n}"
      echo "Base slot ${z_n} already pinned: ${z_ref}"
      return 0
      ;;
  esac

  z_manifest="/tmp/resolve-manifest-${z_n}"
  gcrane manifest "${z_ref}" > "${z_manifest}" \
    || { echo "FATAL: failed to resolve base slot ${z_n}: ${z_ref}" >&2; exit 1; }

  z_sha="$(sha256sum "${z_manifest}" | cut -d' ' -f1)"
  test -n "${z_sha}" || { echo "FATAL: empty digest for base slot ${z_n}: ${z_ref}" >&2; exit 1; }

  # Strip the tag (everything after the last colon) and pin to the resolved digest.
  z_pinned="${z_ref%:*}@sha256:${z_sha}"
  printf '%s' "${z_pinned}" > ".resolved_base_${z_n}"
  echo "Base slot ${z_n} resolved: ${z_ref} -> ${z_pinned}"
}

echo "=== Resolving base image digests ==="
zrbgjb_resolve_slot "${_RBGY_IMAGE_1}" 1
zrbgjb_resolve_slot "${_RBGY_IMAGE_2}" 2
zrbgjb_resolve_slot "${_RBGY_IMAGE_3}" 3
echo "=== Base digest resolution complete ==="
