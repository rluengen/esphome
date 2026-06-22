#!/usr/bin/env python3
"""Crop each vehicle schematic layer to ITS OWN alpha bounding box.

All source PNGs in layers/ share a 960x960 canvas. Storing every layer at the
shared (union) bounding box wastes a lot of flash because tiny overlays (a
window sliver, a tire) still occupy the full ~248x436 footprint (~316 KB each
as RGB565+alpha). Instead we crop each layer to its own non-transparent box and
emit a per-layer x/y offset so the layers still stack pixel-aligned in LVGL.

Because the whole schematic is drawn at half scale (resize /2) and the LVGL
card origin is the source-canvas origin scaled by /2, each layer's widget
offset is simply (left//2, top//2) of its own even-aligned bounding box.

Run from the repo root:  python scripts/crop_layers.py
Writes cropped PNGs to layers/cropped/ and prints ready-to-paste YAML
(image: entries and the matching LVGL image widget lines with per-layer x/y).
"""
import os
from PIL import Image

SRC = "layers"
DST = "layers/cropped"

# filename -> (image id, overlay widget id). None overlay id = always-shown base.
# Keep in sync with driver-controller.yaml.
LAYERS = [
    ("907600_car.png",                                  "img_van_base",     None),
    ("907600_cowl.png",                                 "img_cowl",         "ovl_cowl"),
    # Driver (front-left) door + unlock + windows
    ("907600_door_frontleft_open.png",                  "img_door_drv",     "ovl_door_drv_open"),
    ("907600_door_frontleft_unlock.png",                "img_unlock_drv",   "ovl_unlock_drv"),
    ("907600_window_frontleft_opendoorclosed.png",      "img_dwin_open_dc", "ovl_dwin_open_dc"),
    ("907600_window_frontleft_opendooropened.png",      "img_dwin_open_do", "ovl_dwin_open_do"),
    ("907600_window_frontleft_ventilatedoorclosed.png", "img_dwin_vent_dc", "ovl_dwin_vent_dc"),
    ("907600_window_frontleft_ventilatedooropened.png", "img_dwin_vent_do", "ovl_dwin_vent_do"),
    # Passenger (front-right) door + unlock + windows
    ("907600_door_frontright_open.png",                 "img_door_pass",    "ovl_door_pass_open"),
    ("907600_door_frontright_unlock.png",               "img_unlock_pass",  "ovl_unlock_pass"),
    ("907600_window_frontright_opendoorclosed.png",     "img_win_open_dc",  "ovl_win_open_dc"),
    ("907600_window_frontright_opendooropened.png",     "img_win_open_do",  "ovl_win_open_do"),
    ("907600_window_frontright_ventilatedoorclosed.png","img_win_vent_dc",  "ovl_win_vent_dc"),
    ("907600_window_frontright_ventilatedooropened.png","img_win_vent_do",  "ovl_win_vent_do"),
    # Sliding (rear-right) door + unlock
    ("907600_door_rearright_open.png",                  "img_door_slide",   "ovl_door_slide_open"),
    ("907600_door_rearright_unlock.png",                "img_unlock_slide", "ovl_unlock_slide"),
    # Rear barn doors / trunk + unlock
    ("907600_trunk_open.png",                           "img_trunk_open",   "ovl_trunk_open"),
    ("907600_trunk_unlock.png",                         "img_unlock_trunk", "ovl_unlock_trunk"),
    # Tires (low-pressure warnings)
    ("907600_tire_frontleft.png",                       "img_tire_fl",      "ovl_tire_fl"),
    ("907600_tire_frontright.png",                      "img_tire_fr",      "ovl_tire_fr"),
    ("907600_tire_rearleft.png",                        "img_tire_rl",      "ovl_tire_rl"),
    ("907600_tire_rearright.png",                       "img_tire_rr",      "ovl_tire_rr"),
]


def even_box(bb):
    """Even-align a bbox so a /2 resize/offset is exact."""
    l, t, r, b = bb
    l -= l % 2
    t -= t % 2
    if (r - l) % 2:
        r += 1
    if (b - t) % 2:
        b += 1
    return max(0, l), max(0, t), min(960, r), min(960, b)


def main():
    os.makedirs(DST, exist_ok=True)
    results = []
    total_bytes = 0

    for fname, img_id, ovl_id in LAYERS:
        im = Image.open(os.path.join(SRC, fname)).convert("RGBA")
        bb = im.getchannel("A").getbbox()
        if bb is None:
            print("SKIP (empty):", fname)
            continue
        l, t, r, b = even_box(bb)
        im.crop((l, t, r, b)).save(os.path.join(DST, fname))
        w, h = (r - l) // 2, (b - t) // 2
        x, y = l // 2, t // 2  # widget offset within the card
        total_bytes += w * h * 3  # RGB565 + alpha_channel = 3 bytes/px
        results.append((fname, img_id, ovl_id, w, h, x, y))

    print("\n# ---- image: block ----")
    for fname, img_id, ovl_id, w, h, x, y in results:
        print(f"  - file: layers/cropped/{fname}")
        print(f"    id: {img_id}")
        print(f"    type: RGB565")
        print(f"    transparency: alpha_channel")
        print(f"    resize: {w}x{h}")

    print("\n# ---- LVGL widget lines (inside card_doors) ----")
    for fname, img_id, ovl_id, w, h, x, y in results:
        if ovl_id is None:
            print(f"        - image: {{ src: {img_id}, align: TOP_LEFT, x: {x}, y: {y} }}")
        else:
            print(f"        - image: {{ id: {ovl_id}, src: {img_id}, align: TOP_LEFT, x: {x}, y: {y}, hidden: true }}")

    print(f"\n# TOTAL image flash: {total_bytes/1048576:.2f} MB ({len(results)} layers)")
    print("done, wrote", len(results), "files to", DST)


if __name__ == "__main__":
    main()
