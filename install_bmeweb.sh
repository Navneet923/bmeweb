#!/usr/bin/env bash
set -euo pipefail

echo "Updating system and installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg software-properties-common

echo "Adding Docker's GPG key and repository..."
sudo install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi
ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Installing Docker Engine..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Starting Docker service..."
sudo systemctl enable --now docker

# Add the invoking user (correct even when using sudo)
TARGET_USER="${SUDO_USER:-$USER}"
echo "Adding user '${TARGET_USER}' to the docker group..."
sudo usermod -aG docker "$TARGET_USER"

echo "Verifying Docker and Docker Compose installations..."
docker --version || echo "NOTE: open a new shell or run: newgrp docker"
docker compose version || echo "NOTE: 'docker compose' may need a re-login to pick up group membership."

echo "Bme Web setup...."

APP_DIR="/home/bmeweb"
IMAGES_DIR="${APP_DIR}/images"
IMAGE_TAR="bmeweb15102025.tar"

# Check paths before proceeding
if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: App directory not found: $APP_DIR"; exit 1
fi
if [[ ! -d "$IMAGES_DIR" ]]; then
  echo "WARN: Images directory not found: $IMAGES_DIR"
fi

# Safer permissions
echo "Setting permissions (safe defaults)..."
sudo find "$APP_DIR" -type d -exec chmod 755 {} \;
sudo find "$APP_DIR" -type f -exec chmod 644 {} \;

# Load image (use sudo/newgrp-safe)
if [[ -f "${IMAGES_DIR}/${IMAGE_TAR}" ]]; then
  echo "Loading Docker image from ${IMAGES_DIR}/${IMAGE_TAR} ..."
  sudo docker load -i "${IMAGES_DIR}/${IMAGE_TAR}"
else
  echo "WARN: Image tar not found: ${IMAGES_DIR}/${IMAGE_TAR} (skipping docker load)"
fi

# Bring up with modern Compose v2
if [[ -f "${APP_DIR}/docker-compose.yml" || -f "${APP_DIR}/compose.yml" || -f "${APP_DIR}/compose.yaml" ]]; then
  echo "Starting services with docker compose..."
  (cd "$APP_DIR" && sudo docker compose up -d)
else
  echo "WARN: No compose file found; expected docker-compose.yml / compose.yml / compose.yaml"
fi

echo "Listing containers..."
sudo docker ps -a

echo "bmeweb setup done!"
echo "Open your browser to the machine IP:PORT your app exposes."
echo "If just added to 'docker' group, log out/in or run: newgrp docker"
