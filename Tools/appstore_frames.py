#!/usr/bin/env python3
"""Frames a raw app screenshot into a captioned App Store marketing image.

The store lets you upload a bare screenshot, but a bare screenshot sells nothing:
the shots that convert carry a line of copy above them and stand the phone on a
background rather than filling the frame edge to edge. This does that, once per
shot, in the map's own materials — the screenshot laid on a sheet of the same
paper the map is drawn on, with the caption lettered over it in the same ink and
the same hand as the street names, and a stroke of terracotta under it.

It keeps the canvas the exact size of the shot it is handed, so a screenshot
captured on the simulator App Review actually asks for — iPhone 6.9 inch at
1320x2868, iPad 13 inch at 2064x2752 — comes out framed at the very size the
store wants back. The output is flattened to RGB, since App Store screenshots
carry no alpha.

    python3 Tools/appstore_frames.py \\
        --input raw/question.png \\
        --output framed/01_question.png \\
        --caption "Find the neighborhood on the map"

The workflow in .github/workflows/appstore-assets.yml drives it over every shot;
run it by hand to re-frame one, or to try a caption on for size.
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# The map's own colours, out of MapPalette, so the frame and the screen inside it
# are painted from one tin. RGB, since that is what Pillow wants.
PALETTES = {
    "light": {
        # The paper: the halo the street names sit on at the top, settling into
        # the land colour — the map's paper with the light falling off it.
        "top": (0xF7, 0xF0, 0xDF),
        "bottom": (0xE6, 0xD9, 0xBC),
        "ink": (0x5B, 0x4A, 0x3A),
        "accent": (0xB0, 0x76, 0x5A),
        "shadow": (60, 40, 22, 110),
        "grain": (0x5B, 0x4A, 0x3A),
    },
    "dark": {
        "top": (0x2B, 0x2A, 0x26),
        "bottom": (0x16, 0x1C, 0x24),
        "ink": (0xE2, 0xD6, 0xBE),
        "accent": (0xD4, 0x79, 0x4C),
        "shadow": (0, 0, 0, 150),
        "grain": (0xEF, 0xE6, 0xD2),
    },
}

# The hand the map is lettered in. Bradley Hand is what the app uses, and every
# Mac has it, which is where the workflow runs; the rest are so a run on any other
# machine still produces something to look at rather than dying for want of a face.
FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Bradley Hand Bold.ttf",
    "/Library/Fonts/Bradley Hand Bold.ttf",
    "/System/Library/Fonts/Supplemental/Noteworthy.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    """The map's hand at the asked size, from the first candidate that loads."""
    for path in FONT_CANDIDATES:
        if not Path(path).exists():
            continue
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def font_name() -> str:
    """Which face the captions will actually be set in, for the log."""
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return path
    return "Pillow's built-in default"


def paper(width: int, height: int, colours: dict) -> Image.Image:
    """A vertical wash from one paper tone to the next, with a little tooth in it.

    The tooth is the same idea as PaperGrain in the app: a scatter of faint flecks
    in the ink colour, seeded so the same shot frames the same way twice.
    """
    top, bottom = colours["top"], colours["bottom"]
    base = Image.new("RGB", (width, height), top)
    draw = ImageDraw.Draw(base)
    for y in range(height):
        t = y / max(height - 1, 1)
        draw.line(
            [(0, y), (width, y)],
            fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )

    grain = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    flecks = ImageDraw.Draw(grain)
    rng = random.Random(width * 7919 + height)
    for _ in range(width * height // 900):
        x, y = rng.randrange(width), rng.randrange(height)
        r = rng.choice((1, 1, 1, 2))
        flecks.ellipse([x, y, x + r, y + r], fill=(*colours["grain"], rng.randrange(10, 28)))
    out = base.convert("RGBA")
    out.alpha_composite(grain)
    return out


def rounded(image: Image.Image, radius: int) -> Image.Image:
    """The screenshot with its corners taken off, so it reads as a phone."""
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), image.size], radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def wrapped(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, limit: int) -> list:
    """The caption broken into lines that each fit inside the limit.

    One line if it fits on one. If it takes two, the break goes where the two come
    out nearest the same length, so "Bank what you earn" is set as two halves rather
    than as three words and an orphan.
    """
    words = text.split()
    if draw.textlength(text, font=font) <= limit:
        return [text]

    best: list[str] | None = None
    best_width = float("inf")
    for cut in range(1, len(words)):
        pair = [" ".join(words[:cut]), " ".join(words[cut:])]
        width = max(draw.textlength(line, font=font) for line in pair)
        if width <= limit and width < best_width:
            best, best_width = pair, width
    if best:
        return best

    # Too long for two: fill each line greedily, and let the caller shrink the type.
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


