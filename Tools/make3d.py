#!/usr/bin/env python3
"""
Turn a squeeshy cut-out into a real 3D mesh, free, using the public TRELLIS
Space on Hugging Face.

    pip3 install gradio_client
    python3 Tools/make3d.py TestPhotos/mochi.png

Writes <name>.glb and <name>_turntable.mp4 next to the input.

Quota: anonymous callers get a couple of minutes of GPU per day, which is about
one or two squeeshies. A *free* Hugging Face token raises that substantially:

    https://huggingface.co/settings/tokens   ->  create a read token
    export HF_TOKEN=hf_xxxxxxxx

This is a prototyping path, not a production one. The Space is a shared community
demo — fine for seeing whether the quality is good enough, not for shipping user
traffic through. Production means self-hosting the weights or paying an API.
"""

import os
import shutil
import sys
import time

try:
    from gradio_client import Client, handle_file
except ImportError:
    sys.exit("pip3 install gradio_client")

SPACE = "trellis-community/TRELLIS"


def generate(image_path: str, out_dir: str | None = None) -> str | None:
    if not os.path.exists(image_path):
        sys.exit(f"no such file: {image_path}")

    out_dir = out_dir or os.path.dirname(os.path.abspath(image_path))
    stem = os.path.splitext(os.path.basename(image_path))[0]
    token = os.environ.get("HF_TOKEN")

    print(f"{stem}: connecting to {SPACE}{' (authenticated)' if token else ' (anonymous)'}")
    client = Client(SPACE, hf_token=token, verbose=False, httpx_kwargs={"timeout": 900})

    # The Space keeps per-session state; harmless if it is not exposed.
    try:
        client.predict(api_name="/start_session")
    except Exception:
        pass

    started = time.time()
    job = client.submit(
        image=handle_file(image_path),
        multiimages=[],
        seed=0,
        ss_guidance_strength=7.5,
        ss_sampling_steps=12,
        slat_guidance_strength=3.0,
        slat_sampling_steps=12,
        multiimage_algo="stochastic",
        # Squeeshies are smooth blobs, so they simplify hard without visible loss
        # and the app has to load these over a phone connection.
        mesh_simplify=0.95,
        texture_size=1024,
        api_name="/generate_and_extract_glb",
    )

    seen = None
    while not job.done():
        status = job.status()
        if str(status.code) != seen:
            seen = str(status.code)
            queue = f" (queue {status.rank})" if status.rank is not None else ""
            print(f"  {seen}{queue} — {time.time() - started:.0f}s")
        time.sleep(4)
        if time.time() - started > 900:
            sys.exit("  timed out after 15 minutes")

    try:
        result = job.result()
    except Exception as exc:
        message = str(exc)
        if "quota" in message.lower():
            print("  out of GPU quota. Set HF_TOKEN for more, or wait for the reset.")
        print(f"  failed: {message[:300]}")
        return None

    glb_out = os.path.join(out_dir, f"{stem}.glb")
    shutil.copy(result[1], glb_out)
    print(f"  mesh    {glb_out}  ({os.path.getsize(glb_out) / 1024:.0f} KB)")

    video = result[0].get("video") if isinstance(result[0], dict) else None
    if video and os.path.exists(video):
        mp4_out = os.path.join(out_dir, f"{stem}_turntable.mp4")
        shutil.copy(video, mp4_out)
        print(f"  preview {mp4_out}")

    print(f"  done in {time.time() - started:.0f}s")
    return glb_out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        generate(path)
