#!/usr/bin/env python3
"""Draw the app icon: the same Manhattan the app draws, turned onto the diagonal.

The icon is the map, not a picture of a map. It reads the very same
NeighborhoodQuiz/Resources/manhattan.json the app reads, so a re-fetch of the city's
data corrects the tile along with everything else and the two can never drift apart.
What it does differently is the angle: the app stands the avenues upright, which
leaves a tall thin island in a square tile, so the icon turns the whole thing another
forty-five degrees and lets Manhattan run corner to corner.

Deliberately dependency-free — no Pillow, no cairo — because it writes three PNGs a
year and a toolchain nobody has installed is a toolchain that rots. It rasterises by
scanline at four times the final size and averages back down, which is slow and
perfectly adequate.

Usage:
    python3 Tools/fetch_map_data.py     # if the data is stale
    python3 Tools/generate_app_icon.py

Writes AppIcon.png, AppIcon-Dark.png and AppIcon-Tinted.png into
NeighborhoodQuiz/Resources/Assets.xcassets/AppIcon.appiconset/.
"""

from __future__ import annotations

import json
import math
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path

SIZE = 1024
SUPERSAMPLE = 4
# Manhattan's grid runs about twenty-nine degrees east of north; the app turns the
# plane back by that to stand the avenues up. The icon turns it another forty-five so
# the island runs corner to corner instead of filling a narrow stripe.
ROTATION_DEGREES = -29.0 + 45.0
PADDING = 40  # in final pixels, before supersampling

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "NeighborhoodQuiz/Resources/manhattan.json"
OUTPUT = ROOT / "NeighborhoodQuiz/Resources/Assets.xcassets/AppIcon.appiconset"

# Only the avenues. The tile is sixty points across on a home screen, where the
# hundred-odd major cross streets are not lines but a smudge — the same lesson the
# map itself learned at its widest zoom, arrived at from the other direction.
ICON_TIERS = {0: 7.0}


@dataclass(frozen=True)
class Palette:
    filename: str
    water: tuple[int, int, int]
    land: tuple[int, int, int]
    park: tuple[int, int, int]
    shore: tuple[int, int, int]
    avenue: tuple[int, int, int]
    street: tuple[int, int, int]


LIGHT = Palette(
    filename="AppIcon.png",
    water=(0x8F, 0xB4, 0xC4),
    land=(0xEF, 0xE6, 0xD2),
    park=(0xBC, 0xD1, 0xA6),
    shore=(0x5C, 0x86, 0x9E),
    avenue=(0x6E, 0x5A, 0x45),
    street=(0xB7, 0xA7, 0x8F),
)

DARK = Palette(
    filename="AppIcon-Dark.png",
    water=(0x12, 0x18, 0x20),
    land=(0x2B, 0x2A, 0x26),
    park=(0x36, 0x45, 0x2F),
    shore=(0x4A, 0x67, 0x7E),
    avenue=(0xC2, 0xAE, 0x91),
    street=(0x6A, 0x60, 0x52),
)

TINTED = Palette(
    filename="AppIcon-Tinted.png",
    water=(0x1A, 0x1A, 0x1A),
    land=(0xC9, 0xC9, 0xC9),
    park=(0x8E, 0x8E, 0x8E),
    shore=(0x55, 0x55, 0x55),
    avenue=(0x3A, 0x3A, 0x3A),
    street=(0x8A, 0x8A, 0x8A),
)


class Projection:
    """Mercator, turned, and fitted to a square."""

    def __init__(self, coordinates, size: int, padding: float, rotation: float) -> None:
        radians = math.radians(rotation)
        self.cos = math.cos(radians)
        self.sin = math.sin(radians)

        turned = [self._turn(c) for c in coordinates]
        min_x = min(p[0] for p in turned)
        max_x = max(p[0] for p in turned)
        min_y = min(p[1] for p in turned)
        max_y = max(p[1] for p in turned)

        usable = size - 2 * padding
        span_x = max(max_x - min_x, 1e-12)
        span_y = max(max_y - min_y, 1e-12)
        self.scale = min(usable / span_x, usable / span_y)
        self.origin_x = (size - span_x * self.scale) / 2 - min_x * self.scale
        self.origin_y = (size - span_y * self.scale) / 2 - min_y * self.scale

    def _turn(self, coordinate) -> tuple[float, float]:
        longitude, latitude = coordinate
        x = math.radians(longitude)
        y = -math.log(math.tan(math.pi / 4 + math.radians(latitude) / 2))
        return (x * self.cos - y * self.sin, x * self.sin + y * self.cos)

    def point(self, coordinate) -> tuple[float, float]:
        x, y = self._turn(coordinate)
        return (x * self.scale + self.origin_x, y * self.scale + self.origin_y)


