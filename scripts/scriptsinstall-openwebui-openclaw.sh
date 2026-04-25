#!/usr/bin/env bash
set -euo pipefail

# Install Open WebUI (Docker) and optionally clone an OpenClaw project.
#
# Usage examples:
#   bash scripts/scriptsinstall-openwebui-openclaw.sh
#   OPENCLAW_REPO_URL='https://github.com/<org>/openclaw.git' bash scripts/scriptsinstall-openwebui-openclaw.sh
#   OPENWEBUI_PORT=3001 bash scripts/scriptsinstall-openwebui-openclaw.sh

openwebui_port="${OPENWEBUI_PORT:-3000}"
openwebui_data_dir="${OPENWEBUI_DATA_DIR:-/opt/open-webui}"
openclaw_repo_url="${OPENCLAW_REPO_URL:-}"
openclaw_dir="${OPENCLAW_DIR:-$HOME/openclaw}"

recover_apt_update() {
  local apt_log
  apt_log="$(mktemp)"

  if sudo apt update 2>&1 | tee "$apt_log"; then
    rm -f "$apt_log"
    return 0
  fi

  mapfile -t broken_repos < <(
    sed -n -E "s/^E: The repository '([^']+)' does not have a Release file\\./\\1/p" "$apt_log"
  )

  if [[ ${#broken_repos[@]} -eq 0 ]]; then
    echo "sudo apt update failed for a reason other than a missing Release file."
    echo "See log: $apt_log"
    return 1
  fi

  echo "Detected broken apt repositories. Disabling related source files:"
  shopt -s nullglob
  for repo in "${broken_repos[@]}"; do
    repo_url="$(awk '{print $1}' <<<"$repo")"
    repo_suite="$(awk '{print $2}' <<<"$repo")"
    echo " - $repo_url ($repo_suite)"

    for src_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
      if sudo grep -Fq "$repo_url" "$src_file"; then
        sudo mv "$src_file" "${src_file}.disabled-by-strixhalosetup"
        echo "   disabled: $src_file"
      fi
    done

    if [[ -f /etc/apt/sources.list ]]; then
      sudo sed -i -E "\|^[[:space:]]*deb[[:space:]].*${repo_url}.*${repo_suite}| s|^|# disabled-by-strixhalosetup |" /etc/apt/sources.list
    fi
  done
  shopt -u nullglob

  rm -f "$apt_log"
  sudo apt update
}

if [[ $EUID -eq 0 ]]; then
  echo "Please run as a regular user with sudo privileges (not root)."
  exit 1
fi

if [[ ! "$openwebui_port" =~ ^[0-9]+$ ]]; then
  echo "OPENWEBUI_PORT must be numeric."
  exit 1
fi

recover_apt_update
sudo apt -y install ca-certificates curl git

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker Engine..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  recover_apt_update
  sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if ! groups | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  echo "Added $USER to docker group. Re-log before using Docker without sudo."
fi

sudo mkdir -p "$openwebui_data_dir"
sudo chown -R "$USER:$USER" "$openwebui_data_dir"

sudo docker pull ghcr.io/open-webui/open-webui:main
sudo docker rm -f open-webui >/dev/null 2>&1 || true
sudo docker run -d \
  --name open-webui \
  --restart unless-stopped \
  -p "${openwebui_port}:8080" \
  -e OPENAI_API_BASE_URL="http://host.docker.internal:8080/v1" \
  -v "${openwebui_data_dir}:/app/backend/data" \
  --add-host=host.docker.internal:host-gateway \
  ghcr.io/open-webui/open-webui:main

if [[ -n "$openclaw_repo_url" ]]; then
  if [[ -d "$openclaw_dir/.git" ]]; then
    echo "OpenClaw repo already exists at $openclaw_dir. Pulling latest changes."
    git -C "$openclaw_dir" pull --ff-only
  else
    git clone "$openclaw_repo_url" "$openclaw_dir"
  fi
  echo "OpenClaw repository ready at: $openclaw_dir"
else
  echo "OPENCLAW_REPO_URL not provided; skipping OpenClaw clone."
fi

echo "Open WebUI is running at: http://localhost:${openwebui_port}"
echo "Set llama.cpp server endpoint in Open WebUI to: http://host.docker.internal:8080/v1"
