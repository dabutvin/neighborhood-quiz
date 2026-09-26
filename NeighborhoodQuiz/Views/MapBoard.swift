import SwiftUI

/// The map you can push about: the drawing, the camera over it, and the fingers on the
/// glass. Everything that is true whether you are playing the quiz or just looking.
///
/// What it does *not* decide is what a tap means. It reports which neighborhood was
/// touched, if any, and the view above it decides whether that is a place being looked
/// up or a guess being made.
struct MapBoard: View {
    /// Where the map starts. The screenshot runs ask for the pulled-in ones so the
    /// gallery shows cross street names, and a neighborhood picked out, as well as the
    /// whole borough.
    enum Opening: Equatable {
        /// The whole borough — the name is from when there was only the one, and an
        /// island at that.
        case island
        /// Times Square, close in. Manhattan only: it is a spot on one borough's map,
        /// and nothing but the screenshot runs asks for it.
        case midtown
        /// Times Square with the map pulled all the way in, for the screenshot that shows
        /// street names at their close-in size.
        case closest
        case neighborhood(String)
    }

    let palette: MapPalette
    /// Which borough to draw. Change it and the drawing is built from that borough's
    /// file — the first time; after that it is taken from the cache below — and the
    /// camera goes home, because it is a different map, not a move.
    let borough: Borough
    var opening: Opening = .island
    /// Filled and named. The quiz uses it for the place you have just found; the map
    /// on its own uses it for whatever you last touched.
    var selected: Int?
    /// Guessed and wrong, marked so a player can see what they have crossed off.
    var ruledOut: Set<Int> = []
    /// Found earlier in the round, left filled and named.
    var settled: Set<Int> = []
    /// Shown to the player after three goes were not enough — named, but in grey.
    var givenAway: Set<Int> = []
    /// Picked out but not yet answered with — outlined, and deliberately not named.
    var candidate: Int?
    /// Change this and the map goes back to the whole borough. The quiz bumps it at the
    /// start of a round, because arriving at Inwood still zoomed into SoHo is no use to
    /// anybody.
    var resetToken: Int = 0
    /// Which neighborhood was touched, or nothing for the water and the parks.
    var onTap: (Int?) -> Void = { _ in }
    /// Handed back once a drawing exists that did not before. The map on its own picks
    /// its opening highlight off it; the quiz cares about the moment rather than the
    /// map, since the first time it fires is the first time a round could be shown.
    var onReady: (DrawnMap) -> Void = { _ in }

    /// The drawings, one per borough visited, all at `drawnSize`.
    ///
    /// A cache rather than the one map, because in the anywhere mode the map hops
    /// between boroughs every question and a borough the size of Queens takes a good
    /// fraction of a second to draw. Built once each, the second visit is free. A new
    /// size empties it, since every drawing in it was for the old one — a rotation
    /// pays for one borough again, not for all five.
    @State private var drawn: [Borough: DrawnMap] = [:]
    @State private var drawnSize: CGSize = .zero
    @State private var camera = MapCamera()
    /// Set once, the first time the view is given a size, so an opening that has to be
    /// aimed somewhere in particular is not re-aimed on every rotation.
    @State private var hasOpened = false

    @GestureState private var pinch: CGFloat = 1

    /// Where a drag started, and where the map was when it started.
    ///
    /// A pan is driven straight into `camera` rather than held in a `@GestureState`,
    /// which would be tidier but cannot carry momentum. Gesture state snaps back to
    /// nothing the instant a finger lifts, so animating the camera from `onEnded` would
    /// animate it from where the drag *began* — the map would jump back across the
    /// screen and then glide forward from there.
    ///
    /// Keyed on where the finger went down, so a drag that is cancelled rather than
    /// ended cannot leave a stale anchor behind for the next one to jump from.
    private struct Grab: Equatable {
        var finger: CGPoint
        var pan: CGSize
    }

    @State private var grab: Grab?


    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                if let drawn = drawn[borough], drawn.size == size {
                    BoroughMapView(
                        drawn: drawn,
                        camera: live(in: size),
                        palette: palette,
                        selected: selected,
                        ruledOut: ruledOut,
                        settled: settled,
                        givenAway: givenAway,
                        candidate: candidate,
                        interacting: pinch != 1 || grab != nil
                    )
                    .contentShape(Rectangle())
                    // The tap is asked first. A drag has ten points of slop to travel
                    // before it counts as one, so a touch that goes nowhere reaches this
                    // and a touch that moves does not.
                    .onTapGesture(coordinateSpace: .local) { location in
                        onTap(drawn.neighborhood(at: live(in: size).modelPoint(location, in: size))?.id)
                    }
                    .gesture(pan(in: size).simultaneously(with: magnify(in: size)))
                }

