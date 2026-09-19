#!/usr/bin/env python3
"""Fetch the maps the app draws from NYC Open Data and write them into the app bundle.

Run on demand, never at build time and never at runtime:

    python3 Tools/fetch_map_data.py             # every borough the tool knows
    python3 Tools/fetch_map_data.py brooklyn    # just the one

It writes NeighborhoodQuiz/Resources/<borough>.json — manhattan.json, brooklyn.json —
which are committed. The app reads those files and nothing else; CI never touches the
network and neither does a shipped build. This is the same arrangement the Park Slope
map uses.

Five datasets, all from data.cityofnewyork.us:

  Centerline (inkn-q76z)          every street segment in the city, with its name
  Borough Boundaries (gthc-hcne)  the real shoreline, piers and all
  Parks Properties (enfh-gkve)    the greens, Central Park and Prospect Park chief among them
  2020 NTAs (9nt8-h7nd)           the neighborhoods the city recognises
  2020 Census Tracts (63ge-mke6)  what those are built out of, and what ours are

What comes back is not drawable as it stands. The city stores a street as the
dozens of little segments between its corners — Broadway is 389 rows — named in
clipped upper case ("1 AVE", "E  HOUSTON ST") and interleaved with ramps and
service roads that are not streets at all. So this joins the segments back into
whole streets, spells the names the way a person writes them, throws the plumbing
away, and thins the geometry down to what a map drawn with a shaky pen can show.

Everything that differs between one borough and the next — the codes the city files
it under, how many streets carry a name at the widest zoom, whether a numbered avenue
is written in words, and above all what its neighborhoods are — lives in one
`Borough` record. The pipeline is the same for all of them.
"""

from __future__ import annotations

import collections
import json
import math
import re
import sys
import textwrap
import urllib.parse
import urllib.request
from pathlib import Path
from typing import NamedTuple

DOMAIN = "https://data.cityofnewyork.us/resource"
CENTERLINE = "inkn-q76z"
BOUNDARIES = "gthc-hcne"
PARKS = "enfh-gkve"
NEIGHBORHOODS = "9nt8-h7nd"
TRACTS = "63ge-mke6"

RESOURCES = Path(__file__).resolve().parents[1] / "NeighborhoodQuiz/Resources"

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

# Rings smaller than this are piers and mooring dolphins rather than land. The marsh
# islands in Jamaica Bay clear it, and they are Brooklyn, so they stay.
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
# Park, Prospect Park, Green-Wood, Floyd Bennett Field — type 6 is an institution
# that is a place but not a neighborhood anybody is asked to name (the United
# Nations, the Navy Yard, Fort Hamilton), and type 7 is a cemetery. Only type 0 is
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


class Borough(NamedTuple):
    """Everything the pipeline needs to know about one borough and nothing else."""

    #: As the tract and NTA tables spell it.
    name: str
    #: The city's digit for it: `borocode` in the boundaries table, and the first digit
    #: of every centerline segment's `b5sc`, which is what the street query keys on.
    code: str
    #: The parks table keeps its own initial instead.
    park_letter: str
    #: What is written to Resources.
    file: str
    #: What the map is divided into. See the two lists below.
    areas: tuple[Area, ...]
    #: The streets that carry their name at the widest zoom, and the ones after them.
    #: Both are counts rather than lengths, so the map's density does not change when
    #: the city re-surveys a block.
    avenue_count: int
    major_count: int
    #: Whether a numbered avenue is written in words. Manhattan writes Fifth Avenue;
    #: Brooklyn's avenues run to 28th, and "Twelfth Avenue" beside "13th Avenue" reads
    #: wrong, so Brooklyn writes 4th Avenue. Numbered streets are figures everywhere.
    avenues_in_words: bool
    #: Rings of the borough boundary that reach south or west of these are left out.
    #: None keeps every island the city files under the borough.
    min_ring_latitude: float | None = None
    min_ring_longitude: float | None = None


