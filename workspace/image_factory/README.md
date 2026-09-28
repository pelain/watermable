# image_factory — M1 맥북 로컬 Stable Diffusion

Apple Silicon(M1/M2/M3/M4) 맥에서 Stable Diffusion을 로컬로 돌리는 세 가지 방법을 스크립트로 정리했습니다.
모든 스크립트는 이 폴더(`~/workspace/image_factory`) 안에만 설치합니다 (DiffusionBee 앱은 `/Applications`).

| 옵션 | 도구 | 용도 | 난이도 |
|---|---|---|---|
| 1 | DiffusionBee | 설치 즉시 GUI로 생성 테스트 | 가장 쉬움 |
| 2 | ComfyUI | 노드 기반 워크플로우, 커스텀 노드/LoRA/ControlNet, HTTP API 자동화 | 중간 |
| 3 | diffusers + PyTorch MPS | 파이썬 스크립트로 배치 생성, 다른 코드에 통합 | 중간 |

## 요구 사항

- Apple Silicon 맥, macOS 12.3 이상 (MPS 가속 필요, 최신 macOS 권장)
- 메모리: 8GB면 SD 1.5까지, SDXL은 16GB 이상 권장
- 디스크 여유 공간: 20GB 이상 (모델 1개 4~7GB)
- 터미널은 **Rosetta 없이** 네이티브(arm64)로 실행

## 0. 폴더 만들기 + 공통 준비

```bash
mkdir -p ~/workspace && cd ~/workspace
git clone -b claude/m1-stable-diffusion-setup-0c5ilm https://github.com/pelain/watermable.git _watermable
cp -R _watermable/workspace/image_factory ~/workspace/image_factory
cd ~/workspace/image_factory
chmod +x scripts/*.sh

./scripts/00_bootstrap.sh     # arm64 확인, Xcode CLT, Homebrew, python@3.12, git
```

## 1. DiffusionBee (가장 빠른 이미지 생성 테스트)

```bash
./scripts/01_diffusionbee.sh
```

- 공식 릴리스에서 Apple Silicon용 `.dmg`를 받아 `/Applications`에 설치하고 실행합니다.
  자동 탐지가 실패하면 https://diffusionbee.com/download 페이지를 열어 줍니다 → **macOS – Apple Silicon** 선택.
- 첫 실행 시 기본 모델을 자동으로 내려받습니다.
- **테스트:** Text To Image → 프롬프트 입력 → Generate → 결과를 `outputs/diffusionbee/`에 저장.
- 처음 열 때 "확인되지 않은 개발자" 경고가 나오면: 시스템 설정 → 개인정보 보호 및 보안 → "확인 없이 열기".

## 2. ComfyUI (권장: 본격 활용)

```bash
./scripts/02_comfyui_install.sh          # ComfyUI + PyTorch(MPS) + ComfyUI-Manager + SD1.5 모델
# 16GB 이상이면 SDXL도:  ./scripts/02_comfyui_install.sh --sdxl
./scripts/03_comfyui_run.sh              # http://127.0.0.1:8188
```

브라우저에서 기본 워크플로우가 뜨면 **Load Checkpoint** 노드에서 `v1-5-pruned-emaonly.safetensors`를 고르고 **Queue/Run** 을 누릅니다.
결과는 `outputs/comfyui/`에 저장됩니다.

터미널에서 자동 생성 테스트 (서버 실행 중인 상태에서 다른 탭):

```bash
.venv-comfy/bin/python scripts/comfy_api_test.py
.venv-comfy/bin/python scripts/comfy_api_test.py --prompt "a red fox, watercolor" --seed 42 --steps 25
.venv-comfy/bin/python scripts/comfy_api_test.py --ckpt sd_xl_base_1.0.safetensors --size 1024
```

폴더 구조 (모델 추가 위치):

```
ComfyUI/models/checkpoints/   # .safetensors 체크포인트 (SD1.5, SDXL 등)
ComfyUI/models/loras/         # LoRA
ComfyUI/models/vae/           # VAE
ComfyUI/models/controlnet/    # ControlNet
ComfyUI/custom_nodes/         # 커스텀 노드 (UI 우측 상단 Manager 버튼으로 설치 가능)
```

업데이트는 설치 스크립트를 다시 실행하면 됩니다 (`git pull` + 의존성 갱신, 받은 모델은 건너뜀).
MPS 관련 오류가 나면 `./scripts/02_comfyui_install.sh --nightly --no-model` 로 PyTorch nightly를 시도해 보세요.

## 3. diffusers + MPS (파이썬 스크립트)

```bash
./scripts/04_diffusers_install.sh

# ComfyUI에서 받은 모델을 그대로 재사용 (추가 다운로드 없음)
.venv-diffusers/bin/python scripts/generate.py \
  --ckpt ComfyUI/models/checkpoints/v1-5-pruned-emaonly.safetensors \
  --prompt "a lighthouse on a cliff, golden hour" -n 4 --seed 1234

# SDXL
.venv-diffusers/bin/python scripts/generate.py \
  --ckpt ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors --sdxl
```

결과: `outputs/diffusers/<시각>_seed<시드>.png`

## M1 성능 팁

- 기대 속도(M1 기본형, SD1.5 512×512, 20 step): 대략 20~40초/장. SDXL 1024×1024는 수 분 걸릴 수 있습니다.
- 8GB 맥에서는 `03_comfyui_run.sh`가 자동으로 `--lowvram`을 붙입니다. 생성 중에는 브라우저 탭 등 다른 앱을 줄이세요.
- 첫 생성은 MPS 커널 컴파일 때문에 느립니다. 두 번째부터 측정하세요.
- 검은 이미지가 나오면: SD1.5는 `--seed`를 바꿔 보고, SDXL은 ComfyUI 실행 시 `./scripts/03_comfyui_run.sh --fp32-vae` 로 VAE를 fp32로 돌리세요.
- Core ML 기반 네이티브 앱(Draw Things, Mochi Diffusion)도 M1에서 빠르고 메모리 효율이 좋으니 GUI 대안으로 고려할 만합니다.

## 정리 / 삭제

```bash
rm -rf ComfyUI .venv-comfy .venv-diffusers downloads   # 이 폴더 설치분
rm -rf ~/.cache/huggingface                            # diffusers 모델 캐시
rm -rf /Applications/DiffusionBee.app ~/.diffusionbee  # DiffusionBee
```
