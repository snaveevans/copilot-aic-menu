#!/usr/bin/env python3
"""Create public README screenshots from the private captures in the repo root.

Requires Pillow: python3 -m pip install Pillow
The sensitive pixels are REPLACED with synthetic blurred marks, not blurred in
place, so the original numbers/account name cannot be recovered from the PNG.
"""

from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "images"
OUT.mkdir(parents=True, exist_ok=True)

menu = Image.open(ROOT / "menu_bar.png").convert("RGBA")
if menu.size != (164, 62):
    raise SystemExit("menu_bar.png dimensions changed; inspect before publishing")
menu.save(OUT / "menu_bar.png")

image = Image.open(ROOT / "expanded_menu.png").convert("RGBA")
if image.size != (768, 804):
    raise SystemExit("expanded_menu.png dimensions changed; inspect redaction boxes")

# Pixel boxes in the original screenshot: counts, username, time, reset date.
# The 22.9% in the menu bar and next to the count is intentionally untouched.
boxes = [
    (235, 77, 421, 115),  # Used and allowance (9,160 / 40,000)
    (176, 125, 276, 168), # Remaining credits
    (238, 172, 416, 215), # GitHub username (privacy for a public README)
    (153, 266, 276, 307), # Updated time
    (383, 266, 544, 307), # Reset date
]

rng = random.Random(83017)
for left, top, right, bottom in boxes:
    # Erase the entire rectangle with neighboring background pixels row by row.
    # This is opaque replacement; blurring the original text would be reversible.
    draw = ImageDraw.Draw(image)
    for y in range(top, bottom):
        background = image.getpixel((left - 8, y))
        draw.line((left, y, right - 1, y), fill=background)

    # A synthetic, softly pixelated placeholder makes the redaction visible,
    # without using ANY pixels or letter shapes from the original text.
    width, height = right - left, bottom - top
    mask = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    pixels = ImageDraw.Draw(mask)
    for x in range(7, width - 7, 8):
        if rng.random() < 0.85:
            glyph_height = rng.randint(9, 15)
            y = (height - glyph_height) // 2
            pixels.rounded_rectangle(
                (x, y, x + rng.randint(3, 5), y + glyph_height),
                radius=2,
                fill=(120, 128, 139, 175),
            )
    image.alpha_composite(mask.filter(ImageFilter.GaussianBlur(4)), (left, top))

image.save(OUT / "expanded_menu.png")
print(f"Wrote public screenshots to {OUT}")
