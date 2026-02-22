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

# Resolve ROCm tools from PATH first so the script works across package layouts.
hipcc_path="$(command -v hipcc || true)"
hipconfig_path="$(command -v hipconfig || true)"
rocminfo_path="$(command -v rocminfo || true)"

if [[ -z "$hipcc_path" || -z "$hipconfig_path" ]]; then
  echo "Could not find hipcc/hipconfig in PATH after installing ROCm packages."
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

if [[ -z "${AMDGPU_TARGETS:-}" ]]; then
  if [[ -z "$rocminfo_path" ]]; then
    rocminfo_path="$rocm_root/bin/rocminfo"
  fi

  detect_targets() {
    local from_rocminfo=""
    local from_hipconfig=""
    local from_hipcc=""

    if [[ -x "$rocminfo_path" ]]; then
      from_rocminfo="$("$rocminfo_path" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i ~ /^gfx[0-9a-z]+$/) print $i}' | sort -u | paste -sd';' -)"
    fi

    if [[ -x "$hipconfig_path" ]]; then
      from_hipconfig="$("$hipconfig_path" --amdgpu-target 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i ~ /^gfx[0-9a-z]+$/) print $i}' | sort -u | paste -sd';' -)"
    fi

    if [[ -x "$hipcc_path" ]]; then
      from_hipcc="$("$hipcc_path" --offload-arch 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i ~ /^gfx[0-9a-z]+$/) print $i}' | sort -u | paste -sd';' -)"
    fi

    if [[ -n "$from_rocminfo" ]]; then
      printf '%s' "$from_rocminfo"
      return
    fi

    if [[ -n "$from_hipconfig" ]]; then
      printf '%s' "$from_hipconfig"
      return
    fi

    if [[ -n "$from_hipcc" ]]; then
      printf '%s' "$from_hipcc"
      return
    fi
  }

  detected_targets="$(detect_targets || true)"
  if [[ -z "$detected_targets" ]]; then
    echo "Could not auto-detect AMD GPU target."
    echo "Checked rocminfo, hipconfig --amdgpu-target, and hipcc --offload-arch."
    echo "hipcc: $hipcc_path"
    echo "hipconfig: $hipconfig_path"
    echo "rocminfo: $rocminfo_path"
    echo "Set AMDGPU_TARGETS manually (example: AMDGPU_TARGETS=gfx1100)."
    exit 1
  fi
  export AMDGPU_TARGETS="$detected_targets"
fi

echo "Using AMDGPU_TARGETS=$AMDGPU_TARGETS"

sudo -u "$target_user" bash <<USER_SCRIPT
set -euo pipefail
export ROCM_PATH="$ROCM_PATH"
export HIP_PATH="$HIP_PATH"
export HIPCXX="$HIPCXX"
cd "$target_home"
if [[ ! -d llama.cpp ]]; then
  git clone https://github.com/ggerganov/llama.cpp.git
fi
cd llama.cpp
cmake -S . -B build -G Ninja -DGGML_HIP=ON -DAMDGPU_TARGETS="$AMDGPU_TARGETS" -DCMAKE_HIP_COMPILER="$HIPCXX"
cmake --build build -j"$(nproc)"
USER_SCRIPT

echo "ROCm + llama.cpp complete. Reboot recommended (group changes)."
echo "Verify: /opt/rocm/bin/rocminfo | grep -i gfx"
