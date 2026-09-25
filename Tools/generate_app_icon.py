#!/usr/bin/env python3
"""Draw the app icon: the whole city the app draws, with its name lettered over it.

The icon is the map, not a picture of a map. It reads the very same five files in
NeighborhoodQuiz/Resources/ the app reads, so a re-fetch of the city's data corrects
the tile along with everything else and the two can never drift apart. It used to be
Manhattan on its own, turned onto the diagonal to fit; now that all five boroughs are
drawn it is all five, north-up, which is the shape everybody knows the city by, and it
very nearly fills a square without being turned at all.

Over the city, "NYC" in ink, lettered by the same unsteady hand that draws the streets.
The letters are strokes rather than glyphs from a font — there is no font here, and a
font would be a dependency — three lines for the N, three for the Y, one arc for the
C, each shaken a little as the map's pen is. A coat of paper under the ink is what
keeps the word readable where it crosses the water.

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
PADDING = 76  # in final pixels, before supersampling

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "NeighborhoodQuiz/Resources"
BOROUGH_FILES = ("manhattan", "brooklyn", "queens", "bronx", "staten-island")
OUTPUT = RESOURCES / "Assets.xcassets/AppIcon.appiconset"

# A green has to be about this big to be more than a fleck at sixty points across:
# Central Park, Prospect Park, Flushing Meadows, Van Cortlandt, Pelham Bay, the
# Greenbelt. In square degrees; a hundred acres or so.
MIN_ICON_PARK_AREA = 4e-6

# Streets are not drawn at all. Manhattan alone could carry its avenues; five boroughs
# on the same tile cannot, and a smudge of two thousand roads is what the map itself
# refuses to draw at its widest zoom.

# The word. Letter shapes in a box one unit tall, drawn as strokes: a list of
# polylines each, in a coordinate system where y runs down the page, as it does on
# the tile. The C is an arc from a bit past top-right round to a bit past bottom-right.
LETTER_WIDTH = 0.78
LETTER_GAP = 0.20
WORD_HEIGHT = 0.31  # of the tile
WORD_TILT_DEGREES = -3.0
INK_WIDTH = 0.105  # of the letter height
HALO_WIDTH = 0.19


def _arc(cx: float, cy: float, rx: float, ry: float, start: float, end: float, steps: int = 40):
    return [
        (cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a)))
        for a in (start + (end - start) * i / steps for i in range(steps + 1))
    ]


LETTERS = {
    "N": [[(0.0, 1.0), (0.0, 0.0), (LETTER_WIDTH, 1.0), (LETTER_WIDTH, 0.0)]],
    "Y": [[(0.0, 0.0), (LETTER_WIDTH / 2, 0.52)], [(LETTER_WIDTH, 0.0), (LETTER_WIDTH / 2, 0.52), (LETTER_WIDTH / 2, 1.0)]],
    "C": [_arc(LETTER_WIDTH * 0.55, 0.5, LETTER_WIDTH * 0.55, 0.5, -48, -312)],
}


@dataclass(frozen=True)
class Palette:
    filename: str
    water: tuple[int, int, int]
    land: tuple[int, int, int]
    park: tuple[int, int, int]
    shore: tuple[int, int, int]
    ink: tuple[int, int, int]
    halo: tuple[int, int, int]


LIGHT = Palette(
    filename="AppIcon.png",
    water=(0x8F, 0xB4, 0xC4),
    land=(0xEF, 0xE6, 0xD2),
    park=(0xBC, 0xD1, 0xA6),
    shore=(0x5C, 0x86, 0x9E),
    ink=(0x5B, 0x4A, 0x3A),
    halo=(0xF7, 0xF0, 0xDF),
)

DARK = Palette(
    filename="AppIcon-Dark.png",
    water=(0x12, 0x18, 0x20),
    land=(0x2B, 0x2A, 0x26),
    park=(0x36, 0x45, 0x2F),
    shore=(0x4A, 0x67, 0x7E),
    ink=(0xE2, 0xD6, 0xBE),
    halo=(0x2B, 0x2A, 0x26),
)

TINTED = Palette(
    filename="AppIcon-Tinted.png",
    water=(0x1A, 0x1A, 0x1A),
    land=(0xC9, 0xC9, 0xC9),
    park=(0x8E, 0x8E, 0x8E),
    shore=(0x55, 0x55, 0x55),
    ink=(0x2A, 0x2A, 0x2A),
    halo=(0xDD, 0xDD, 0xDD),
)


class Projection:
    """Mercator, fitted to a square. North-up: nothing to turn any more."""

    def __init__(self, coordinates, size: int, padding: float) -> None:
        projected = [self._mercator(c) for c in coordinates]
        min_x = min(p[0] for p in projected)
        max_x = max(p[0] for p in projected)
        min_y = min(p[1] for p in projected)
        max_y = max(p[1] for p in projected)

        usable = size - 2 * padding
        span_x = max(max_x - min_x, 1e-12)
        span_y = max(max_y - min_y, 1e-12)
        self.scale = min(usable / span_x, usable / span_y)
        self.origin_x = (size - span_x * self.scale) / 2 - min_x * self.scale
        self.origin_y = (size - span_y * self.scale) / 2 - min_y * self.scale

    @staticmethod
    def _mercator(coordinate) -> tuple[float, float]:
        longitude, latitude = coordinate
        return (math.radians(longitude), -math.log(math.tan(math.pi / 4 + math.radians(latitude) / 2)))

    def point(self, coordinate) -> tuple[float, float]:
        x, y = self._mercator(coordinate)
        return (x * self.scale + self.origin_x, y * self.scale + self.origin_y)


class Canvas:
    """A flat RGB buffer with a scanline polygon fill. That is the whole drawing kit:
    every stroke on the icon is a four-cornered polygon with a round cap, and so is
    every island."""

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

    def fill_dot(self, centre, radius: float, colour) -> None:
        self.fill_polygon(_arc(centre[0], centre[1], radius, radius, 0, 360, 24)[:-1], colour)

    def stroke_segment(self, start, end, width: float, colour) -> None:
        """A thick line is a rectangle, near enough at this size."""
        dx, dy = end[0] - start[0], end[1] - start[1]
        length = math.hypot(dx, dy)
        if length < 1e-9:
            return
        nx, ny = -dy / length * width / 2, dx / length * width / 2
        self.fill_polygon([
            (start[0] + nx, start[1] + ny), (end[0] + nx, end[1] + ny),
            (end[0] - nx, end[1] - ny), (start[0] - nx, start[1] - ny),
        ], colour)

    def stroke_polyline(self, points, width: float, colour) -> None:
        """Segments with a round dot at every joint and end, which is what makes a
        thick line turn a corner without a notch."""
        for i in range(len(points) - 1):
            self.stroke_segment(points[i], points[i + 1], width, colour)
        for p in points:
            self.fill_dot(p, width / 2, colour)

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


def ring_area(ring) -> float:
    total = 0.0
    for i in range(len(ring)):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % len(ring)]
        total += x1 * y2 - x2 * y1
    return abs(total) / 2


def load():
    """Every borough's land and its big greens, in one list each."""
    land, parks = [], []
    for name in BOROUGH_FILES:
        path = RESOURCES / f"{name}.json"
        if not path.exists():
            raise SystemExit(f"{path} is missing — run Tools/fetch_map_data.py first")
        data = json.loads(path.read_text())
        land.extend(data["land"])
        parks.extend(p["ring"] for p in data["parks"] if ring_area(p["ring"]) >= MIN_ICON_PARK_AREA)
    return land, parks


