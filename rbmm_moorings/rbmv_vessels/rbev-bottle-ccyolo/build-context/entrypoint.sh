#!/bin/bash
set -e

# Align container user UID/GID with host when bind-mounting workspace.
# RBOB_HOST_UID/GID arrive via compose environment from rbob_bottle.sh.
# Vessels without bind mounts simply don't set these — the block is skipped.
if [ -n "${RBOB_HOST_UID:-}" ] && [ -n "${RBRV_USER:-}" ]; then
  usermod  -o -u "${RBOB_HOST_UID}" "${RBRV_USER}"
  groupmod -o -g "${RBOB_HOST_GID}" "${RBRV_USER}"
fi

CLAUDE_HOME=$(getent passwd claude | cut -d: -f6)
chown -R claude:claude "${CLAUDE_HOME}"

# Start SSH daemon in foreground (container lifecycle tied to sshd)
exec /usr/sbin/sshd -D
