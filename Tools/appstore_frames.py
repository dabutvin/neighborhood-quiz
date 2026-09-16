#!/usr/bin/env python3
"""Frames a raw app screenshot into a captioned App Store marketing image.

The store lets you upload a bare screenshot, but a bare screenshot sells nothing:
the shots that convert carry a line of copy above them and stand the phone on a
background rather than filling the frame edge to edge. This does that, once per
shot — a cozy pasture gradient, the caption in the game's own brown, and the
screenshot floated in the lower two-thirds with rounded corners and a soft
shadow, the way a phone sits on a table.

It keeps the canvas the exact size of the shot it is handed, so a screenshot
captured on the simulator App Review actually asks for — iPhone 6.9 inch at
1320x2868, iPad 13 inch at 2064x2752 — comes out framed at the very size the
store wants back. The output is flattened to RGB, since App Store screenshots
carry no alpha.

    python3 Tools/appstore_frames.py \\
        --input raw/iphone_title.png \\
        --output framed/iphone_1_title.png \\
        --caption "A cozy pig puzzle"

The workflow in .github/workflows/appstore-assets.yml drives it over every shot;
run it by hand to re-frame one, or to try a caption on for size.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# The game's own colours, out of GamePalette, so the frame and the screen inside
# it are painted from one tin. RGB, since that is what Pillow wants.
CREAM = (252, 242, 222)
POST = (69, 43, 26)
# The pasture the phone stands on: a warm cream sky at the top settling into a
# lit meadow green at the foot, light enough that the brown caption stays legible.
SKY = (244, 237, 221)
MEADOW = (171, 206, 135)

# Where to look for a bold, rounded face. SF Pro Rounded first, since that is the
# font the game itself sets its wordmark in, then whatever the machine has, then
# Pillow's own last-resort bitmap so the tool never dies for want of a typeface.
FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/SFCompactRounded.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    """A bold rounded face at the asked size, from the first candidate that loads.

    Apple's system fonts ship as variable faces whose default cut is a regular
    weight, so where the file offers a heavier named instance we take it — a
    caption wants to be heavy — and shrug off any file that does not.
    """
    for path in FONT_CANDIDATES:
        if not Path(path).exists():
            continue
        try:
            font = ImageFont.truetype(path, size)
        except OSError:
            continue
        for weight in ("Black", "Heavy", "Bold"):
            try:
                font.set_variation_by_name(weight)
                break
            except (OSError, ValueError, AttributeError):
                continue
        return font
    return ImageFont.load_default(size)


def gradient(width: int, height: int, top: tuple, bottom: tuple) -> Image.Image:
    """A vertical wash from one colour to another, the pasture behind the phone."""
    base = Image.new("RGB", (width, height), top)
    draw = ImageDraw.Draw(base)
    for y in range(height):
        t = y / max(height - 1, 1)
        draw.line(
            [(0, y), (width, y)],
            fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return base


def rounded(image: Image.Image, radius: int) -> Image.Image:
    """The screenshot with its corners taken off, so it reads as a phone."""
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), image.size], radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def wrapped(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, limit: int) -> list:
    """The caption broken into lines that each fit inside the limit."""
    words = text.split()
    lines: list[str] = []
    line = ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= limit or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def frame(input_path: Path, caption: str, output_path: Path) -> tuple:
    """Composes one framed shot and writes it, returning the canvas size."""
    shot = Image.open(input_path).convert("RGB")
    width, height = shot.size

    canvas = gradient(width, height, SKY, MEADOW)

    # The phone sits in the lower four-fifths, leaving a band at the top for the
    # caption; it is scaled to fit that box with room to breathe on either side.
    box_w, box_h = width * 0.82, height * 0.78
    scale = min(box_w / width, box_h / height)
    shot_w, shot_h = round(width * scale), round(height * scale)
    shot = shot.resize((shot_w, shot_h), Image.LANCZOS)

    shot_x = (width - shot_w) // 2
    shot_y = round(height * 0.185)
    radius = round(shot_w * 0.085)

    # A soft shadow under the phone, drawn as a blurred dark plate a touch below
    # and behind it, so the screenshot lifts off the pasture rather than sitting flat.
    blur = round(width * 0.02)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    plate = [
        (shot_x, shot_y + round(height * 0.006)),
        (shot_x + shot_w, shot_y + shot_h + round(height * 0.006)),
    ]
    ImageDraw.Draw(shadow).rounded_rectangle(plate, radius=radius, fill=(40, 26, 14, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    canvas = canvas.convert("RGBA")
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(rounded(shot, radius), (shot_x, shot_y))

    draw = ImageDraw.Draw(canvas)

    # The caption, set as large as two lines will allow, centred in the band above
    # the phone. It shrinks until it fits rather than spilling over the shot.
    limit = round(width * 0.86)
    size = round(height * 0.036)
    while size > round(height * 0.02):
        font = load_font(size)
        lines = wrapped(draw, caption, font, limit)
        line_h = (font.getbbox("Ag")[3] - font.getbbox("Ag")[1]) + round(size * 0.28)
        if len(lines) <= 2 and all(draw.textlength(ln, font=font) <= limit for ln in lines):
            break
        size -= 4
    else:
        font = load_font(size)
        lines = wrapped(draw, caption, font, limit)
        line_h = (font.getbbox("Ag")[3] - font.getbbox("Ag")[1]) + round(size * 0.28)

    block_h = line_h * len(lines)
    y = max(round(height * 0.055), (shot_y - block_h) // 2)
    for line in lines:
        w = draw.textlength(line, font=font)
        draw.text((round((width - w) / 2), y), line, font=font, fill=POST)
        y += line_h

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output_path, "PNG")
    return canvas.size


def main() -> None:
    parser = argparse.ArgumentParser(description="Frame a screenshot into an App Store image.")
    parser.add_argument("--input", required=True, type=Path, help="Raw screenshot PNG.")
    parser.add_argument("--output", required=True, type=Path, help="Where the framed image is written.")
    parser.add_argument("--caption", required=True, help="The line of copy above the phone.")
    args = parser.parse_args()

    size = frame(args.input, args.caption, args.output)
    print(f"Wrote {args.output} ({size[0]}x{size[1]}) — {args.caption!r}")


if __name__ == "__main__":
    main()
