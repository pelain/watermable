#!/usr/bin/env bash
# 옵션 1: DiffusionBee (Apple Silicon용 GUI 앱) 다운로드 + /Applications 설치
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DL_DIR="$ROOT/downloads"
mkdir -p "$DL_DIR"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[오류] %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || die "Apple Silicon macOS 전용입니다."

if [[ -d "/Applications/DiffusionBee.app" ]]; then
  say "DiffusionBee가 이미 설치되어 있습니다."
  open -a DiffusionBee
  exit 0
fi

# diffusionbee.com의 다운로드 버튼은 공식 GitHub 릴리스로 연결됩니다.
# 최신 릴리스에서 arm64(Apple Silicon)용 .dmg를 찾습니다.
say "최신 DiffusionBee 릴리스 조회"
API="https://api.github.com/repos/divamgupta/diffusionbee-stable-diffusion-ui/releases/latest"
DMG_URL="$(curl -fsSL "$API" | /usr/bin/python3 -c '
import json, sys
assets = json.load(sys.stdin).get("assets", [])
dmgs = [a["browser_download_url"] for a in assets if a["name"].lower().endswith(".dmg")]
arm = [u for u in dmgs if "arm64" in u.lower() or "apple" in u.lower() or "silicon" in u.lower()]
intel = [u for u in dmgs if "intel" in u.lower() or "x86" in u.lower() or "x64" in u.lower()]
pick = arm or [u for u in dmgs if u not in intel]
print(pick[0] if pick else "")
' || true)"

if [[ -z "$DMG_URL" ]]; then
  echo "자동으로 다운로드 링크를 찾지 못했습니다. 브라우저에서 직접 받으세요:"
  echo "  https://diffusionbee.com/download  →  'Download for macOS - Apple Silicon'"
  open "https://diffusionbee.com/download"
  exit 1
fi

DMG="$DL_DIR/$(basename "$DMG_URL")"
say "다운로드: $DMG_URL"
curl -fL --progress-bar -o "$DMG" "$DMG_URL"

say "DMG 마운트 후 /Applications 로 복사"
MNT="$(hdiutil attach -nobrowse -readonly "$DMG" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
trap 'hdiutil detach "$MNT" -quiet || true' EXIT
APP="$(find "$MNT" -maxdepth 1 -name '*.app' | head -1)"
[[ -n "$APP" ]] || die "DMG 안에서 .app을 찾지 못했습니다: $MNT"
ditto "$APP" "/Applications/$(basename "$APP")"

say "설치 완료. DiffusionBee 실행"
open -a "/Applications/$(basename "$APP")"

cat <<'EOF'

[이미지 생성 테스트 방법]
 1. 첫 실행 시 기본 모델(수 GB)을 자동으로 내려받습니다. 완료될 때까지 기다리세요.
 2. 'Text To Image' 탭 → 프롬프트 입력 예:
      a cozy cabin in a snowy forest at dusk, warm light, highly detailed
 3. 'Generate' 클릭 → 결과 이미지 우클릭 → Save 로
      ~/workspace/image_factory/outputs/diffusionbee/ 에 저장
 4. 생성 시간(초)과 메모리 사용량(활성 상태 보기)을 기록해 두면 ComfyUI와 비교하기 좋습니다.
EOF
mkdir -p "$ROOT/outputs/diffusionbee"
