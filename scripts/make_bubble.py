"""Generate the spirit-level bubble image used by m5stack-tab5-lvgl.yaml.

Produces images/bubble.png: a soft, anti-aliased translucent green disc with a
small highlight, on a fully transparent background. Re-run to regenerate:

    python scripts/make_bubble.py
"""

import os

from PIL import Image, ImageDraw, ImageFilter

# Final on-screen size in pixels (keep in sync with the LVGL bubble math).
SIZE = 48
# Supersample factor for anti-aliasing, then downscale.
SCALE = 8

FILL_COLOR = (76, 175, 80)        # green disc (mdi green)
EDGE_COLOR = (27, 94, 32)         # darker rim
HIGHLIGHT_COLOR = (200, 255, 200) # soft top-left highlight
FILL_ALPHA = 210                  # translucent so the crosshair shows through


def build_bubble() -> Image.Image:
    high_resolution = SIZE * SCALE
    image = Image.new("RGBA", (high_resolution, high_resolution), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    margin = SCALE  # leave a 1px (final) transparent border for clean edges
    disc_box = [margin, margin, high_resolution - margin, high_resolution - margin]

    # Rim then fill, slightly inset, gives a subtle border.
    draw.ellipse(disc_box, fill=EDGE_COLOR + (FILL_ALPHA,))
    rim = SCALE * 3
    fill_box = [disc_box[0] + rim, disc_box[1] + rim, disc_box[2] - rim, disc_box[3] - rim]
    draw.ellipse(fill_box, fill=FILL_COLOR + (FILL_ALPHA,))

    # Highlight in the upper-left quadrant.
    highlight_diameter = int(high_resolution * 0.32)
    highlight_x = int(high_resolution * 0.30)
    highlight_y = int(high_resolution * 0.28)
    highlight_box = [
        highlight_x,
        highlight_y,
        highlight_x + highlight_diameter,
        highlight_y + highlight_diameter,
    ]
    draw.ellipse(highlight_box, fill=HIGHLIGHT_COLOR + (120,))

    image = image.filter(ImageFilter.GaussianBlur(radius=SCALE * 0.4))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    repository_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    images_directory = os.path.join(repository_root, "images")
    os.makedirs(images_directory, exist_ok=True)
    output_path = os.path.join(images_directory, "bubble.png")
    build_bubble().save(output_path)
    print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