                zoomControls(in: size)
            }
            .onAppear { prepare(for: size) }
            .onChange(of: size) { _, newSize in prepare(for: newSize) }
            .onChange(of: resetToken) { _, _ in
                withAnimation(.easeOut(duration: 0.35)) { camera = MapCamera() }
            }
            // A new borough is a new drawing, so the camera is put back rather than
            // animated: there is nothing for a move from Inwood to Coney Island to
            // travel across. The drawing itself is built only if this is the first
            // visit; a borough seen before is already in the cache.
            .onChange(of: borough) { _, _ in
                camera = MapCamera()
                prepare(for: size)
            }
        }
    }

    // MARK: - Chrome

    private func zoomControls(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            zoomButton("+", to: camera.zoom * 1.7, in: size)
            zoomButton("\u{2212}", to: camera.zoom / 1.7, in: size)
        }
        .padding(.trailing, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func zoomButton(_ symbol: String, to target: Double, in size: CGSize) -> some View {
        // At either end of the travel the button has nothing left to do, since the
        // camera would only clamp the request back to where it already is.
        let reachable = clamped(target) != camera.zoom

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                camera.setZoom(target)
                camera.clampPan(in: size)
            }
        } label: {
            Text(symbol)
                .font(MapFont.chrome(size: 22))
                .foregroundStyle(palette.ink)
                // Apple asks for forty-four points of target, and a map you are holding
                // one-handed asks for it more loudly than most screens.
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(palette.land.opacity(0.92))
                        .overlay(Circle().strokeBorder(palette.inkSoft, lineWidth: 1.8))
                )
        }
        .buttonStyle(.plain)
        .disabled(!reachable)
        .opacity(reachable ? 1 : 0.4)
        .accessibilityLabel(symbol == "+" ? "Zoom in" : "Zoom out")
    }

    /// `setZoom` clamps, so a button at the end of its travel has to ask the same
    /// question the camera would to know it has nothing left to do.
    private func clamped(_ zoom: Double) -> Double {
        min(max(zoom, MapCamera.range.lowerBound), MapCamera.range.upperBound)
    }

    // MARK: - Gestures

    /// How much of a flick to carry after the finger has gone.
    ///
    /// `predictedEndTranslation` is where UIKit reckons a scroll view would have come to
    /// rest, which is a long way — it is tuned for lists that are meant to fly. Half of
    /// it gives a map that coasts to a stop rather than either stopping dead under the
    /// thumb or sliding out from under it.
    private static let coast = 0.5

    /// What settles the map after a flick, and what pulls it home when it has been
    /// dragged past its leash. Almost no bounce: a map that wobbles as it lands reads as
    /// loose rather than smooth.
    private static let glide = Animation.spring(response: 0.5, dampingFraction: 0.9)

    /// The camera as it stands *plus* whatever pinch is in flight. A drag is already in
    /// `camera` by the time this is asked.
    private func live(in size: CGSize) -> MapCamera {
        guard pinch != 1 else { return camera }
        var live = camera
        live.setZoom(camera.zoom * Double(pinch))
        live.clampPan(in: size)
        return live
    }

    /// Where the map was when this drag took hold of it. A gesture is recognised by
    /// where the finger went down, so the anchor for a new one is never the leftovers
    /// of an old one.
    private func anchor(for value: DragGesture.Value) -> Grab {
        if let grab, grab.finger == value.startLocation { return grab }
        return Grab(finger: value.startLocation, pan: camera.pan)
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let grabbed = anchor(for: value)
                grab = grabbed

                var moved = camera
                moved.pan = CGSize(
                    width: grabbed.pan.width + value.translation.width,
                    height: grabbed.pan.height + value.translation.height
                )
                // Springy at the edges rather than solid. Clamping here is what made a
                // pan feel like it hit something: at the limit the map stopped answering
                // the thumb while the thumb kept going.
                moved.resistPan(in: size)

                // Explicitly not animated. The map is animatable now, and under the
                // thumb it must not be: interpolating towards the finger instead of
                // arriving at it is exactly the lag this is all meant to remove.
                var immediate = Transaction()
                immediate.disablesAnimations = true
                withTransaction(immediate) { camera = moved }
            }
            .onEnded { value in
                let grabbed = anchor(for: value)
                grab = nil

                // What the flick still had in it when the finger left.
                let fling = CGSize(
                    width: (value.predictedEndTranslation.width - value.translation.width) * MapBoard.coast,
                    height: (value.predictedEndTranslation.height - value.translation.height) * MapBoard.coast
                )

                var settled = camera
                settled.pan = CGSize(
                    width: grabbed.pan.width + value.translation.width + fling.width,
                    height: grabbed.pan.height + value.translation.height + fling.height
                )
                // Back inside the leash, so a drag that ended past the edge is pulled
                // home by the same spring that does the coasting.
                settled.clampPan(in: size)

                withAnimation(MapBoard.glide) { camera = settled }
            }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                camera.setZoom(camera.zoom * Double(value.magnification))
                camera.clampPan(in: size)
            }
    }

    // MARK: - Building

    private func prepare(for size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if size != drawnSize {
            drawn = [:]
            drawnSize = size
        }
        guard drawn[borough] == nil else { return }

        let map = DrawnMap.build(borough: borough, size: size)
        drawn[borough] = map
        onReady(map)

        guard !hasOpened else {
            camera.clampPan(in: size)
            return
        }
        hasOpened = true

        switch opening {
        case .island:
            camera = MapCamera()
        case .midtown:
            // Times Square, far enough in that the numbered cross streets have their
            // names on — which is the point of the shot. A Manhattan coordinate on
            // whichever borough is drawn; only the `-map-zoomed` screenshot asks for
            // it, and that one asks for Manhattan.
            let midtown = map.projection.point(Coordinate(-73.9855, 40.7580))
            camera = MapCamera.centred(on: midtown, zoom: 4.2, in: size)
            camera.clampPan(in: size)
        case .closest:
            let midtown = map.projection.point(Coordinate(-73.9855, 40.7580))
            camera = MapCamera.centred(on: midtown, zoom: MapCamera.range.upperBound, in: size)
            camera.clampPan(in: size)
        case .neighborhood(let name):
            guard let area = map.neighborhood(named: name) else { break }
            camera = MapCamera.framing(area.bounds, in: size)
            camera.clampPan(in: size)
        }
    }
}
