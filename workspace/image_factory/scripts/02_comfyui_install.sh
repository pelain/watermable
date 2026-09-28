#!/usr/bin/env bash
# 옵션 2: ComfyUI 설치 (PyTorch MPS 가속) + ComfyUI-Manager + SD 1.5 체크포인트
#   사용법: scripts/02_comfyui_install.sh [--nightly] [--sdxl] [--no-model]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMFY="$ROOT/ComfyUI"
VENV="$ROOT/.venv-comfy"

NIGHTLY=0; SDXL=0; MODEL=1
for a in "$@"; do
  case "$a" in
    --nightly) NIGHTLY=1 ;;
    --sdxl) SDXL=1 ;;
    --no-model) MODEL=0 ;;
    *) echo "알 수 없는 옵션: $a"; exit 2 ;;
  esac
done

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[오류] %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || die "Apple Silicon macOS 전용입니다."
command -v brew >/dev/null || die "Homebrew가 없습니다. 먼저 scripts/00_bootstrap.sh 를 실행하세요."
PY="$(brew --prefix python@3.12)/bin/python3.12"
[[ -x "$PY" ]] || die "python@3.12 가 없습니다. 먼저 scripts/00_bootstrap.sh 를 실행하세요."

say "ComfyUI 소스"
if [[ -d "$COMFY/.git" ]]; then
  git -C "$COMFY" pull --ff-only
else
  git clone https://github.com/Comfy-Org/ComfyUI.git "$COMFY"
fi

say "가상환경: $VENV"
[[ -d "$VENV" ]] || "$PY" -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --upgrade pip wheel

say "PyTorch (Apple Silicon wheel에는 MPS 백엔드가 포함되어 있음)"
if [[ $NIGHTLY -eq 1 ]]; then
  pip install --pre --upgrade torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/nightly/cpu
else
  pip install --upgrade torch torchvision torchaudio
fi
python - <<'EOF'
import torch
print("torch", torch.__version__)
print("MPS built:", torch.backends.mps.is_built(), "/ available:", torch.backends.mps.is_available())
assert torch.backends.mps.is_available(), "MPS를 사용할 수 없습니다 (macOS 12.3+ 및 arm64 Python 필요)"
x = torch.ones(2, 2, device="mps"); print("MPS 연산 테스트:", (x @ x).sum().item())
EOF

say "ComfyUI 의존성"
pip install -r "$COMFY/requirements.txt"

say "ComfyUI-Manager (커스텀 노드/모델 설치 도우미)"
MGR="$COMFY/custom_nodes/ComfyUI-Manager"
if [[ -d "$MGR/.git" ]]; then
  git -C "$MGR" pull --ff-only
else
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$MGR"
fi
[[ -f "$MGR/requirements.txt" ]] && pip install -r "$MGR/requirements.txt"

download() {  # $1=url $2=dest
  if [[ -s "$2" ]]; then echo "이미 있음: $2"; return; fi
  echo "다운로드: $1"
  curl -fL --retry 3 -C - --progress-bar -o "$2.part" "$1" && mv "$2.part" "$2"
}

CKPT_DIR="$COMFY/models/checkpoints"
mkdir -p "$CKPT_DIR" "$ROOT/outputs/comfyui"
if [[ $MODEL -eq 1 ]]; then
  say "SD 1.5 체크포인트 (~4.3GB, 8GB M1에서도 동작)"
  download "https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors" \
           "$CKPT_DIR/v1-5-pruned-emaonly.safetensors"
fi
if [[ $SDXL -eq 1 ]]; then
  say "SDXL base 1.0 체크포인트 (~6.9GB, 16GB 이상 권장)"
  download "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
           "$CKPT_DIR/sd_xl_base_1.0.safetensors"
fi

say "설치 완료"
cat <<EOF
  실행:        $ROOT/scripts/03_comfyui_run.sh
  브라우저:    http://127.0.0.1:8188
  API 테스트:  $VENV/bin/python $ROOT/scripts/comfy_api_test.py
EOF
