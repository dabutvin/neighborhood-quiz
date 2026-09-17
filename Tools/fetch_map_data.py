#!/usr/bin/env python3
"""Fetch the map the app draws from NYC Open Data and write it into the app bundle.

Run on demand, never at build time and never at runtime:

    python3 Tools/fetch_map_data.py

It writes NeighborhoodQuiz/Resources/manhattan.json, which is committed. The app
reads that file and nothing else; CI never touches the network and neither does a
shipped build. This is the same arrangement the Park Slope map uses.

Four datasets, all from data.cityofnewyork.us:

  Centerline (inkn-q76z)          every street segment in the city, with its name
  Borough Boundaries (gthc-hcne)  the real shoreline, piers and all
  Parks Properties (enfh-gkve)    the greens, Central Park chief among them
  2020 NTAs (9nt8-h7nd)           the neighborhoods the city recognises
  2020 Census Tracts (63ge-mke6)  what those are built out of, and what ours are

What comes back is not drawable as it stands. The city stores a street as the
dozens of little segments between its corners — Broadway is 389 rows — named in
clipped upper case ("1 AVE", "E  HOUSTON ST") and interleaved with ramps and
service roads that are not streets at all. So this joins the segments back into
whole streets, spells the names the way a person writes them, throws the plumbing
away, and thins the geometry down to what a map drawn with a shaky pen can show.
"""

from __future__ import annotations

import collections
import json
import math
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import NamedTuple

DOMAIN = "https://data.cityofnewyork.us/resource"
CENTERLINE = "inkn-q76z"
BOROUGHS = "gthc-hcne"
PARKS = "enfh-gkve"
NEIGHBORHOODS = "9nt8-h7nd"
TRACTS = "63ge-mke6"
MANHATTAN = "1"

OUT = Path(__file__).resolve().parents[1] / "NeighborhoodQuiz/Resources/manhattan.json"

# Roadway types worth drawing: an ordinary street, a highway, a bridge. The rest of
# the table is ramps, driveways, ferry routes, u-turns and "non-physical" segments
# that exist to make the address system work rather than because you can walk them.
DRAWN_TYPES = ("1", "2", "3")

# How far a point may be moved when thinning, in degrees. About four metres, which
# is inside the width of the pen at every zoom the map offers.
STREET_TOLERANCE = 0.00004
# The shoreline is thinned much harder than the streets. The city's polygon traces
# every pier and mooring in 4,785 points, which is both more detail than a shaky pen
# can show and — since the outline is one path that is always on screen and so can
# never be culled — a thousand bezier curves on every frame. Twenty metres is under
# a point on the glass with the whole island in view.
SHORE_TOLERANCE = 0.00025
PARK_TOLERANCE = 0.00006

# Rings smaller than this are piers and mooring dolphins rather than land.
MIN_RING_AREA = 1e-5
# A green is filtered by its acreage instead, so this only throws out rings that are
# degenerate rather than small — Washington Square is a twentieth of the area the
# smallest island has to clear, and belongs on the map.
MIN_PARK_AREA = 1e-7

# A neighborhood's outline is thinned about as hard as the shoreline. It is a shape
# somebody taps rather than reads, and the tap is tested against the thinned ring, so
# what is drawn and what is hit are the same polygon either way.
NEIGHBORHOOD_TOLERANCE = 0.00025

# Unioning tracts leaves slivers behind: a tract's share of the river, a mooring, the
# odd pier. Every real neighborhood comes out at 6e-5 or larger and every sliver at
# 1.2e-7 or smaller, so there is a factor of five hundred either side of this.
MIN_NEIGHBORHOOD_AREA = 1e-6

# The NTA table is not only neighborhoods. Type 9 is a park or a cemetery — Central
# Park, Highbridge, Inwood Hill, Randall's Island — and type 6 is the United Nations,
# which is a place but not a neighborhood anybody is asked to name. Only type 0 is
# somewhere people live and call something.
NEIGHBORHOOD_TYPE = "0"

