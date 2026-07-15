#!/bin/sh
# RBGJV Step 01: Prepare verification keys
# Builder: alpine (from reliquary)
# Entrypoint: sh (not bash — alpine does not have bash)
# Substitutions: _RBGV_VESSEL_MODE

set -eu
echo "=== Prepare verification keys ==="

# Conjure-only: write GCB attestor public key for DSSE envelope verification
if [ "${_RBGV_VESSEL_MODE}" = "rbnve_conjure" ]; then
  mkdir -p /workspace/keys
  # KMS: projects/verified-builder/locations/global/keyRings/attestor/cryptoKeys/google-hosted-worker/cryptoKeyVersions/1
  cat > /workspace/keys/google-hosted-worker.pub << 'KEYEOF'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEg9KII7kzr/30HBluf00y9WwtMFkE
qc3oCcFVH3QJ37IBLUv/MUApbnNHFfD75ayJ/a0F45xa+MLv5zoep+GxsA==
-----END PUBLIC KEY-----
KEYEOF
  echo "Attestor public keys written to /workspace/keys/"
fi
