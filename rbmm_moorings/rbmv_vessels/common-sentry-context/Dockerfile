# Debian bookworm-slim for minimal trust boundary sentry
ARG RBF_IMAGE_1
FROM ${RBF_IMAGE_1}

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install sentry operational packages + pentacle diagnostic packages
# (pentacle container shares this image for trusted network observation)
RUN apt-get update && apt-get install -y \
    bash            `# Shell for sentry setup script`       \
    iptables        `# Firewall rule configuration`         \
    dnsmasq         `# DNS forwarding for enclave`          \
    iproute2        `# Network configuration (ip command)`  \
    iputils-ping    `# ICMP tests (pentacle role)`            \
    dnsutils        `# dig/nslookup (pentacle role)`          \
    procps          `# pidof/ps for process inspection`       \
    tcpdump         `# Network probe diagnostic (scry)`       \
    && rm -rf /var/lib/apt/lists/*

# Pin iptables-legacy backend (nftables not available in slim)
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy

# Bake entrypoint scripts (sentry setup + pentacle routing)
# Source of truth: Tools/rbk/rbjs_sentry.sh, Tools/rbk/rbjp_pentacle.sh
# Changes require deliberate build→vouch cycle
COPY rbjs_sentry.sh  /opt/rbk/rbjs_sentry.sh
COPY rbjp_pentacle.sh /opt/rbk/rbjp_pentacle.sh
RUN chmod +x /opt/rbk/rbjs_sentry.sh /opt/rbk/rbjp_pentacle.sh

# Default: sentry entrypoint (pentacle overrides via compose command)
CMD ["/opt/rbk/rbjs_sentry.sh"]
