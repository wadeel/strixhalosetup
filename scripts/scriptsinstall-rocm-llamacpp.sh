#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

target_user="${SUDO_USER:-${USER}}"
target_home="$(getent passwd "$target_user" | cut -d: -f6)"

export DEBIAN_FRONTEND=noninteractive

recover_apt_update() {
  local apt_log
  apt_log="$(mktemp)"

  if apt update 2>&1 | tee "$apt_log"; then
    rm -f "$apt_log"
    return 0
  fi

  mapfile -t broken_repos < <(
    sed -n -E "s/^E: The repository '([^']+)' does not have a Release file\\./\\1/p" "$apt_log"
  )

  if [[ ${#broken_repos[@]} -eq 0 ]]; then
    echo "apt update failed for a reason other than a missing Release file."
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
      if grep -Fq "$repo_url" "$src_file"; then
        mv "$src_file" "${src_file}.disabled-by-strixhalosetup"
        echo "   disabled: $src_file"
      fi
    done

    if [[ -f /etc/apt/sources.list ]]; then
      sed -i -E "\|^[[:space:]]*deb[[:space:]].*${repo_url}.*${repo_suite}| s|^|# disabled-by-strixhalosetup |" /etc/apt/sources.list
    fi
  done
  shopt -u nullglob

  rm -f "$apt_log"
  apt update
}

recover_apt_update
apt -y install wget gpg curl git build-essential cmake ninja-build pkg-config python3 python3-pip libssl-dev

# One-time cleanup for older ROCm package stacks/repos so amdgpu-install starts clean.
rm -f /etc/apt/sources.list.d/rocm.list /etc/apt/preferences.d/rocm-pin-600
apt -y purge 'rocm-*' 'hip*' 'roc*' 'amdgpu-dkms' 'amdgpu' || true
apt -y autoremove --purge || true

amdgpu_installer_deb='amdgpu-install_7.2.70200-1_all.deb'
amdgpu_installer_url='https://repo.radeon.com/amdgpu-install/25.35/ubuntu/noble/amdgpu-install_7.2.70200-1_all.deb'
wget -qO "$amdgpu_installer_deb" "$amdgpu_installer_url"
apt -y install "./$amdgpu_installer_deb"
amdgpu-install -y --usecase=rocm,hiplibsdk
rm -f "$amdgpu_installer_deb"

recover_apt_update
apt -y install rocm-cmake rocm-hip-runtime rocm-hip-runtime-dev rocm-hip-sdk rocm-smi-lib rocminfo hipcc

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
cmake -S . -B build -G Ninja -DGGML_HIP=ON -DGGML_CCACHE=OFF -DAMDGPU_TARGETS="$AMDGPU_TARGETS" -DCMAKE_HIP_COMPILER="$hip_clang_path"
cmake --build build -j"$(nproc)"
USER_SCRIPT

echo "ROCm + llama.cpp complete. Reboot recommended (group changes)."
echo "Verify: /opt/rocm/bin/rocminfo | grep -i gfx"
