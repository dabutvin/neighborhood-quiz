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

# Type 7 is drawn green, the way a park is. A cemetery is a park to the eye — Green-Wood
# is four hundred and seventy-eight acres of trees and paths in the middle of Brooklyn —
# and it is not in the Parks Properties table, because the city does not run it. Left
# out, it was a blank hole in the map the size of a neighborhood, and the one shape on
# the page that looked like a mistake.
CEMETERY_TYPE = "7"


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
    #: Rings of the borough boundary smaller than this are left out, as piers and
    #: mooring dolphins rather than land. The city-wide floor suits every borough but
    #: one; see the Queens record for why it lifts its own.
    min_ring_area: float = MIN_RING_AREA


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


# The two tracts of Woodside that the city files with Astoria: the wedge between
# Northern Boulevard and Astoria Boulevard, east of the expressway, which is across the
# road from the rest of Woodside and a mile from Astoria's Broadway.
WOODSIDE_NORTH = ("295", "297")
# Beechhurst is the north shore east of 154th Street; Whitestone is the rest.
BEECHHURST = ("987", "991")
# The three tracts of Rochdale Village, the co-op boxed in by Baisley Boulevard,
# Bedell Street, 137th Avenue and Guy R. Brewer Boulevard.
ROCHDALE = ("334.03", "334.04", "334.05")
# Bayswater is the peninsula north of Mott Avenue, west of Beach 25th Street.
BAYSWATER = ("1008.01",)

