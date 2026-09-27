#!/usr/bin/env python3
"""Draws the Squeeshy app icon.

The icon is the app's own ground with one squeeshy sitting on it: the dark
near-black-blue from AdaptiveBackground, the two pastel glows behind it, and a
compressed squircle carrying Tint.fallback's pink-to-cyan. Kept to a single bold
silhouette because the smallest size this has to survive is 40x40.

    python3 Tools/makeicon.py

Writes a 1024x1024 opaque PNG to the AppIcon asset. Rendered at 4x and
downsampled, because PIL's polygon fill has no antialiasing of its own.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 4096                       # supersampled working size
OUT = 1024                      # what the asset catalog gets
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(HERE, "Squeeshy", "Resources", "Assets.xcassets",
                    "AppIcon.appiconset", "AppIcon.png")

# Straight out of the app. AdaptiveBackground's base, and Tint.fallback's two
# hues converted from HSB to 8-bit RGB.
GROUND = (8, 7, 13)
PINK = (255, 148, 186)          # hue 0.94, sat 0.42, bri 1.0
CYAN = (158, 220, 255)          # hue 0.56, sat 0.38, bri 1.0


def radial(size, cx, cy, radius, color, strength):
    """One of AdaptiveBackground's RadialGradients, as an additive layer."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / size
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / radius
    falloff = np.clip(1.0 - d, 0.0, 1.0) ** 2 * strength
    return falloff[..., None] * np.array(color, dtype=np.float32)


def squircle_mask(size, cx, cy, rx, ry, nx=3.2, ny=2.5):
    """A superellipse, squashed wider than tall so it reads as compressed.

    The two exponents differ on purpose. A higher exponent straightens that
    axis' edges, so pushing nx above ny makes the left and right sides bulge
    while the top and bottom stay round — which is what a soft toy does when
    something presses down on it.
    """
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    u = np.abs((x - cx) / rx) ** nx
    v = np.abs((y - cy) / ry) ** ny
    # Smooth the boundary over ~1.5px so the 4x downsample has clean edges.
    edge = (u + v) ** (1.0 / ny)
    return np.clip((1.02 - edge) * (size / 40), 0.0, 1.0)


def main():
    # --- ground ------------------------------------------------------------
    bg = np.zeros((SS, SS, 3), dtype=np.float32)
    bg += np.array(GROUND, dtype=np.float32)
    bg += radial(SS, 0.26, 0.16, 0.78, PINK, 0.34)
    bg += radial(SS, 0.84, 0.88, 0.72, CYAN, 0.22)
    bg += radial(SS, 0.50, 0.55, 0.55, PINK, 0.16)

    # --- the squeeshy ------------------------------------------------------
    cx, cy = SS * 0.5, SS * 0.53
    rx, ry = SS * 0.335, SS * 0.263
    mask = squircle_mask(SS, cx, cy, rx, ry)

    # A pink-to-cyan diagonal, the same pairing the app tints itself with. The
    # endpoints run richer than Tint.fallback because the sheen laid over them
    # lightens everything it touches; at the pastel values the body went white.
    body_pink = np.array([255, 116, 168], dtype=np.float32)
    body_cyan = np.array([124, 200, 255], dtype=np.float32)
    yy, xx = np.mgrid[0:SS, 0:SS].astype(np.float32) / SS
    t = np.clip((xx * 0.45 + yy * 0.75 - 0.18) / 0.82, 0.0, 1.0)[..., None]
    body = body_pink * (1 - t) + body_cyan * t

    # Volume: lift the top, drop the bottom, so it sits rather than floats.
    shade = np.clip((yy - 0.30) / 0.55, 0.0, 1.0)[..., None]
    body *= (1.10 - shade * 0.34)

    # --- outer glow, painted under the body --------------------------------
    glow_src = Image.fromarray((mask * 255).astype(np.uint8), "L")
    glow = np.asarray(glow_src.filter(ImageFilter.GaussianBlur(SS * 0.055)),
                      dtype=np.float32) / 255.0
    bg += glow[..., None] * np.array(PINK, dtype=np.float32) * 0.30

    canvas = bg * (1 - mask[..., None]) + body * mask[..., None]

    # --- glass highlight ---------------------------------------------------
    # A soft wide sheen across the upper body, clipped to it. This is the whole
    # reason the shape reads as glossy rather than as a flat sticker. Kept broad
    # and weak — a small bright one blows out to a lens flare and takes the pink
    # with it, which is exactly what the first pass did.
    spec = Image.new("L", (SS, SS), 0)
    d = ImageDraw.Draw(spec)
    d.ellipse([cx - rx * 0.78, cy - ry * 0.80, cx + rx * 0.34, cy - ry * 0.26], fill=255)
    spec = np.asarray(spec.filter(ImageFilter.GaussianBlur(SS * 0.070)),
                      dtype=np.float32) / 255.0
    spec *= mask
    canvas += spec[..., None] * np.array([255, 252, 255], dtype=np.float32) * 0.26

    # --- rim light ---------------------------------------------------------
    # The lit edge along the top, made by subtracting a shrunken copy of the
    # body from itself and keeping only the upper half.
    inner = squircle_mask(SS, cx, cy + SS * 0.012, rx * 0.972, ry * 0.962)
    rim = np.clip(mask - inner, 0.0, 1.0)
    rim = np.asarray(
        Image.fromarray((rim * 255).astype(np.uint8), "L")
        .filter(ImageFilter.GaussianBlur(SS * 0.004)),
        dtype=np.float32) / 255.0
    fade = np.clip(1.0 - (yy - 0.26) / 0.34, 0.0, 1.0)
    canvas += (rim * fade)[..., None] * np.array([255, 255, 255], dtype=np.float32) * 0.72

    # No dimple. A soft dark ellipse inside the body was meant to read as a
    # thumb press and instead read as a smudge on the lens — the squeeze is
    # carried by the silhouette's bulged sides, which survives 40x40 anyway.

    img = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8), "RGB")
    img = img.resize((OUT, OUT), Image.LANCZOS)

    os.makedirs(os.path.dirname(DEST), exist_ok=True)
    # RGB, never RGBA: the App Store rejects an icon with an alpha channel.
    img.save(DEST, "PNG", optimize=True)
    print(f"wrote {DEST}  {img.size[0]}x{img.size[1]}  mode={img.mode}")


if __name__ == "__main__":
    main()
