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
apt -y install wget gpg curl git build-essential cmake ninja-build pkg-config python3 python3-pip libssl-dev

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

# Resolve ROCm tools from PATH first so the script works across package layouts.
hipcc_path="$(command -v hipcc || true)"
if [[ -z "$hipcc_path" ]]; then
  echo "Could not find hipcc in PATH after installing ROCm packages."
  echo "Verify installation and rerun this script."
  exit 1
fi

# Prefer the canonical /opt/rocm symlink when available.
rocm_root="$(dirname "$(dirname "$hipcc_path")")"
if [[ -d /opt/rocm ]]; then
  rocm_root="/opt/rocm"
fi

export ROCM_PATH="$rocm_root"
export HIP_PATH="$rocm_root"
export HIPCXX="$hipcc_path"

# CMake 3.28+ rejects hipcc wrappers for CMAKE_HIP_COMPILER. Use clang directly.
hip_clang_path="$ROCM_PATH/llvm/bin/clang++"
if [[ ! -x "$hip_clang_path" ]]; then
  hip_clang_path="$(command -v clang++ || true)"
fi

if [[ -z "$hip_clang_path" ]]; then
  echo "Could not find a usable clang++ for CMake HIP compiler detection."
  exit 1
fi

default_amdgpu_targets="${DEFAULT_AMDGPU_TARGETS:-gfx1151}"

if [[ -z "${AMDGPU_TARGETS:-}" ]]; then
  export AMDGPU_TARGETS="$default_amdgpu_targets"
  echo "AMDGPU_TARGETS was not set; using hard-set default: $AMDGPU_TARGETS"
  echo "Override by running with AMDGPU_TARGETS=<gfx_target>."
fi

echo "Using AMDGPU_TARGETS=$AMDGPU_TARGETS"

sudo -u "$target_user" bash <<USER_SCRIPT
set -euo pipefail
export ROCM_PATH="$ROCM_PATH"
export HIP_PATH="$HIP_PATH"
export HIPCXX="$HIPCXX"
export HIP_CLANG_PATH="$hip_clang_path"
cd "$target_home"
if [[ ! -d llama.cpp ]]; then
  git clone https://github.com/ggerganov/llama.cpp.git
fi
cd llama.cpp
cmake -S . -B build -G Ninja -DGGML_HIP=ON -DAMDGPU_TARGETS="$AMDGPU_TARGETS" -DCMAKE_HIP_COMPILER="$hip_clang_path"
cmake --build build -j"$(nproc)"
USER_SCRIPT

echo "ROCm + llama.cpp complete. Reboot recommended (group changes)."
echo "Verify: /opt/rocm/bin/rocminfo | grep -i gfx"