# What Queens is divided into.
#
# The city draws 59 lived-in neighborhoods in Queens, and Queens, being the borough
# of a hundred named places, has the most to undo: Astoria is in four pieces and
# Ozone Park, Richmond Hill, Corona and Springfield Gardens in two, while "Breezy
# Point-Belle Harbor-Rockaway Park-Broad Channel" is three places strung along a
# peninsula plus an island in the bay. So the pieces go back together, the strings
# come apart by tract along the Beach streets, and the qualifiers — "Murray Hill
# (Queens)" is Murray Hill here — come off.
#
# Where an NTA is cut, the cut is the road people draw the line on — 21st Street and
# 36th Avenue round Dutch Kills, 164th Street between Pomonok and Hillcrest, 188th
# Street between Jamaica Estates and Holliswood, Parsons Boulevard between Briarwood
# and Jamaica Hills, Union Turnpike under Glen Oaks, Little Neck Parkway, the Belt
# Parkway under Lindenwood, Beach 126th and Beach 73rd on the peninsula — rounded to
# the nearest tract edge, and a tract that straddles the line goes with the side most
# of it is on. Parks, cemeteries, the airports, Fort Totten and the rail yards are
# not places anybody is asked to name and are left out, which is why Flushing Meadows
# and Forest Park are holes.
QUEENS_AREAS = (
    # --- the west
    Area("Astoria",
         ntas=("Astoria (Central)", "Astoria (North)-Ditmars-Steinway",
               "Old Astoria-Hallets Point", "Astoria (East)-Woodside (North)"),
         without=WOODSIDE_NORTH),
    Area("Woodside", ntas=("Woodside",), tracts=WOODSIDE_NORTH),
    # Long Island City is Queens Plaza, Court Square and the waterfront up to the
    # bridge; Hunters Point is everything south of 44th Drive and Jackson Avenue,
    # from the Gantry piers along Newtown Creek to the yards.
    Area("Long Island City", tracts=("1.03", "19.01", "19.02", "19.03")),
    Area("Hunters Point", tracts=("1.01", "1.02", "1.04", "7.01", "7.02")),
    # Dutch Kills is east of 21st Street and south of 36th Avenue, down to Queens
    # Plaza. Ravenswood is the rest — the Queensbridge and Ravenswood Houses and the
    # power station on the river.
    Area("Ravenswood", tracts=("25", "37", "39", "43", "45", "47", "85")),
    Area("Dutch Kills", tracts=("31", "33.01", "33.02", "51", "55")),
    Area("Sunnyside", ntas=("Sunnyside",)),
    Area("Jackson Heights", ntas=("Jackson Heights",)),
    Area("East Elmhurst", ntas=("East Elmhurst",)),
    Area("Elmhurst", ntas=("Elmhurst",)),
    Area("Corona", ntas=("Corona", "North Corona")),
    Area("Maspeth", ntas=("Maspeth",)),
    Area("Ridgewood", ntas=("Ridgewood",)),
    Area("Glendale", ntas=("Glendale",)),
    Area("Middle Village", ntas=("Middle Village",)),
    # --- the middle
    Area("Rego Park", ntas=("Rego Park",)),
    Area("Forest Hills", ntas=("Forest Hills",)),
    Area("Kew Gardens", ntas=("Kew Gardens",)),
    Area("Kew Gardens Hills", ntas=("Kew Gardens Hills",)),
    # "Jamaica Hills-Briarwood" is split at Parsons Boulevard.
    Area("Briarwood", tracts=("214", "220.01", "220.02", "230", "232")),
    Area("Jamaica Hills", tracts=("448", "450", "452", "454", "456")),
    # "Pomonok-Electchester-Hillcrest" is split at 164th Street: Pomonok and
    # Electchester west of it, Hillcrest and St. John's east of it.
    Area("Pomonok", tracts=("1227.02", "1227.03", "1227.04", "1257")),
    Area("Hillcrest", tracts=("1241", "1247", "1265", "1267")),
    Area("Fresh Meadows", ntas=("Fresh Meadows-Utopia",)),
    # "Jamaica Estates-Holliswood" is split at 188th Street.
    Area("Jamaica Estates", tracts=("458", "464", "466", "472", "1277")),
    Area("Holliswood", tracts=("476", "478.01", "492.01")),
    # --- Flushing and the north shore
    Area("Flushing", ntas=("Flushing-Willets Point",)),
    Area("Queensboro Hill", ntas=("Queensboro Hill",)),
    Area("East Flushing", ntas=("East Flushing",)),
    Area("Murray Hill", ntas=("Murray Hill-Broadway Flushing",)),
    Area("College Point", ntas=("College Point",)),
    Area("Whitestone", ntas=("Whitestone-Beechhurst",), without=BEECHHURST),
    Area("Beechhurst", tracts=BEECHHURST),
    Area("Bay Terrace", ntas=("Bay Terrace-Clearview",)),
    Area("Auburndale", ntas=("Auburndale",)),
    Area("Bayside", ntas=("Bayside",)),
    Area("Oakland Gardens", ntas=("Oakland Gardens-Hollis Hills",)),
    # "Douglaston-Little Neck" is split at Little Neck Parkway north of the
    # expressway — Douglas Manor, Douglaston Hill and Douglaston Park on the west —
    # and Little Neck takes the blocks south of it, Deepdale included.
    Area("Douglaston", tracts=("1479", "1483", "1507.01")),
    Area("Little Neck", tracts=("1507.02", "1529.01", "1529.02")),
    # "Glen Oaks-Floral Park-New Hyde Park" is split at Union Turnpike; the Queens
    # end of New Hyde Park goes with whichever side of the turnpike it is on.
    Area("Glen Oaks", tracts=("1551.01", "1551.03", "1551.04")),
    Area("Floral Park", tracts=("1579.01", "1579.02", "1579.03")),
    Area("Bellerose", ntas=("Bellerose",)),
    # --- the south-east
    Area("Jamaica", ntas=("Jamaica",)),
    Area("South Jamaica", ntas=("South Jamaica",)),
    Area("Baisley Park", ntas=("Baisley Park",)),
    Area("Hollis", ntas=("Hollis",)),
    Area("St. Albans", ntas=("St. Albans",)),
    Area("Queens Village", ntas=("Queens Village",)),
    Area("Cambria Heights", ntas=("Cambria Heights",)),
    Area("Laurelton", ntas=("Laurelton",)),
    Area("Rosedale", ntas=("Rosedale",)),
    Area("Springfield Gardens",
         ntas=("Springfield Gardens (North)-Rochdale Village",
               "Springfield Gardens (South)-Brookville"),
         without=ROCHDALE),
    Area("Rochdale", tracts=ROCHDALE),
    # --- the south-west
    Area("Woodhaven", ntas=("Woodhaven",)),
    Area("Richmond Hill", ntas=("Richmond Hill", "South Richmond Hill")),
    Area("Ozone Park", ntas=("Ozone Park", "Ozone Park (North)")),
    Area("South Ozone Park", ntas=("South Ozone Park",)),
    # "Howard Beach-Lindenwood" is split at the Belt Parkway: Lindenwood north of it,
    # Howard Beach on both sides of Cross Bay Boulevard south of it.
    Area("Howard Beach", tracts=("884", "892.01")),
    Area("Lindenwood", tracts=("62.01", "62.02")),
    # --- the Rockaways
    # The peninsula, west to east. Breezy Point is everything west of Fort Tilden,
    # Roxbury included. Belle Harbor runs from Beach 149th to Beach 126th, Neponsit
    # included; Rockaway Park from there to Beach 100th; Rockaway Beach to Beach
    # 73rd; Arverne to Beach 59th; Edgemere to Beach 32nd; Far Rockaway is the end.
    Area("Breezy Point", tracts=("916.03",)),
    Area("Belle Harbor", tracts=("922", "928")),
    Area("Rockaway Park", tracts=("934.01", "934.02", "938")),
    Area("Rockaway Beach", tracts=("942.01", "942.02", "942.03")),
    Area("Arverne", tracts=("954", "964")),
    Area("Edgemere", tracts=("972.02", "972.04", "972.05", "972.06")),
    Area("Far Rockaway", ntas=("Far Rockaway-Bayswater",), without=BAYSWATER),
    Area("Bayswater", tracts=BAYSWATER),
    Area("Broad Channel", tracts=("1072.01",)),
)


