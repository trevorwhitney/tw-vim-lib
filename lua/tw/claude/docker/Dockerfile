FROM node:22

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    dnsutils \
    fd-find \
    fzf \
    gh \
    git \
    gnupg2 \
    iproute2 \
    ipset \
    iptables \
    jq \
    jsonnet \
    nano \
    ncurses-bin \
    neovim \
    ripgrep \
    sudo \
    unzip \
    vim \
    zsh \
    # Add Python and UV for MCP tools
    python3 \
    python3-pip \
    python3-venv \
    # Add tools for building Go and other binaries
    build-essential \
    ca-certificates \
    # Puppeteer/Chrome dependencies
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgbm1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    lsb-release \
    wget \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# Install UV for zen-mcp-server
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Go
ARG GO_VERSION=1.22.6
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        curl -LO https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz && \
        tar -C /usr/local -xzf go${GO_VERSION}.linux-arm64.tar.gz && \
        rm go${GO_VERSION}.linux-arm64.tar.gz; \
    else \
        curl -LO https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz && \
        tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
        rm go${GO_VERSION}.linux-amd64.tar.gz; \
    fi
ENV PATH="/usr/local/go/bin:$PATH"
ENV GOPATH="/home/node/go"
ENV PATH="$GOPATH/bin:$PATH"

# Install Go tools
RUN go install github.com/go-delve/delve/cmd/dlv@latest && \
    go install github.com/fatih/faillint@latest && \
    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest && \
    go install gotest.tools/gotestsum@latest && \
    go install golang.org/x/tools/...@latest

# Install golang-perf (build from source as no pre-built binaries)
RUN go install golang.org/x/perf/cmd/benchstat@latest && \
    ln -s $GOPATH/bin/benchstat /usr/local/bin/golang-perf

# Create symlinks for expected binary names
RUN ln -s $GOPATH/bin/dlv /usr/local/bin/delve && \
    ln -s /usr/local/go/bin/go /usr/local/bin/gotools

# Install helm-docs
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        curl -LO https://github.com/norwoodj/helm-docs/releases/download/v1.13.1/helm-docs_1.13.1_Linux_arm64.tar.gz && \
        tar -xzf helm-docs_1.13.1_Linux_arm64.tar.gz && \
        mv helm-docs /usr/local/bin/ && \
        rm helm-docs_1.13.1_Linux_arm64.tar.gz; \
    else \
        curl -LO https://github.com/norwoodj/helm-docs/releases/download/v1.13.1/helm-docs_1.13.1_Linux_x86_64.tar.gz && \
        tar -xzf helm-docs_1.13.1_Linux_x86_64.tar.gz && \
        mv helm-docs /usr/local/bin/ && \
        rm helm-docs_1.13.1_Linux_x86_64.tar.gz; \
    fi

# Install jsonnet-bundler
RUN go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest && \
    ln -s $GOPATH/bin/jb /usr/local/bin/jsonnet-bundler

# Install security tools
# Snyk
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        curl -LO https://static.snyk.io/cli/latest/snyk-linux-arm64 && \
        chmod +x snyk-linux-arm64 && \
        mv snyk-linux-arm64 /usr/local/bin/snyk; \
    else \
        curl -LO https://static.snyk.io/cli/latest/snyk-linux && \
        chmod +x snyk-linux && \
        mv snyk-linux /usr/local/bin/snyk; \
    fi

# Trivy
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Install claude-code
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Install stylua
RUN npm install -g @johnnymorganz/stylua

# Install Gemini CLI
RUN npm install -g @google/gemini-cli

# Install Gemini MCP tool
RUN npm install -g gemini-mcp-tool

# Install Playwright and Puppeteer MCP server
RUN npm install -g @modelcontextprotocol/server-puppeteer && \
    npx puppeteer browsers install chrome && \
    npm install -g @playwright/mcp@latest

# Install OpenAI Codex
RUN npm i -g @openai/codex

# Create non-root user permissions
RUN usermod -aG sudo node
RUN echo "node ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh" >> /etc/sudoers
RUN echo "node ALL=(ALL) NOPASSWD: /usr/sbin/iptables" >> /etc/sudoers
RUN echo "node ALL=(ALL) NOPASSWD: /usr/sbin/ipset" >> /etc/sudoers
RUN echo "node ALL=(ALL) NOPASSWD: /usr/bin/apt" >> /etc/sudoers
RUN echo "node ALL=(ALL) NOPASSWD: /usr/bin/apt-get" >> /etc/sudoers

# Copy firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh

# Set up directories
RUN mkdir -p /home/node/.claude /home/node/.mcp /home/node/.local/bin /home/node/.config /commandhistory

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
