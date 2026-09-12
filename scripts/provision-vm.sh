#!/bin/bash
# provision-vm.sh
#
# One-shot, idempotent provisioning script for a fresh Ubuntu/Debian-based
# Linux VM guest (Proxmox, VirtualBox, Kali, bare metal any of them).
# Safe to run multiple times: every step checks whether it's already done
# before doing it again.
#
# Usage (from a totally fresh VM):
#   git clone <this-repo-url>
#   cd <repo-folder>
#   bash scripts/provision-vm.sh

set -e

echo "[*] Refreshing package index..."
sudo apt-get update -y

echo "[*] Installing prerequisites..."
sudo apt-get install -y ca-certificates curl gnupg git


# Docker Engine

echo "[*] Checking Docker Engine..."
if ! command -v docker &> /dev/null; then
  echo "    Not found installing via get.docker.com ..."
  curl -fsSL https://get.docker.com | sudo sh
else
  echo "    Docker Engine already installed, skipping."
fi


# Docker group

NEWLY_ADDED_TO_DOCKER_GROUP=0
if ! groups "$USER" | grep -qw docker; then
  echo "[*] Adding $USER to the docker group..."
  sudo usermod -aG docker "$USER"
  NEWLY_ADDED_TO_DOCKER_GROUP=1
else
  echo "[*] $USER is already in the docker group."
fi


# Docker Compose plugin installed SYSTEM-WIDE so it works for every user
# (including root via sudo), avoiding the "works without sudo, breaks with
# sudo" mismatch you'd get installing it only under $HOME/.docker.

echo "[*] Checking Docker Compose plugin..."
if ! docker compose version &> /dev/null; then
  echo "    Not found installing..."
  sudo apt-get install -y docker-compose-plugin || {
    echo "    apt package unavailable, falling back to direct binary download..."
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    sudo curl -fsSL \
      https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  }
else
  echo "    Docker Compose plugin already installed, skipping."
fi

echo "[*] Verifying Docker + Compose..."
docker --version
docker compose version


# Get the lab source (skip cloning if we're already inside the repo)

REPO_URL="${1:-https://github.com/DarthWakamiya/Cyber-Range-Lab.git}"
DEST_DIR="Cyber-Range-Lab"

if [ -f "docker-compose.yml" ] && [ -f "server.js" ]; then
  echo "[*] Already inside the lab repo, skipping clone."
elif [ -d "$DEST_DIR" ]; then
  echo "[*] $DEST_DIR already exists, pulling latest changes..."
  cd "$DEST_DIR"
  git pull
else
  echo "[*] Cloning lab repository..."
  git clone "$REPO_URL" "$DEST_DIR"
  cd "$DEST_DIR"
fi


# Build & start the stack.
# If we JUST added the user to the docker group in this same run, the
# current shell session doesn't have that membership yet (normally requires
# logout/login) so we use `sg docker` to apply it for this one command
# without forcing the user to log out.

echo "[*] Building and starting the lab (web + blue-team + log-injector)..."
if [ "$NEWLY_ADDED_TO_DOCKER_GROUP" = "1" ]; then
  sg docker -c "docker compose up -d --build"
else
  docker compose up -d --build
fi

echo ""
echo "[+] Provisioning complete."
IP="$(hostname -I | awk '{print $1}')"
echo "    Web app (Red Team target): http://${IP}:3075"
echo "    SSH (Blue Team access):    ssh analyst@${IP} -p 2275"
echo "    (SSH password: blue_team_rocks)"
if [ "$NEWLY_ADDED_TO_DOCKER_GROUP" = "1" ]; then
  echo ""
  echo "    Note: you were just added to the 'docker' group. Log out and back"
  echo "    in (or run 'newgrp docker') before running any further docker"
  echo "    commands directly without this script."
fi
