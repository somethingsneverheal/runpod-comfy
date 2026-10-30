#!/usr/bin/env bash
# Instalador de nodos y modelos que corre en cada arranque del pod (sin volumen: cada pod nace limpio).
# Lee BLOQUES (depth,mascaras,matting,upscale,hdr) y HF_TOKEN. Sin claves en este archivo.
# ponytail: rutas y reinicio de ComfyUI sin verificar en un pod real; revisar /workspace/bootstrap.log tras el primer arranque
set -uo pipefail
COMFY=/workspace/runpod-slim/ComfyUI
LOG=/workspace/bootstrap.log
exec > >(tee -a "$LOG") 2>&1
echo "== bootstrap $(date -u +%FT%TZ) PERFIL=${PROFILE:-} BLOQUES=${BLOQUES:-}"

# start.sh crea la carpeta de ComfyUI en el primer arranque: esperamos a que esté lista (máx. 15 min)
for _ in $(seq 1 180); do [ -d "$COMFY/custom_nodes/ComfyUI-Manager" ] && break; sleep 5; done
[ -d "$COMFY/custom_nodes" ] || { echo "ERROR: ComfyUI no apareció en $COMFY"; exit 1; }

source "$COMFY/.venv-cu128/bin/activate" || echo "AVISO: no encuentro el venv, uso python del sistema"
[ -f /opt/comfyui-runtime-constraints.txt ] && export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt  # que pip no cambie torch
CAMBIOS=0
hay() { case ",${BLOQUES:-}," in *",$1,"*) return 0;; *) return 1;; esac; }

nodo() {  # nodo <url git>: clona o actualiza y instala sus dependencias
  d="$COMFY/custom_nodes/$(basename "$1" .git)"
  if [ -d "$d/.git" ]; then git -C "$d" pull --ff-only -q || echo "AVISO: no se pudo actualizar $1"
  else git clone --depth 1 -q "$1" "$d" || { echo "ERROR clonando $1"; return 1; }; fi
  [ -f "$d/requirements.txt" ] && pip install -q -r "$d/requirements.txt" || true
  CAMBIOS=1; echo "nodo ok: $(basename "$d")"
}

# ComfyUI queda fijado por la imagen (0.30.0): actualizar el núcleo sin probar puede romper sus dependencias
echo "ComfyUI: $(git -C "$COMFY" describe --tags 2>/dev/null || echo 'versión de la imagen')"

nodo https://github.com/crystian/ComfyUI-Crystools          # monitor de GPU y VRAM, siempre
nodo https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite # cargar vídeo y exportar (ProRes), siempre

# huggingface_hub ya viene en el venv: no se actualiza, porque transformers exige <2.0
command -v hf >/dev/null || pip install -q "huggingface_hub>=1.5,<2"
HF=$(command -v hf || command -v huggingface-cli)
bajar() { "$HF" download "$@" || echo "ERROR descargando $1"; }  # bajar <repo> <archivos…> --local-dir <carpeta>; HF_TOKEN lo lee solo

if hay upscale || hay hdr; then
  nodo https://github.com/Lightricks/ComfyUI-LTXVideo
  M="$COMFY/models"
  bajar Lightricks/LTX-2.5 \
    diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors \
    text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors \
    vae/ltx-2.5-video-vae-bf16.safetensors vae/ltx-2.5-audio-vae-bf16.safetensors \
    latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
    --local-dir "$M"
  bajar Lightricks/LTX-2.5-22b-IC-LoRA-Pixel-Spatial-Upscaler ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors --local-dir "$M/loras"
  bajar Lightricks/LTX-2.5-22b-IC-LoRA-Restore ltx-2.5-22b-ic-lora-restore-1.0.safetensors --local-dir "$M/loras"
fi
hay hdr && { pip install -q openimageio || echo "AVISO: openimageio no se instaló"; echo "hdr: LoRA de HDR de 2.5 pendiente de localizar"; }
for b in depth mascaras matting; do hay "$b" && echo "bloque $b: pendiente, instalador aún sin escribir"; done

if [ "$CAMBIOS" = 1 ]; then  # reiniciar ComfyUI para que cargue los nodos nuevos
  echo "reiniciando ComfyUI…"; curl -s -m 10 http://127.0.0.1:8188/manager/reboot >/dev/null || echo "AVISO: reinicio por Manager falló"
  for _ in $(seq 1 60); do sleep 5; curl -sf -m 3 http://127.0.0.1:8188/system_stats >/dev/null && break; done
fi
echo "== bootstrap terminado $(date -u +%FT%TZ)"
