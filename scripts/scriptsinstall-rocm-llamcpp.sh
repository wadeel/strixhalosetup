#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible wrapper for the frequently misspelled script name.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${script_dir}/scriptsinstall-rocm-llamacpp.sh" "$@"
