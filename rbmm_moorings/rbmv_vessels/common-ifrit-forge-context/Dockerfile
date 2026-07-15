# Ifrit forge — pre-stages apt packages and warms cargo dependency cache
#
# Build-time fixture, not a runtime vessel. The forge image is conjured
# tethered, then enshrined into GAR as a base for the airgap ifrit build.
# By pre-staging all apt packages and compiled Rust dependencies, the
# airgap build needs zero network access — only project source compiles.
#
# Build context: rbev-vessels/common-ifrit-forge-context/
# Cargo.toml + Cargo.lock must stay in sync with common-ifrit-context/.

ARG RBF_IMAGE_1
FROM ${RBF_IMAGE_1}

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install network tools for security boundary probes (matches Dockerfile.tether)
RUN apt-get update && apt-get install -y --no-install-recommends \
    socat           `# Echo service on port 8888 (entry port security tests)`  \
    dnsutils        `# dig/nslookup for DNS security tests`                    \
    netcat-openbsd  `# nc for TCP connectivity tests`                          \
    traceroute      `# ICMP path verification tests`                           \
    strace          `# Syscall boundary mapping from inside the container`     \
    libcap2-bin     `# setcap for CAP_NET_RAW file capability on ifrit binary` \
    curl            `# HTTP client for ad-hoc connectivity diagnosis`          \
    && rm -rf /var/lib/apt/lists/*

# Layer-cached dependency build: copy manifests first, dummy compile
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs && \
    cargo build --release && \
    rm -rf src target/release/deps/rbid-* target/release/.fingerprint/rbid-*
