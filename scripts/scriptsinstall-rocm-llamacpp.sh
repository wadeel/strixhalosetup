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

cat > /etc/apt/preferences.d/rocm-pin-600 <<'PIN'
Package: hipcc rocminfo rocm-cmake rocm-hip-runtime rocm-hip-runtime-dev rocm-hip-sdk rocm-smi-lib
Pin: origin repo.radeon.com
Pin-Priority: 1001
PIN

apt update
apt -y --allow-downgrades install rocm-cmake rocm-hip-runtime rocm-hip-runtime-dev rocm-hip-sdk rocm-smi-lib rocminfo hipcc

usermod -aG render,video "$target_user"

if [[ -z "${AMDGPU_TARGETS:-}" ]]; then
  detected_target="$(/opt/rocm/bin/rocminfo 2>/dev/null | awk '/Name: *gfx/{print $2; exit}')"
  if [[ -z "$detected_target" ]]; then
    echo "Could not auto-detect AMD GPU target from rocminfo."
    echo "Set AMDGPU_TARGETS manually (example: AMDGPU_TARGETS=gfx1100)."
    exit 1
  fi
  export AMDGPU_TARGETS="$detected_target"
fi

echo "Using AMDGPU_TARGETS=$AMDGPU_TARGETS"

sudo -u "$target_user" bash <<USER_SCRIPT
set -euo pipefail
cd "$target_home"
if [[ ! -d llama.cpp ]]; then
  git clone https://github.com/ggerganov/llama.cpp.git
fi
cd llama.cpp
cmake -S . -B build -G Ninja -DGGML_HIP=ON -DAMDGPU_TARGETS="$AMDGPU_TARGETS"
cmake --build build -j"$(nproc)"
USER_SCRIPT

echo "ROCm + llama.cpp complete. Reboot recommended (group changes)."
echo "Verify: /opt/rocm/bin/rocminfo | grep -i gfx"