class Canvas:
    """A flat RGB buffer with a scanline polygon fill. That is the whole drawing kit:
    every line on the icon is a four-cornered polygon, and so is the island."""

    def __init__(self, size: int, background: tuple[int, int, int]) -> None:
        self.size = size
        self.buffer = bytearray(bytes(background) * (size * size))

    def fill_polygon(self, points, colour: tuple[int, int, int]) -> None:
        if len(points) < 3:
            return
        size = self.size
        swatch = bytes(colour)
        top = max(0, int(math.floor(min(p[1] for p in points))))
        bottom = min(size - 1, int(math.ceil(max(p[1] for p in points))))

        for y in range(top, bottom + 1):
            centre = y + 0.5
            crossings = []
            for index in range(len(points)):
                x1, y1 = points[index]
                x2, y2 = points[(index + 1) % len(points)]
                if (y1 > centre) != (y2 > centre):
                    crossings.append(x1 + (centre - y1) * (x2 - x1) / (y2 - y1))
            crossings.sort()
            row = y * size
            for pair in range(0, len(crossings) - 1, 2):
                left = max(0, int(math.ceil(crossings[pair] - 0.5)))
                right = min(size - 1, int(math.floor(crossings[pair + 1] - 0.5)))
                if right < left:
                    continue
                start = (row + left) * 3
                self.buffer[start:start + (right - left + 1) * 3] = swatch * (right - left + 1)

    def stroke_segment(self, start, end, width: float, colour) -> None:
        """A thick line is a rectangle with a cap at each end, near enough at this size."""
        dx, dy = end[0] - start[0], end[1] - start[1]
        length = math.hypot(dx, dy)
        if length < 1e-9:
            return
        nx, ny = -dy / length * width / 2, dx / length * width / 2
        self.fill_polygon([
            (start[0] + nx, start[1] + ny), (end[0] + nx, end[1] + ny),
            (end[0] - nx, end[1] - ny), (start[0] - nx, start[1] - ny),
        ], colour)

    def downsample(self, factor: int) -> tuple[int, bytearray]:
        size = self.size // factor
        out = bytearray(size * size * 3)
        area = factor * factor
        for y in range(size):
            for x in range(size):
                totals = [0, 0, 0]
                for sub_y in range(factor):
                    row = ((y * factor + sub_y) * self.size + x * factor) * 3
                    for sub_x in range(factor):
                        offset = row + sub_x * 3
                        totals[0] += self.buffer[offset]
                        totals[1] += self.buffer[offset + 1]
                        totals[2] += self.buffer[offset + 2]
                target = (y * size + x) * 3
                out[target] = totals[0] // area
                out[target + 1] = totals[1] // area
                out[target + 2] = totals[2] // area
        return size, out


def write_png(path: Path, size: int, pixels: bytearray) -> None:
    """An 8-bit RGB PNG, written by hand. No alpha: App Review rejects an icon with one."""
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter: none
        raw += pixels[y * size * 3:(y + 1) * size * 3]

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def load():
    if not DATA.exists():
        raise SystemExit(f"{DATA} is missing — run Tools/fetch_map_data.py first")
    return json.loads(DATA.read_text())


def draw(palette: Palette, data) -> None:
    size = SIZE * SUPERSAMPLE
    land = data["land"]
    projection = Projection(
        [tuple(c) for ring in land for c in ring], size, PADDING * SUPERSAMPLE, ROTATION_DEGREES
    )
    canvas = Canvas(size, palette.water)

    for ring in land:
        canvas.fill_polygon([projection.point(c) for c in ring], palette.land)
    for park in data["parks"]:
        canvas.fill_polygon([projection.point(c) for c in park["ring"]], palette.park)

    # Heaviest last, so an avenue is never broken by a cross street over it.
    roads = [r for r in data["roads"] if r["t"] in ICON_TIERS]
    for road in sorted(roads, key=lambda r: -r["t"]):
        width = ICON_TIERS[road["t"]] * SUPERSAMPLE
        colour = palette.avenue if road["t"] == 0 else palette.street
        points = [projection.point(c) for c in road["p"]]
        for i in range(len(points) - 1):
            canvas.stroke_segment(points[i], points[i + 1], width, colour)

    # The shoreline itself, inked last so nothing crosses it.
    for ring in land:
        points = [projection.point(c) for c in ring]
        for i in range(len(points)):
            canvas.stroke_segment(
                points[i], points[(i + 1) % len(points)], 6.0 * SUPERSAMPLE, palette.shore
            )

    final_size, pixels = canvas.downsample(SUPERSAMPLE)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    write_png(OUTPUT / palette.filename, final_size, pixels)
    print(f"wrote {OUTPUT / palette.filename}")


def main() -> None:
    data = load()
    for palette in (LIGHT, DARK, TINTED):
        draw(palette, data)


if __name__ == "__main__":
    main()
