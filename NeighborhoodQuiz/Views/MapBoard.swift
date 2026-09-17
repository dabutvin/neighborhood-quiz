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
    /// whole island.
    enum Opening: Equatable {
        case island
        case midtown
        case neighborhood(String)
    }

    let palette: MapPalette
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
    /// Change this and the map goes back to the whole island. The quiz bumps it between
    /// questions, because arriving at Inwood still zoomed into SoHo is no use to
    /// anybody.
    var resetToken: Int = 0
    /// Which neighborhood was touched, or nothing for the water and the parks.
    var onTap: (Int?) -> Void = { _ in }
    /// Handed back once the drawing exists, for anything that needs to know what is on
    /// the map — the quiz asks it what there is to ask about.
    var onReady: (DrawnMap) -> Void = { _ in }

    @State private var drawn: DrawnMap?
    @State private var camera = MapCamera()
    /// Set once, the first time the view is given a size, so an opening that has to be
    /// aimed somewhere in particular is not re-aimed on every rotation.
    @State private var hasOpened = false

    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                if let drawn, drawn.size == size {
                    ManhattanMapView(
                        drawn: drawn,
                        camera: live(in: size),
                        palette: palette,
                        selected: selected,
                        ruledOut: ruledOut,
                        settled: settled,
                        givenAway: givenAway,
                        candidate: candidate,
                        interacting: pinch != 1 || drag != .zero
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

    /// The camera as it stands *plus* whatever gesture is in flight, which is what the
    /// map is drawn against while a finger is down.
    private func live(in size: CGSize) -> MapCamera {
        var live = camera
        live.setZoom(camera.zoom * Double(pinch))
        live.pan = CGSize(
            width: live.pan.width + drag.width,
            height: live.pan.height + drag.height
        )
        live.clampPan(in: size)
        return live
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                camera.pan = CGSize(
                    width: camera.pan.width + value.translation.width,
                    height: camera.pan.height + value.translation.height
                )
                camera.clampPan(in: size)
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
        guard drawn?.size != size else { return }

        let map = DrawnMap.build(size: size)
        drawn = map
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
            // names on — which is the point of the shot.
            let midtown = map.projection.point(Coordinate(-73.9855, 40.7580))
            camera = MapCamera.centred(on: midtown, zoom: 4.2, in: size)
            camera.clampPan(in: size)
        case .neighborhood(let name):
            guard let area = map.neighborhood(named: name) else { break }
            camera = MapCamera.framing(area.bounds, in: size)
            camera.clampPan(in: size)
        }
    }
}
