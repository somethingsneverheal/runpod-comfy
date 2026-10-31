#!/usr/bin/env bash
# Instalador para edición de foto: FLUX 3 Klein + SAM 3.1 + Depth Anything 3. Aparte de bootstrap.sh (LTX), no lo toca.
# Sin volumen: cada pod nace limpio. Lee HF_TOKEN; exige haber aceptado la licencia de flux-3-image-klein-comfy.
# ponytail: subida de ComfyUI sin verificar en un pod real; revisar /workspace/bootstrap.log tras el primer arranque
set -uo pipefail
VERSION=v0.43.2  # FLUX 3 Klein pide >=0.41 y la imagen de RunPod va en 0.35
COMFY=/workspace/runpod-slim/ComfyUI
LOG=/workspace/bootstrap.log
exec > >(tee -a "$LOG") 2>&1
echo "== bootstrap_flux3 $(date -u +%FT%TZ)"

# start.sh crea la carpeta de ComfyUI en el primer arranque: esperamos a que esté lista (máx. 15 min)
for _ in $(seq 1 180); do [ -d "$COMFY/custom_nodes/ComfyUI-Manager" ] && break; sleep 5; done
[ -d "$COMFY/custom_nodes" ] || { echo "ERROR: ComfyUI no apareció en $COMFY"; exit 1; }

source "$COMFY"/.venv*/bin/activate || echo "AVISO: no encuentro el venv, uso python del sistema"
[ -f /opt/comfyui-runtime-constraints.txt ] && export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt  # que pip no cambie torch

git -C "$COMFY" fetch --depth 1 origin tag "$VERSION" -q && git -C "$COMFY" checkout -q "$VERSION" \
  || { echo "ERROR: no se pudo pasar ComfyUI a $VERSION"; exit 1; }
pip install -q -r "$COMFY/requirements.txt" || echo "AVISO: fallo instalando dependencias de ComfyUI"
# comfy_kitchen va ligado a cada versión de ComfyUI y la restricción de la imagen lo deja viejo: se instala sin ella
K=$(grep -iE '^comfy[-_]kitchen' "$COMFY/requirements.txt")
[ -n "$K" ] && PIP_CONSTRAINT= pip install -q "$K"
python -c "import comfy_kitchen.int8_decode" || echo "ERROR: comfy_kitchen sigue sin int8_decode"
echo "ComfyUI: $(git -C "$COMFY" describe --tags)"

git clone --depth 1 -q https://github.com/crystian/ComfyUI-Crystools "$COMFY/custom_nodes/ComfyUI-Crystools" \
  && pip install -q -r "$COMFY/custom_nodes/ComfyUI-Crystools/requirements.txt"

command -v hf >/dev/null || pip install -q "huggingface_hub>=1.5,<2"
HF=$(command -v hf || command -v huggingface-cli)
M="$COMFY/models"
FALLOS=0
bajar() { "$HF" download "$@" || { echo "ERROR descargando $1"; FALLOS=1; }; }

# bf16: la mejor calidad
bajar black-forest-labs/flux-3-image-klein-comfy \
  diffusion_models/flux3-image-klein-bf16.safetensors \
  diffusion_models/flux3-image-klein-base-bf16.safetensors \
  text_encoders/qwen3vl_4b_bf16.safetensors \
  text_encoders/qwen3.5_9b_flux3_prompt_upsampler_bf16.safetensors \
  vae/flux2-vae.safetensors \
  --local-dir "$M"
bajar Comfy-Org/sam3.1 checkpoints/sam3.1_multiplex_fp16.safetensors --local-dir "$M"
bajar Comfy-Org/Depth-Anything-3 geometry_estimation/depth_anything_3_mono_large.safetensors --local-dir "$M"

# start.sh no relanza ComfyUI si se cae (el cambio de versión lo tumba): reiniciar si vive, arrancar si no
if curl -sf -m 3 http://127.0.0.1:8188/system_stats >/dev/null; then
  echo "reiniciando ComfyUI…"; curl -s -m 10 -X POST http://127.0.0.1:8188/manager/reboot >/dev/null || echo "AVISO: reinicio por Manager falló"; sleep 10
else
  echo "arrancando ComfyUI…"; (cd "$COMFY" && nohup python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header >> /workspace/comfyui.log 2>&1 &)
fi
for _ in $(seq 1 60); do sleep 5; curl -sf -m 3 http://127.0.0.1:8188/system_stats >/dev/null && break; done
curl -s -m 5 http://127.0.0.1:8188/system_stats | head -c 400; echo
[ "$FALLOS" = 0 ] && echo "== LISTO $(date -u +%FT%TZ)" || echo "== TERMINADO CON ERRORES $(date -u +%FT%TZ)"