# The three tracts in the East River. The city files them under Lenox Hill; nobody
# standing on them would agree.
ROOSEVELT_ISLAND = ("238.02", "238.03", "238.04")


# What Manhattan is divided into.
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
# check at the end of `build_neighborhoods()` is what keeps those lists honest.
MANHATTAN_AREAS = (
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


# The one tract of Sea Gate: the gated end of the Coney Island peninsula, west of West
# 37th Street. The city files it with Coney Island; the gate says otherwise.
SEA_GATE = ("336",)

# What Brooklyn is divided into.
#
# The city draws 51 lived-in neighborhoods in Brooklyn, and the same things are wrong
# with them: Bed-Stuy, Bushwick, Crown Heights, East New York and East Flatbush are
# each cut into halves and quarters nobody names, while "Carroll Gardens-Cobble
# Hill-Gowanus-Red Hook" is four places that do not even touch in the middle. So the
# halves go back together, the compounds come apart, and the double-barrelled names
# lose the barrel nobody uses.
#
# Where an NTA is cut, the cut follows the streets people actually draw the line on —
# Hamilton Avenue under the expressway for Red Hook, Bond Street for Gowanus, 9th
# Avenue between Sunset Park and Borough Park, Ocean Parkway between Gravesend and
# Homecrest, Flatbush Avenue between Marine Park and Mill Basin — rounded to the
# nearest tract edge. A tract that straddles the line goes with the side most of it is
# on, which is why 414.02 is Gravesend though the city filed it under "(East)".
BROOKLYN_AREAS = (
    # --- the north
    Area("Greenpoint", ntas=("Greenpoint",)),
    Area("Williamsburg", ntas=("Williamsburg",)),
    Area("South Williamsburg", ntas=("South Williamsburg",)),
    Area("East Williamsburg", ntas=("East Williamsburg",)),
    Area("Bushwick", ntas=("Bushwick (East)", "Bushwick (West)")),
    # --- downtown and the brownstone belt
    # DUMBO is everything north of the BQE, Vinegar Hill included; the Farragut Houses
    # south of the expressway go with Downtown, as does everything down to Atlantic.
    Area("DUMBO", tracts=("21",)),
    Area("Downtown Brooklyn", tracts=("11", "13", "15.01", "15.02", "23", "37")),
    Area("Boerum Hill", tracts=("39", "41", "43", "69.01")),
    Area("Brooklyn Heights", ntas=("Brooklyn Heights",)),
    Area("Fort Greene", ntas=("Fort Greene",)),
    Area("Clinton Hill", ntas=("Clinton Hill",)),
    # Red Hook is what lies south of Hamilton Avenue and the expressway above it. The
    # Columbia Street waterfront north of there has no tract of its own — the piers
    # (53.03) and the blocks behind them (51) go with Carroll Gardens, which they
    # adjoin, and the northern end (47) with Cobble Hill. Gowanus is the canal and
    # the blocks east of Bond Street on its far side, down to the expressway.
    Area("Red Hook", tracts=("53.01", "53.02", "59", "85")),
    Area("Cobble Hill", tracts=("45", "47", "49")),
    Area("Carroll Gardens", tracts=("51", "53.03", "63", "65", "67", "69.02", "75", "77")),
    Area("Gowanus", tracts=("71", "117", "119.01", "119.02", "121", "127")),
    Area("Park Slope", ntas=("Park Slope",)),
    Area("Prospect Heights", ntas=("Prospect Heights",)),
    Area("Windsor Terrace", ntas=("Windsor Terrace-South Slope",)),
    Area("Kensington", ntas=("Kensington",)),
    # --- central
    Area("Bedford-Stuyvesant", ntas=("Bedford-Stuyvesant (East)", "Bedford-Stuyvesant (West)")),
    Area("Crown Heights", ntas=("Crown Heights (North)", "Crown Heights (South)")),
    Area("Prospect Lefferts Gardens", ntas=("Prospect Lefferts Gardens-Wingate",)),
    Area("Flatbush", ntas=("Flatbush",)),
    Area("Ditmas Park", ntas=("Flatbush (West)-Ditmas Park-Parkville",)),
    Area("East Flatbush",
         ntas=("East Flatbush-Erasmus", "East Flatbush-Farragut",
               "East Flatbush-Remsen Village", "East Flatbush-Rugby")),
    Area("Midwood", ntas=("Midwood",)),
    # --- the east
    Area("Ocean Hill", ntas=("Ocean Hill",)),
    Area("Brownsville", ntas=("Brownsville",)),
    Area("Cypress Hills", ntas=("Cypress Hills",)),
    Area("East New York",
         ntas=("East New York (North)", "East New York-New Lots", "East New York-City Line")),
    Area("Starrett City", ntas=("Spring Creek-Starrett City",)),
    Area("Canarsie", ntas=("Canarsie",)),
    Area("Flatlands", ntas=("Flatlands",)),
    # --- the south-west
    # "Sunset Park (East)-Borough Park (West)" is the two blocks between 8th Avenue and
    # Fort Hamilton Parkway. 9th Avenue is the line: the strip west of it goes to
    # Sunset Park, the strip east of it to Borough Park.
    Area("Sunset Park",
         ntas=("Sunset Park (West)", "Sunset Park (Central)"),
         tracts=("90.02", "92.02", "94.02", "104.02", "106.02", "108.02")),
    Area("Borough Park", ntas=("Borough Park",), tracts=("110", "112", "114", "116")),
    Area("Bay Ridge", ntas=("Bay Ridge",)),
    Area("Dyker Heights", ntas=("Dyker Heights",)),
    Area("Bensonhurst", ntas=("Bensonhurst",)),
    Area("Bath Beach", ntas=("Bath Beach",)),
    Area("Mapleton", ntas=("Mapleton-Midwood (West)",)),
    # --- the south
    # "Gravesend (East)-Homecrest" is split at Ocean Parkway.
    Area("Gravesend",
         ntas=("Gravesend (West)", "Gravesend (South)"),
         tracts=("386", "388", "396", "398", "414.01", "414.02", "422")),
    Area("Homecrest",
         tracts=("390", "392", "394", "416", "418", "420", "554", "556", "582", "584", "588")),
    Area("Madison", ntas=("Madison",)),
    Area("Coney Island", ntas=("Coney Island-Sea Gate",), without=SEA_GATE),
    Area("Sea Gate", tracts=SEA_GATE),
    Area("Brighton Beach", ntas=("Brighton Beach",)),
    # Manhattan Beach is the peninsula south of the bay. Gerritsen Beach is both its
    # sections — the old one on the peninsula east of Knapp Street and the new one
    # north of the creek, up to Avenue U. Sheepshead Bay is the rest, Emmons Avenue
    # and the Plumb Beach end included.
    Area("Manhattan Beach", tracts=("612", "616", "620")),
    Area("Gerritsen Beach", tracts=("628", "632")),
    Area("Sheepshead Bay",
         tracts=("570", "572", "586", "590", "592", "594.02", "594.03", "594.04", "596",
                 "598", "600", "606", "608", "622", "626")),
    # Marine Park is west of Flatbush Avenue and the park it is named for. Mill Basin
    # is east of Flatbush on both sides of Avenue U — the peninsulas either side of the
    # basin and Old Mill Basin behind them; 670 straddles Flatbush and lies mostly on
    # the Kings Plaza side. Bergen Beach is north-east of the basin, Georgetown included.
    Area("Marine Park",
         tracts=("636", "640", "644", "646", "648", "652", "654", "656", "658", "660", "662")),
    Area("Mill Basin", tracts=("670", "686", "698", "702.01")),
    Area("Bergen Beach", tracts=("696.01", "696.02", "700", "706.01")),
)


MANHATTAN = Borough(
    name="Manhattan",
    code="1",
    park_letter="M",
    file="manhattan.json",
    areas=MANHATTAN_AREAS,
    avenue_count=25,
    major_count=175,
    avenues_in_words=True,
    # Manhattan borough runs down to Governors, Ellis and Liberty Islands. They are
    # real but they are a mile out to sea, and a map that fits them in shrinks the
    # island it is actually about. Ellis and Liberty sit west of anything Manhattan
    # proper reaches, and Governors sits south, so a corner of water either way is
    # enough to leave them out.
    min_ring_latitude=40.695,
    min_ring_longitude=-74.03,
)

BROOKLYN = Borough(
    name="Brooklyn",
    code="3",
    park_letter="B",
    file="brooklyn.json",
    areas=BROOKLYN_AREAS,
    # Brooklyn has twice Manhattan's streets and, being wider than it is tall, is drawn
    # a good deal smaller on the glass, so the bands are not scaled up in proportion:
    # forty named at the widest zoom is about what stays legible before the names
    # start to fight.
    avenue_count=40,
    major_count=350,
    avenues_in_words=False,
)

BOROUGHS = {"manhattan": MANHATTAN, "brooklyn": BROOKLYN}


# Length alone makes a poor avenue. The longest roads in Manhattan include the
# Henry Hudson Parkway, the FDR and the Harlem River Driveway, none of which anybody
# gives directions by, and the carriage drives that loop through Central Park, which
# are long precisely because they wander. Brooklyn has the Belt Parkway, the BQE
# and the drives round Prospect Park to say the same thing. Two rules sort the real
# avenues out:
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

# The city's abbreviations, spelled out. A numbered *street* is written in figures
# ("42nd Street") everywhere; whether a numbered *avenue* is written in words is the
# borough's call (see `Borough.avenues_in_words`). Neither is a rule any dataset
# carries.
EXPANSIONS = {
    "ST": "Street", "STR": "Street", "AVE": "Avenue", "AV": "Avenue", "PL": "Place",
    "RD": "Road", "DR": "Drive", "BLVD": "Boulevard", "BL": "Boulevard",
    "PKWY": "Parkway", "PKY": "Parkway", "PY": "Parkway",
    "SQ": "Square", "CT": "Court", "TER": "Terrace", "LN": "Lane", "ALY": "Alley",
    "PLZ": "Plaza", "CIR": "Circle", "EXPY": "Expressway", "EXPWY": "Expressway",
    "EXWPY": "Expressway", "EP": "Expressway", "HWY": "Highway", "DRV": "Drive", "BRG": "Bridge", "BRDG": "Bridge", "BR": "Bridge", "TUNL": "Tunnel",
    "APPR": "Approach", "WALK": "Walk", "SLIP": "Slip", "DY": "Driveway", "HL": "Hill",
    "HTS": "Heights", "PZ": "Plaza", "RDWY": "Roadway", "ESPL": "Esplanade",
    "PROM": "Promenade", "CMNS": "Commons", "GDNS": "Gardens", "MNR": "Manor",
    "CV": "Cove", "CTR": "Center", "FT": "Fort", "BCH": "Beach", "IS": "Island",
    "PED": "Pedestrian", "ACAD": "Academy", "HSNG": "Housing",
    "E": "East", "W": "West", "N": "North", "S": "South",
    "NE": "Northeast", "NW": "Northwest", "SE": "Southeast", "SW": "Southwest",
    "JR": "Jr.", "JJ": "J.J.",
    "OF": "of", "THE": "the", "AND": "and", "AT": "at", "TO": "to",
}

# Names that capitalise in the middle, which `str.capitalize` cannot know.
PROPER = {"DEKALB": "DeKalb", "METROTECH": "MetroTech"}

# Rows whose name marks them as a ramp, a direction of travel or a piece of highway
# plumbing. These are named like streets in the data and are not streets.
PLUMBING = re.compile(r"\b(EN|EX|NB|SB|EB|WB|OPAS|RAMP|RP|SR|SVC|VIADUCT APPR)\b")

# The city records a segment it has no name for as "UNNAMED STREET" — or "UNNAMED
# ST", depending on who typed it. That is a row with a blank in it, not a street
# called Unnamed, and ninety-one rows of Brooklyn are called nothing but "CONNECTOR".
NAMELESS = {"DRIVEWAY", "STREET", "CONNECTOR"}


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


def capitalised(word: str) -> str:
    """"O'BRIEN" -> "O'Brien". A capital after every apostrophe, not only the first."""
    return re.sub(r"[A-Z]+", lambda run: run.group().capitalize(), word)


def spell_word(
    word: str,
    follows: str,
    first: bool,
    avenues_in_words: bool,
    unknown: collections.Counter | None,
) -> str:
    if "-" in word:
        # "MARINE PY-GIL HODGES MEMORIAL BRG": each side of the hyphen is spelled on
        # its own, so the abbreviation on the left still expands.
        return "-".join(
            spell_word(part, "", False, avenues_in_words, unknown) for part in word.split("-")
        )
    if word.isdigit():
        number = int(word)
        if avenues_in_words and follows in ("AVE", "AV") and number in ORDINAL_WORDS:
            return ORDINAL_WORDS[number]
        return ordinal(number)
    if word == "ST" and first:
        # Leading ST is Saint, not Street: St Nicholas Avenue, St Marks Place.
        # Anywhere else it is the street — "65 ST TRANSVERSE" is a cross street.
        return "St."
    if word in EXPANSIONS:
        return EXPANSIONS[word]
    if word in PROPER:
        return PROPER[word]
    if word.startswith("MC") and len(word) > 3 and word.isalpha():
        # McDonald Avenue, McGuinness Boulevard: the city writes them as one shout.
        return "Mc" + word[2:].capitalize()
    if word.isalpha():
        if unknown is not None and 2 <= len(word) <= 4:
            # Short and unknown: possibly a word, possibly an abbreviation the table
            # above has not met. Counted so it can be looked at, not guessed at.
            unknown[word] += 1
        return word.capitalize()
    return capitalised(word)


def spell(
    raw: str | None,
    avenues_in_words: bool = True,
    unknown: collections.Counter | None = None,
) -> str | None:
    """"E  HOUSTON ST" -> "East Houston Street". None for anything that is not a street.

    `unknown`, if given, collects the short words that were capitalised without being
    recognised, so an abbreviation the table has not met shows up rather than shipping
    as "Bch 37th Street".
    """
    if not raw:
        return None
    words = " ".join(raw.upper().split())
    if PLUMBING.search(words) or words in NAMELESS or words.startswith("UNNAMED"):
        return None

    parts = words.split(" ")
    spelled = []
    index = 0
    while index < len(parts):
        word = parts[index]
        follows = parts[index + 1] if index + 1 < len(parts) else ""
        if len(parts) == 2 and index == 1 and len(word) == 1 and parts[0] in ("AVE", "AV"):
            # "AVE N" is Avenue N. Brooklyn's lettered avenues run A to Z, so here
            # N, S and W are letters and not compass points — though in "PARK AVE S"
            # the S is still South.
            spelled.append(word)
            index += 1
            continue
        if word in ("MC", "MAC") and follows.isalpha() and len(follows) > 1:
            # "MC KIBBIN ST", "MAC DONOUGH ST": the city puts a space in the name
            # where the name has none. Note MACON and MACKAY do not come this way.
            spelled.append(word.capitalize() + follows.capitalize())
            index += 2
            continue
        spelled.append(spell_word(word, follows, index == 0 and len(parts) > 1, avenues_in_words, unknown))
        index += 1
    return " ".join(spelled).strip() or None


def thin_indices(points: list[tuple[float, float]], tolerance: float) -> list[int]:
    """Ramer–Douglas–Peucker, iteratively so a long shoreline cannot blow the stack.

    Returns the indices of the points kept, in order, so a caller can tell which
    stretch of the original a thinned edge stands for.
    """
    if len(points) < 3:
        return list(range(len(points)))
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
    return [i for i, k in enumerate(keep) if k]


def thin(points: list[tuple[float, float]], tolerance: float) -> list[tuple[float, float]]:
    return [points[i] for i in thin_indices(points, tolerance)]


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


def crossing_edges(ring) -> set[int]:
    """The edges of a closed ring that cross an edge they are not joined to, by the
    index of the point each starts at.

    A sweep over the edges' extents rather than every pair against every pair: a
    borough's raw shoreline is twelve thousand points, and the pairs of those would
    take a coffee break to test.
    """
    count = len(ring)
    extents = []
    for i in range(count):
        (ax, ay), (bx, by) = ring[i], ring[(i + 1) % count]
        extents.append((min(ax, bx), max(ax, bx), min(ay, by), max(ay, by), i))
    extents.sort()
    crossing: set[int] = set()
    active: list[tuple] = []
    for x0, x1, y0, y1, i in extents:
        active = [e for e in active if e[1] >= x0]
        for _, _, ey0, ey1, j in active:
            if ey1 < y0 or ey0 > y1:
                continue
            if (j + 1) % count == i or (i + 1) % count == j:
                continue  # neighbours share a corner, which is not a crossing
            if segments_cross(ring[i], ring[(i + 1) % count], ring[j], ring[(j + 1) % count]):
                crossing.add(i)
                crossing.add(j)
        active.append((x0, x1, y0, y1, i))
    return crossing


def folds_over_itself(ring) -> bool:
    """Whether any two non-adjacent edges of a closed ring cross."""
    return bool(crossing_edges(ring))


def as_written(points):
    """The points as the file will carry them, so a fold is looked for in the ring
    that ships rather than in one a hair different: five places is a bit over a
    metre, and a metre is enough to make two edges that nearly touch cross."""
    return [(round(x, 5), round(y, 5)) for x, y in points]


def thin_ring(ring, tolerance: float):
    """Thin a closed ring as hard as it can be thinned without folding it over.

    Thinning is per-ring rather than per-map because the rings are not the same size.
    A tolerance that smooths a pier off twenty-one kilometres of Manhattan shoreline
    pinches Wards Island — which is two islands joined by landfill — into a bow tie,
    and a ring that crosses itself fills as a shape with a hole punched in it.

    And it is backed off per-edge rather than per-ring, because the rings are not the
    same shape all the way round either. Brooklyn's shoreline is sound at the full
    tolerance except in three creeks, where two banks a few metres apart get thinned
    across one another; halving the tolerance for the whole ring until the last creek
    came right would carry five times the points everywhere else. So only the edges
    that cross are re-thinned, from the original points, at half the tolerance they
    had — and again, halved again, until they stop — which leaves every reach of the
    shore thinned as far as its own shape allows and no further.

    A ring that still crosses when its crossing edges are back at the city's own
    resolution is one the city drew that way — a parkway ribbon pinched to a point, or
    a park boundary that doubles back within the metre the file rounds to — and it is
    returned as it stands rather than dropped. The shoreline's caller checks; a nick
    in a green is nothing anybody will see.
    """
    closed = ring[:-1] if len(ring) > 1 and ring[0] == ring[-1] else ring[:]
    if len(closed) < 4:
        return closed
    kept = thin_indices(closed, tolerance)
    halvings = [0] * len(kept)  # of the edge that starts at each kept point
    points = closed
    for _ in range(12):
        points = [closed[i] for i in kept]
        crossing = crossing_edges(as_written(points))
        if not crossing and len(points) >= 4:
            break
        refined, levels = [], []
        for position, start in enumerate(kept):
            refined.append(start)
            levels.append(halvings[position])
            if position not in crossing:
                continue
            end = kept[(position + 1) % len(kept)]
            span = closed[start:end + 1] if end > start else closed[start:] + closed[:end + 1]
            level = halvings[position] + 1
            levels[-1] = level
            for inner in thin_indices(span, tolerance / (2 ** level))[1:-1]:
                refined.append((start + inner) % len(closed))
                levels.append(level)
        kept, halvings = refined, levels
    return points


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

    def finish(ring):
        # Start the ring at its westernmost point rather than wherever the walk
        # happened to begin. Thinning pins a ring's first point and works out from
        # it, so a ring that started somewhere different came out thinned
        # differently, and the file changed on every run without the city having
        # changed a thing.
        if len(ring) >= 3:
            start = ring.index(min(ring))
            rings.append(ring[start:] + ring[:start])

    while onward:
        first = min(onward)
        ring = [first]
        position = {first: 0}
        here = first
        while True:
            nexts = onward.get(here)
            if not nexts:
                break
            step = min(nexts)
            nexts.remove(step)
            if not nexts:
                del onward[here]
            if step == first:
                break
            if step in position:
                # Back at a corner the ring has already been through: two lobes that
                # touch at a point, like Inwood at the edge of its park. Walked straight
                # through, that is one ring with a vertex in it twice, which is a fold.
                # Pinched off, it is two sound rings, one of them usually a sliver.
                lobe = ring[position[step]:]
                del ring[position[step]:]
                for vertex in lobe:
                    del position[vertex]
                finish(lobe)
            position[step] = len(ring)
            ring.append(step)
            here = step
        finish(ring)
    # Largest first, so the order of the file does not depend on the order of the walk.
    rings.sort(key=lambda ring: (-ring_area(ring), ring[0]))
    return rings


def build_neighborhoods(borough: Borough) -> list[dict]:
    """The areas of `borough.areas`, drawn out of census tracts.

    The city's lived-in NTAs say which tracts are in play; the area list says how to
    divide them up again. Every tract of every lived-in NTA has to end up in exactly
    one area — claimed twice and two neighborhoods would overlap, claimed by nobody and
    there would be a hole in the borough a tap falls through — so this counts them and
    refuses to write a map where that is not true.
    """
    rows = fetch(
        TRACTS,
        where=f"boroname='{borough.name}'",
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
        where=f"boroname='{borough.name}' AND ntatype='{NEIGHBORHOOD_TYPE}'",
        limit=500,
    ):
        lived_in.add((row["properties"].get("ntaname") or "").strip())

    in_play = {label for label, nta in nta_of.items() if nta in lived_in}

    claimed: dict[str, str] = {}
    neighborhoods = []
    for area in borough.areas:
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
        for ring in outline([shape for label in sorted(labels) for shape in polygons[label]]):
            if ring_area(ring) < MIN_NEIGHBORHOOD_AREA:
                continue  # a tract's share of the river, a pier, a mooring
            thinned = thin_ring(ring, NEIGHBORHOOD_TOLERANCE)
            if folds_over_itself(as_written(thinned)):
                # A folded ring both fills wrong and hit-tests wrong, and the app's
                # tests check every one.
                raise SystemExit(f"{area.name}: its outline folds over itself as drawn, and cannot be thinned sound")
            if len(thinned) >= 4:
                rings.append(thinned)
        if not rings:
            raise SystemExit(f"{area.name}: nothing left to draw")
        neighborhoods.append({"name": area.name, "rings": rings})

    orphans = sorted(in_play - set(claimed))
    if orphans:
        raise SystemExit(
            "no neighborhood claims these tracts, which would leave holes in the borough: "
            + ", ".join(f"{label} ({nta_of[label]})" for label in orphans)
        )

    neighborhoods.sort(key=lambda area: area["name"])
    print(
        f"    {len(neighborhoods)} neighborhoods from {len(claimed)} tracts, "
        f"{sum(len(r) for n in neighborhoods for r in n['rings'])} points"
    )
    return neighborhoods


def build(borough: Borough) -> None:
    print(f"{borough.name}, from NYC Open Data:")

    # --- the shoreline
    boundary = fetch(BOUNDARIES, where=f"borocode='{borough.code}'", limit=10)
    rings = [r for poly in boundary[0]["geometry"]["coordinates"] for r in poly]
    land = []
    for ring in rings:
        if ring_area(ring) < MIN_RING_AREA:
            continue
        if borough.min_ring_latitude is not None and min(p[1] for p in ring) < borough.min_ring_latitude:
            continue
        if borough.min_ring_longitude is not None and min(p[0] for p in ring) < borough.min_ring_longitude:
            continue
        thinned = thin_ring([(x, y) for x, y in ring], SHORE_TOLERANCE)
        if folds_over_itself(as_written(thinned)):
            # The one ring that has to be sound: it is filled as the land, and the
            # app's tests say so.
            raise SystemExit(f"{borough.name}: an island folds over itself as drawn, and cannot be thinned sound")
        land.append(thinned)
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
        where=f"starts_with(b5sc,'{borough.code}') AND rw_type in({','.join(repr(t) for t in DRAWN_TYPES)})",
        select="full_street_name,rw_type,the_geom",
    )
    by_name: dict[str, list] = collections.defaultdict(list)
    kinds: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    spelling: dict[str, str | None] = {}
    unknown: collections.Counter = collections.Counter()
    plumbing = 0
    for row in rows:
        raw = row["properties"].get("full_street_name") or ""
        if raw not in spelling:
            # Spelled once per distinct name, so the unknown-word count is of names
            # rather than of the rows that happen to carry them.
            spelling[raw] = spell(raw, borough.avenues_in_words, unknown)
        name = spelling[raw]
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
    if unknown:
        # Most of these are words — BAY, PARK, YORK — and a few are abbreviations the
        # table above should learn. Read the list; do not trust it.
        listed = ", ".join(f"{word}×{count}" for word, count in unknown.most_common())
        print(textwrap.fill(
            f"short words capitalised without being recognised: {listed}",
            width=96, initial_indent="    ", subsequent_indent="      ",
        ))

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
    park_rows = fetch(PARKS, where=f"borough='{borough.park_letter}'", limit=2000)
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
            ranked < borough.avenue_count
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
        street["tier"] = 1 if rank < borough.major_count else 2
    print(f"    {ranked} of them rank as avenues")

    # The file's order is the order names are offered in when two of them want the
    # same piece of paper, so it has to be priority order — rank first, then length.
    # Sorting by length alone was enough while rank *followed* length, and stopped
    # being enough the moment a long highway could sit above a shorter avenue.
    streets.sort(key=lambda s: (s["tier"], -s["length"]))

    # --- the neighborhoods
    neighborhoods = build_neighborhoods(borough)

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
    out = RESOURCES / borough.file
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(document, separators=(",", ":")))
    print(f"\nwrote {out} ({out.stat().st_size / 1024:.0f} KB)")
    print(f"  {len(names)} streets, {len(roads)} runs, {len(land)} islands, "
          f"{len(parks)} greens, {len(neighborhoods)} neighborhoods\n")


def main(argv: list[str]) -> None:
    which = argv[1] if len(argv) > 1 else "all"
    if which == "all":
        chosen = list(BOROUGHS.values())
    elif which in BOROUGHS:
        chosen = [BOROUGHS[which]]
    else:
        raise SystemExit(f"usage: {Path(argv[0]).name} [{'|'.join(BOROUGHS)}|all]")
    for borough in chosen:
        build(borough)


if __name__ == "__main__":
    main(sys.argv)
