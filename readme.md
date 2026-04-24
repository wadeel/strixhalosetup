# Strix Halo setup (Ubuntu Desktop 24.04 + ROCm + llama.cpp + Open WebUI)

This repo is now tuned for a **local LLM workstation** flow on **Ubuntu Desktop 24.04** (GUI), with:

- ROCm + HIP on AMD Strix Halo systems.
- `llama.cpp` built directly with HIP acceleration.
- Open WebUI running locally in Docker.
- Optional OpenClaw repo bootstrap.

---

## 0) Hardware assumptions and BIOS notes

This setup assumes:

- You already disabled **IOMMU**.
- You set iGPU default/UMA frame buffer to **512 MB**.
- You want llama.cpp to use large shared memory budgets (for example, up to ~128 GB addressable pool depending on workload).

> Important: The 512 MB BIOS frame buffer does **not** cap runtime LLM memory use for shared-memory APU workloads. Actual allocation still depends on kernel/driver behavior, model quantization, context size, and runtime pressure.

---

## 1) One-time bootstrap on fresh Ubuntu Desktop 24.04

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ca-certificates
```

Clone this repository:

```bash
git clone https://github.com/<your-org-or-user>/strixhalosetup.git
cd strixhalosetup
```

---

## 2) Install ROCm + build llama.cpp (HIP)

Run:

```bash
sudo bash scripts/scriptsinstall-rocm-llamacpp.sh
```

What the script does:

- Installs dependencies and ROCm packages from AMD `amdgpu-install` for Ubuntu noble.
- Cleans older ROCm stacks before install.
- Adds your user to `render` and `video`.
- Builds `llama.cpp` with `-DGGML_HIP=ON`.
- Uses `clang++` as HIP compiler for CMake 3.28+ compatibility.
- Sets default `AMDGPU_TARGETS=gfx1151` (override when needed).

Override target explicitly:

```bash
sudo AMDGPU_TARGETS=gfx1151 bash scripts/scriptsinstall-rocm-llamacpp.sh
```

Reboot:

```bash
sudo reboot
```

Verify after reboot:

```bash
/opt/rocm/bin/rocminfo | grep -i gfx
id -nG "$USER"
```

Expected: a `gfx...` target appears, and your user is in `render` and `video`.

---

## 3) Run llama.cpp directly on the local hardware

Example with aggressive GPU offload:

```bash
cd ~/llama.cpp
./build/bin/llama-cli \
  -m /models/your-model.gguf \
  -ngl 999 \
  -c 8192 \
  -n 256 \
  -p "Reply with a short hardware test summary."
```

If you prefer serving for WebUI/API clients:

```bash
cd ~/llama.cpp
./build/bin/llama-server \
  -m /models/your-model.gguf \
  -ngl 999 \
  -c 8192 \
  --host 0.0.0.0 \
  --port 8080
```

---

## 4) Install/download GGUF models

Use the helper script:

```bash
bash scripts/scriptsinstall-70b-model.sh
```

Example explicit model file:

```bash
MODEL_SOURCE=huggingface \
MODEL_ID='puwaer/Qwen3-Next-80B-A3B-Thinking-GRPO-Uncensored-gguf' \
MODEL_FILE='Qwen3-Next-80B-A3B-Thinking-GRPO-Uncensored-Q4_K_M.gguf' \
MODEL_DIR='/models' \
bash scripts/scriptsinstall-70b-model.sh
```

Or by pattern:

```bash
MODEL_SOURCE=huggingface \
MODEL_ID='puwaer/Qwen3-Next-80B-A3B-Thinking-GRPO-Uncensored-gguf' \
MODEL_PATTERN='*Q4_K_M*.gguf' \
MODEL_DIR='/models' \
bash scripts/scriptsinstall-70b-model.sh
```

---

## 5) Install Open WebUI + optional OpenClaw bootstrap

Run:

```bash
bash scripts/scriptsinstall-openwebui-openclaw.sh
```

This will:

- Install Docker Engine if missing.
- Run Open WebUI at `http://localhost:3000`.
- Configure Open WebUI container with access to host llama.cpp endpoint at `http://host.docker.internal:8080/v1`.

If you want to clone OpenClaw in the same pass:

```bash
OPENCLAW_REPO_URL='https://github.com/<your-org>/openclaw.git' \
bash scripts/scriptsinstall-openwebui-openclaw.sh
```

Then point OpenClaw/Open WebUI to your llama.cpp server URL.

---

## Optional: shell session logging installer

```bash
sudo bash scripts/scriptsinstall-shell-logging.sh
```

This enables login-shell capture to `/var/log/shell-capture/<user>/`.
