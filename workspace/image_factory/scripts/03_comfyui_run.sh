#!/usr/bin/env bash
# ComfyUI 실행 (http://127.0.0.1:8188). 추가 인자는 main.py 로 그대로 전달됩니다.
#   예) scripts/03_comfyui_run.sh --lowvram
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMFY="$ROOT/ComfyUI"
VENV="$ROOT/.venv-comfy"
[[ -f "$COMFY/main.py" && -d "$VENV" ]] || { echo "먼저 scripts/02_comfyui_install.sh 를 실행하세요."; exit 1; }

# MPS 미지원 연산은 CPU로 대체 (드물게 필요한 커스텀 노드 대비)
export PYTORCH_ENABLE_MPS_FALLBACK=1

EXTRA=()
MEM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
if [[ $MEM_GB -le 8 && " $* " != *" --lowvram "* && " $* " != *" --normalvram "* ]]; then
  echo "메모리 ${MEM_GB}GB 감지 → --lowvram 자동 적용 (끄려면 --normalvram)"
  EXTRA+=(--lowvram)
fi

cd "$COMFY"
exec "$VENV/bin/python" main.py \
  --listen 127.0.0.1 --port 8188 \
  --output-directory "$ROOT/outputs/comfyui" \
  "${EXTRA[@]+"${EXTRA[@]}"}" "$@"
