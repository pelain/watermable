#!/usr/bin/env python3
"""diffusers + MPS(Apple GPU)로 Stable Diffusion 이미지 생성.

  python scripts/generate.py --ckpt ComfyUI/models/checkpoints/v1-5-pruned-emaonly.safetensors
  python scripts/generate.py --model stable-diffusion-v1-5/stable-diffusion-v1-5 -n 4
  python scripts/generate.py --ckpt .../sd_xl_base_1.0.safetensors --sdxl --size 1024
"""
import argparse
import time
from datetime import datetime
from pathlib import Path

import torch
from diffusers import (EulerAncestralDiscreteScheduler, StableDiffusionPipeline,
                       StableDiffusionXLPipeline)

ROOT = Path(__file__).resolve().parent.parent


def pick_device(name):
    if name != "auto":
        return name
    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def main():
    p = argparse.ArgumentParser()
    src = p.add_mutually_exclusive_group()
    src.add_argument("--ckpt", help="단일 .safetensors/.ckpt 파일 경로")
    src.add_argument("--model", default="stable-diffusion-v1-5/stable-diffusion-v1-5",
                     help="Hugging Face 모델 ID 또는 diffusers 폴더")
    p.add_argument("--sdxl", action="store_true", help="SDXL 모델일 때 지정")
    p.add_argument("--prompt", default="a cozy cabin in a snowy forest at dusk, "
                                       "warm window light, highly detailed, 35mm photo")
    p.add_argument("--negative", default="blurry, low quality, deformed, watermark, text")
    p.add_argument("--steps", type=int, default=25)
    p.add_argument("--cfg", type=float, default=7.0)
    p.add_argument("--size", type=int, default=None, help="기본: SD1.5=512, SDXL=1024")
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("-n", "--num", type=int, default=1, help="생성할 이미지 수")
    p.add_argument("--device", default="auto", choices=["auto", "mps", "cuda", "cpu"])
    p.add_argument("--out", default=str(ROOT / "outputs" / "diffusers"))
    a = p.parse_args()

    device = pick_device(a.device)
    dtype = torch.float32 if device == "cpu" else torch.float16
    size = a.size or (1024 if a.sdxl else 512)
    Pipe = StableDiffusionXLPipeline if a.sdxl else StableDiffusionPipeline

    t0 = time.time()
    if a.ckpt:
        pipe = Pipe.from_single_file(a.ckpt, torch_dtype=dtype)
    else:
        pipe = Pipe.from_pretrained(a.model, torch_dtype=dtype)
    if getattr(pipe, "safety_checker", None) is not None:
        pipe.safety_checker = None  # 로컬 테스트용: 오탐으로 검은 이미지가 나오는 것 방지
    pipe.scheduler = EulerAncestralDiscreteScheduler.from_config(pipe.scheduler.config)
    pipe = pipe.to(device)
    if device == "mps":
        pipe.enable_attention_slicing()  # 16GB 이하 통합 메모리에서 피크 메모리 절감
    # SDXL VAE의 fp16 NaN(검은 이미지) 문제는 파이프라인이 vae.config.force_upcast 로 자동 처리
    print(f"로드 완료 ({time.time() - t0:.1f}s) device={device} dtype={dtype}")

    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    base_seed = a.seed if a.seed is not None else torch.seed() % (2**32)

    for i in range(a.num):
        seed = base_seed + i
        gen = torch.Generator("cpu").manual_seed(seed)  # MPS에서도 재현 가능한 시드
        t1 = time.time()
        img = pipe(a.prompt, negative_prompt=a.negative, num_inference_steps=a.steps,
                   guidance_scale=a.cfg, width=size, height=size, generator=gen).images[0]
        dest = out_dir / f"{datetime.now():%Y%m%d_%H%M%S}_seed{seed}.png"
        img.save(dest)
        print(f"[{i + 1}/{a.num}] {time.time() - t1:.1f}s → {dest}")


if __name__ == "__main__":
    main()
