#!/usr/bin/env python
"""Local SDXL-Turbo text-to-image HTTP service for the dsh generate_image tool.

Usage:  python server.py [--port 17821] [--device cuda:0]
API:    POST /generate  {prompt, negative_prompt?, steps?, guidance_scale?, width?, height?, seed?}
        -> image/png bytes (Content-Type image/png; margin/prompt echoed in headers)
        GET  /health -> {"ok": true, "model": "sdxl-turbo", "device": "cuda:0"}
"""
import argparse, base64, io, json, os, sys, time

import torch
from fastapi import FastAPI
from fastapi.responses import Response, JSONResponse
import uvicorn

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=17821)
parser.add_argument("--device", default="cuda:0")
parser.add_argument("--model", default="stabilityai/sdxl-turbo")
args = parser.parse_args()

# HF_ENDPOINT allows mirroring (e.g. https://hf-mirror.com) via env.
os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "0")
# Pin the HF cache so the 3GB model is reused no matter how the server starts.
os.environ.setdefault("HF_HOME", "F:/tools/image-gen/hf")
# Force offline so the 3GB cached model is used even when the Hub is unreachable.
os.environ.setdefault("HF_HUB_OFFLINE", "1")

from diffusers import AutoPipelineForText2Image

# Resolve the local snapshot directory directly so an incomplete metadata
# snapshot (missing README/LICENSE etc.) does not block loading.
from pathlib import Path
_hf_home = Path(os.environ.get("HF_HOME", "F:/tools/image-gen/hf"))
_repo_dir = _hf_home / "hub" / ("models--" + args.model.replace("/", "--"))
_ref_file = _repo_dir / "refs" / "main"
if _ref_file.exists():
    _rev = _ref_file.read_text().strip()
    _model_path = _repo_dir / "snapshots" / _rev
    if _model_path.exists():
        args.model = str(_model_path)
print(f"[image-gen] loading {args.model} on {args.device} ...", flush=True)
t0 = time.time()
pipe = AutoPipelineForText2Image.from_pretrained(
    args.model,
    torch_dtype=torch.float16,
    variant="fp16",
    local_files_only=True,
).to(args.device)
print(f"[image-gen] model loaded in {time.time()-t0:.1f}s", flush=True)

app = FastAPI(title="dsh-image-gen")

@app.get("/health")
def health():
    return {"ok": True, "model": args.model, "device": args.device}

@app.post("/generate")
def generate(payload: dict):
    prompt = str(payload.get("prompt") or "").strip()
    if not prompt:
        return JSONResponse({"error": "prompt is required"}, status_code=400)
    steps = int(payload.get("steps") or 4)
    guidance = float(payload.get("guidance_scale") or 0.0)
    width = int(payload.get("width") or 512)
    height = int(payload.get("height") or 512)
    seed = payload.get("seed")
    # clamp to sane SDXL range
    width = max(384, min(width, 1344)); width -= width % 8
    height = max(384, min(height, 1344)); height -= height % 8
    gen = None
    if seed is not None:
        gen = torch.Generator(device=args.device).manual_seed(int(seed))
    t0 = time.time()
    image = pipe(
        prompt=prompt,
        negative_prompt=str(payload.get("negative_prompt") or "").strip() or None,
        num_inference_steps=steps,
        guidance_scale=guidance,
        width=width,
        height=height,
        generator=gen,
    ).images[0]
    elapsed = time.time() - t0
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    png = buf.getvalue()
    return Response(
        content=png,
        media_type="image/png",
        headers={
            "X-Image-Gen-Seconds": f"{elapsed:.2f}",
            "X-Image-Gen-Size": f"{width}x{height}",
            "X-Image-Gen-Steps": str(steps),
        },
    )

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")
