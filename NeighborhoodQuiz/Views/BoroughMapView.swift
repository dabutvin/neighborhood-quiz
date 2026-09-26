import SwiftUI

/// The borough, drawn.
///
/// Everything below the labels happens inside one `Canvas`: the paths are built once
/// for the view's size and then re-stroked under whatever transform the camera is
/// holding, with every pen weight divided by the zoom so a line stays a line rather
/// than swelling into a band as you come in on it. The names are drawn afterwards, in
/// screen coordinates, so they keep their size too — pulling the map in shows *more*
/// street names rather than bigger ones.
/// The conformance is isolated to the main actor because a `View`'s members already are,
/// while `Animatable`'s requirement is not. SwiftUI drives animation on the main actor,
/// so this is the truth rather than a way round the compiler.
struct BoroughMapView: View, @MainActor Animatable {
    let drawn: DrawnMap
    var camera: MapCamera
    let palette: MapPalette
    /// Which neighbourhood is picked out, if any, by `DrawnNeighborhood.id`.
    var selected: Int?
    /// Neighbourhoods guessed at and crossed off, greyed so a player can see where they
    /// have already looked.
    var ruledOut: Set<Int> = []
    /// Neighbourhoods already found and settled. Washed and named, but quietly: the
    /// borough fills in as a round goes on, so what you have done so far is on the map
    /// rather than in a tally somewhere.
    var settled: Set<Int> = []
    /// Neighbourhoods three goes were not enough for, which the round showed the player
    /// instead. Named like the found ones so the map still teaches, but in the flat grey
    /// of a crossing-out rather than in terracotta — being given a place is not the same
    /// as knowing it, and the map should not flatter anybody about which was which.
    var givenAway: Set<Int> = []
    /// The neighbourhood picked out but not yet answered with.
    ///
    /// Drawn in ink rather than terracotta and — this is the whole point — **never
    /// named**. A candidate that told you what it was would hand over the game: you
    /// could tap your way round the borough reading names off until one of them matched
    /// the question. So it shows you the shape you have your finger on and nothing else.
    var candidate: Int?
    /// Whether a finger is on the map right now. Drawing is at its most expensive
    /// exactly when it has the least time, so a couple of things the eye cannot follow
    /// mid-drag are left until the map is still again.
    var interacting: Bool = false

    /// Whether this frame is a step of a move rather than the map sitting still.
    ///
    /// Nobody passes this in. It is set by the animator and by nothing else: SwiftUI
    /// interpolates by handing each step to `animatableData` on a copy of the view and
    /// then drawing that copy, so a view that finds its camera was *put* there rather
    /// than passed in is, by that fact alone, mid-move.
    ///
    /// Which matters because the halo is four fifths of what a street name costs, and
    /// until the map was made animatable a coast after a flick was a single frame — an
    /// unanimated camera change lands in one step, so the whole cost of it was paid
    /// once. It is now every frame of half a second, each one laying four extra passes
    /// of paper behind every name on a map sliding past too fast to read one of them:
    /// the most expensive thing on the screen, spent at the one moment there is least
    /// room for it, on something nobody can see.
    var moving: Bool = false