class Area(NamedTuple):
    """One neighborhood of the finished map, and where its ground comes from."""

    name: str
    #: Whole NTAs it takes, by the city's name for them.
    ntas: tuple[str, ...] = ()
    #: Census tracts it takes by hand, by `ctlabel`, which is unique within the borough.
    tracts: tuple[str, ...] = ()
    #: Tracts to leave out of the NTAs above, for the one case where a name has a
    #: passenger it should not be carrying.
    without: tuple[str, ...] = ()


# The three tracts in the East River. The city files them under Lenox Hill; nobody
# standing on them would agree.
ROOSEVELT_ISLAND = ("238.02", "238.03", "238.04")


# What the map is divided into.
#
# The city draws 32 lived-in neighborhoods in Manhattan and gives several of them
# compound names — "SoHo-Little Italy-Hudson Square" is one area — which is fine to read
# off a map and no good at all to be asked to name. So the map is divided again here:
# the compounds come apart, the halves of Harlem and Washington Heights go back
# together, and a few names are shortened to what people say.
#
# The dividing is done in census tracts, which is what NTAs are built out of and which
# therefore nest inside them exactly. That matters twice over: the pieces still tile the
# island with no gaps and no overlaps, and every border is a real one the city surveyed
# rather than a line drawn here by eye. Where an area is a whole NTA, or two of them put
# back together, it says so; where it is a piece of one, the tracts are listed, and the
# check at the end of `neighborhoods()` is what keeps those lists honest.
AREAS = (
    # --- below Houston
    Area("Battery Park City", tracts=("317.03", "317.04")),
    Area("Financial District", tracts=("7", "9", "13", "15.01", "15.02")),
    Area("Civic Center", tracts=("29.01", "31")),
    Area("Tribeca", tracts=("21", "33", "39")),
    Area("Chinatown", tracts=("8", "16", "25", "27", "29.02")),
    Area("Two Bridges", tracts=("2.01", "6")),
    Area("Little Italy", tracts=("41", "43")),
    Area("SoHo", tracts=("45", "47", "49")),
    Area("Hudson Square", tracts=("37",)),
    # --- Houston to 14th
    Area("Lower East Side", ntas=("Lower East Side",)),
    Area("East Village", tracts=("30.02", "32", "34", "36.02", "38", "40.01", "40.02", "42")),
    Area("Alphabet City", tracts=("20", "22.02", "24", "26.01", "26.02", "28")),
    Area("Greenwich Village", ntas=("Greenwich Village",)),
    Area("West Village", ntas=("West Village",)),
    # --- 14th to 42nd
    Area("Chelsea", tracts=("81", "83", "87", "89", "91", "93", "97", "99.01", "99.02")),
    Area("Hudson Yards", tracts=("99.03", "103", "111", "117")),
    Area("Union Square", tracts=("52", "54")),
    Area("Flatiron", tracts=("56", "58")),
    Area("NoMad", tracts=("74", "76", "95", "101")),
    Area("Gramercy", ntas=("Gramercy",)),
    Area("Stuy Town", ntas=("Stuyvesant Town-Peter Cooper Village",)),
    Area("Kips Bay", tracts=("62", "66", "70.01", "70.02", "72")),
    Area("Murray Hill", tracts=("78", "80", "86.01", "88")),
    # --- 42nd to 59th
    Area("Times Square", tracts=("113", "119", "125")),
    Area("Midtown", tracts=("82", "84", "94", "96", "102", "104", "109", "112.01",
                            "112.02", "131", "137")),
    Area("Midtown East", tracts=("92", "100", "106.01", "108.01", "108.02", "108.03",
                                 "112.03")),
    Area("Turtle Bay", tracts=("86.03", "90", "98")),
    Area("Hell's Kitchen", ntas=("Hell's Kitchen",)),
    # --- above 59th
    Area("Upper East Side",
         ntas=("Upper East Side-Carnegie Hill",
               "Upper East Side-Lenox Hill-Roosevelt Island",
               "Upper East Side-Yorkville"),
         without=ROOSEVELT_ISLAND),
    Area("Roosevelt Island", tracts=ROOSEVELT_ISLAND),
    Area("Upper West Side",
         ntas=("Upper West Side (Central)",
               "Upper West Side-Lincoln Square",
               "Upper West Side-Manhattan Valley")),
    Area("Morningside Heights", ntas=("Morningside Heights",)),
    Area("Manhattanville", tracts=("213.03", "219")),
    Area("West Harlem", tracts=("217.03", "223.01", "223.02")),
    Area("Harlem", ntas=("Harlem (North)", "Harlem (South)")),
    Area("East Harlem", ntas=("East Harlem (North)", "East Harlem (South)")),
    Area("Hamilton Heights", tracts=("225", "229", "233", "237")),
    Area("Sugar Hill", tracts=("227", "231", "235.01")),
    Area("Washington Heights", ntas=("Washington Heights (North)", "Washington Heights (South)")),
    Area("Inwood", ntas=("Inwood",)),
)


