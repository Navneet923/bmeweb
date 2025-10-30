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

# ---------- Config (overridable via env) ----------
: "${APP_DIR:=/home/bmeweb}"
: "${IMAGES_DIR:=${APP_DIR}/images}"
: "${IMAGE_TAR:=bmeweb15102025.tar}"

# Docker Hub image (override if needed)
: "${DOCKER_IMAGE:=navneet8889/bmeweb15102025:uiapi}"

# Pull policy:
#   auto  -> load tar if present, otherwise docker pull
#   pull  -> always docker pull (ignores tar)
#   tar   -> only load tar (skip pull)
: "${IMAGE_SOURCE:=auto}"

# Optional: for private Docker Hub repos
: "${DOCKERHUB_USERNAME:=}"
: "${DOCKERHUB_PASSWORD:=}"   # or use DOCKERHUB_TOKEN

# Optional: directly run the image if no compose file is found
# Set RUN_DIRECT=yes and define PORTS (e.g. "8080:80") and NAME if desired.
: "${RUN_DIRECT:=no}"
: "${DIRECT_NAME:=bmeweb}"
: "${DIRECT_PORTS:=}"      # e.g. "8080:80" or "8080:80,8443:443"
# ---------------------------------------------------

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

# --- Image acquisition: tar vs Docker Hub ---
have_tar="no"
if [[ -f "${IMAGES_DIR}/${IMAGE_TAR}" ]]; then
  have_tar="yes"
fi

pull_image() {
  echo "Preparing to pull image: ${DOCKER_IMAGE}"
  if [[ -n "$DOCKERHUB_USERNAME" && -n "$DOCKERHUB_PASSWORD" ]]; then
    echo "Logging into Docker Hub as ${DOCKERHUB_USERNAME} ..."
    echo "$DOCKERHUB_PASSWORD" | sudo docker login -u "$DOCKERHUB_USERNAME" --password-stdin || {
      echo "WARN: Docker Hub login failed. Will try anonymous pull."
    }
  fi
  echo "Pulling ${DOCKER_IMAGE} ..."
  sudo docker pull "${DOCKER_IMAGE}"
}

case "$IMAGE_SOURCE" in
  pull)
    pull_image
    ;;
  tar)
    if [[ "$have_tar" == "yes" ]]; then
      echo "Loading Docker image from ${IMAGES_DIR}/${IMAGE_TAR} ..."
      sudo docker load -i "${IMAGES_DIR}/${IMAGE_TAR}"
    else
      echo "ERROR: IMAGE_SOURCE=tar but ${IMAGES_DIR}/${IMAGE_TAR} not found."
      exit 1
    fi
    ;;
  auto|*)
    if [[ "$have_tar" == "yes" ]]; then
      echo "Loading Docker image from ${IMAGES_DIR}/${IMAGE_TAR} ..."
      sudo docker load -i "${IMAGES_DIR}/${IMAGE_TAR}"
    else
      echo "Image tar not found: ${IMAGES_DIR}/${IMAGE_TAR} -> switching to Docker Hub pull"
      pull_image
    fi
    ;;
esac

echo "Local images:"
sudo docker image ls | sed '1,1!b; /^/!b' >/dev/null # no-op to avoid nonzero if empty
sudo docker image ls || true

# --- Start services ---
if [[ -f "${APP_DIR}/docker-compose.yml" || -f "${APP_DIR}/compose.yml" || -f "${APP_DIR}/compose.yaml" ]]; then
  echo "Starting services with docker compose..."
  (
    cd "$APP_DIR"
    # Tip: reference the image in compose as: image: ${DOCKER_IMAGE}
    DOCKER_IMAGE="${DOCKER_IMAGE}" sudo -E docker compose up -d
  )
else
  echo "No compose file found; expected docker-compose.yml / compose.yml / compose.yaml"
  if [[ "$RUN_DIRECT" == "yes" ]]; then
    echo "RUN_DIRECT=yes -> launching container directly from ${DOCKER_IMAGE}"
    ports_args=()
    if [[ -n "$DIRECT_PORTS" ]]; then
      IFS=',' read -ra arr <<< "$DIRECT_PORTS"
      for p in "${arr[@]}"; do
        ports_args+=( -p "$p" )
      done
    fi
    # Add volumes, env vars here if needed; this is a minimal run:
    sudo docker rm -f "$DIRECT_NAME" >/dev/null 2>&1 || true
    sudo docker run -d --name "$DIRECT_NAME" "${ports_args[@]}" "${DOCKER_IMAGE}"
  else
    echo "WARN: No compose file and RUN_DIRECT!=yes; skipping container start."
  fi
fi

echo "Listing containers..."
sudo docker ps -a

echo "bmeweb setup done!"
echo "Open your browser to the machine IP:PORT your app exposes."
echo "If just added to 'docker' group, log out/in or run: newgrp docker"
