#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

target_user="${SUDO_USER:-${USER}}"
target_home="$(getent passwd "$target_user" | cut -d: -f6)"

export DEBIAN_FRONTEND=noninteractive
apt update
apt -y install wget gpg curl git build-essential cmake ninja-build pkg-config python3 python3-pip

mkdir -p /etc/apt/keyrings
wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg

cat > /etc/apt/sources.list.d/rocm.list <<'LIST'
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.3 noble main
LIST

apt update
apt -y install rocm-hip-runtime rocm-hip-sdk rocm-smi-lib rocminfo hipcc

usermod -aG render,video "$target_user"

sudo -u "$target_user" bash <<USER_SCRIPT
set -euo pipefail
cd "$target_home"
if [[ ! -d llama.cpp ]]; then
  git clone https://github.com/ggerganov/llama.cpp.git
fi
cd llama.cpp
cmake -S . -B build -G Ninja -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151
cmake --build build -j"$(nproc)"
USER_SCRIPT

echo "ROCm + llama.cpp complete. Reboot recommended (group changes)."
echo "Verify: /opt/rocm/bin/rocminfo | grep -i gfx"