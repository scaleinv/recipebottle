# ccyolo — Claude Code sandbox bottle for Recipe Bottle crucible
#
# SSH-accessible container running Claude Code. The sentry DNAT
# forwards ENTRY_PORT_WORKSTATION to this container's port 22.
# User SSHs in as "claude" (empty password, PAM-permissive),
# then runs `claude` to authenticate via OAuth copy/paste flow.
#
# Build context: rbev-vessels/rbev-bottle-ccyolo/build-context/

ARG RBF_IMAGE_1
FROM ${RBF_IMAGE_1}

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install SSH server and Claude Code operational dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server    `# SSH daemon for workstation entry via sentry DNAT`  \
    ca-certificates   `# TLS root certs — required for HTTPS to Anthropic API` \
    curl              `# HTTP client (Claude Code operational dependency)`  \
    git               `# Version control (Claude Code operational dependency)` \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally via npm (node and npm provided by base image)
# Pin version — v2.1.105+ has a bracketed paste regression that breaks
# OAuth code entry through SSH/docker-exec terminals.
RUN npm install -g @anthropic-ai/claude-code@2.1.89

# Create unprivileged claude user with empty password
RUN useradd -m -s /bin/bash claude && \
    passwd -d claude

# Generate SSH host keys
RUN ssh-keygen -A

# Configure SSH daemon
RUN mkdir -p /var/run/sshd                                       && \
    echo "Port 22"                    >> /etc/ssh/sshd_config    && \
    echo "PermitRootLogin no"         >> /etc/ssh/sshd_config    && \
    echo "PermitEmptyPasswords yes"   >> /etc/ssh/sshd_config    && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

# Configure PAM for permissive authentication (no password prompt)
RUN sed -i 's/@include common-auth/#@include common-auth/' /etc/pam.d/sshd && \
    echo "auth sufficient pam_permit.so" >> /etc/pam.d/sshd

# Ensure PATH includes npm global bin for SSH sessions
RUN echo 'export PATH="/usr/local/bin:$PATH"' >> /etc/bash.bashrc

# Preconfigure Claude Code for full autonomy (yolo mode).
# Inside a network-contained crucible, bypassing permission prompts is
# the correct posture — the sentry enforces the real security boundary.
RUN mkdir -p /home/claude/.claude && \
    echo '{"permissions":{"defaultMode":"bypassPermissions"}}' \
      > /home/claude/.claude/settings.json && \
    chown -R claude:claude /home/claude/.claude

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
