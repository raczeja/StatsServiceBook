FROM ubuntu:22.04

# Install prerequisites
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    sudo \
    ca-certificates \
    software-properties-common \
  && rm -rf /var/lib/apt/lists/*

# Install Docker (CLI)
RUN apt-get update \
  && apt-get install -y --no-install-recommends docker.io \
  && rm -rf /var/lib/apt/lists/*

# Install Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# Ensure the 'vscode' user exists in official devcontainers; add to docker group
RUN groupadd -f docker || true
RUN if id -u vscode >/dev/null 2>&1; then usermod -aG docker vscode || true; fi

CMD ["sleep", "infinity"]
