#!/usr/bin/env bash
# Instalador para Seedance por BytePlus: solo el nodo propio, sin modelos. Lee BYTEPLUS_API_KEY del secreto del pod.
set -uo pipefail
COMFY=/workspace/runpod-slim/ComfyUI
exec > >(tee -a /workspace/bootstrap.log) 2>&1
for _ in $(seq 1 180); do [ -d "$COMFY/custom_nodes/ComfyUI-Manager" ] && break; sleep 5; done
mkdir -p "$COMFY/custom_nodes/ComfyUI-SeedanceBytePlus"
curl -fsSL "https://raw.githubusercontent.com/somethingsneverheal/runpod-comfy/main/ComfyUI-SeedanceBytePlus/__init__.py?t=$(date +%s)" -o "$COMFY/custom_nodes/ComfyUI-SeedanceBytePlus/__init__.py" || { echo "ERROR nodo"; exit 1; }
for _ in $(seq 1 60); do curl -sf -m 3 http://127.0.0.1:8188/system_stats >/dev/null && break; sleep 5; done
curl -s -m 10 -X POST http://127.0.0.1:8188/manager/reboot >/dev/null || echo "AVISO: reinicio fallo"
echo "== LISTO $(date -u +%FT%TZ)"
