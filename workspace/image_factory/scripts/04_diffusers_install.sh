#!/usr/bin/env bash
# 옵션 3: Hugging Face diffusers + PyTorch MPS 로 파이썬 스크립트 기반 생성 환경
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/.venv-diffusers"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[오류] %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || die "Apple Silicon macOS 전용입니다."
command -v brew >/dev/null || die "먼저 scripts/00_bootstrap.sh 를 실행하세요."
PY="$(brew --prefix python@3.12)/bin/python3.12"
[[ -x "$PY" ]] || die "python@3.12 가 없습니다. 먼저 scripts/00_bootstrap.sh 를 실행하세요."

say "가상환경: $VENV"
[[ -d "$VENV" ]] || "$PY" -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade pip wheel
"$VENV/bin/pip" install --upgrade torch torchvision
"$VENV/bin/pip" install --upgrade diffusers transformers accelerate safetensors pillow
"$VENV/bin/python" -c 'import torch; assert torch.backends.mps.is_available(), "MPS 사용 불가"; print("torch", torch.__version__, "MPS OK")'
mkdir -p "$ROOT/outputs/diffusers"

say "완료. 테스트:"
cat <<EOF
  # ComfyUI에서 받은 체크포인트 재사용 (추가 다운로드 없음)
  $VENV/bin/python $ROOT/scripts/generate.py --ckpt $ROOT/ComfyUI/models/checkpoints/v1-5-pruned-emaonly.safetensors

  # 또는 Hugging Face 허브에서 자동 다운로드 (~/.cache/huggingface)
  $VENV/bin/python $ROOT/scripts/generate.py --model stable-diffusion-v1-5/stable-diffusion-v1-5
EOF
