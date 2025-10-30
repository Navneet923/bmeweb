cat > docker.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/Navneet923/bmeweb/main/install-dockeronline.sh"

# Pass through any env vars you set in this shell (e.g., APP_DIR, IMAGE_TAR)
# Just fetch and execute:
bash -c "$(curl -fsSL "$RAW_URL")"
EOF
