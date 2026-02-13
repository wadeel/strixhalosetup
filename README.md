# Strix Halo 70B Bring-up (Ubuntu Server 24.04)

This repo contains a practical, repeatable setup flow for:

- HP Z2 Mini G1a with Ryzen AI Max+ Pro 395 (Strix Halo)
- Ubuntu Server 24.04
- ROCm + `llama.cpp` on integrated Radeon 8060S
- Loading a 70B model using full shared iGPU memory budget
- Forcing Realtek RTL8125BPH-CG to use `r8125` (and blacklist `r8169`)
- Full shell session logging with quick on/off controls

> ⚠️ **Run as a sudo-capable user.**

## 1) One-shot base update

```bash
sudo apt update
sudo apt -y full-upgrade
sudo apt -y install git curl wget build-essential cmake ninja-build python3 python3-pip pciutils dkms linux-headers-$(uname -r) jq
sudo reboot
```

## 2) Enable full command+output logging (and quick disable)

Install logging helpers:

```bash
chmod +x scripts/*.sh
sudo ./scripts/install-shell-logging.sh
```

Behavior:

- Per-session logs go to `/var/log/shell-capture/$USER/`
- The active log symlink is `/var/log/shell-capture/$USER/latest.log`
- Logging can be toggled by dropping/removing `/etc/profile.d/99-shell-logging.sh`

Quick controls:

```bash
sudo /usr/local/sbin/shell-logging-on
sudo /usr/local/sbin/shell-logging-off
```

## 3) Fix NIC driver (RTL8125BPH-CG)

Run:

```bash
sudo ./scripts/fix-rtl8125-driver.sh
```

What it does:

1. Installs `r8125-dkms` when available (or builds Realtek out-of-tree fallback).
2. Blacklists `r8169`.
3. Regenerates initramfs.
4. Gives reboot guidance.

After reboot, verify:

```bash
lsmod | grep -E 'r8125|r8169'
sudo ethtool -i <your_nic_ifname>
```

Expected: `r8125` loaded, `r8169` absent.

## 4) Install ROCm + build llama.cpp for Strix Halo

Run:

```bash
sudo ./scripts/install-rocm-llamacpp.sh
```

Key points:

- Adds ROCm apt repository for Ubuntu 24.04.
- Installs HIP runtime and dev stack.
- Adds your user to `render` + `video` groups.
- Builds `llama.cpp` with HIP backend.

Verify:

```bash
/opt/rocm/bin/rocminfo | grep -i gfx
/opt/rocm/bin/rocm-smi
~/llama.cpp/build/bin/llama-cli --version
```

For Strix Halo you should typically see `gfx1151`.

## 5) Model format for 70B

Short answer: **No, it does not strictly have to be GGUF** in general ML tooling, but for `llama.cpp` you should use **GGUF**.

- `llama.cpp` expects GGUF.
- Ollama also uses GGUF under the hood, but currently has less explicit control for advanced split/offload tuning on unusual unified-memory targets.
- For your goal (max memory control), direct `llama.cpp` is usually best.

## 6) Download and run a 70B model

Example model (you can swap):

```bash
mkdir -p ~/models
cd ~/models
# Example only; replace with a compatible GGUF URL you are licensed to use.
# wget -O qwen2.5-72b-instruct-q4_k_m.gguf '<MODEL_URL>'
```

Run with aggressive GPU offload:

```bash
~/llama.cpp/build/bin/llama-cli \
  -m ~/models/<your-70b>.gguf \
  -ngl 999 \
  -c 8192 \
  -b 512 \
  --temp 0.7 \
  -p "Write a short hello from Strix Halo."
```

Tuning notes:

- `-ngl 999` asks to offload all possible layers.
- Increase/decrease `-c` context and `-b` batch for stability.
- If OOM occurs, move to a smaller quantization (for example Q4_K_M instead of Q5/Q6).

## 7) BIOS and memory allocation expectations

To approach ~103 GB addressable graphics memory:

- Set maximum UMA/iGPU memory aperture in BIOS (target your 96 GB share setting).
- Keep system RAM in high-performance profile (dual-channel, rated speed).
- Disable unnecessary framebuffer consumers.

Inside Linux, verify free/total memory before launch:

```bash
free -h
/opt/rocm/bin/rocm-smi --showmeminfo vram
```

## 8) Recommended bring-up sequence

1. BIOS: max UMA share.
2. Freshly updated Ubuntu.
3. NIC driver fix + reboot.
4. ROCm + llama.cpp install + reboot.
5. Add model GGUF and benchmark with incremental context/batch.

---

## Troubleshooting

- If `rocminfo` does not show your APU: ensure secure boot and unsigned DKMS constraints are resolved, and verify kernel compatibility with your ROCm release.
- If HIP build fails: rerun cmake with explicit target
  `-DAMDGPU_TARGETS=gfx1151`.
- If performance is unexpectedly low: check power profile and thermal limits in BIOS.
