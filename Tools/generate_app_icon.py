#!/usr/bin/env python3
"""Draw the app icon: the same Manhattan the app draws, turned onto the diagonal.

The icon is the map, not a picture of a map — it is projected from the same shoreline
and the same 1811 grid the Swift draws from (`ManhattanMapData`, `ManhattanGrid`), so
correcting the island corrects the tile. What it does differently is the angle: the app
stands the avenues upright, which leaves a tall thin island in a square tile, so the
icon turns the whole thing another forty-five degrees and lets Manhattan run corner to
corner.

Deliberately dependency-free — no Pillow, no cairo — because it writes three PNGs a
year and a toolchain nobody has installed is a toolchain that rots. It rasterises by
scanline at four times the final size and averages back down, which is slow and
perfectly adequate.

Usage:
    python3 Tools/generate_app_icon.py

Writes AppIcon.png, AppIcon-Dark.png and AppIcon-Tinted.png into
NeighborhoodQuiz/Resources/Assets.xcassets/AppIcon.appiconset/.
"""

from __future__ import annotations

import math
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path

SIZE = 1024
SUPERSAMPLE = 4
# Where the app's own map is defined, kept in step with it by hand. Anything here that
# drifts from the Swift will show up as an icon that is not the app's map.
ROTATION_DEGREES = 16.0  # the app uses -29, which stands the avenues up
PADDING = 40  # in final pixels, before supersampling

OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "NeighborhoodQuiz/Resources/Assets.xcassets/AppIcon.appiconset"
)

# The shoreline, transcribed from ManhattanMapData.shoreline.
SHORELINE = [
    (-74.0170, 40.7033), (-74.0175, 40.7110), (-74.0168, 40.7185), (-74.0110, 40.7262),
    (-74.0100, 40.7340), (-74.0095, 40.7420), (-74.0090, 40.7490), (-74.0070, 40.7570),
    (-74.0000, 40.7650), (-73.9925, 40.7720), (-73.9855, 40.7855), (-73.9750, 40.8000),
    (-73.9630, 40.8195), (-73.9545, 40.8350), (-73.9475, 40.8517), (-73.9345, 40.8690),
    (-73.9270, 40.8760), (-73.9180, 40.8745), (-73.9230, 40.8620), (-73.9290, 40.8480),
    (-73.9335, 40.8300), (-73.9320, 40.8155), (-73.9295, 40.8040), (-73.9310, 40.7950),
    (-73.9400, 40.7825), (-73.9440, 40.7742), (-73.9490, 40.7660), (-73.9585, 40.7580),
    (-73.9680, 40.7490), (-73.9730, 40.7405), (-73.9730, 40.7310), (-73.9745, 40.7188),
    (-73.9765, 40.7135), (-73.9880, 40.7095), (-73.9985, 40.7075), (-74.0030, 40.7055),
]

# The avenues worth showing at icon size, as (feet west of Fifth, first street, last).
ICON_AVENUES = [
    (-2950, 1, 125), (-1650, 6, 129), (-840, 17, 132), (0, 8, 142),
    (920, 3, 59), (1720, 11, 59), (2520, 13, 110), (3320, 13, 110), (4120, 14, 125),
]

BEARING_DEGREES = 29.0
ANCHOR = (-73.98145, 40.75368)
ANCHOR_STREET = 42.0
FEET_PER_BLOCK = 5280.0 / 20
METRES_PER_FOOT = 0.3048
METRES_PER_DEGREE_LATITUDE = 111_320.0


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


def grid_coordinate(street: float, west_of_fifth: float) -> tuple[float, float]:
    """The corner of a numbered street and a line so many feet west of Fifth Avenue."""
    bearing = math.radians(BEARING_DEGREES)
    along = (street - ANCHOR_STREET) * FEET_PER_BLOCK
    north_feet = along * math.cos(bearing) + west_of_fifth * math.sin(bearing)
    east_feet = along * math.sin(bearing) - west_of_fifth * math.cos(bearing)
    metres_per_degree_longitude = METRES_PER_DEGREE_LATITUDE * math.cos(math.radians(ANCHOR[1]))
    return (
        ANCHOR[0] + east_feet * METRES_PER_FOOT / metres_per_degree_longitude,
        ANCHOR[1] + north_feet * METRES_PER_FOOT / METRES_PER_DEGREE_LATITUDE,
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


def inside(polygon, point) -> bool:
    result = False
    previous = len(polygon) - 1
    for index in range(len(polygon)):
        ax, ay = polygon[index]
        bx, by = polygon[previous]
        if (ay > point[1]) != (by > point[1]):
            x = (bx - ax) * (point[1] - ay) / (by - ay) + ax
            if point[0] < x:
                result = not result
        previous = index
    return result


def draw(palette: Palette) -> None:
    size = SIZE * SUPERSAMPLE
    projection = Projection(SHORELINE, size, PADDING * SUPERSAMPLE, ROTATION_DEGREES)
    canvas = Canvas(size, palette.water)

    shore = [projection.point(c) for c in SHORELINE]
    canvas.fill_polygon(shore, palette.land)

    park = [
        projection.point(grid_coordinate(59, 0)),
        projection.point(grid_coordinate(110, 0)),
        projection.point(grid_coordinate(110, 2520)),
        projection.point(grid_coordinate(59, 2520)),
    ]
    canvas.fill_polygon(park, palette.park)

    # Every fifth cross street, and then the avenues over them. Both are cut at the
    # water by walking the line and keeping the parts that land on the island, which
    # is the same trick the app plays with `Shoreline.clip` and a great deal cruder.
    def draw_ruled(a, b, width, colour) -> None:
        steps = 240
        run = []
        for step in range(steps + 1):
            t = step / steps
            point = projection.point((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            if inside(shore, point):
                run.append(point)
            else:
                if len(run) > 1:
                    canvas.stroke_segment(run[0], run[-1], width, colour)
                run = []
        if len(run) > 1:
            canvas.stroke_segment(run[0], run[-1], width, colour)

    for number in range(5, 156, 5):
        spans = [(-4000, 0), (2520, 6200)] if 60 <= number <= 109 else [(-4000, 6200)]
        for west_from, west_to in spans:
            draw_ruled(
                grid_coordinate(number, west_from),
                grid_coordinate(number, west_to),
                3.0 * SUPERSAMPLE,
                palette.street,
            )

    for west, first, last in ICON_AVENUES:
        draw_ruled(
            grid_coordinate(first, west),
            grid_coordinate(last, west),
            5.5 * SUPERSAMPLE,
            palette.avenue,
        )

    # The shoreline itself, inked last so nothing crosses it.
    for index in range(len(shore)):
        canvas.stroke_segment(
            shore[index], shore[(index + 1) % len(shore)], 7.0 * SUPERSAMPLE, palette.shore
        )

    final_size, pixels = canvas.downsample(SUPERSAMPLE)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    write_png(OUTPUT / palette.filename, final_size, pixels)
    print(f"wrote {OUTPUT / palette.filename}")


def main() -> None:
    for palette in (LIGHT, DARK, TINTED):
        draw(palette)


if __name__ == "__main__":
    main()