    /// What lets the map actually *move* when the camera is animated.
    ///
    /// A canvas draws inside a closure, and SwiftUI cannot interpolate a closure. With
    /// nothing animatable between a camera and the drawing it produces, `withAnimation`
    /// around a camera change had nothing to work with and the change landed in a single
    /// step — so every animated camera move in the app was a jump wearing the word
    /// "animation": the coast after a flick, the spring back from an edge pulled past
    /// its leash, the zoom buttons, and the pull-back to the whole borough between
    /// rounds. The last two had been jumping since the day they were written.
    ///
    /// Handing SwiftUI the three numbers a camera is made of gives it something it can
    /// interpolate. It runs `body` again at each step with the values in between, which
    /// is what a moving map is.
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get {
            AnimatablePair(
                camera.zoom,
                AnimatablePair(Double(camera.pan.width), Double(camera.pan.height))
            )
        }
        set {
            camera.zoom = newValue.first
            camera.pan = CGSize(width: newValue.second.first, height: newValue.second.second)
            moving = true
        }
    }

    var body: some View {
        Canvas { context, size in
            draw(map: drawn, in: &context, size: size)
            // The picked-out name claims its paper before any street name is offered
            // one, so a street is never written across the answer.
            let claimed = drawNames(in: &context, size: size)
            draw(labels: drawn.labels, in: &context, size: size, claimed: claimed)
        }
        // Text drawn inside a `Canvas` is resolved against the canvas's own
        // environment, and this is the only way to reach it: `Text` has no alignment
        // modifier that hands back a `Text`. It matters for one label — a long
        // neighbourhood name wrapping onto a second line — and does nothing at all to
        // the street names, which are a line each.
        .multilineTextAlignment(.center)
        // One element, described below, rather than nine hundred street names.
        //
        // Here rather than at the two places this view is used, because one of them had
        // it and the other did not, and the one that did not is the quiz — the screen
        // people actually spend their time on.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            BoroughMapView.spoken(
                borough: drawn.borough.name,
                showing: chosen?.name,
                picked: candidate != nil,
                found: settled.count,
                missed: givenAway.count
            )
        )
        .accessibilityHint("Drag to move the map, pinch to zoom, tap a neighborhood to pick it")
    }

    /// What the map says to somebody who is not looking at it.
    ///
    /// A canvas has no structure for VoiceOver to walk, so SwiftUI offers it the only
    /// thing it can find in one: every piece of text drawn into it. On a borough that is
    /// most of a thousand street names read out one after another, which is no way to
    /// find anything — and through the accessibility annotations behind it, it was also
    /// what took the app down. The street names are of use on the glass. They are of
    /// none in a list.
    ///
    /// What it says is exactly what the map shows and not a word more. A neighbourhood
    /// that has been found is written on the map, so it is named here. One that has
    /// only been picked is deliberately *not* written on the map — naming it would hand
    /// over the game — so it is not named here either. The quiz has to be as hard to
    /// listen to as it is to look at.
    static func spoken(
        borough: String,
        showing: String?,
        picked: Bool,
        found: Int,
        missed: Int
    ) -> String {
        var said = "Map of \(borough)"
        if let showing {
            said += ", showing \(showing)"
        } else if picked {
            said += ", with a neighborhood picked but not named"
        }

        var tally: [String] = []
        if found > 0 { tally.append("\(found) found") }
        if missed > 0 { tally.append("\(missed) given away") }
        if !tally.isEmpty { said += ". " + tally.joined(separator: ", ") }

        return said
    }

    /// The picked-out neighbourhood. Held by identity rather than by position, so a map
    /// rebuilt for a new size — a rotation, a split view — keeps hold of the same place
    /// whatever order the new list came out in.
    private var chosen: DrawnNeighborhood? {
        guard let selected else { return nil }
        return drawn.neighborhoods.first { $0.id == selected }
    }

    // MARK: - The drawing

    private func draw(map: DrawnMap, in context: inout GraphicsContext, size: CGSize) {
        var board = context
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let zoom = CGFloat(camera.zoom)
        board.translateBy(x: centre.x + camera.pan.width, y: centre.y + camera.pan.height)
        board.scaleBy(x: zoom, y: zoom)
        board.translateBy(x: -centre.x, y: -centre.y)

        board.fill(map.land, with: .color(palette.land))
        board.stroke(
            map.landEdge,
            with: .color(palette.waterInk.opacity(0.85)),
            style: StrokeStyle(lineWidth: 2.2 / zoom, lineCap: .round, lineJoin: .round)
        )

        board.fill(map.parks, with: .color(palette.park))
        board.stroke(
            map.parkEdge,
            with: .color(palette.parkInk),
            style: StrokeStyle(lineWidth: 1.2 / zoom, lineCap: .round, lineJoin: .round)
        )

        let onScreen = camera.visibleRect(in: size, margin: 8)
        draw(roads: map, in: &board, onScreen: onScreen, zoom: zoom)

        // Crossed off. Over the streets like the highlight, and before the borders, so
        // that a greyed neighborhood still has a line round it saying where it ends.
        //
        // And crossed off in the literal sense as well as the figurative one. The wash
        // on its own was too quiet to be an answer: you tapped a place, said it, were
        // wrong, and the map went very slightly grey there. A wrong guess should look
        // like somebody drew a line through it, because that is what it is — the two
        // strokes say *no* in a way a change of shade does not.
        if !ruledOut.isEmpty {
            for area in map.neighborhoods where ruledOut.contains(area.id) {
                guard area.bounds.intersects(onScreen) else { continue }
                board.fill(area.shape, with: .color(palette.ruledOut.opacity(0.42)))

                // Kept inside the place it crosses off. The arms are sized from the
                // bounding box, and a neighborhood is not a rectangle — on an awkward
                // shape a diagonal can leave it and land on the one next door, which
                // is the one thing this mark must never look like it is saying.
                var marked = board
                marked.clip(to: area.shape)
                marked.stroke(
                    area.cross,
                    with: .color(palette.ruledOutInk.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 2.6 / zoom, lineCap: .round, lineJoin: .round)
                )
            }
        }

        // Every border, over the streets rather than under them.
        //
        // Under them was the mistake, and no amount of weight or colour was going to
        // fix it: a border under the drawing is crossed by every street that crosses
        // it, and fifteen hundred strokes of road painted these into stubs a few points
        // long. Dashes on top of that left not a line but a rash. A boundary is not part
        // of the drawing underneath — it is something said about it — and it belongs on
        // top the way a line drawn over a finished map in coloured pencil would be.
        //
        // The casing of paper underneath is the other half of that. It is what a road
        // atlas puts round a motorway, and it does the same job here: the line is read
        // against the paper rather than against whatever grid it happens to be crossing.
        for area in map.neighborhoods where area.bounds.intersects(onScreen) {
            // Anything found or picked has an unbroken line of its own coming later.
            guard area.id != selected, area.id != candidate,
                  !settled.contains(area.id), !givenAway.contains(area.id)
            else { continue }
            let dash = [5 / zoom, 3.5 / zoom]
            board.stroke(
                area.edge,
                with: .color(palette.land.opacity(0.9)),
                style: StrokeStyle(
                    lineWidth: CGFloat(borderWeight + 1.8) / zoom,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: dash
                )
            )
            board.stroke(
                area.edge,
                with: .color(palette.border),
                style: StrokeStyle(
                    lineWidth: CGFloat(borderWeight) / zoom,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: dash
                )
            )
        }

        // The ones already found, filled and left there. No coat of paper under them —
        // that is for the place being looked at now, and ten quieted neighborhoods would
        // be most of the borough with the life taken out of it.
        for area in map.neighborhoods where settled.contains(area.id) && area.id != selected {
            guard area.bounds.intersects(onScreen) else { continue }
            board.fill(area.shape, with: .color(palette.highlight.opacity(0.22)))
            board.stroke(
                area.edge,
                with: .color(palette.highlightInk.opacity(0.55)),
                style: StrokeStyle(lineWidth: 2 / zoom, lineCap: .round, lineJoin: .round)
            )
        }

        // And the ones the round gave away, in grey rather than terracotta.
        for area in map.neighborhoods where givenAway.contains(area.id) && area.id != selected {
            guard area.bounds.intersects(onScreen) else { continue }
            board.fill(area.shape, with: .color(palette.ruledOut.opacity(0.3)))
            board.stroke(
                area.edge,
                with: .color(palette.ruledOutInk.opacity(0.75)),
                style: StrokeStyle(lineWidth: 2 / zoom, lineCap: .round, lineJoin: .round)
            )
        }

        // What is picked but not yet answered with. Ink, not terracotta: terracotta on
        // this map means found, and this is a question being asked, not one answered.
        if let candidate, let area = drawn.neighborhoods.first(where: { $0.id == candidate }),
           area.bounds.intersects(onScreen) {
            board.fill(area.shape, with: .color(palette.ink.opacity(0.16)))
            board.stroke(
                area.edge,
                with: .color(palette.ink),
                style: StrokeStyle(lineWidth: 3 / zoom, lineCap: .round, lineJoin: .round)
            )
        }

        // The picked-out one, last of all.
        //
        // Two coats. The first is the colour of the paper, and its whole job is to take
        // the contrast out of the grid underneath: the streets are still all there,
        // just gone quiet, so the shape and its name are what the eye lands on instead
        // of forty cross streets. The second is the wash that says which one it is.
        // Under the streets — which is where this started — the wash was true to the
        // drawing and almost impossible to read a name off.
        if let chosen {
            let earned = !givenAway.contains(chosen.id)
            board.fill(chosen.shape, with: .color(palette.land.opacity(0.62)))

            // The greens come back through it. Taking the contrast out of every street
            // inside was the point; taking it out of Washington Square along with them
            // was not. A park is a landmark, and which neighbourhood has which is a
            // good part of what knowing a neighbourhood means.
            var greens = board
            greens.clip(to: chosen.shape)
            greens.fill(map.parks, with: .color(palette.park.opacity(0.7)))

            board.fill(
                chosen.shape,
                with: .color(earned ? palette.highlight.opacity(0.28) : palette.ruledOut.opacity(0.34))
            )
            // And its own line, unbroken and heavier than any avenue, which is what
            // makes it read as one shape rather than as a stain on the drawing.
            board.stroke(
                chosen.edge,
                with: .color(earned ? palette.highlightInk : palette.ruledOutInk),
                style: StrokeStyle(lineWidth: 3 / zoom, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// How heavy a border is drawn, in points on screen.
    ///
    /// A little heavier when pulled back, where the borders are shortest and there is
    /// most of the borough on the glass at once.
    ///
    /// Lighter than the first version over the top, which at two points and more was a
    /// quilt of dashes with a street map somewhere behind it — the same mistake as
    /// hiding them under the streets, with the sign flipped. Heavier than the second,
    /// which corrected too far. This sits between the two: a line you can follow across
    /// the borough without it becoming the thing the borough is made of.
    private var borderWeight: Double {
        let pulledBack = min(max((3 - camera.zoom) / 2, 0), 1)
        return 1.2 + 0.5 * pulledBack
    }

    /// The streets.
    ///
    /// There are two ways to put them down and which is cheaper depends entirely on how
    /// much of the borough is on the glass. Pulled back, nothing is off the edge, so
    /// skipping what cannot be seen finds nothing to skip and every road pays for a
    /// stroke of its own — four hundred of them at the view the app opens on. Pulled in,
    /// nineteen twentieths of the borough is off the glass and skipping it is the whole
    /// game.
    ///
    /// So: when most of a rank is showing, stroke the single path holding all of it;
    /// when little of it is, stroke the few that are. A third is roughly where one stops
    /// being the obvious choice.
    ///
    /// The sheet is only allowed once a rank is fully in, and that restriction is the
    /// whole of what keeps the two paths drawing the same picture. Half-transparent
    /// strokes laid down one at a time build up where they cross; the same lines in one
    /// path are composited once and do not. So a fading rank drawn as a sheet has paler
    /// crossings, and switching between the two part-way through a pinch would show it —
    /// a flicker in the middle of the gesture this is all meant to smooth out. At full
    /// ink there is no difference to see.
    private func draw(
        roads map: DrawnMap,
        in board: inout GraphicsContext,
        onScreen: CGRect,
        zoom: CGFloat
    ) {
        // Light lines under heavy ones, which is the order the roads themselves are in.
        for kind in [RoadKind.side, .major, .avenue] {
            let ink = DrawnMap.presence(of: kind, at: camera.zoom)
            // A rank with no ink in it is not counted, never mind drawn. Pulled back
            // to the whole island, that is a thousand side streets passed over before
            // anything asks where any of them is.
            guard ink > 0.01 else { continue }

            let rank = map.roadsByKind[kind.rawValue]
            var showing = 0
            for road in rank where road.bounds.intersects(onScreen) { showing += 1 }
            guard showing > 0 else { continue }

            let colour = GraphicsContext.Shading.color(palette.colour(for: kind).opacity(ink))
            let style = StrokeStyle(
                lineWidth: CGFloat(palette.weight(for: kind)) / zoom,
                lineCap: .round,
                lineJoin: .round
            )

            if ink >= 1, showing * 3 >= rank.count {
                board.stroke(map.roadSheets[kind.rawValue], with: colour, style: style)
            } else {
                for road in rank where road.bounds.intersects(onScreen) {
                    board.stroke(road.path, with: colour, style: style)
                }
            }
        }
    }


    // MARK: - The names

    /// Writes the names of every neighbourhood that has been found, and hands back the
    /// paper they took so no street name is offered the same patch.
    ///
    /// The one just found goes on last and largest, and is the only one shouldered back
    /// onto the glass if its shape has been dragged off the edge: knowing what you have
    /// just found matters more than knowing exactly where its middle is, and the
    /// highlight is already saying where. The ones that have settled stay where they
    /// belong and simply go if you look elsewhere — ten names pinned to the edges of the
    /// screen would be a list, not a map.
    private func drawNames(in context: inout GraphicsContext, size: CGSize) -> [CGRect] {
        var claimed: [CGRect] = []

        for area in drawn.neighborhoods where area.id != selected {
            let earned = settled.contains(area.id)
            guard earned || givenAway.contains(area.id) else { continue }
            let point = camera.screenPoint(area.labelPoint, in: size)
            guard CGRect(origin: .zero, size: size).contains(point) else { continue }
            if let box = write(
                area.name,
                at: point,
                size: palette.settledLabelSize,
                ink: earned ? palette.highlightInk.opacity(0.9) : palette.ruledOutInk,
                reach: palette.labelHaloReach,
                in: &context,
                on: size,
                avoiding: claimed
            ) {
                claimed.append(box)
            }
        }

        guard let chosen else { return claimed }

        let point = camera.screenPoint(chosen.labelPoint, in: size)
        if let box = write(
            chosen.name,
            at: point,
            size: palette.neighborhoodLabelSize,
            ink: givenAway.contains(chosen.id) ? palette.ruledOutInk : palette.highlightInk,
            reach: palette.neighborhoodHaloReach,
            in: &context,
            on: size,
            avoiding: [],  // the newest name wins any argument about paper
            keepingOnScreen: true
        ) {
            // Anything a settled name had claimed under it has been drawn over, so the
            // street names are told about the new box rather than the old ones.
            claimed.removeAll { $0.intersects(box) }
            claimed.append(box)
        }
        return claimed
    }

    /// One name on the glass, in ink with paper showing through it. Hands back the patch
    /// it took, or nothing if that patch was already spoken for.
    private func write(
        _ name: String,
        at wanted: CGPoint,
        size textSize: Double,
        ink inkColour: Color,
        reach: Double,
        in context: inout GraphicsContext,
        on size: CGSize,
        avoiding taken: [CGRect],
        keepingOnScreen: Bool = false
    ) -> CGRect? {
        let text = Text(name).font(MapFont.label(size: textSize))
        let ink = context.resolve(text.foregroundStyle(inkColour))
        let halo = context.resolve(text.foregroundStyle(palette.labelHalo))

        // Every name fits on one line at the width of a phone, now that they are names
        // people say rather than the city's compound ones. Measuring inside the width it
        // will be drawn in anyway, so that the day one does not fit — a longer name, a
        // smaller screen, a larger type setting — it wraps rather than running off both
        // edges.
        let room = CGSize(width: max(size.width - 32, 40), height: 240)
        let measured = ink.measure(in: room)

        // The generous margin top and bottom keeps a name out from under the question
        // and the zoom buttons.
        let point = keepingOnScreen
            ? CGPoint(
                x: clamp(wanted.x, measured.width / 2 + 16, size.width - measured.width / 2 - 16),
                y: clamp(wanted.y, measured.height / 2 + 30, size.height - measured.height / 2 - 72)
            )
            : wanted
        let box = CGRect(
            x: point.x - measured.width / 2,
            y: point.y - measured.height / 2,
            width: measured.width,
            height: measured.height
        )
        guard !taken.contains(where: { $0.intersects(box) }) else { return nil }

        // Eight passes rather than four, and further out. A street name crosses one
        // street; these lie across a whole grid of them, and four points of compass left
        // the corners of every letter sitting on somebody's cross street. There are at
        // most ten of them, so the extra draws cost nothing worth counting.
        for offset in BoroughMapView.ringOffsets(radius: reach) {
            context.draw(halo, in: box.offsetBy(dx: offset.x, dy: offset.y))
        }
        context.draw(ink, in: box)

        return box.insetBy(dx: -4, dy: -4)
    }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        // On a narrow screen a long name can want more room than there is, and the two
        // ends of the travel cross over. Middle of the screen, then.
        guard low <= high else { return (low + high) / 2 }
        return min(max(value, low), high)
    }

    private func draw(
        labels: [DrawnLabel],
        in context: inout GraphicsContext,
        size: CGSize,
        claimed: [CGRect]
    ) {
        // A margin either side of the screen, so a name whose middle has just gone off
        // the edge does not blink out while part of it is still showing.
        let visible = CGRect(origin: .zero, size: size).insetBy(dx: -90, dy: -90)

        // The paper each name has already taken. Labels arrive most important first, so
        // the first to claim a patch keeps it and whatever would have been written across
        // it is left off — which is what stops "Central Park West" being written straight
        // through "96th Street" at the widest zoom.
        var taken: [CGRect] = claimed
        // Close in the names are written larger, and the paper round them grows with
        // them. Worked out once for the whole pass rather than once per name.
        let zoom = camera.zoom
        let growth = palette.labelSize(for: .side, at: zoom) / palette.labelSize(for: .side)
        let offsets = BoroughMapView.crossOffsets(radius: palette.labelHaloReach * growth)

        for label in labels where camera.zoom >= label.minZoom {
            var point = camera.screenPoint(label.position, in: size)
            guard visible.contains(point) else { continue }

            // Measured from the cache, which knows the answer after the first frame a
            // name is offered on. Deciding whether there is room for a name used to mean
            // laying it out first, so every name the grid was too crowded to fit paid in
            // full for the privilege of being left off — and at four times in, where all
            // seven hundred side street names are on offer, most of them are left off.
            //
            // The cache measures every name at its pulled-back size; a name written at
            // a larger size fills a box larger by the same factor, near enough to decide
            // whether it collides, so the one measurement serves every zoom.
            let fontSize = palette.labelSize(for: label.kind, at: zoom)
            let scale = fontSize / palette.labelSize(for: label.kind)
            let base = drawn.metrics.size(of: label, palette: palette, in: context)
            let measured = CGSize(width: base.width * scale, height: base.height * scale)

            // A name whose place on its street is near the edge of the glass hangs off
            // it, and close in — where a name is written large and a street crosses the
            // whole screen — that was half the cross streets reading "t-47th Street".
            // Slid along its own street until all of it is on screen, it reads whole
            // and is still on the line it names.
            point = BoroughMapView.slid(
                point,
                box: footprint(measured, at: point, angle: label.angle),
                angle: label.angle,
                reach: measured.width,
                onto: size
            )
            let box = footprint(measured, at: point, angle: label.angle)
            if taken.contains(where: { $0.intersects(box) }) { continue }
            taken.append(box)

            let text = Text(label.text)
                .font(MapFont.label(size: fontSize))
            let ink = context.resolve(text.foregroundStyle(palette.label))

            // The paper showing through a name is what keeps it readable where it
            // crosses its own street: the same word laid down four times just off the
            // mark in the colour of the page, and then once more in ink.
            //
            // It is also four fifths of what a name costs to draw, and while a finger is
            // down that is four fifths of the work for something nobody is reading. So
            // the halo is left off mid-gesture and comes back the moment the map is let
            // go of — the names stay put either way, which is far less distracting than
            // having them disappear.
            let halo = interacting || moving
                ? nil
                : context.resolve(text.foregroundStyle(palette.labelHalo))

            context.drawLayer { layer in
                layer.translateBy(x: point.x, y: point.y)
                layer.rotate(by: .radians(label.angle))
                if let halo {
                    for offset in offsets {
                        layer.draw(halo, at: offset, anchor: .center)
                    }
                }
                layer.draw(ink, at: .zero, anchor: .center)
            }
        }
    }

    /// Four points round a circle. What a street name gets: it crosses one street, and
    /// there are a thousand of them to draw.
    ///
    /// These passes are not free in the way they look. Every piece of text drawn into a
    /// canvas is registered with accessibility as a label and a bounding rect, and the
    /// sweep that clears those registrations scans the whole list per entry — so the
    /// cost of them is quadratic in how many there are. That is what killed the app:
    /// the watchdog, ten seconds into a scene update, inside
    /// `+[AXUIContextDrawingAnnotation addLabel:boundingRect:withContext:]` with
    /// forty-six thousand of them queued up.
    ///
    /// A shadow with no offset is the same halo for one draw, and it was tried. It is
    /// not the same halo to look at: a blur spreads its opacity out, and a street line
    /// ran straight through the middle of "West 50th Street" where the ring had broken
    /// it cleanly. The ring stays.
    ///
    /// What makes it safe is the `interacting || moving` guard above, and it is worth
    /// being explicit about why. Registrations only pile up while frames are being
    /// produced continuously, which is to say while the map is being pushed about — and
    /// that is exactly when the halo is already off. A map standing still draws a frame
    /// and then stops. Four passes on a frame that happens once cost nothing; four
    /// passes on every frame of a flick are what cost the app.
    private static func crossOffsets(radius: Double) -> [CGPoint] {
        [
            CGPoint(x: -radius, y: 0), CGPoint(x: radius, y: 0),
            CGPoint(x: 0, y: -radius), CGPoint(x: 0, y: radius),
        ]
    }

    /// Eight points round a circle — the four compass points and the four corners —
    /// which is enough passes that the paper showing through a name has no notches in
    /// it at the corners of the letters.
    private static func ringOffsets(radius: Double) -> [CGPoint] {
        let corner = radius * 0.7071
        return [
            CGPoint(x: -radius, y: 0), CGPoint(x: radius, y: 0),
            CGPoint(x: 0, y: -radius), CGPoint(x: 0, y: radius),
            CGPoint(x: -corner, y: -corner), CGPoint(x: corner, y: -corner),
            CGPoint(x: -corner, y: corner), CGPoint(x: corner, y: corner),
        ]
    }

    /// The upright box a rotated name sits in. A name written up an avenue is measured
    /// lying down and then stood up, which is what the sine and cosine are doing.
    /// Where a name should sit so that none of it hangs off the screen: moved along its
    /// own direction — which, for a name lying on a straight street, is along the street
    /// — by as much as it overhangs the edge it is crossing.
    ///
    /// Moved no further than `reach`, a name's own length, since a name is placed on the
    /// part of its street it belongs to and a curving street is only straight for so
    /// long. A name that would need more, or that overhangs an edge it runs parallel
    /// to — the top of the screen for a cross street — is left where it was; it can
    /// only be moved along its street, and along its street is no help.
    static func slid(
        _ point: CGPoint,
        box: CGRect,
        angle: Double,
        reach: CGFloat,
        onto screen: CGSize
    ) -> CGPoint {
        let glass = CGRect(origin: .zero, size: screen).insetBy(dx: 4, dy: 4)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if box.minX < glass.minX { dx = glass.minX - box.minX }
        else if box.maxX > glass.maxX { dx = glass.maxX - box.maxX }
        if box.minY < glass.minY { dy = glass.minY - box.minY }
        else if box.maxY > glass.maxY { dy = glass.maxY - box.maxY }
        guard dx != 0 || dy != 0 else { return point }

        // Along the name, by whichever of the two it mostly runs along: a cross street
        // is moved by its overhang at the side, an avenue by its overhang at the top
        // or bottom. The larger component is never under 0.7, so nothing is divided
        // by a sliver.
        let along = CGPoint(x: cos(angle), y: sin(angle))
        let travel = abs(along.x) >= abs(along.y) ? dx / along.x : dy / along.y
        guard travel != 0, abs(travel) <= reach else { return point }
        return CGPoint(x: point.x + travel * along.x, y: point.y + travel * along.y)
    }

    private func footprint(_ measured: CGSize, at point: CGPoint, angle: Double) -> CGRect {
        let across = abs(cos(angle))
        let down = abs(sin(angle))
        // A point of air either side, so two names never quite touch.
        let width = measured.width * across + measured.height * down + 2
        let height = measured.width * down + measured.height * across + 2
        return CGRect(
            x: point.x - width / 2,
            y: point.y - height / 2,
            width: width,
            height: height
        )
    }

}
