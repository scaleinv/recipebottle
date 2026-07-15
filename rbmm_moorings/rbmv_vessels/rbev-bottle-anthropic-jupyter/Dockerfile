# Base image resolved by Foundry (anchored GAR ref or upstream pass-through)
ARG RBF_IMAGE_1
FROM ${RBF_IMAGE_1}

# Define ARG and ENV: defaults for building remotely, from nameplate when used locally
ARG RBEV_BOTTLE_JUPYTER_PORT=8000
ENV RBEV_BOTTLE_JUPYTER_PORT=${RBEV_BOTTLE_JUPYTER_PORT}

ARG RBEV_BOTTLE_WORKDIR=/workspace
ENV RBEV_BOTTLE_WORKDIR=${RBEV_BOTTLE_WORKDIR}

# Add Jupyter-specific environment variables
ENV JUPYTER_BASE_URL="/"
ENV JUPYTER_IP="0.0.0.0"

# Install system dependencies and diagnostic tools
RUN apt-get update && apt-get install -y                                       \
    iputils-ping         `#For network connectivity tests`                     \
    iproute2             `#For network configuration`                          \
    net-tools            `#For network interface configuration and statistics` \
    dnsutils             `#For DNS lookups and diagnostics`                    \
    curl                 `#For making HTTP requests`                           \
    traceroute           `#For tracing network routes`                         \
    tcpdump              `#For packet analysis`                                \
    nmap                 `#For network discovery`                              \
    procps               `#For ps, top, etc.`                                  \
    netcat-openbsd       `#For network testing`                                \
    lsof                 `#For checking open ports/files`                      \
    htop                 `#For process monitoring`                             \
    strace               `#For system call tracing`                            \
    vim                  `#For file editing`                                   \
    wget                 `#For downloading files`                              \
    telnet               `#For testing TCP connections`                        \
    conntrack            `#For connection tracking`                            \
    socat                `#For multipurpose relay`                             \
    iptraf-ng            `#For interactive network monitoring`                 \
    iftop                `#For bandwidth monitoring`                           \
    mtr                  `#For network diagnostic combining ping & traceroute` \
    ethtool              `#For network interface card settings`                \
    bridge-utils         `#For bridge network diagnostics`                     \
    psmisc               `#For fuser, killall, etc.`                           \
    ipcalc               `#For IP calculations and subnet info`                \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir jupyter jupyterlab
RUN pip install --no-cache-dir anthropic

# Set the working directory to the mount point
WORKDIR ${RBEV_BOTTLE_WORKDIR}

# Generate Jupyter config and set dark theme using settings override
RUN jupyter lab --generate-config                                                                                                         &&\
    mkdir -p                                 /root/.jupyter/lab/user-settings/@jupyterlab/apputils-extension                              &&\
    echo '{"theme": "JupyterLab Dark"}'   >  /root/.jupyter/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings   &&\
    echo "c.ServerApp.allow_origin = '*'" >> /root/.jupyter/jupyter_server_config.py                                                       &&\
    echo "c.ServerApp.ip = '0.0.0.0'"     >> /root/.jupyter/jupyter_server_config.py

# Create a startup script with enhanced logging
RUN echo '#!/bin/sh'                                                                     >  /startup.sh  &&\
    echo 'echo "Starting Jupyter environment with enhanced logging..."'                 >>  /startup.sh  &&\
    echo 'echo "Network interface configuration:"'                                      >>  /startup.sh  &&\
    echo 'ip addr'                                                                      >>  /startup.sh  &&\
    echo 'echo "Current listening ports:"'                                              >>  /startup.sh  &&\
    echo 'netstat -tuln'                                                                >>  /startup.sh  &&\
    echo 'echo "Disable nag: Would you like to receive official Jupyter news?"'         >>  /startup.sh  &&\
    echo 'jupyter labextension disable "@jupyterlab/apputils-extension:announcements"'  >>  /startup.sh  &&\
    echo 'echo "Starting Jupyter Lab server..."'                                        >>  /startup.sh  &&\
    echo 'jupyter lab'                                        \
         '--ip=0.0.0.0'                                       \
         '--port=${RBEV_BOTTLE_JUPYTER_PORT}'                 \
         '--no-browser'                                       \
         '--allow-root'                                       \
         '--ServerApp.token=""'                               \
         '--ServerApp.password=""'                            \
         '--ServerApp.authenticate_prometheus=False'          \
         '--ServerApp.base_url=${JUPYTER_BASE_URL}'           \
         '--notebook-dir=${RBEV_BOTTLE_WORKDIR}'              \
         '--ServerApp.allow_origin="*"'                       \
         '--log-level=DEBUG'                                  \
                                                                                        >>  /startup.sh  &&\
    echo 'tail -f /dev/null'                                                            >>  /startup.sh  &&\
    chmod +x                                                                                /startup.sh

# Expose the Jupyter port
EXPOSE ${RBEV_BOTTLE_JUPYTER_PORT}

# Use the startup script as the entry point
CMD ["/startup.sh"]