# The industrial south-east corner of the borough, below Bruckner Boulevard: the rail
# yards and the power plant between the Harlem River and the Bronx Kill.
PORT_MORRIS = ("19.01", "19.02", "19.03")
# The three tracts the city files as "Claremont (West)" that actually adjoin Claremont
# Park — north of it along the Cross Bronx, and south of it along East 170th. The
# fourth, 225, touches nothing of Claremont but the park and goes with Mount Eden.
CLAREMONT_WEST = ("177.02", "227.03", "229.02")
# South of Allerton Avenue and north of Pelham Parkway, from Bronx Park East to
# Williamsbridge Road; the Bronxdale Houses are in 332.02.
BRONXDALE = ("324", "328", "330", "332.01", "332.02")
# West of the Bronx River Parkway, between the cemetery and the county line.
WOODLAWN = ("449.01", "449.02", "451.01", "451.02")
# The peninsula south of Lacombe Avenue, Harding Park included.
CLASON_POINT = ("2", "4")
# North of the Bruckner Expressway, from White Plains Road to Westchester Creek.
UNIONPORT = ("40.01", "72", "78", "92")
# North of East Tremont Avenue and the Bruckner interchange, up to Middletown Road.
SCHUYLERVILLE = ("184", "194", "264")

# What the Bronx is divided into.
#
# The city draws 37 lived-in neighborhoods in the Bronx, and its compounds are the same
# trouble as Brooklyn's: "Pelham Bay-Country Club-City Island" is a shore, a peninsula
# and an island, "Eastchester-Edenwald-Baychester" three places with three subway
# stops, and "University Heights (North)-Fordham" a half of one place stapled to a
# whole other. So the compounds come apart by tract, the two halves of University
# Heights go back together, and the double-barrelled names lose the barrel nobody
# says — Concourse, Kingsbridge, Van Nest, Castle Hill.
#
# Where a cut is made it follows the line people draw it on — Bruckner Boulevard for
# Port Morris, Allerton Avenue for Bronxdale, the Bronx River Parkway for Woodlawn,
# Jerome Avenue for Fordham, Sagamore Street for Van Nest — rounded to the nearest
# tract edge. Marble Hill is not here: it is Manhattan by law and in Manhattan's
# tract file, and is on Manhattan's map. Van Cortlandt and Pelham Bay Parks, Bronx
# Park with the zoo and the garden, Woodlawn Cemetery, Hart and Rikers Islands are
# not lived in and are left out, as the parks are everywhere.
BRONX_AREAS = (
    # --- the south
    Area("Mott Haven", ntas=("Mott Haven-Port Morris",), without=PORT_MORRIS),
    Area("Port Morris", tracts=PORT_MORRIS),
    Area("Melrose", ntas=("Melrose",)),
    Area("Hunts Point", ntas=("Hunts Point",)),
    Area("Longwood", ntas=("Longwood",)),
    Area("Morrisania", ntas=("Morrisania",)),
    Area("Crotona Park East", ntas=("Crotona Park East",)),
    Area("Claremont", ntas=("Claremont Village-Claremont (East)",), tracts=CLAREMONT_WEST),
    Area("Mount Eden", ntas=("Mount Eden-Claremont (West)",), without=CLAREMONT_WEST),
    Area("Concourse", ntas=("Concourse-Concourse Village",)),
    Area("Highbridge", ntas=("Highbridge",)),
    # --- the west
    Area("Mount Hope", ntas=("Mount Hope",)),
    # "University Heights (South)-Morris Heights" is cut at West Burnside Avenue: the
    # campus and the blocks above it are University Heights, the slope down to the
    # Harlem River below is Morris Heights. "University Heights (North)-Fordham"
    # is cut at Jerome Avenue — west of it, over University and Sedgwick Avenues, is the
    # top of University Heights; east of it, Fordham Plaza and the blocks up to
    # Kingsbridge Road, is Fordham, which takes Fordham Heights south of the road too:
    # Fordham is the road and both sides of it.
    Area("Morris Heights",
         tracts=("53", "205.01", "205.02", "213.01", "215.01", "215.02", "217", "243", "245.01")),
    Area("University Heights",
         tracts=("245.02", "247", "249", "251", "253", "255", "257", "261", "263", "265", "269")),
    Area("Fordham", ntas=("Fordham Heights",), tracts=("399.01", "401")),
    Area("Bedford Park", ntas=("Bedford Park",)),
    Area("Norwood", ntas=("Norwood",)),
    Area("Kingsbridge Heights", ntas=("Kingsbridge Heights-Van Cortlandt Village",)),
    Area("Kingsbridge", ntas=("Kingsbridge-Marble Hill",)),
    # One NTA, "Riverdale-Spuyten Duyvil", is the whole north-west corner. Spuyten
    # Duyvil is the tip by the Harlem River, west of the Henry Hudson Parkway and south
    # of West 232nd; Fieldston is the private streets between the parkway and Van
    # Cortlandt Park, Manhattan College Parkway to West 250th; North Riverdale is
    # everything above West 254th; Riverdale is the rest.
    Area("Spuyten Duyvil", tracts=("293.01", "293.02", "301")),
    Area("Riverdale", tracts=("295", "297", "307.01", "309")),
    Area("Fieldston", tracts=("335", "351")),
    Area("North Riverdale", tracts=("319", "323", "337", "343", "345")),
    # --- the middle
    # The city's "Tremont" runs from Webster Avenue to Crotona Park; it is cut at
    # Arthur Avenue, with the Southern Boulevard side as East Tremont.
    Area("Tremont", tracts=("369.01", "369.02", "375.04", "395")),
    Area("East Tremont", tracts=("365.01", "365.02", "367", "371", "373")),
    Area("West Farms", ntas=("West Farms",)),
    Area("Belmont", ntas=("Belmont",)),
    Area("Bronxdale", tracts=BRONXDALE),
    Area("Allerton", ntas=("Allerton",), without=BRONXDALE),
    # "Pelham Parkway-Van Nest" is cut at Sagamore Street.
    Area("Pelham Parkway", tracts=("224.01", "224.03", "224.04", "228", "230")),
    Area("Van Nest", tracts=("232", "236", "238", "240")),
    Area("Morris Park", ntas=("Morris Park",)),
    Area("Pelham Gardens", ntas=("Pelham Gardens",)),
    # --- the north
    Area("Williamsbridge", ntas=("Williamsbridge-Olinville",)),
    Area("Woodlawn", tracts=WOODLAWN),
    Area("Wakefield", ntas=("Wakefield-Woodlawn",), without=WOODLAWN),
    # Edenwald is the houses and the blocks round them, Laconia Avenue to Boston Road
    # between East 222nd and Bussing Avenue; Eastchester is east of Boston Road up to
    # the Hutchinson River, Dyre Avenue included; Baychester is south of both, Boston
    # Road and Gun Hill Road down to Bay Plaza.
    Area("Edenwald", tracts=("426", "458", "460", "484.02")),
    Area("Eastchester", tracts=("456", "462.09", "484.01")),
    Area("Baychester", tracts=("356", "358", "364", "386", "462.08")),
    Area("Co-op City", ntas=("Co-op City",)),
    # --- the east
    Area("Parkchester", ntas=("Parkchester",)),
    Area("Westchester Square", ntas=("Westchester Square",)),
    Area("Unionport", tracts=UNIONPORT),
    Area("Castle Hill", ntas=("Castle Hill-Unionport",), without=UNIONPORT),
    # Soundview is both of the city's Soundviews less the point: the Bronx River
    # Houses and Bruckner blocks in the north, Soundview Avenue in the south.
    Area("Soundview",
         ntas=("Soundview-Bruckner-Bronx River", "Soundview-Clason Point"),
         without=CLASON_POINT),
    Area("Clason Point", tracts=CLASON_POINT),
    Area("Schuylerville", tracts=SCHUYLERVILLE),
    Area("Throgs Neck", ntas=("Throgs Neck-Schuylerville",), without=SCHUYLERVILLE),
    # Pelham Bay is the blocks by the park's gate, Country Club the peninsula east of
    # the Bruckner, City Island the island.
    Area("Pelham Bay", tracts=("266.01", "266.02", "300")),
    Area("Country Club", tracts=("274.01", "274.02")),
    Area("City Island", tracts=("516.01",)),
)