class Pen:
    """The unsteady hand, the map's own arithmetic in miniature: a straight run is
    walked in short steps, each nudged a little off the line, so a letter comes out
    lettered rather than set. Seeded, so the icon is the same icon every time."""

    def __init__(self, seed: int, stray: float) -> None:
        self.state = seed
        self.stray = stray

    def next(self) -> float:
        self.state = (self.state * 1_103_515_245 + 12_345) & 0x7FFFFFFF
        return self.state / 0x7FFFFFFF * 2 - 1

    def shake(self, points, step: float):
        out = [points[0]]
        for i in range(len(points) - 1):
            (x1, y1), (x2, y2) = points[i], points[i + 1]
            length = math.hypot(x2 - x1, y2 - y1)
            pieces = max(1, int(length / step))
            nx, ny = -(y2 - y1) / max(length, 1e-9), (x2 - x1) / max(length, 1e-9)
            for k in range(1, pieces + 1):
                t = k / pieces
                wobble = 0.0 if k == pieces else self.next() * self.stray
                out.append((x1 + (x2 - x1) * t + nx * wobble, y1 + (y2 - y1) * t + ny * wobble))
        return out


def word_strokes(size: int):
    """"NYC", laid across the middle of the tile as lists of points in tile pixels."""
    height = WORD_HEIGHT * size
    width = (3 * LETTER_WIDTH + 2 * LETTER_GAP) * height
    left = (size - width) / 2
    top = (size - height) / 2 + 0.03 * size
    tilt = math.radians(WORD_TILT_DEGREES)
    cx, cy = size / 2, size / 2
    pen = Pen(seed=7, stray=height * 0.008)

    def place(x: float, y: float) -> tuple[float, float]:
        px, py = left + x * height, top + y * height
        # The whole word leans a touch, as a word written quickly does.
        dx, dy = px - cx, py - cy
        return (cx + dx * math.cos(tilt) - dy * math.sin(tilt), cy + dx * math.sin(tilt) + dy * math.cos(tilt))

    strokes = []
    for index, letter in enumerate("NYC"):
        offset = index * (LETTER_WIDTH + LETTER_GAP)
        for polyline in LETTERS[letter]:
            placed = [place(offset + x, y) for x, y in polyline]
            strokes.append(pen.shake(placed, step=height * 0.06))
    return strokes, height


def draw(palette: Palette, land, parks) -> None:
    size = SIZE * SUPERSAMPLE
    projection = Projection([tuple(c) for ring in land for c in ring], size, PADDING * SUPERSAMPLE)
    canvas = Canvas(size, palette.water)

    for ring in land:
        canvas.fill_polygon([projection.point(c) for c in ring], palette.land)
    for ring in parks:
        canvas.fill_polygon([projection.point(c) for c in ring], palette.park)

    # The shoreline, inked so the islands read as drawn rather than cut out.
    for ring in land:
        points = [projection.point(c) for c in ring]
        canvas.stroke_polyline(points + points[:1], 3.2 * SUPERSAMPLE, palette.shore)

    # The word: paper first, then ink, the way the map halos its labels.
    strokes, height = word_strokes(size)
    for stroke in strokes:
        canvas.stroke_polyline(stroke, HALO_WIDTH * height, palette.halo)
    for stroke in strokes:
        canvas.stroke_polyline(stroke, INK_WIDTH * height, palette.ink)

    final_size, pixels = canvas.downsample(SUPERSAMPLE)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    write_png(OUTPUT / palette.filename, final_size, pixels)
    print(f"wrote {OUTPUT / palette.filename}")


def main() -> None:
    land, parks = load()
    for palette in (LIGHT, DARK, TINTED):
        draw(palette, land, parks)


if __name__ == "__main__":
    main()
