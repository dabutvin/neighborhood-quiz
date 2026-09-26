# NYC Neighborhoods: Map Quiz

An iOS app about knowing where you are in New York. It opens on Manhattan — drawn by
hand, in ink, on paper — with every avenue and every numbered cross street named, and
not one neighbourhood.

That omission is the whole idea. Naming the neighbourhoods is the quiz, and a map that
has already told you where SoHo is has given the game away. The other four boroughs are
drawn the same way, and are what the money buys.

## The game

The first time, the app opens straight into a round: a new player has nothing to read on
a menu, and the map with a question over it is the whole pitch. Once there is money it
opens on the menu instead — what you have to spend, how far off the next borough is,
which borough the next round is about, and one button to start. A round can be left
part-way from the same menu — though a round pays when it is played out, so walking away
from one banks nothing.

The first round is also the tutorial. Rather than pages of rules in front of the game,
four tips come up over it, each at the moment it is about: tap where you think the place
is, and the streets are the clues; the outline is the neighborhood picked, and Answer
locks it in; what each of the three tries pays, said right after the first one, with a
Got it to put it away; and, on the card at the end of the round, that the money is kept
and what it buys. Every tip can be skipped, "How to play" in Settings brings
them back, and a player who was already playing before there were tips is not given them.
"Delete all saved data" puts the app back as it was on a fresh install, tips included.

A round is ten neighbourhoods. You are given a name and three tries to put your finger on
it: five dollars if you know it straight away, three on the second try, one on the third,
and nothing if three tries are not enough — at which point the round shows you where it
was and moves on. Fifty dollars is a perfect round.

The money is kept. It banks up across every round you ever play, and it buys the rest of
the city, a borough at a time:

| | |
|---|---|
| Manhattan | free — where everyone starts |
| the first borough you buy | $200 |
| the second | $600 |
| the third | $1,200 |
| the fourth | $2,000 |

The order is yours. The price is about how far you have got, not which borough it is:
the second borough costs $600 whether it is Queens or Brooklyn, and taking the city in
an odd order costs exactly what taking it in the obvious one does. A perfect round is
fifty dollars, so the first borough is four good rounds away and the fourth is a long
winter.