# Manhattan borough runs down to Governors, Ellis and Liberty Islands. They are real
# but they are a mile out to sea, and a map that fits them in shrinks the island it
# is actually about. Ellis and Liberty sit west of anything Manhattan proper reaches,
# and Governors sits south, so a corner of water either way is enough to leave them out.
MIN_RING_LATITUDE = 40.695
MIN_RING_LONGITUDE = -74.03

# The streets that carry their name at the widest zoom, and the ones after them.
# Both are counts rather than lengths, so the map's density does not change when
# the city re-surveys a block.
AVENUE_COUNT = 25
MAJOR_COUNT = 175

# Length alone makes a poor avenue. The longest roads in Manhattan include the
# Henry Hudson Parkway, the FDR and the Harlem River Driveway, none of which anybody
# gives directions by, and the carriage drives that loop through Central Park, which
# are long precisely because they wander. Two rules sort the real avenues out:
#
#   - an avenue is a *street*. The city's roadway type tells a street (1) from a
#     highway (2) and a bridge (3), and Fifth, Madison, Lexington, Amsterdam, Park
#     and Broadway are every one of them a hundred per cent type 1.
#   - an avenue is not in a park. West Drive and East Drive are type 1 and look like
#     avenues by length, so they are caught by the greens instead: a road that spends
#     most of itself inside a park polygon is a carriage drive.
#
# Neither rule is a list of street names, so both survive the city re-surveying.

ORDINAL_WORDS = {
    1: "First", 2: "Second", 3: "Third", 4: "Fourth", 5: "Fifth", 6: "Sixth",
    7: "Seventh", 8: "Eighth", 9: "Ninth", 10: "Tenth", 11: "Eleventh", 12: "Twelfth",
}

# The city's abbreviations, spelled out. A numbered *avenue* is written in words
# ("Fifth Avenue") and a numbered *street* in figures ("42nd Street"), which is how
# New York writes them and not a rule any dataset carries.
EXPANSIONS = {
    "ST": "Street", "STR": "Street", "AVE": "Avenue", "AV": "Avenue", "PL": "Place",
    "RD": "Road", "DR": "Drive", "BLVD": "Boulevard", "PKWY": "Parkway", "PKY": "Parkway",
    "SQ": "Square", "CT": "Court", "TER": "Terrace", "LN": "Lane", "ALY": "Alley",
    "PLZ": "Plaza", "CIR": "Circle", "EXPY": "Expressway", "HWY": "Highway",
    "BRG": "Bridge", "TUNL": "Tunnel", "APPR": "Approach", "WALK": "Walk", "SLIP": "Slip",
    "DY": "Driveway", "HL": "Hill", "HTS": "Heights", "PZ": "Plaza",
    "E": "East", "W": "West", "N": "North", "S": "South", "JR": "Jr.",
    "OF": "of", "THE": "the", "AND": "and", "AT": "at",
}

