FROM node:20-bullseye

# Install foundry (cast, forge, anvil)
RUN apt-get update && apt-get install -y curl git && \
    curl -L https://foundry.paradigm.xyz | bash && \
    export PATH="/root/.foundry/bin:$PATH" && \
    /root/.foundry/bin/foundryup && \
    ln -s /root/.foundry/bin/cast /usr/local/bin/cast && \
    ln -s /root/.foundry/bin/forge /usr/local/bin/forge && \
    ln -s /root/.foundry/bin/anvil /usr/local/bin/anvil && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Hyperlane CLI
ARG CLI_VERSION=16.2.0
RUN npm i -g @hyperlane-xyz/cli@${CLI_VERSION}

# Setup Node modules for scripts
RUN mkdir -p /opt/hyperlane && cd /opt/hyperlane && npm init -y && npm i ethers yaml
ENV NODE_PATH=/opt/hyperlane/node_modules

# Set working directory
WORKDIR /work

# Copy deployment scripts (these need to be copied into build context)
COPY deploy_core.sh /usr/local/bin/deploy_core.sh
COPY warp_routes.sh /usr/local/bin/warp_routes.sh
COPY seed_liquidity.sh /usr/local/bin/seed_liquidity.sh

# Copy utility scripts
COPY scripts/send_warp.sh /usr/local/bin/send_warp.sh
COPY scripts/balances.js /usr/local/bin/balances.js
COPY scripts/parse_txhash.js /usr/local/bin/parse_txhash.js

# Copy common utilities
COPY common.sh /usr/local/bin/common.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh

# Default command
CMD ["sleep", "infinity"]