All of that lives in one preference on the phone and nowhere else — there is no account
and no server of the app's own — and Settings will delete it, which is the only destructive
thing the app can do. The one thing that does leave the phone is an anonymous count of how
the rounds go, described under [What it counts](#what-it-counts), with a switch in Settings
that stops it.

Two numbers are tracked, not one. The balance is what you can spend and it goes down when
you spend it; the career total is every dollar ever earned and it never goes down, because
buying a borough should not make it look like you played less than you did.

A best round is kept too, one for each thing a round can be about: each borough on its
own, and the whole city. The menu shows the best for whichever is picked, the Boroughs
screen lists each borough's under its name, and the end of a round says "New best!"
when one falls. A first round of a choice sets its best quietly; there was nothing to
beat.

**All five boroughs are drawn.** Buying one opens it; the menu then offers each you
have, and one more thing — "Anywhere" — which draws the ten from every borough you have
open and draws them all on one map, laid out as they sit and north-up, so getting from
SoHo to Astoria is a push across the river; the card says which borough each question is
in, and a place given away off the edge of the screen is brought into view. Whichever you pick is written down with the money so the app opens where you left
it. The game still will not take money for a borough it cannot open — nothing is in that
state today, but the guard stays for the next map that is not drawn yet, whichever that
turns out to be — and when the balance is there and the map is not, it says so and there
is no button to press.

The end of a round can be shared — the score, and where it was scored — and Settings has
a row to rate the app and one to pass it on. Both go through the phone's own sheets;
nothing is sent by the app itself.

## The map

The map is not a tile server and not an `MKMapView`, but nor is it invented. It is the
City of New York's own street centreline file, drawn by hand.

`Tools/fetch_map_data.py` takes a borough, pulls three datasets from
[NYC Open Data](https://data.cityofnewyork.us) and writes one file per borough —
`NeighborhoodQuiz/Resources/manhattan.json`, `brooklyn.json`, `queens.json`,
`bronx.json`, `staten-island.json` — which are committed:

| Dataset | What it gives |
|---|---|
| Centerline (`inkn-q76z`) | every street segment in the borough, with its name |
| Borough Boundaries (`gthc-hcne`) | the real shoreline, piers and all |
| Parks Properties (`enfh-gkve`) | the greens, Central Park chief among Manhattan's |
| 2020 NTAs (`9nt8-h7nd`) | the neighbourhoods, and the cemeteries — Green-Wood, Woodlawn, Calvary — which are green on the map but not in the parks table |

It runs on demand, never at build time and never at runtime. CI does not touch the
network and neither does a shipped build.

What comes back is not drawable as it stands, and most of the tool is the difference:

- **The city stores a street as the pieces between its corners.** Broadway is 389 rows.
  Those are sewn back into whole streets on shared endpoints — 12,025 segments become
  1,528 runs — so that Broadway is one line with one name on it rather than 389.
- **Names are stored clipped and shouted**: `1 AVE`, `E  HOUSTON ST`. They are spelled
  out the way a person writes them, which includes knowing that a numbered *avenue* is
  written in words (Fifth Avenue) and a numbered *street* in figures (42nd Street).
- **Ramps and service roads are named like streets and are not streets.** `FDR DRIVE NB
  EN E HOUSTON ST` is plumbing; 229 rows like it are dropped.
- **There is no "avenue" in the data** — no road class at all, only a roadway type that
  tells a street from a bridge. So rank is taken from the one thing that does separate
  an avenue: length. The streets are sorted by how far they run and cut into three
  bands, which means the map re-ranks itself if the city re-surveys a block and nothing
  anywhere holds a hand-written list of which streets matter.
- **37,252 points is more than a shaky pen can show**, so the geometry is thinned to
  5,800. The shoreline is thinned harder still — it is one path that is always on screen
  and so can never be culled — but only as hard as each island's own shape allows: the
  tool backs the tolerance off until the ring stops folding over itself, because a
  tolerance that smooths a pier off Manhattan pinches Wards Island into a bow tie.

The result, for Manhattan, is 216 KB, 967 streets and four islands. Everything below
Houston Street is there, because it is there in the data; Washington Heights is laid out
the way it was actually laid out rather than the way the 1811 grid would have continued.

The one thing left of that grid is its bearing. Manhattan runs about twenty-nine degrees
east of north, and turning the projected plane back by that much is what stands the
avenues upright and lays the cross streets flat — the difference between a drawing and a
satellite photograph.

### The other boroughs

The same tool, the same treatment, a different borough on the command line — and one
thing done differently for all four, which is that they are drawn north-up. Brooklyn is
not for want of a grid: it has half a dozen of them, at different angles — Williamsburg's,
Bushwick's, Park Slope's, Bay Ridge's, the Flatbush avenues — and no one of them is the
borough. There is no turn that stands Brooklyn's streets up the way the twenty-nine
degrees stands Manhattan's; whichever grid you chose, the others would lean. Queens is the
same problem twice over, with a dozen grids that never agreed on a number. The Bronx does
have Manhattan's grid — the numbered streets carry on over the Harlem River — but they
bend and give out a mile or two in, and a turn that suited Mott Haven would put Riverdale
and Throgs Neck on a slant for nothing. Staten Island has no grid to speak of, and it
runs north-east to south-west as it is. North-up is how a map of any of them is drawn,
so that is how these are.

Their numbered avenues and streets are in figures, because that is how the outer
boroughs write them: 4th Avenue and 18th Avenue in Brooklyn, 82nd Street and 37th
Avenue in Queens, where Manhattan has Fifth — a borough whose avenues run to 28th cannot
switch from words to figures at Twelfth without it showing. And their neighbourhoods are
the same census-tract treatment Manhattan's had — the city's compounds taken apart and
the split ones put back together — which comes to 52 places in Brooklyn, 68 in Queens,
51 in the Bronx and 40 on Staten Island: the places a player would actually call
something, and no "Elmhurst-Corona" among them.

### Why it wobbles

The style is lifted from [parkslopemap](https://github.com/dabutvin/parkslopemap): warm
paper, soft ink, sage green, and a pen that is not quite steady. `Pen` is a Swift port of
the arithmetic [rough.js](https://roughjs.com) uses — every straight run becomes a
shallow bezier that leaves its start a little off the mark, bends somewhere past a third
of the way along, arrives a little off the other end, and is then drawn a second time
slightly differently, because a person going over a line twice never quite retraces it.

The wobble is seeded, which matters more than it sounds: an unseeded one would re-roll
itself on every redraw and the island would shimmer under your finger. Each road gets its
own seed from its place in the list, so it wobbles the same way for ever.

It is also a good deal steadier than it started. The first settings were chosen against
269 generated streets, where a wandering line was most of what said the drawing was
drawn; against fifteen hundred real ones the same numbers read as a shake rather than a
style, and Broadway wavered where Broadway does not. At a third of that stray the
doubled stroke and the soft corners carry the hand, which is where it shows anyway.

Manhattan is an island, so the palette is used the other way up from the Park Slope map:
there, paper is the background and the neighbourhood is a lighter patch on it; here the
background is the water and the paper is the land, which is what makes the shape read
from across the room. There is a night palette too — the same drawing after dark.

### How it moves

The expensive part — two hundred and some roads, each cut against the shoreline and then
redrawn twice with a wobbling pen — happens once, when the view first gets its size, and
never again while the map is being pushed about. What moves is the transform, not the
drawing. Pen weights are divided by the zoom so a line stays a line rather than swelling
into a band, and the street names are drawn afterwards in screen coordinates so they keep
their size: pulling the map in shows *more* names rather than bigger ones. They arrive in
waves — the four avenues anybody could place blind, then the rest of the numbered ones,
then the long names, then every side street.

```
NeighborhoodQuiz/
├── App/
│   ├── NeighborhoodQuizApp.swift   # App entry point, and the launch arguments CI shoots with
│   ├── AppVersion.swift            # What build this is, read from the bundle rather than written down
│   ├── AppStore.swift              # The listing's name and links, and the words the share sheet gets
│   ├── Analytics.swift             # Every signal the game sends, and the one switch that stops them
│   └── TelemetryDeckSink.swift     # Puts a batch of signals on the wire, in a dozen lines of URLSession
├── Game/
│   ├── Borough.swift               # The five, what the next one costs, which are drawn, and how each is turned
│   ├── Place.swift                 # A neighbourhood anywhere in the city: which borough, which shape
│   ├── Wallet.swift                # The money, the boroughs bought, and what the next round is about
│   ├── Bank.swift                  # The one wallet the app plays with, written down after every change
│   ├── QuizRound.swift             # Ten places, three tries each, and what the tries are worth
│   └── Tutorial.swift              # The four tips over a first round: which is up when, and who gets them
├── Map/
│   ├── Geography.swift             # A coordinate, and a Mercator turned so the avenues stand up
│   ├── BoroughMap.swift            # Reads a borough's .json: the land, the greens, the streets
│   ├── Polyline.swift              # Measuring along a line: length, middle, which way a name goes
│   ├── Pen.swift                   # The unsteady hand: seeded wobble, after rough.js
│   ├── DrawnMap.swift              # Builds the whole drawing of one borough once for a given size
│   ├── DrawnNeighborhood.swift     # A neighbourhood as drawn: the shape, the line, what a tap tests
│   ├── MapCamera.swift             # How far in, how far pushed about, and what is on the glass
│   └── MapPalette.swift            # Paper, ink, sage — day and night — and the hand it is lettered in
├── Views/
│   ├── QuizView.swift              # The game: the question, the map, the menu, the end of a round
│   ├── TipCard.swift               # One tutorial tip, on paper
│   ├── MapBoard.swift              # The map you can push about, and what a tap on it means
│   ├── BoroughMapView.swift        # One Canvas: the borough under the transform, the names over it
│   ├── BoroughsView.swift          # The city: what you have, and what the next borough costs
│   ├── HomeView.swift              # The map on its own, for the screenshot runs
│   ├── SettingsView.swift          # The version, the tips again, rate and share, the privacy switch, and the one destructive thing
│   └── PaperGrain.swift            # The tooth of the paper, and the vignette
└── Resources/
    ├── manhattan.json              # The city's Manhattan, written by Tools/fetch_map_data.py
    ├── brooklyn.json               # And its Brooklyn, from the same tool
    ├── queens.json                 # Queens, the Bronx and Staten Island likewise —
    ├── bronx.json                  #   one file per borough, and the whole city now
    ├── staten-island.json          #   (hyphenated, so no resource has a space in its name)
    ├── Assets.xcassets             # App icon (drawn from the same data) and accent colour
    └── PrivacyInfo.xcprivacy       # What is counted, in Apple's words: usage, anonymous, never for tracking
```

## What it counts

A game that is tuned by playing it wants to know how it is played, and the only honest way
to know which neighbourhoods are too hard is to count how often they are found. So the app
counts — anonymously, in the open, and with a switch to stop it.

**What goes out.** Every signal is written out in one place, `Analytics.swift`, so the
list can be read end to end. A launch. A round started, and whether it was one borough's
or the whole city's. Each question settled: which neighbourhood, and on which try it was
found — or that it was never found, which is the signal the whole thing is for. A round
finished, with the score and how it was made; a round left part-way, and how far it got.
A borough bought, which rung of the ladder it was and how many rounds it took. Each
tutorial tip as it comes up, and whether the tips were skipped, finished or asked for
again — which makes the four of them a funnel. Which
borough the next round was pointed at, the ladder and settings being opened, the rating
sheet being asked for, and the privacy switch itself being moved.

**What does not go out.** No name, no account, no email, no advertising identifier, no
vendor identifier, no location, and nothing a player typed — there is no way to type
anything into this app, and there is nowhere in the shape of a signal to put it if there
were; `AnalyticsTests` holds every value to a borough, a neighbourhood's name out of the
data, or a number. A batch is stamped with two random numbers: one minted on this phone
the first time the app opens and SHA256'd before it leaves, and one minted fresh every
launch. Because nothing is used for tracking, the app never asks for a tracking
permission. `PrivacyInfo.xcprivacy` says all of the above in Apple's own words.

**The switch.** On as the app comes, and off in one tap under *Anonymous usage* in
Settings, which says in plain words what is counted. Off means nothing is recorded, held
or sent — the signal is dropped at the door rather than queued quietly. Turning it off
sends one last signal saying so, because a chart that cannot tell *switched off* from
*stopped playing* reads every opt-out as a player lost. *Delete all saved data* throws the
install's number away, so the player is somebody nobody has counted before, and
deliberately leaves the switch alone: a player who opted out and then deleted their
wallet has not asked to be counted again.

**Where it goes.** [TelemetryDeck](https://telemetrydeck.com), over its ingest API — one
POST of one JSON array, in about a dozen lines of `URLSession` in `TelemetryDeckSink`,
rather than an SDK that would be the only third-party code in the repo. Signals gather
into batches of twenty and go when a batch fills or when the player puts the app down.
Nothing retries and nothing is written to disk: a batch that cannot get out on a train is
dropped, which costs a few rows on a chart and nothing at all to the player. Debug and
simulator builds are marked as test signals, so they land on TelemetryDeck's test screen
rather than beside real players.

**A camera is not a player.** The screenshot runs open straight onto a screen with one of
the app's own launch arguments, and a fortnight of CI on the charts would read as somebody
who knows exactly where SoHo is, ten times a day. Which arguments mean *camera* is not a
list kept by hand: `Screen.isPhotographing` asks the same reading of the arguments that
opens the screens whether it opened on anything but the plain game, so an argument cannot
be added without the counting already knowing to ignore it.

**Turning it on.** Set the `TELEMETRYDECK_APP_ID` secret (see
[Required Secrets](#required-secrets)). Without it the plist key is empty,
`TelemetryDeckSink` hands back nothing, and the app counts nothing and sends nowhere —
which is what a fork, a checkout and every CI run get. It is an ordinary build setting —
`TELEMETRYDECK_APP_ID` in `project.yml`, read into the plist as `TelemetryDeckAppID` — so
a local build that wants to send somewhere overrides it on the command line:

```bash
xcodebuild build -project NeighborhoodQuiz.xcodeproj -scheme NeighborhoodQuiz TELEMETRYDECK_APP_ID=your-app-id
```

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift 6.2 |
| UI | SwiftUI |
| Min iOS | 17.0 |
| Project | XcodeGen (no `.xcodeproj` in repo) |
| CI/CD | GitHub Actions |
| Distribution | TestFlight + App Store |

## Development

### Prerequisites

- Xcode 26+ (for local dev) or just use GitHub Actions — no laptop needed, including for
  [signing setup](#signing)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Build locally

```bash
xcodegen generate
open NeighborhoodQuiz.xcodeproj
```

`NeighborhoodQuiz.xcodeproj` and `NeighborhoodQuiz/Resources/Info.plist` are both
generated from `project.yml` and are gitignored — edit `project.yml`, never the generated
project.

### Refreshing the map

```bash
python3 Tools/fetch_map_data.py             # re-reads NYC Open Data, all five boroughs
python3 Tools/fetch_map_data.py manhattan   # or one at a time
python3 Tools/fetch_map_data.py brooklyn
python3 Tools/fetch_map_data.py queens
python3 Tools/fetch_map_data.py bronx
python3 Tools/fetch_map_data.py staten-island
python3 Tools/generate_app_icon.py          # the icon is the whole city, so it follows
```

Commit whatever changes. There is no list of streets to maintain: a street the city adds
appears, one it renames is renamed, and the avenue/major/side ranking re-derives itself
from the lengths.

`ManhattanMapDataTests` is the check on a re-fetch — that the island is still an island
and has not folded over itself, that every street is named exactly once, that the
speller did not meet an abbreviation it does not know, that ramps stayed out, and that
the streets below Houston are still there. There is one of these per borough —
`BrooklynMapDataTests`, `QueensMapDataTests`, `BronxMapDataTests`,
`StatenIslandMapDataTests` — each the same checks with that borough's own particulars:
that the Belt Parkway, the Grand Central, the Major Deegan and the Staten Island
Expressway did not rank as avenues, that Prospect Park, Flushing Meadows, Van Cortlandt
and the Greenbelt are among the greens, that the streets anybody would look for first
are there, and that the neighbourhoods came out as places rather than as the city's
hyphenated compounds.

### App icon

The icon is the map, not a picture of a map: it reads the very same five files the app
reads, so a re-fetch corrects the tile too and the two cannot drift apart. It is all five
boroughs, north-up — the shape everybody knows the city by, which very nearly fills a
square without being turned — with the big greens on it and no streets at all: at sixty
points across, five boroughs of roads are not lines but a smudge.

Over the city, "NYC", lettered in ink by the same unsteady hand that draws the streets.
There is no font in the icon script and no dependency to bring one in, so the letters are
strokes — three for the N, three for the Y, an arc for the C — each shaken a little the
way the map's pen shakes, over a coat of paper that keeps the word readable where it
crosses the water. (Not "I ♥ NY": that is New York State's registered mark, and App
Review would be right to ask.)

No Pillow, no cairo, nothing to install — it rasterises by scanline at four times the
final size, averages back down, and writes the PNGs by hand. Commit the regenerated
PNGs; the build reads them, not the script.

## How changes ship

1. Open a pull request. **CI** builds it and runs the tests; **PR Screenshots** shoots the
   home screen light and dark, on a phone and a tablet, and posts them to the pull request.
2. Merge to `main`. **TestFlight** builds, signs and uploads it.
3. Tag `vX.Y.Z`. **App Store Release** builds, signs, uploads to App Store Connect and cuts
   a GitHub release.

**App Store Assets** is hand-cranked from the Actions tab: it shoots the screens on the
exact simulators App Review asks for — iPhone 6.9 inch and iPad 13 inch — and frames each
with a line of copy.

## Required Secrets

Set these in GitHub repo settings → Secrets and variables → Actions.

| Secret | Purpose | How to get it |
|---|---|---|
| `TEAM_ID` | Apple Developer Team ID | developer.apple.com → Membership |
| `APP_STORE_CONNECT_API_KEY_ID` | API key ID, for uploading builds | App Store Connect → Users and Access → Integrations → Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID | Same page as above |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | API key (`.p8` file contents), **raw text** | Paste the full text including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` |
| `APPLE_DISTRIBUTION_CERT_P12` | Optional. Distribution certificate **and its private key**, base64 | [One stored certificate](#one-stored-certificate) |
| `APPLE_DISTRIBUTION_CERT_PASSWORD` | Optional. Password protecting that `.p12` | Same |
| `APPLE_PROVISIONING_PROFILE` | Optional. App Store profile for `com.nycneighborhoodsquiz.app`, base64 | Same |
| `TELEMETRYDECK_APP_ID` | Optional. Where usage counting is sent | telemetrydeck.com → your app → App ID. Leave it unset and the app counts nothing |

CI and the PR screenshots need none of them — a fork builds, tests and photographs the app
with no secrets at all. Only TestFlight and the release need signing, and only they carry
the counting's app id.

The App Store Connect app record must exist with bundle ID `com.nycneighborhoodsquiz.app` (see
`project.yml`) before the first TestFlight upload.

## Signing

A distribution certificate is only usable together with the private key it was created
from, and Apple caps each account at a couple of certificates — so a build cannot just ask
for a fresh one each time. Apple's instructions have you make the key in Keychain Access on
a Mac, but nothing requires that: the key can be generated anywhere, the signing request
submitted over the App Store Connect API, and the `.p12` assembled with openssl.
`Tools/bootstrap_signing.py` does that, so none of what follows needs a Mac.

### Per-build certificates

This is what happens by default, with no setup beyond the App Store Connect API key. Each
build creates its own certificate and profile, signs, uploads, and a later build retires
them, so the account holds one certificate at rest per prefix and never approaches the
limit.

The sweep runs at the *start* of a build rather than the end of the previous one. That keeps
revocation well away from App Store Connect still processing an upload, and it collects
anything a cancelled run left behind.

The two workflows mint under different prefixes, and each sweeps only its own. TestFlight
builds sign as `NYC Neighborhoods CI <run id>` and retire each other. A release signs as
`NYC Neighborhoods Release <run id>`, and its certificate is retired only by the *next*
release's sweep — never by the TestFlight builds that keep shipping `main` in between. That
difference is load-bearing: a build sitting in App Review has its signature re-checked when
the submission is resubmitted, and a revoked certificate fails that check (`ITMS-90035`).
With the prefixes split, merging to `main` while a release is under review is safe; the one
rule left is not to cut a *new* release while the previous one is still in review.

### One stored certificate

If you would rather builds never touch Apple's certificate API, set the three `APPLE_*`
secrets and every build reuses that one certificate instead of minting anything. From a
phone:

1. Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new)
   scoped to this repository with **Secrets: read and write**, and save it as a secret named
   `SIGNING_BOOTSTRAP_PAT`. The built-in workflow token cannot write secrets, which is the
   only reason a PAT is needed.
2. Actions → **Signing Setup** → *Run workflow* → task `create`. It registers the App ID if
   missing, creates the certificate and profile, and sets the three secrets.
3. Delete `SIGNING_BOOTSTRAP_PAT`. The next build signs with the stored certificate.

Renew it before it expires a year later. A GitHub secret can be written but never read back,
so a certificate created this way lives only inside Actions; if you also want the `.p12` in
hand, run the script locally instead:

```bash
export APP_STORE_CONNECT_API_KEY_ID=... APP_STORE_CONNECT_ISSUER_ID=...
export APP_STORE_CONNECT_API_KEY_CONTENT="$(cat ~/Downloads/AuthKey_XXXXXX.p8)"

Tools/bootstrap_signing.py list
Tools/bootstrap_signing.py create   # writes the three values to .signing-secrets/
```

### Clearing out certificates

Actions → **Signing Setup** → task `list` shows every certificate and profile on the account
with their ids, and task `revoke` takes those ids. That is the way out of "your account has
reached the maximum number of certificates": revoke the ones nobody holds a private key for.

### Using a certificate from a Mac

If you would rather use Xcode's own certificate flow for the stored-certificate route:

1. Xcode → Settings → Accounts → select the team → *Manage Certificates* → `+` → *Apple
   Distribution*.
2. Keychain Access → *My Certificates* → right-click the `Apple Distribution: …` row →
   *Export*, save as `.p12`, set a password. Expanding the row must reveal a private key; if
   it does not, this Mac does not have the key and the export is useless.
3. developer.apple.com → Profiles → `+` → *App Store Connect* → App ID
   `com.nycneighborhoodsquiz.app` → pick that certificate → download the `.mobileprovision`.
4. Check and encode the pair, which also confirms the profile was really issued for that
   certificate:

```bash
Tools/prepare_signing_secrets.sh ~/Downloads/Certificates.p12 ~/Downloads/NeighborhoodQuiz_AppStore.mobileprovision
```

5. Set the three secrets with the `gh secret set` commands it prints, then delete
   `.signing-secrets/` and keep the `.p12` and its password somewhere safe.

Local development needs none of this: `project.yml` keeps `CODE_SIGN_STYLE: Automatic`, so
Xcode signs with your personal team, and only the release workflows override it with the
shared identity.

## When it crashes

Actions → **Crash Logs** → *Run workflow*. It pulls what testers sent from TestFlight and
puts the reading on the run's summary page, with the raw reports in an artifact.

What it is for is the first ten lines rather than the stack. An app that is shot by the
watchdog for hanging the main thread, one reclaimed for holding too much memory, and one
that reached for memory it did not own all look the same from the outside — the app
vanishes — and as bugs they have nothing to do with each other. The summary names which of
those it was, so a fix starts from the right end. Reasoning it out from the source instead
has a poor record.

The one thing it cannot do is conjure a report nobody sent. A TestFlight crash reaches App
Store Connect only if the tester shares it, and the prompt after a crash is easy to dismiss,
so an empty run means *not shared* rather than *did not crash*. On the phone: TestFlight →
the app → turn sharing on, then reproduce it and tap Share when iOS offers.

Stack frames come back as names rather than addresses because every TestFlight build now
keeps its `dSYMs` as an artifact for ninety days. Builds from before that change are the
exception, and their reports will have bare hex where the app's own frames should be.

Locally, with the same three credentials the signing script uses:

```bash
Tools/testflight_crashes.py --out-dir crashes
Tools/testflight_crashes.py --report-file crashes/crash-01.ips   # re-read a saved one
```

## What is next

The map is finished: five boroughs, one file each, and nothing left on the ladder that
the game cannot open. What is next is the game, and that is not something to plan from
here — it is whatever the play says. The neighbourhood names in the outer boroughs are
a judgement, and playing them is how the wrong ones get found; the ladder was tuned
against two boroughs and may want a look now that it buys four; and a round across the
whole city is now one map of all five, which is a lot of city to find a neighbourhood in. None of that is a feature. It is
the tuning that comes after the drawing, and it starts with playing it.

## License

MIT — see [LICENSE](LICENSE).
