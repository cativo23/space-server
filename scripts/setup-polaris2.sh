#!/bin/bash
# Setup script for polaris2 - Ubuntu server
# Run with: bash setup-polaris2.sh

set -e

echo "=== Polaris2 Setup Script ==="
echo ""

# Update system
echo "1. Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install dependencies
echo ""
echo "2. Installing dependencies..."
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    ufw \
    git

# Install Docker
echo ""
echo "3. Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
echo ""
echo "4. Adding user to docker group..."
sudo usermod -aG docker $USER

# Configure swap (8GB)
echo ""
echo "5. Creating 8GB swap file..."
sudo fallocate -l 8G /swap.img
sudo chmod 600 /swap.img
sudo mkswap /swap.img
sudo swapon /swap.img

# Make swap permanent
if ! grep -q "/swap.img" /etc/fstab; then
    echo "/swap.img none swap sw 0 0" | sudo tee -a /etc/fstab
fi

# Configure UFW firewall
echo ""
echo "6. Configuring UFW firewall..."
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH
sudo ufw allow 52222/tcp comment 'SSH'

# HTTP/HTTPS
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# Mail ports
sudo ufw allow 25/tcp comment 'SMTP'
sudo ufw allow 465/tcp comment 'SMTPS'
sudo ufw allow 587/tcp comment 'Submission'
sudo ufw allow 993/tcp comment 'IMAPS'
sudo ufw allow 143/tcp comment 'IMAP'

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Docker version:"
docker --version
docker compose version
echo ""
echo "Memory status:"
free -h
echo ""
echo "⚠️  IMPORTANT: Log out and back in for docker group to take effect"
echo "    Or run: newgrp docker"