# What Staten Island is divided into.
#
# The city draws only 16 lived-in neighborhoods on Staten Island, and all but one of
# them are compounds: "Annadale-Huguenot-Prince's Bay-Woodrow" is four places with four
# railway stations, "New Springville-Willowbrook-Bulls Head-Travis" four that do not
# even touch in the middle. So this borough is nearly all tract-level splitting, the
# other way round from Brooklyn, where the work was putting halves back together.
#
# Staten Island's tracts are big and its borders are vaguer than Brooklyn's — a hill,
# a railway station, a stretch of Amboy Road — so the cuts follow the roads people do
# draw the line on where a tract edge runs along one (Woodrow Road between Rossville
# and Woodrow, Armstrong Avenue between Eltingville and Great Kills, Arden Avenue
# between Annadale and Huguenot, Jersey Street between St. George and New Brighton,
# Sand Lane between Arrochar and South Beach), and where none does the name a tract
# is folded into is the neighbour whose centre it is nearest. The places that could
# not be cut out at tract size are folded rather than drawn wrong: Shore Acres into
# Rosebank, Concord and Fox Hills into Park Hill, Randall Manor into West Brighton,
# Sunnyside into Castleton Corners, Meiers Corners into Westerleigh, Manor Heights
# and Sea View into Willowbrook, Emerson Hill into Todt Hill, Heartland Village into
# New Springville, Egbertville into Lighthouse Hill, New Dorp Beach into New Dorp,
# Bay Terrace into Great Kills, Pleasant Plains and Richmond Valley into Prince's Bay
# and Charleston. The parks the city files as neighborhoods — Freshkills, Great Kills
# Park, Miller Field, Fort Wadsworth, Snug Harbor — are not lived-in and stay out.
STATEN_ISLAND_AREAS = (
    # --- the north shore, east
    # St. George is the ferry end, east of Jersey Street and north of Victory
    # Boulevard; New Brighton is west of Jersey Street along the Kill, down to Forest
    # Avenue. Tompkinsville, Stapleton and Clifton follow Bay Street south one tract
    # each; Park Hill is the hill behind them, Fox Hills and Concord included.
    Area("St. George", tracts=("3", "9", "11")),
    Area("New Brighton", tracts=("7", "75", "77", "81")),
    Area("Tompkinsville", tracts=("17",)),
    Area("Stapleton", tracts=("21",)),
    Area("Clifton", tracts=("27", "40.01")),
    Area("Park Hill", tracts=("29", "40.02", "40.03", "40.04")),
    # Rosebank runs down Bay Street to Fort Wadsworth, the Shore Acres waterfront
    # included; 20.01 straddles the bridge approach and lies mostly north of it.
    Area("Rosebank", tracts=("6", "8", "20.01", "36")),
    # Grymes Hill is the college on the hill between Clove Road and Howard Avenue;
    # Silver Lake is the reservoir and the blocks round it up to Forest Avenue,
    # Clove Lakes Park on its western tract.
    Area("Grymes Hill", tracts=("39", "47")),
    Area("Silver Lake", tracts=("33", "59.01", "59.02")),
    # West Brighton is Bard Avenue to Port Richmond, the Kill to Forest Avenue, with
    # Randall Manor and Livingston on its eastern tracts. Castleton Corners is the
    # far side of Clove Road down to the expressway, Sunnyside included.
    Area("West Brighton", tracts=("67", "97.01", "105", "125", "133.01")),
    Area("Castleton Corners", tracts=("121", "147", "169.01")),
    # --- the north shore, west
    Area("Port Richmond", ntas=("Port Richmond",)),
    # Arlington is the one big tract at the western end, Howland Hook included;
    # Mariners Harbor is everything between it and Port Richmond north of Forest
    # Avenue; Graniteville is south of Forest Avenue from the expressway to
    # Willowbrook Road.
    Area("Arlington", tracts=("323",)),
    Area("Mariners Harbor", tracts=("223", "231", "239", "319.01", "319.02")),
    Area("Graniteville", tracts=("251", "303.01", "303.02")),
    # Westerleigh is the grid between Willowbrook Road and Manor Road, north of the
    # expressway, Meiers Corners on its Victory Boulevard edge.
    Area("Westerleigh", tracts=("151", "187.01", "189.01", "197", "201")),
    # --- mid-island
    # Bulls Head is the Victory Boulevard–Richmond Avenue crossing and its tracts to
    # the west and south; Travis is the west shore tract beyond it. Willowbrook is the
    # park and the college, the expressway to Rockland Avenue and Richmond Avenue to
    # Manor Road, with Manor Heights and Sea View on its eastern side. New Springville
    # is the mall and Richmond Avenue south of it, Heartland Village included.
    Area("Bulls Head", tracts=("291.04", "291.05", "291.06")),
    Area("Travis", tracts=("291.02",)),
    Area("Willowbrook", tracts=("173", "187.03", "187.04", "189.02", "273.01", "273.02")),
    Area("New Springville", tracts=("277.02", "277.04", "277.05", "277.06", "279")),
    # Todt Hill is the hill, Emerson Hill on its Richmond Road slope; Lighthouse Hill
    # is the tract below it, which is the Greenbelt and Egbertville too.
    Area("Todt Hill", tracts=("177.01", "177.02")),
    Area("Lighthouse Hill", tracts=("181",)),
    # --- the east shore
    # Grasmere is the lakes and the station, Old Town Road its southern edge.
    # Arrochar is under the bridge, north of Sand Lane; South Beach is the boardwalk
    # from Sand Lane to Seaview Avenue, Hylan Boulevard to the water.
    Area("Grasmere", tracts=("50", "96.01")),
    Area("Arrochar", tracts=("20.02", "64")),
    Area("South Beach", tracts=("70.01", "70.02", "74")),
    # Dongan Hills is both sides of the station between Richmond Road and Hylan;
    # Midland Beach is seaward of Hylan from Seaview Avenue to New Dorp Lane; New
    # Dorp is the lane and the plaza, New Dorp Beach south of Miller Field included.
    Area("Dongan Hills", tracts=("96.02", "114.01")),
    Area("Midland Beach", tracts=("112.01", "112.03")),
    Area("New Dorp", tracts=("114.02", "122", "128.04", "134")),
    # Oakwood is Guyon Avenue down to the beach; Richmondtown is the old county seat
    # at the top of Richmond Road.
    Area("Oakwood", tracts=("128.05", "128.06", "132.01", "132.04")),
    Area("Richmondtown", tracts=("138",)),
    # --- the south shore
    # Great Kills and Eltingville are cut at Armstrong Avenue, halfway between their
    # stations; Great Kills has Bay Terrace on its eastern side. Eltingville and
    # Annadale are cut at the tract edge nearest Arbutus Avenue, Annadale and Huguenot
    # at the one nearest Arden Avenue, halfway between those two stations, and
    # Huguenot and Woodrow at the one between Huguenot Avenue and Bloomingdale Road.
    Area("Great Kills", tracts=("132.03", "146.05", "146.06", "146.08", "156.03")),
    Area("Eltingville", tracts=("146.04", "146.07", "156.01", "156.02", "170.11", "170.12")),
    Area("Annadale", tracts=("170.05", "176")),
    Area("Huguenot", tracts=("170.09", "208.04")),
    Area("Arden Heights", tracts=("170.07", "170.13", "170.14", "170.15", "170.16")),
    # Rossville is north of Woodrow Road, Woodrow south of it down to the parkway.
    Area("Rossville", tracts=("208.05", "208.06")),
    Area("Woodrow", tracts=("208.03", "226.01")),
    # Prince's Bay is one tract with Pleasant Plains on its western edge; Charleston
    # is one tract with Richmond Valley on its southern; Tottenville is the end of
    # the island, Page Avenue and everything beyond it.
    Area("Prince's Bay", tracts=("198",)),
    Area("Charleston", tracts=("226.02",)),
    Area("Tottenville", tracts=("244.01", "244.02", "248")),
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

QUEENS = Borough(
    name="Queens",
    code="4",
    park_letter="Q",
    file="queens.json",
    areas=QUEENS_AREAS,
    avenue_count=45,
    major_count=400,
    avenues_in_words=False,
    # Queens' share of Jamaica Bay is a dozen marsh islands, and the city has drawn
    # the smallest of them with their creeks folded over themselves at its own
    # resolution, which no thinning can make sound. They are specks at the scale the
    # borough is drawn — none is two hundred metres across — so the floor is lifted
    # just enough to leave them out; the islands anybody could point to stay.
    min_ring_area=1.7e-5,
)

BRONX = Borough(
    name="Bronx",
    code="2",
    park_letter="X",
    file="bronx.json",
    areas=BRONX_AREAS,
    # The Bronx has about Brooklyn's streets on two-thirds of the ground, and much of
    # what is longest is parkway — the Bronx River, Hutchinson River, Pelham, Mosholu
    # and Henry Hudson Parkways, the Deegan, the Cross Bronx and the Bruckner — which
    # the roadway type and the greens keep out of the avenue band. Thirty-five named
    # at the widest zoom puts the Grand Concourse, the Boulevards and the long
    # avenues on the paper without their names fighting.
    avenue_count=35,
    major_count=300,
    # Its numbered avenues are in figures, as its street signs write them: 3rd Avenue.
    avenues_in_words=False,
)

STATEN_ISLAND = Borough(
    name="Staten Island",
    code="5",
    park_letter="R",
    file="staten-island.json",
    areas=STATEN_ISLAND_AREAS,
    # Staten Island's streets wind, and few of them run far: twenty in, the length
    # order is already down to the railroad service roads and the loop round the
    # college campus, which nobody gives directions by. So fewer avenues than
    # Manhattan, not more, though the borough has twice Brooklyn's street names —
    # most of them a court in a subdivision — and the second band is cut to match,
    # since the island is drawn small on the glass, being the tallest of the five
    # as well as the widest.
    avenue_count=20,
    major_count=250,
    avenues_in_words=False,
)

BOROUGHS = {
    "manhattan": MANHATTAN,
    "brooklyn": BROOKLYN,
    "queens": QUEENS,
    "bronx": BRONX,
    "staten-island": STATEN_ISLAND,
}


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
#   - an avenue is not called an expressway. The city files an expressway's frontage
#     roads under the expressway's own name and as ordinary streets, and where there
#     are more frontage rows than highway rows — the Throgs Neck, the Whitestone —
#     the first rule lets the whole thing through. The word on the sign is the tell.
#
# None of the rules is a list of street names, so all three survive the city
# re-surveying.

# What a road is called when it is a highway whatever the city's roadway type says.
HIGHWAY_WORDS = ("Expressway", "Freeway", "Thruway")

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
    "CRES": "Crescent",
    "TRL": "Trail",
    "VLG": "Village",
    "PT": "Point",
    "UNIV": "University",
    "CONC": "Concourse",  # 323 rows of "GRAND CONC" beside the rows of "GRAND CONCOURSE"
    "TRWY": "Thruway",
    "MEM": "Memorial",
    "MSGR": "Msgr.",
    "REV": "Rev.",
    "BX": "Bronx",
    "CP": "Camp",  # Pennyfield Camp, a lane in Edgewater Park
    "VETS": "Veterans",
    "GRN": "Green",
    "VIA": "Viaduct",
    "GLN": "Glen",
    "XING": "Crossing",
    "TPKE": "Turnpike",
    "FWY": "Freeway",
    "LK": "Lake",
    "CLOS": "Close",
    "GRDN": "Garden",
    "RDG": "Ridge",
    "CRSE": "Course",
    "VET": "Veterans",
}

