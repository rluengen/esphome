#!/usr/bin/env python3
"""Uniformly crop the vehicle schematic layers to their shared alpha bounding box.

All source PNGs in layers/ share a 960x960 canvas. To save flash, every *used*
layer is cropped to the SAME bounding box (the union of all their non-transparent
pixels) so they stay pixel-aligned when stacked at one card offset in LVGL.

Run from the repo root:  python scripts/crop_layers.py
It prints the BBOX / RESIZE (half) / OFFSET (half) values to plug into
driver-controller.yaml (image resize + image-widget x/y), and writes the cropped
PNGs to layers/cropped/.
"""
import os
from PIL import Image

SRC = "layers"
DST = "layers/cropped"

# Layers actually used by driver-controller.yaml. Keep in sync with the image: block.
FILES = [
    "907600_car.png",
    "907600_cowl.png",
    # Driver (front-left) door + window
    "907600_door_frontleft_open.png",
    "907600_door_frontleft_unlock.png",
    "907600_window_frontleft_opendoorclosed.png",
    "907600_window_frontleft_opendooropened.png",
    "907600_window_frontleft_ventilatedoorclosed.png",
    "907600_window_frontleft_ventilatedooropened.png",
    # Passenger (front-right) door + window
    "907600_door_frontright_open.png",
    "907600_door_frontright_unlock.png",
    "907600_window_frontright_opendoorclosed.png",
    "907600_window_frontright_opendooropened.png",
    "907600_window_frontright_ventilatedoorclosed.png",
    "907600_window_frontright_ventilatedooropened.png",
    # Sliding (rear-right) door
    "907600_door_rearright_open.png",
    "907600_door_rearright_unlock.png",
    # Rear barn doors / trunk
    "907600_trunk_open.png",
    "907600_trunk_unlock.png",
    # Tires (low-pressure warnings)
    "907600_tire_frontleft.png",
    "907600_tire_frontright.png",
    "907600_tire_rearleft.png",
    "907600_tire_rearright.png",
]


def main():
    os.makedirs(DST, exist_ok=True)

    bbox = None
    for f in FILES:
        im = Image.open(os.path.join(SRC, f)).convert("RGBA")
        a = im.getchannel("A").getbbox()
        if a is None:
            continue
        if bbox is None:
            bbox = list(a)
        else:
            bbox[0] = min(bbox[0], a[0])
            bbox[1] = min(bbox[1], a[1])
            bbox[2] = max(bbox[2], a[2])
            bbox[3] = max(bbox[3], a[3])

    l, t, r, b = bbox
    # Even-align so a /2 resize is exact.
    l -= l % 2
    t -= t % 2
    if (r - l) % 2:
        r += 1
    if (b - t) % 2:
        b += 1
    l = max(0, l)
    t = max(0, t)
    r = min(960, r)
    b = min(960, b)

    w, h = r - l, b - t
    print("BBOX", l, t, r, b)
    print("CROP_SIZE", w, "x", h)
    print("RESIZE", w // 2, "x", h // 2)
    print("OFFSET", l // 2, t // 2)

    for f in FILES:
        im = Image.open(os.path.join(SRC, f)).convert("RGBA")
        im.crop((l, t, r, b)).save(os.path.join(DST, f))
    print("done, wrote", len(FILES), "files to", DST)


if __name__ == "__main__":
    main()
