# Neighborhood Quiz

An iOS app about knowing where you are in New York. It opens on Manhattan — drawn by
hand, in ink, on paper — with every avenue and every numbered cross street named, and
not one neighbourhood.

That omission is the whole idea. Naming the neighbourhoods is the quiz, and a map that
has already told you where SoHo is has given the game away. For now the island is
streets, Central Park and the water round it.

## The map

The map is not a tile server and not a `MKMapView`. It is drawn from two things the app
carries in its binary:

- **The 1811 grid, as arithmetic.** Above Houston Street Manhattan is a ruled sheet:
  numbered streets every twentieth of a mile, avenues at fixed distances either side of
  Fifth, the whole thing turned about twenty-nine degrees east of north. `ManhattanGrid`
  is that ruling, and it lands where it should — Times Square, Columbus Circle and the
  north-east corner of Central Park all come out within a block of where they are, which
  `ManhattanGridTests` pins down against their real coordinates.
- **A traced shoreline.** Three dozen fixed points round the island, in
  `ManhattanMapData.shoreline`.

Everything else falls out of those two. Each street is drawn far too long — out into the
Hudson on one side and the East River on the other — and then cut against the shoreline
by `Shoreline.clip`, so the map's edges all come from the one traced outline and a
correction to the shoreline corrects every street that meets it. Below Fourteenth, where
the ruling gives out and the streets have names, a handful are traced by hand instead:
Houston, Canal, Delancey, the Bowery, Chambers, Wall — and Broadway, which was a
footpath before there was a grid and still refuses it.

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

Manhattan is an island, so the palette is used the other way up from the Brooklyn map:
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
│   └── NeighborhoodQuizApp.swift   # App entry point, and the launch arguments CI shoots with
├── Map/
│   ├── Geography.swift             # A coordinate, and a Mercator turned so the avenues stand up
│   ├── ManhattanGrid.swift         # The 1811 grid as arithmetic: street and avenue to lon/lat
│   ├── ManhattanMapData.swift      # The shoreline, the park, the avenues, the streets, Broadway
│   ├── Shoreline.swift             # Cutting lines off at the water's edge
│   ├── Pen.swift                   # The unsteady hand: seeded wobble, after rough.js
│   ├── DrawnMap.swift              # Builds the whole drawing once for a given size
│   ├── MapCamera.swift             # How far in, and how far pushed about
│   └── MapPalette.swift            # Paper, ink, sage — day and night — and the hand it is lettered in
├── Views/
│   ├── HomeView.swift              # The screen: the map, the header, the zoom buttons, the gestures
│   ├── ManhattanMapView.swift      # One Canvas: the island under the transform, the names over it
│   └── PaperGrain.swift            # The tooth of the paper, and the vignette
└── Resources/
    ├── Assets.xcassets             # App icon (drawn by Tools/generate_app_icon.py) and accent colour
    └── PrivacyInfo.xcprivacy       # Nothing collected, nothing sent
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

### App icon

The icon is the map, not a picture of a map: it is projected from the same shoreline and
the same grid the app draws from, so correcting the island corrects the tile. What it does
differently is the angle — the app stands the avenues upright, which leaves a tall thin
island in a square tile, so the icon turns the whole thing another forty-five degrees and
lets Manhattan run corner to corner.

```bash
python3 Tools/generate_app_icon.py
```

No Pillow, no cairo, nothing to install: it rasterises by scanline at four times the final
size and averages back down, and writes the PNGs by hand. It writes three tiles — the
standard one, the dark one and the grayscale tinted one. Commit the regenerated PNGs; the
build reads them, not the script.

### Adding a street

Almost every street is already there, because the grid draws them. What needs adding is a
street the grid cannot find:

- **A numbered street** — it is drawn already. To give it a *name* at a wide zoom, add its
  number to `majorCrossStreets`, and to `headlineCrossStreets` if it belongs on the opening
  map.
- **An avenue** — one line in `ManhattanMapData.avenues`: how far west of Fifth it runs (in
  feet, negative east), between which two numbered streets, where along itself its name is
  written, and how far in the map must be pulled before that name appears.
- **A named street downtown** — a traced polyline in `namedStreets`. Overshoot the ends; the
  shoreline will cut it.

`ManhattanMapDataTests` checks the table is coherent and `DrawnMapTests` checks that not one
road is clipped out of existence — which on a map made of two hundred lines is exactly the
sort of thing nobody notices by eye.

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
| `APPLE_PROVISIONING_PROFILE` | Optional. App Store profile for `com.neighborhoodquiz.app`, base64 | Same |

CI and the PR screenshots need none of them — a fork builds, tests and photographs the app
with no secrets at all. Only TestFlight and the release need signing.

The App Store Connect app record must exist with bundle ID `com.neighborhoodquiz.app` (see
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
builds sign as `Neighborhood Quiz CI <run id>` and retire each other. A release signs as
`Neighborhood Quiz Release <run id>`, and its certificate is retired only by the *next*
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
   `com.neighborhoodquiz.app` → pick that certificate → download the `.mobileprovision`.
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

## What is next

The neighbourhoods. The map is deliberately silent about them, because that is what there
will be to guess.

## License

MIT — see [LICENSE](LICENSE).
