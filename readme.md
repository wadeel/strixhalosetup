# Strix Halo setup (Ubuntu Server 24.04 + AMDGPU installer + llama.cpp)

This repo installs ROCm via AMD's `amdgpu-install` package and builds `llama.cpp` with HIP support so you can run large GGUF models on AMD GPUs.

## 0) Prerequisites to verify first

- Ubuntu Server **24.04 (noble)**.
- Supported AMD GPU + driver stack compatible with AMDGPU installer 25.35 (ROCm 7.2 series packages).
- Enough memory/VRAM for your chosen 70B quantization:
  - 70B Q4 variants typically need roughly **40-50 GB** combined GPU/host memory.
  - Plan additional headroom for long context windows.

## 1) One-time bootstrap command (fresh server)

If this machine has nothing installed yet, run this first so you can clone from GitHub:

```bash
sudo apt update && sudo apt upgrade -y && sudo apt install -y git curl ca-certificates
```

Then clone this repo:

```bash
git clone https://github.com/<your-org-or-user>/strixhalosetup.git
cd strixhalosetup
```

## 2) Run ROCm + llama.cpp installer

```bash
sudo bash scripts/scriptsinstall-rocm-llamacpp.sh
```

What it does:
- Installs build dependencies and ROCm packages.
- Purges older ROCm package stacks/sources before reinstalling.
- Installs `https://repo.radeon.com/amdgpu-install/25.35/ubuntu/noble/amdgpu-install_7.2.70200-1_all.deb`.
- Adds your user to `render` and `video` groups.
- Uses a hard-set default `AMDGPU_TARGETS` (`gfx1151`) unless you override it manually.
- Uses ROCm `clang++` as the HIP compiler for CMake 3.28+ compatibility.
- Clones and builds `llama.cpp` with `-DGGML_HIP=ON`.

### One-time cleanup command (manual option)

If you want to purge older ROCm stacks yourself before running the installer:

```bash
sudo apt -y purge 'rocm-*' 'hip*' 'roc*' 'amdgpu-dkms' 'amdgpu' && sudo apt -y autoremove --purge
```

To override the default target manually, for example:

```bash
sudo AMDGPU_TARGETS=gfx1151 bash scripts/scriptsinstall-rocm-llamacpp.sh
```

### AMDGPU target behavior

This installer now hard-sets a default AMD GPU target when `AMDGPU_TARGETS` is not provided:

- Default: `gfx1151`
- Override anytime by setting `AMDGPU_TARGETS` explicitly.

Examples:

```bash
sudo bash scripts/scriptsinstall-rocm-llamacpp.sh
sudo AMDGPU_TARGETS=gfx1151 bash scripts/scriptsinstall-rocm-llamacpp.sh
```

## 3) Reboot and verify ROCm visibility

```bash
sudo reboot
```

After reconnect:

```bash
/opt/rocm/bin/rocminfo | grep -i gfx
id -nG "$USER"
```

You should see a `gfx...` target and your user should include `render` and `video` groups.

## 4) Run a 70B model with llama.cpp

Example command (adjust model path, quant, context, and GPU layers):

```bash
cd ~/llama.cpp
./build/bin/llama-cli \
  -m /models/your-70b-model.gguf \
  -ngl 999 \
  -c 4096 \
  -n 256 \
  -p "Write a one paragraph test response."
```

Notes:
- `-ngl 999` asks llama.cpp to offload as many layers as possible.
- If memory is tight, use a smaller quantization or lower context.

## Optional: shell session logging installer

```bash
sudo bash scripts/scriptsinstall-shell-logging.sh
```

This enables login-shell capture to `/var/log/shell-capture/<user>/`.
