import SwiftUI

/// The screen the app opens on: Manhattan, drawn by hand, with its streets named and
/// nothing else on it.
///
/// The neighbourhoods are deliberately absent. They are what the quiz will eventually
/// be about, and a map that has already told you where SoHo is has given the game
/// away — so for now the island is streets, the park, and the water round it.
struct HomeView: View {
    /// Where the map opens. The screenshot runs ask for the pulled-in one so the
    /// gallery shows the cross street names as well as the avenues.
    enum Opening: Equatable {
        case island
        case midtown

        init(arguments: [String]) {
            self = arguments.contains("-map-zoomed") ? .midtown : .island
        }
    }

    var opening: Opening = .island

    @Environment(\.colorScheme) private var colorScheme

    @State private var drawn: DrawnMap?
    @State private var camera = MapCamera()
    /// Set once, the first time the view is given a size, so an opening that has to be
    /// aimed at somewhere in particular is not re-aimed on every rotation.
    @State private var hasOpened = false

    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private var palette: MapPalette { .of(colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                palette.water.ignoresSafeArea()

                if let drawn, drawn.size == size {
                    ManhattanMapView(drawn: drawn, camera: live(in: size), palette: palette)
                        .contentShape(Rectangle())
                        .gesture(pan(in: size).simultaneously(with: magnify(in: size)))
                        .accessibilityElement()
                        .accessibilityLabel("Map of Manhattan")
                        .accessibilityHint("Drag to move the map, pinch to zoom in on the streets")
                }

                PaperTexture(palette: palette)

                header
                zoomControls(in: size)
            }
            .onAppear { prepare(for: size) }
            .onChange(of: size) { _, newSize in prepare(for: newSize) }
        }
        .background(palette.water)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("Neighborhood Quiz")
                .font(MapFont.chrome(size: 26))
                .foregroundStyle(palette.ink)
            Text("MANHATTAN")
                .font(.system(size: 10, weight: .semibold))
                .kerning(2.2)
                .foregroundStyle(palette.inkSoft)
        }
        .padding(.trailing, 18)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
    }

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
                // Apple asks for forty-four points of target, and a map you are
                // holding one-handed asks for it more loudly than most screens.
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
        }
    }
}

#Preview {
    HomeView()
}
