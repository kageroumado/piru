"""The generative prior for the replication lab: SD-Turbo img2img over a WebSocket.

The browser sends a frame and the prior's settings; this answers with the same frame
re-imagined under the prior. Where the result is shown, and how strongly, is decided in the
browser by the precision map, so the server stays one function: frame in, prior out.

Message in:  4-byte big-endian header length, JSON header, JPEG bytes.
             header = {prompt, strength, seed, id}
Message out: the same framing; header = {id, ms}.

Run:  .venv/bin/python prior_server.py        (setup in README.md)
"""

import asyncio
import io
import json
import math
import struct
import sys
import time

import torch
from diffusers import AutoPipelineForImage2Image
from PIL import Image
from websockets.asyncio.server import serve

PORT = 8799
MODEL = "stabilityai/sd-turbo"


def device():
    if torch.backends.mps.is_available():
        return "mps"
    return "cuda" if torch.cuda.is_available() else "cpu"


def load():
    dev = device()
    dtype = torch.float32 if dev == "cpu" else torch.float16
    pipe = AutoPipelineForImage2Image.from_pretrained(MODEL, torch_dtype=dtype, variant="fp16")
    pipe.to(dev)
    pipe.set_progress_bar_config(disable=True)
    return pipe


def imagine(pipe, image, prompt, strength, seed):
    # SD-Turbo runs int(steps * strength) denoising steps; one is enough below 0.5, two above.
    effective = 1 if strength < 0.5 else 2
    steps = max(effective, math.ceil(effective / strength))
    # The same seed every frame keeps the injected noise fixed, so the prior settles on the same
    # interpretation of a still scene instead of flickering between new ones.
    generator = torch.Generator("cpu").manual_seed(seed)
    return pipe(
        prompt=prompt,
        image=image,
        strength=strength,
        num_inference_steps=steps,
        guidance_scale=0.0,
        generator=generator,
    ).images[0]


def pack(header, payload):
    h = json.dumps(header).encode()
    return struct.pack(">I", len(h)) + h + payload


def unpack(message):
    n = struct.unpack(">I", message[:4])[0]
    return json.loads(message[4 : 4 + n]), message[4 + n :]


async def main():
    pipe = load()
    imagine(pipe, Image.new("RGB", (512, 288), "gray"), "warmup", 0.5, 0)
    lock = asyncio.Lock()

    async def handler(ws):
        async for message in ws:
            header, jpeg = unpack(message)
            image = Image.open(io.BytesIO(jpeg)).convert("RGB")
            async with lock:
                t0 = time.perf_counter()
                out = await asyncio.to_thread(
                    imagine,
                    pipe,
                    image,
                    header.get("prompt", ""),
                    float(header.get("strength", 0.5)),
                    int(header.get("seed", 7)),
                )
                ms = (time.perf_counter() - t0) * 1000
            buf = io.BytesIO()
            out.save(buf, "JPEG", quality=88)
            await ws.send(pack({"id": header.get("id"), "ms": round(ms)}, buf.getvalue()))

    async with serve(handler, "127.0.0.1", PORT, max_size=8 * 1024 * 1024) as server:
        print(f"prior server ready on ws://127.0.0.1:{PORT}", flush=True)
        await server.serve_forever()


def bench(path, prompt):
    pipe = load()
    image = Image.open(path).convert("RGB").resize((512, 288))
    for strength in (0.3, 0.5, 0.7):
        imagine(pipe, image, prompt, strength, 7)
        t0 = time.perf_counter()
        for _ in range(5):
            out = imagine(pipe, image, prompt, strength, 7)
        print(
            f"strength {strength}: {(time.perf_counter() - t0) / 5 * 1000:.0f} ms/frame", flush=True
        )
        out.save(path.rsplit(".", 1)[0] + f"-prior-{strength}.jpg")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "bench":
        bench(sys.argv[2], sys.argv[3])
    else:
        asyncio.run(main())