# Names that capitalise in the middle, which `str.capitalize` cannot know.
PROPER = {
    "DEKALB": "DeKalb", "METROTECH": "MetroTech",
    "OP": "op",  # "CO-OP CITY BLVD" is spelled a side of the hyphen at a time: Co-op
    "RFK": "RFK",
    "USS": "USS",
    "JFK": "JFK",
    "LGA": "LGA",
    "LIRR": "LIRR",
    "NYCTA": "NYCTA",
    "GCP": "GCP",
    "FMCP": "FMCP",
    "VWE": "VWE",
}

# Rows whose name marks them as a ramp, a direction of travel or a piece of highway
# plumbing. These are named like streets in the data and are not streets.
PLUMBING = re.compile(
    r"\b(EN|EX|NB|SB|EB|WB|OPAS|RAMP|RP|SR|SVC|VIADUCT APPR"
    # Queens adds the exits the city writes out in full — "WHITESTONE EXPY EXIT 13A",
    # "GRAND CENTRAL PARKWAY ET 14" — an underpass, and the roads inside its two
    # airports, which are named like streets ("JFK TERMINAL 4 ARRIVALS RD") and are
    # kerbs outside a terminal. The speller would write that one as "Terminal 4th".
    r"|EXIT|ET|UNP|TERMINAL|TERMINALS|ARRIVALS|DEPARTURES)\b"
)

