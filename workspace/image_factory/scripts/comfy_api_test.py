#!/usr/bin/env python3
"""ComfyUI HTTP API로 txt2img 한 장을 생성해 저장하는 테스트 (표준 라이브러리만 사용).

ComfyUI가 실행 중이어야 합니다 (scripts/03_comfyui_run.sh).

  python scripts/comfy_api_test.py
  python scripts/comfy_api_test.py --prompt "a red fox, watercolor" --steps 25 --seed 42
  python scripts/comfy_api_test.py --ckpt sd_xl_base_1.0.safetensors --size 1024
"""
import argparse
import json
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def build_workflow(a):
    """ComfyUI 'API format' 워크플로우 (기본 txt2img 그래프)."""
    return {
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": a.ckpt}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": a.prompt, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": a.negative, "clip": ["4", 1]}},
        "5": {"class_type": "EmptyLatentImage",
              "inputs": {"width": a.size, "height": a.size, "batch_size": 1}},
        "3": {"class_type": "KSampler", "inputs": {
            "seed": a.seed, "steps": a.steps, "cfg": a.cfg,
            "sampler_name": "euler_ancestral", "scheduler": "normal", "denoise": 1.0,
            "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0],
            "latent_image": ["5", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage",
              "inputs": {"images": ["8", 0], "filename_prefix": "api_test"}},
    }


def call(base, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(base + path, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
    return json.loads(body) if body[:1] in (b"{", b"[") else body


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--server", default="http://127.0.0.1:8188")
    p.add_argument("--ckpt", default="v1-5-pruned-emaonly.safetensors")
    p.add_argument("--prompt", default="a cozy cabin in a snowy forest at dusk, "
                                       "warm window light, highly detailed, 35mm photo")
    p.add_argument("--negative", default="blurry, low quality, deformed, watermark, text")
    p.add_argument("--steps", type=int, default=20)
    p.add_argument("--cfg", type=float, default=7.0)
    p.add_argument("--size", type=int, default=512)
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--out", default=str(ROOT / "outputs" / "comfyui"))
    p.add_argument("--timeout", type=int, default=900, help="생성 대기 최대 초")
    a = p.parse_args()
    if a.seed is None:
        a.seed = random.randint(0, 2**32 - 1)
    base = a.server.rstrip("/")

    try:
        stats = call(base, "/system_stats")
    except (urllib.error.URLError, ConnectionError) as e:
        sys.exit(f"ComfyUI 서버({base})에 연결할 수 없습니다: {e}\n"
                 "먼저 scripts/03_comfyui_run.sh 로 실행하세요.")
    dev = (stats.get("devices") or [{}])[0]
    print(f"서버 OK — device: {dev.get('name', '?')} ({dev.get('type', '?')})")

    try:
        res = call(base, "/prompt", {"prompt": build_workflow(a), "client_id": uuid.uuid4().hex})
    except urllib.error.HTTPError as e:
        sys.exit(f"워크플로우 제출 실패 ({e.code}): {e.read().decode(errors='replace')}\n"
                 f"models/checkpoints 에 '{a.ckpt}' 가 있는지 확인하세요.")
    pid = res["prompt_id"]
    print(f"제출됨 prompt_id={pid} seed={a.seed} steps={a.steps} size={a.size}")

    t0 = time.time()
    while True:
        hist = call(base, f"/history/{pid}")
        if pid in hist:
            entry = hist[pid]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                sys.exit(f"생성 실패: {json.dumps(status.get('messages'), ensure_ascii=False)}")
            if status.get("completed", True):
                break
        if time.time() - t0 > a.timeout:
            sys.exit("시간 초과")
        time.sleep(1)
    elapsed = time.time() - t0

    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    saved = []
    for node in entry.get("outputs", {}).values():
        for img in node.get("images", []):
            q = urllib.parse.urlencode({k: img[k] for k in ("filename", "subfolder", "type")})
            dest = out_dir / img["filename"]
            if not dest.exists():  # 서버 output-directory 가 같으면 이미 저장되어 있음
                dest.write_bytes(call(base, f"/view?{q}"))
            saved.append(dest)
    if not saved:
        sys.exit("출력 이미지가 없습니다.")
    for s in saved:
        print(f"저장: {s}")
    print(f"생성 시간: {elapsed:.1f}초")


if __name__ == "__main__":
    main()
