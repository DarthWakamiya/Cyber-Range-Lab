#!/bin/bash
# provision-vm.sh
#
# Run this ON a fresh Ubuntu 22.04 VM guest (e.g. one created on a Proxmox
# host by your infra team). This script does NOT install or configure
# Proxmox itself Proxmox is the hypervisor layer and is assumed to
# already exist; this only provisions the GUEST OS to run the lab.
#
# Usage: bash provision-vm.sh

set -e

echo "[*] Updating system packages..."
sudo apt-get update -y

echo "[*] Installing prerequisites..."
sudo apt-get install -y ca-certificates curl gnupg git

echo "[*] Installing Docker Engine + Compose plugin..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
else
  echo "    Docker already installed, skipping."
fi

echo "[*] Verifying Docker + Compose..."
docker --version
docker compose version

REPO_URL="${1:-https://github.com/DarthWakamiya/Cyber-Range-Lab.git}"
DEST_DIR="nmd-lab"

if [ ! -d "$DEST_DIR" ]; then
  echo "[*] Cloning lab repository..."
  git clone "$REPO_URL" "$DEST_DIR"
else
  echo "    Repo directory already exists, pulling latest changes..."
  (cd "$DEST_DIR" && git pull)
fi

cd "$DEST_DIR"

echo "[*] Building and starting the lab (web + blue-team + log-injector)..."
sudo docker compose up -d --build

echo ""
echo "[+] Provisioning complete."
echo "    Web app (Red Team target): http://$(hostname -I | awk '{print $1}'):3075"
echo "    SSH (Blue Team access):    ssh analyst@$(hostname -I | awk '{print $1}') -p 2275"
echo "    (SSH password: blue_team_rocks)"