# Rows whose name marks them as a ramp, a direction of travel or a piece of highway
# plumbing. These are named like streets in the data and are not streets.
PLUMBING = re.compile(r"\b(EN|EX|NB|SB|EB|WB|OPAS|RAMP|RP|SR|SVC|VIADUCT APPR)\b")

# The city records a segment it has no name for as "UNNAMED STREET". That is a row
# with a blank in it, not a street called Unnamed.
NAMELESS = {"UNNAMED STREET", "UNNAMED", "DRIVEWAY", "STREET"}


def fetch(dataset: str, where: str, limit: int = 50_000, select: str | None = None) -> list[dict]:
    query = {"$where": where, "$limit": str(limit)}
    if select:
        query["$select"] = select
    url = f"{DOMAIN}/{dataset}.geojson?{urllib.parse.urlencode(query)}"
    print(f"  fetching {dataset} …", flush=True)
    with urllib.request.urlopen(url, timeout=300) as response:
        payload = json.load(response)
    if "features" not in payload:
        raise SystemExit(f"{dataset}: {payload.get('message', payload)}")
    print(f"    {len(payload['features'])} features")
    return payload["features"]


def ordinal(number: int) -> str:
    if 10 <= number % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(number % 10, "th")
    return f"{number}{suffix}"


def spell(raw: str | None) -> str | None:
    """"E  HOUSTON ST" -> "East Houston Street". None for anything that is not a street."""
    if not raw:
        return None
    words = " ".join(raw.upper().split())
    if PLUMBING.search(words) or words in NAMELESS:
        return None

    parts = words.split(" ")
    spelled = []
    for index, word in enumerate(parts):
        if word.isdigit():
            number = int(word)
            follows = parts[index + 1] if index + 1 < len(parts) else ""
            if follows in ("AVE", "AV") and number in ORDINAL_WORDS:
                spelled.append(ORDINAL_WORDS[number])
            else:
                spelled.append(ordinal(number))
        elif word == "ST" and index == 0 and len(parts) > 1:
            # Leading ST is Saint, not Street: St Nicholas Avenue, St Marks Place.
            # Anywhere else it is the street — "65 ST TRANSVERSE" is a cross street.
            spelled.append("St.")
        elif word in EXPANSIONS:
            spelled.append(EXPANSIONS[word])
        elif word.isalpha():
            spelled.append(word.capitalize())
        else:
            spelled.append(word)
    return " ".join(spelled).strip() or None


