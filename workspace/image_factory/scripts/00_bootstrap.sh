#!/usr/bin/env bash
# 공통 사전 준비: Apple Silicon 확인, Xcode CLT, Homebrew, Python 3.12, git 설치
set -euo pipefail

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[오류] %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS에서만 실행할 수 있습니다."
if [[ "$(uname -m)" != "arm64" ]]; then
  if [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" == "1" ]]; then
    die "터미널이 Rosetta(x86_64)로 실행 중입니다. Rosetta 옵션을 끄고 네이티브 arm64 터미널에서 다시 실행하세요."
  fi
  die "Apple Silicon(arm64) Mac이 아닙니다: $(uname -m)"
fi

say "시스템 정보"
sw_vers
echo "칩: $(sysctl -n machdep.cpu.brand_string)"
echo "메모리: $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB"
echo "남은 디스크: $(df -h "$HOME" | awk 'NR==2{print $4}')"

say "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install || true
  die "설치 창이 열렸습니다. 설치 완료 후 이 스크립트를 다시 실행하세요."
fi
echo "OK: $(xcode-select -p)"

say "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || \
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
fi
brew --version | head -1

say "python@3.12, git, git-lfs, wget"
brew install python@3.12 git git-lfs wget
git lfs install >/dev/null

PY="$(brew --prefix python@3.12)/bin/python3.12"
"$PY" -c 'import platform,sys; print(sys.version); assert platform.machine()=="arm64", platform.machine()'

say "완료. 다음 단계: scripts/01_diffusionbee.sh 또는 scripts/02_comfyui_install.sh"
