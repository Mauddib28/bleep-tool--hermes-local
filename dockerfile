FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 python3-pip \
    python3-venv \
    git curl wget \
    ffmpeg ripgrep \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create hermes user
RUN useradd -m -s /bin/bash hermes

# Switch to hermes user for installation
USER hermes
WORKDIR /home/hermes

# Install Hermes Agent using the official installer
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash

# Set proper PATH for the hermes command
ENV PATH="/home/hermes/.local/bin:${PATH}"

# Default command
CMD ["/bin/bash"]
