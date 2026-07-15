# Base image resolved by Foundry (anchored GAR ref or upstream pass-through)
ARG RBF_IMAGE_1
FROM ${RBF_IMAGE_1}

# Synthetic federation test IdP — Keycloak in dev mode (HTTP, lenient hostname,
# import-realm at boot). This is a local TEST identity provider, never production:
# the bootstrap admin and realm are test scaffolding, and the realm signing key
# is generated fresh on import (no durable secret committed).
ENV KC_BOOTSTRAP_ADMIN_USERNAME=admin
ENV KC_BOOTSTRAP_ADMIN_PASSWORD=admin

# Realm baked in for reproducibility (developed live, then exported and re-baked).
COPY fdkyclk-realm.json /opt/keycloak/data/import/fdkyclk-realm.json

# kc.sh is the base image's ENTRYPOINT; these are its subcommand + flags.
CMD ["start-dev", "--import-realm", "--http-port=8080"]