# The city records a segment it has no name for as "UNNAMED STREET" — or "UNNAMED
# ST", depending on who typed it. That is a row with a blank in it, not a street
# called Unnamed, and ninety-one rows of Brooklyn are called nothing but "CONNECTOR".
NAMELESS = {
    "DRIVEWAY", "STREET", "CONNECTOR",
    "CONNECTOR RD TO WESTCHESTER AVE",
    "CONNECTOR ROAD MACOMBS DAM BR MN",
    "CONNECTOR ROAD TO BRUCKNER EXPWY",
    "CONNECTOR ROAD TO MDE NORTHBOUND",
    "CONNECTOR TO BRUCKNER BL MAIN RD",
    "MDE SOUTHBOUND EXIT 13",
    "RIKERS IS INTERIOR FACILITY RD",
    "RIKERS ISLAND ACCESS RD",
    "GEORGE R VIERNO CENTER ACCESS RD",
    "ROSE M SINGER CENTER ACCESS RD",
}


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
    if word == "DR" and first:
        # And leading DR is Doctor: Dr. M. L. King Jr. Expressway. A drive is never
        # the first word of its own name.
        return "Dr."
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
    lone = lambda part: len(part) == 1 and part.isalpha()
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
        if lone(word) and index > 0 and (lone(follows) or lone(parts[index - 1])):
            # A run of single letters is a set of initials: "DR M L KING JR EXPY" is
            # Dr. M. L. King Jr. One letter on its own is not — Malcolm X Boulevard,
            # Avenue C Loop, Franklin D Roosevelt Drive are written as they are.
            spelled.append(word + ".")
            index += 1
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
    # An edge of no length — two of the city's points under a metre apart, which
    # round to the same place — is skipped, and the edges either side of it are
    # neighbours: they share a corner, as the file will write them, and do not
    # cross. Queens' tracts trace the Grand Central Parkway that finely.
    real = [i for i in range(count) if ring[i] != ring[(i + 1) % count]]
    following = {i: real[(k + 1) % len(real)] for k, i in enumerate(real)}
    extents = []
    for i in real:
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
            if following[j] == i or following[i] == j:
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
    # A corner is the same corner within a centimetre. The city's topology is exact
    # to the metre and then some, but not to the millimetre: one corner shared by two
    # tracts of Mariners Harbor is off by eight nanodegrees between them, which read
    # exactly is two corners, and two corners is a spike out and back that no
    # thinning can unfold. So corners are matched at seven places and kept at nine,
    # as the first tract to reach one wrote it.
    corner: dict = {}
    for ring in polygons:
        points = [
            corner.setdefault((round(x, 7), round(y, 7)), (round(x, 9), round(y, 9)))
            for x, y in ring
        ]
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
        if ring_area(ring) < borough.min_ring_area:
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

    # --- and the cemeteries, which the parks table does not have
    cemeteries = 0
    for row in fetch(
        NEIGHBORHOODS,
        where=f"boroname='{borough.name}' AND ntatype='{CEMETERY_TYPE}'",
        limit=100,
    ):
        geometry = row.get("geometry")
        if not geometry:
            continue
        name = (row["properties"].get("ntaname") or "").strip()
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        for polygon in polygons:
            ring = thin_ring([(x, y) for x, y, *_ in polygon[0]], PARK_TOLERANCE)
            if len(ring) >= 4 and ring_area(ring) >= MIN_PARK_AREA:
                parks.append({"name": name, "ring": ring})
                cemeteries += 1
    print(f"    {cemeteries} cemetery greens")

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
            and not street["name"].endswith(HIGHWAY_WORDS)
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
        "source": "NYC Open Data — Centerline (inkn-q76z), Borough Boundaries (gthc-hcne), Parks Properties (enfh-gkve), 2020 NTAs (9nt8-h7nd)",
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