def thin(points: list[tuple[float, float]], tolerance: float) -> list[tuple[float, float]]:
    """Ramer–Douglas–Peucker, iteratively so a long shoreline cannot blow the stack."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        if last <= first + 1:
            continue
        (x1, y1), (x2, y2) = points[first], points[last]
        dx, dy = x2 - x1, y2 - y1
        span = math.hypot(dx, dy)
        worst, where = -1.0, first
        for i in range(first + 1, last):
            x, y = points[i]
            away = (abs(dy * x - dx * y + x2 * y1 - y2 * x1) / span) if span else math.hypot(x - x1, y - y1)
            if away > worst:
                worst, where = away, i
        if worst > tolerance:
            keep[where] = True
            stack.append((first, where))
            stack.append((where, last))
    return [p for p, k in zip(points, keep) if k]


def segments_cross(a, b, c, d) -> bool:
    abx, aby = b[0] - a[0], b[1] - a[1]
    cdx, cdy = d[0] - c[0], d[1] - c[1]
    denominator = abx * cdy - aby * cdx
    if abs(denominator) < 1e-15:
        return False
    acx, acy = c[0] - a[0], c[1] - a[1]
    along = (acx * cdy - acy * cdx) / denominator
    across = (acx * aby - acy * abx) / denominator
    return 0 <= along <= 1 and 0 <= across <= 1


def folds_over_itself(ring) -> bool:
    """Whether any two non-adjacent edges of a closed ring cross."""
    count = len(ring)
    for i in range(count):
        a, b = ring[i], ring[(i + 1) % count]
        for j in range(i + 1, count):
            if j == i or j == (i + 1) % count or (j + 1) % count == i:
                continue
            if segments_cross(a, b, ring[j], ring[(j + 1) % count]):
                return True
    return False


def thin_ring(ring, tolerance: float):
    """Thin a closed ring as hard as it can be thinned without folding it over.

    Thinning is per-ring rather than per-map because the rings are not the same size.
    A tolerance that smooths a pier off twenty-one kilometres of Manhattan shoreline
    pinches Wards Island — which is two islands joined by landfill — into a bow tie,
    and a ring that crosses itself fills as a shape with a hole punched in it. So the
    tolerance is backed off until the ring comes out sound, which leaves each island
    thinned as far as its own shape allows and no further.
    """
    closed = ring[:-1] if len(ring) > 1 and ring[0] == ring[-1] else ring[:]
    for attempt in range(6):
        thinned = thin(closed, tolerance / (2 ** attempt))
        if len(thinned) >= 4 and not folds_over_itself(thinned):
            return thinned
    return closed


def chain(segments: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """Sew segments that share an endpoint into whole streets.

    The city's rows meet exactly at corners, so an exact match on the rounded
    endpoint is enough — no tolerance, and no risk of stitching two streets that
    merely pass near one another.
    """
    corner = lambda point: (round(point[0], 7), round(point[1], 7))
    pieces = [list(s) for s in segments if len(s) >= 2]
    at: dict[tuple[float, float], list[int]] = collections.defaultdict(list)
    for index, piece in enumerate(pieces):
        at[corner(piece[0])].append(index)
        at[corner(piece[-1])].append(index)

    used: set[int] = set()
    streets = []
    for index in range(len(pieces)):
        if index in used:
            continue
        used.add(index)
        run = pieces[index][:]
        for _ in range(2):  # grow off the tail, turn round, grow off the other one
            while True:
                tail = corner(run[-1])
                nxt = next((j for j in at.get(tail, []) if j not in used), None)
                if nxt is None:
                    break
                used.add(nxt)
                piece = pieces[nxt]
                run += piece[1:] if corner(piece[0]) == tail else list(reversed(piece))[1:]
            run.reverse()
        streets.append(run)
    return streets


def walked(points: list[tuple[float, float]]) -> float:
    """Length in degrees, with longitude squashed to match this latitude."""
    return sum(
        math.hypot(points[i + 1][0] - points[i][0], (points[i + 1][1] - points[i][1]) / 0.757)
        for i in range(len(points) - 1)
    )


def point_in_ring(point, ring) -> bool:
    """Ray casting: does a ray heading east out of `point` cross the ring an odd
    number of times?"""
    x, y = point
    inside = False
    count = len(ring)
    previous = count - 1
    for index in range(count):
        ax, ay = ring[index]
        bx, by = ring[previous]
        if (ay > y) != (by > y):
            crossing_x = (bx - ax) * (y - ay) / (by - ay) + ax
            if x < crossing_x:
                inside = not inside
        previous = index
    return inside


def ring_area(ring: list[tuple[float, float]]) -> float:
    total = 0.0
    for i in range(len(ring)):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % len(ring)]
        total += x1 * y2 - x2 * y1
    return abs(total) / 2


def round_points(points, places=5, ring=False):
    """Five places is a bit over a metre, which is finer than the pen is steady.

    A ring loses its repeated closing point. GeoJSON writes one and the drawing closes
    its own shapes, so keeping it would leave a zero-length edge — which reads as the
    outline crossing itself and fills as a shape with a nick in it.
    """
    out = []
    for x, y in points:
        point = [round(x, places), round(y, places)]
        if not out or point != out[-1]:
            out.append(point)
    if ring and len(out) > 1 and out[0] == out[-1]:
        out.pop()
    return out


def outline(polygons: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """The boundary of a set of polygons that share their edges exactly.

    Census tracts come out of one topology, so where two of them are neighbours they
    share an edge vertex for vertex. Walk every polygon's edges in order and an interior
    edge turns up once in each direction; throw those pairs away and what is left is the
    outside of the set, which then sews head to tail into rings.

    No clipping, no tolerance, no arithmetic on the coordinates at all — which is why
    the seams come out perfect rather than nearly perfect. Two neighborhoods split from
    one NTA share a border that is the same list of points on both sides.
    """
    edges: collections.Counter = collections.Counter()
    for ring in polygons:
        points = [(round(x, 9), round(y, 9)) for x, y in ring]
        if len(points) > 1 and points[0] == points[-1]:
            points.pop()
        if len(points) < 3:
            continue
        for index in range(len(points)):
            edges[(points[index], points[(index + 1) % len(points)])] += 1

    onward: dict = collections.defaultdict(list)
    for (start, end), count in edges.items():
        if edges.get((end, start)):
            continue  # interior: the tract on the other side walks it the other way
        onward[start].extend([end] * count)

    rings = []
    while onward:
        first = next(iter(onward))
        ring = [first]
        here = first
        while True:
            nexts = onward.get(here)
            if not nexts:
                break
            step = nexts.pop()
            if not nexts:
                del onward[here]
            if step == first:
                break
            ring.append(step)
            here = step
        if len(ring) >= 3:
            rings.append(ring)
    return rings


def build_neighborhoods() -> list[dict]:
    """The forty areas of `AREAS`, drawn out of census tracts.

    The city's lived-in NTAs say which tracts are in play; `AREAS` says how to divide
    them up again. Every tract of every lived-in NTA has to end up in exactly one area —
    claimed twice and two neighborhoods would overlap, claimed by nobody and there would
    be a hole on the island a tap falls through — so this counts them and refuses to
    write a map where that is not true.
    """
    rows = fetch(
        TRACTS,
        where=f"boroname='Manhattan'",
        limit=2_000,
    )

    lived_in = set()
    polygons: dict[str, list] = {}
    nta_of: dict[str, str] = {}
    for row in rows:
        geometry = row.get("geometry")
        properties = row["properties"]
        label = (properties.get("ctlabel") or "").strip()
        nta = (properties.get("ntaname") or "").strip()
        if not geometry or not label:
            continue
        shapes = (
            geometry["coordinates"]
            if geometry["type"] == "MultiPolygon"
            else [geometry["coordinates"]]
        )
        polygons.setdefault(label, []).extend([(x, y) for x, y, *_ in shape[0]] for shape in shapes)
        nta_of[label] = nta

    # Which NTAs are places people live, straight from the NTA table rather than from a
    # list kept by hand here — so a re-fetch that reclassifies one is caught rather than
    # quietly followed.
    for row in fetch(
        NEIGHBORHOODS,
        where=f"boroname='Manhattan' AND ntatype='{NEIGHBORHOOD_TYPE}'",
        limit=500,
    ):
        lived_in.add((row["properties"].get("ntaname") or "").strip())

    in_play = {label for label, nta in nta_of.items() if nta in lived_in}

    claimed: dict[str, str] = {}
    neighborhoods = []
    for area in AREAS:
        labels = set(area.tracts)
        for nta in area.ntas:
            found = {label for label, name in nta_of.items() if name == nta}
            if not found:
                raise SystemExit(f"{area.name}: the city has no NTA called {nta!r}")
            labels |= found
        labels -= set(area.without)

        for label in sorted(labels):
            if label not in in_play:
                raise SystemExit(
                    f"{area.name}: tract {label} is in {nta_of.get(label, 'no NTA')!r}, "
                    "which is not somewhere people live"
                )
            if label in claimed:
                raise SystemExit(
                    f"tract {label} is claimed by both {claimed[label]!r} and {area.name!r}"
                )
            claimed[label] = area.name

        rings = []
        for ring in outline([shape for label in labels for shape in polygons[label]]):
            if ring_area(ring) < MIN_NEIGHBORHOOD_AREA:
                continue  # a tract's share of the river, a pier, a mooring
            thinned = thin_ring(ring, NEIGHBORHOOD_TOLERANCE)
            if len(thinned) >= 4:
                rings.append(thinned)
        if not rings:
            raise SystemExit(f"{area.name}: nothing left to draw")
        neighborhoods.append({"name": area.name, "rings": rings})

    orphans = sorted(in_play - set(claimed))
    if orphans:
        raise SystemExit(
            "no neighborhood claims these tracts, which would leave holes in the island: "
            + ", ".join(f"{label} ({nta_of[label]})" for label in orphans)
        )

    neighborhoods.sort(key=lambda area: area["name"])
    print(
        f"    {len(neighborhoods)} neighborhoods from {len(claimed)} tracts, "
        f"{sum(len(r) for n in neighborhoods for r in n['rings'])} points"
    )
    return neighborhoods


def main() -> None:
    print("NYC Open Data:")

    # --- the shoreline
    boroughs = fetch(BOROUGHS, where=f"borocode='{MANHATTAN}'", limit=10)
    rings = [r for poly in boroughs[0]["geometry"]["coordinates"] for r in poly]
    land = []
    for ring in rings:
        if ring_area(ring) < MIN_RING_AREA:
            continue
        if min(point[1] for point in ring) < MIN_RING_LATITUDE:
            continue
        if min(point[0] for point in ring) < MIN_RING_LONGITUDE:
            continue
        land.append(thin_ring([(x, y) for x, y in ring], SHORE_TOLERANCE))
    land.sort(key=ring_area, reverse=True)
    print(f"    {len(land)} islands, {sum(len(r) for r in land)} points")

    def touches_land(points) -> bool:
        """Whether any part of a street is on one of the islands the map draws.

        A box round the islands will not do this job: Governors Island is close enough
        to the Battery that any slack generous enough to keep a bridge's far end also
        keeps Craig Road. So it is the polygons themselves, and the test is applied to
        a whole joined street rather than to the city's individual rows — a bridge's
        middle span is out over the water, and only the ends of it are on land.
        """
        return any(any(point_in_ring(p, ring) for ring in land) for p in points)

    # --- the streets
    rows = fetch(
        CENTERLINE,
        where=f"starts_with(b5sc,'{MANHATTAN}') AND rw_type in({','.join(repr(t) for t in DRAWN_TYPES)})",
        select="full_street_name,rw_type,the_geom",
    )
    by_name: dict[str, list] = collections.defaultdict(list)
    kinds: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    plumbing = 0
    adrift = 0
    for row in rows:
        name = spell(row["properties"].get("full_street_name"))
        geometry = row.get("geometry")
        if not name or not geometry:
            plumbing += 1
            continue
        kinds[name][row["properties"].get("rw_type")] += 1
        lines = geometry["coordinates"] if geometry["type"] == "MultiLineString" else [geometry["coordinates"]]
        for line in lines:
            by_name[name].append([(x, y) for x, y in line])
    print(f"    {plumbing} rows were ramps, service roads or unnamed")
    print(f"    {len(by_name)} named streets")

    streets = []
    adrift = 0
    for name, segments in by_name.items():
        runs = [thin(run, STREET_TOLERANCE) for run in chain(segments)]
        runs = [r for r in runs if len(r) >= 2]
        kept = [r for r in runs if touches_land(r)]
        adrift += len(runs) - len(kept)
        runs = kept
        if not runs:
            continue
        # One name, one label: the longest run of a street carries it.
        longest = max(range(len(runs)), key=lambda i: walked(runs[i]))
        streets.append({
            "name": name,
            "runs": runs,
            "labelled": longest,
            "length": sum(walked(r) for r in runs),
            "roadway": kinds[name].most_common(1)[0][0] if kinds[name] else "1",
        })

    streets.sort(key=lambda s: -s["length"])

    print(f"    {adrift} runs were on islands the map leaves out")
    pieces = sum(len(s["runs"]) for s in streets)
    points = sum(len(r) for s in streets for r in s["runs"])
    print(f"    joined into {pieces} runs, {points} points after thinning")

    # --- the greens
    park_rows = fetch(PARKS, where="borough='M'", limit=2000)
    parks = []
    for row in park_rows:
        geometry = row.get("geometry")
        if not geometry:
            continue
        acres = float(row["properties"].get("acres") or 0)
        if acres < 8:  # a pocket park is a dot at this scale
            continue
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        for polygon in polygons:
            ring = thin_ring([(x, y) for x, y in polygon[0]], PARK_TOLERANCE)
            if len(ring) >= 4 and ring_area(ring) >= MIN_PARK_AREA:
                parks.append({"name": row["properties"].get("signname") or "", "ring": ring})
    print(f"    {len(parks)} greens over eight acres")

    # --- which of them are avenues
    park_rings = [p["ring"] for p in parks]

    def mostly_in_a_park(street) -> bool:
        points = [p for run in street["runs"] for p in run]
        if not points:
            return False
        inside = sum(1 for p in points if any(point_in_ring(p, ring) for ring in park_rings))
        return inside > len(points) * 0.6

    ranked = 0
    for street in streets:
        avenue = (
            ranked < AVENUE_COUNT
            and street["roadway"] == "1"
            and not mostly_in_a_park(street)
        )
        if avenue:
            street["tier"] = 0
            ranked += 1
        else:
            street["tier"] = 1
    # Everything not an avenue falls back to length order for the second band.
    for rank, street in enumerate(s for s in streets if s["tier"] != 0):
        street["tier"] = 1 if rank < MAJOR_COUNT else 2
    print(f"    {ranked} of them rank as avenues")

    # The file's order is the order names are offered in when two of them want the
    # same piece of paper, so it has to be priority order — rank first, then length.
    # Sorting by length alone was enough while rank *followed* length, and stopped
    # being enough the moment a long highway could sit above a shorter avenue.
    streets.sort(key=lambda s: (s["tier"], -s["length"]))

    # --- the neighborhoods
    neighborhoods = build_neighborhoods()

    # --- write it
    names = [s["name"] for s in streets]
    roads = []
    for index, street in enumerate(streets):
        for position, run in enumerate(street["runs"]):
            roads.append({
                "n": index,
                "t": street["tier"],
                "l": 1 if position == street["labelled"] else 0,
                "p": round_points(run),
            })

    document = {
        "source": "NYC Open Data — Centerline (inkn-q76z), Borough Boundaries (gthc-hcne), Parks Properties (enfh-gkve)",
        "names": names,
        "roads": roads,
        "land": [round_points(r, ring=True) for r in land],
        "parks": [{"name": p["name"], "ring": round_points(p["ring"], ring=True)} for p in parks],
        "neighborhoods": [
            {"name": n["name"], "rings": [round_points(r, ring=True) for r in n["rings"]]}
            for n in neighborhoods
        ],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(document, separators=(",", ":")))
    print(f"\nwrote {OUT} ({OUT.stat().st_size / 1024:.0f} KB)")
    print(f"  {len(names)} streets, {len(roads)} runs, {len(land)} islands, "
          f"{len(parks)} greens, {len(neighborhoods)} neighborhoods")


if __name__ == "__main__":
    main()
