FROM node:20

# Install base dependencies
RUN apt-get update && apt-get install -y \
    git \
    zsh \
    sudo \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    nano \
    vim \
    neovim \
    gh \
    jq \
    unzip \
    gnupg2 \
    fzf \
    ripgrep \
    fd-find \
    ncurses-bin \
    # Add Python and UV for MCP tools
    python3 \
    python3-pip \
    python3-venv \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install UV for zen-mcp-server
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install claude-code
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Create non-root user permissions
RUN usermod -aG sudo node
RUN echo "node ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh" >> /etc/sudoers

# Copy firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh

# Copy Claude hooks
COPY hooks /opt/claude-hooks/
RUN chmod +x /opt/claude-hooks/*.sh

# Set up directories
RUN mkdir -p /home/node/.claude /home/node/.mcp /home/node/.local/bin /commandhistory
RUN chown -R node:node /home/node /commandhistory

# Add UV to PATH for node user
RUN echo 'export PATH="/home/node/.local/bin:$PATH"' >> /home/node/.bashrc
RUN echo 'export PATH="/home/node/.local/bin:$PATH"' >> /home/node/.zshrc

# Set environment variables
ENV NODE_OPTIONS="--max-old-space-size=4096"
ENV CLAUDE_CONFIG_DIR="/home/node/.claude"
ENV PATH="/home/node/.local/bin:$PATH"

USER node
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]