def underline(draw: ImageDraw.ImageDraw, x0: float, x1: float, y: float, weight: int, colour: tuple) -> None:
    """A stroke of terracotta under the caption, drawn the way a pen would put it
    down: a shallow curve rather than a ruled line, a touch heavier in the middle."""
    steps = 48
    points = []
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        sag = (t - 0.5) ** 2 * 4 - 1  # -1 in the middle, 0 at the ends
        points.append((x, y + sag * weight * 0.9))
    for i in range(steps):
        t = i / steps
        w = max(1, round(weight * (0.55 + 0.45 * (1 - abs(t - 0.5) * 2))))
        draw.line([points[i], points[i + 1]], fill=colour, width=w)


def frame(input_path: Path, caption: str, output_path: Path, appearance: str = "light") -> tuple:
    """Composes one framed shot and writes it, returning the canvas size."""
    colours = PALETTES[appearance]
    shot = Image.open(input_path).convert("RGB")
    width, height = shot.size

    canvas = paper(width, height, colours)

    # The phone sits in the lower four-fifths, leaving a band at the top for the
    # caption; it is scaled to fit that box with room to breathe on either side.
    box_w, box_h = width * 0.80, height * 0.76
    scale = min(box_w / width, box_h / height)
    shot_w, shot_h = round(width * scale), round(height * scale)
    shot = shot.resize((shot_w, shot_h), Image.LANCZOS)

    shot_x = (width - shot_w) // 2
    shot_y = round(height * 0.205)
    # A phone's corners on a portrait shot; a tablet's, which are tighter, on one
    # that is nearer square.
    radius = round(shot_w * (0.085 if height / width > 1.8 else 0.035))

    # A soft shadow under the phone, so the screenshot lifts off the paper rather
    # than being printed on it.
    blur = round(width * 0.02)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    drop = round(height * 0.008)
    plate = [(shot_x, shot_y + drop), (shot_x + shot_w, shot_y + shot_h + drop)]
    ImageDraw.Draw(shadow).rounded_rectangle(plate, radius=radius, fill=colours["shadow"])
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    canvas.alpha_composite(shadow)
    canvas.alpha_composite(rounded(shot, radius), (shot_x, shot_y))

    # A hairline of ink round the phone, the way a drawing is boxed on a page.
    edge = ImageDraw.Draw(canvas)
    edge.rounded_rectangle(
        [(shot_x, shot_y), (shot_x + shot_w - 1, shot_y + shot_h - 1)],
        radius=radius,
        outline=(*colours["ink"], 70),
        width=max(2, round(width * 0.0018)),
    )

    draw = ImageDraw.Draw(canvas)

    # The caption, centred in the band above the phone. Every caption in a set
    # starts from the same size, chosen so a line of copy the length of the ones in
    # the workflow fits in two lines, and the set reads as one; a longer one shrinks
    # until it fits rather than spilling over the shot.
    limit = round(width * 0.84)
    band = shot_y - round(height * 0.03)
    size = round(min(height * 0.042, width * 0.08))
    while True:
        font = load_font(size)
        lines = wrapped(draw, caption, font, limit)
        ascent, descent = font.getmetrics()
        line_h = round((ascent + descent) * 0.98)
        fits = len(lines) <= 2 and all(draw.textlength(ln, font=font) <= limit for ln in lines)
        if (fits and line_h * len(lines) + size * 0.5 <= band) or size <= round(height * 0.018):
            break
        size -= 4

    block_h = line_h * len(lines) + round(size * 0.35)
    y = max(round(height * 0.035), (band - block_h) // 2 + round(height * 0.012))
    widest = 0.0
    for line in lines:
        w = draw.textlength(line, font=font)
        widest = max(widest, w)
        draw.text((round((width - w) / 2), y), line, font=font, fill=colours["ink"])
        y += line_h

    # The stroke under it, a little narrower than the longest line.
    reach = min(widest * 0.7, width * 0.5)
    underline(
        draw,
        (width - reach) / 2,
        (width + reach) / 2,
        y + size * 0.12,
        max(3, round(size * 0.07)),
        colours["accent"],
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output_path, "PNG")
    return canvas.size


def main() -> None:
    parser = argparse.ArgumentParser(description="Frame a screenshot into an App Store image.")
    parser.add_argument("--input", required=True, type=Path, help="Raw screenshot PNG.")
    parser.add_argument("--output", required=True, type=Path, help="Where the framed image is written.")
    parser.add_argument("--caption", required=True, help="The line of copy above the phone.")
    parser.add_argument(
        "--appearance",
        choices=sorted(PALETTES),
        default="light",
        help="Paper and ink for a light-mode shot, or the night map's for a dark one.",
    )
    args = parser.parse_args()

    size = frame(args.input, args.caption, args.output, args.appearance)
    print(f"Wrote {args.output} ({size[0]}x{size[1]}) in {font_name()} — {args.caption!r}")


if __name__ == "__main__":
    main()
