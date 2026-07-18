//
//  DistrictMapView.swift
//  EagleEye
//
//  The right "Map" tab: colored congressional-district outlines across the US,
//  fading to state flags + governor pins when zoomed out.
//
//  Rendered with a UIKit `MKMapView` wrapped in `DistrictMapRepresentable`
//  rather than SwiftUI's declarative `Map`. The declarative `Map` rebuilds and
//  re-diffs its entire `MapContent` tree every time the view body re-runs — and
//  camera changes forced that on nearly every gesture frame — which is what made
//  the old implementation stutter and drop district fills at the viewport edge.
//  MKMapView takes the opposite approach: the ~435 district polygons are handed
//  to it once as overlays, and MapKit owns viewport culling, tiling, level of
//  detail, and per-tile redraw internally. Panning reuses cached tiles, so
//  there are no holes and no per-frame geometry rebuild.
//

import SwiftUI
import MapKit
#if canImport(UIKit)
import UIKit
#endif

struct DistrictMapView: View {
    let representatives: [Representative]
    /// The user's last resolved coordinate, if any — lets the map center on
    /// roughly the right place immediately, before the (much slower) district
    /// boundary parsing and lookup finish.
    let userCoordinate: CLLocationCoordinate2D?

    @State private var stateBoundaries: [MapBoundary] = []
    @State private var districtBoundaries: [MapBoundary] = []
    @State private var selectedDistrict: MapBoundary?
    @State private var selectedState: MapBoundary?
    @State private var hasSetInitialRegion = false
    @State private var hasCenteredOnUserDistrict = false
    @State private var isCenteredOnUserDistrict = false
    /// The region the map opens on: a rough metro-wide box around the user's
    /// coordinate, applied once so the map isn't pointed at MapKit's generic
    /// default view while boundaries load.
    @State private var initialRegion: MKCoordinateRegion?
    /// Bumped to ask the map to animate back to the user's district. Every
    /// increment is one recenter request the representable applies.
    @State private var recenterTrigger = 0

    /// `partyByDistrict`, rebuilt only when the underlying roster actually
    /// changes rather than on every access.
    @State private var partyByDistrictCache: [String: Party] = [:]
    @State private var nationalHouseDirectory = NationalHouseDirectory()
    @State private var nationalSenateDirectory = NationalSenateDirectory()
    @State private var populationDirectory = DistrictPopulationDirectory()
    @State private var industryDirectory = DistrictIndustryDirectory()
    @State private var cityDirectory = DistrictCityDirectory()
    @State private var universityDirectory = DistrictUniversityDirectory()
    @State private var statePopulationDirectory = StatePopulationDirectory()
    @State private var stateIndustryDirectory = StateIndustryDirectory()
    @State private var stateCityDirectory = StateCityDirectory()
    @State private var stateUniversityDirectory = StateUniversityDirectory()

    @Environment(\.colorScheme) private var colorScheme

    /// Keeps the camera from panning/zooming out to the rest of the globe —
    /// every district, state, and territory this app tracks (CONUS, Alaska,
    /// Hawaii, Puerto Rico, DC) sits within this box.
    static let cameraBoundsRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45, longitude: -122),
        span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 105)
    )
    static let maxCenterDistance: CLLocationDistance = 12_000_000

    /// Members to show as pins. Senators are excluded — they represent a whole
    /// state rather than a single district, so they have no "middle of the
    /// district" point to pin at.
    private var mappable: [Representative] {
        representatives.filter { $0.office == .representative }
    }

    private func rebuildPartyByDistrictCache() {
        partyByDistrictCache = Dictionary(
            nationalHouseDirectory.members.map { (Self.districtKey(state: $0.state, district: $0.district), $0.party) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// A lookup key combining state and district number; at-large districts use
    /// `0`, matching the bundled Census boundary data. Congress.gov gives a
    /// representative's state as a full name while the boundary data keys
    /// districts by postal code, so both sides are normalized to the postal code.
    static func districtKey(state: String, district: Int?) -> String {
        let code = SenateService.stateCode(for: state) ?? state
        return "\(code)-\(district ?? 0)"
    }

    var body: some View {
        NavigationStack {
            DistrictMapRepresentable(
                districtBoundaries: districtBoundaries,
                stateBoundaries: stateBoundaries,
                partyByDistrict: partyByDistrictCache,
                mappable: mappable,
                colorSchemeIsDark: colorScheme == .dark,
                initialRegion: initialRegion,
                recenterRegion: recenterRegion,
                recenterTrigger: recenterTrigger,
                selectedDistrict: $selectedDistrict,
                selectedState: $selectedState,
                isCentered: $isCenteredOnUserDistrict
            )
            .ignoresSafeArea()
            // The recenter control lives outside the ignored safe area so it
            // stays clear of the home indicator and nav bar.
            .overlay(alignment: .bottomTrailing) {
                recenterButton
                    .padding()
            }
            .navigationTitle("District Map")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if !hasSetInitialRegion, let userCoordinate {
                    hasSetInitialRegion = true
                    initialRegion = wideRegion(centeredOn: userCoordinate)
                }
                async let nationalHouseLoad: Void = nationalHouseDirectory.loadIfNeeded()
                async let nationalSenateLoad: Void = nationalSenateDirectory.loadIfNeeded()
                if districtBoundaries.isEmpty, stateBoundaries.isEmpty {
                    async let districts = Task.detached(priority: .userInitiated) { BoundaryLoader.loadDistricts() }.value
                    async let states = Task.detached(priority: .userInitiated) { BoundaryLoader.loadStates() }.value
                    districtBoundaries = await districts
                    stateBoundaries = await states
                    centerOnUserDistrictIfNeeded()
                }
                await nationalHouseLoad
                await nationalSenateLoad
                rebuildPartyByDistrictCache()
            }
            .onChange(of: representatives) { centerOnUserDistrictIfNeeded() }
            .onChange(of: nationalHouseDirectory.members) { _, _ in
                rebuildPartyByDistrictCache()
            }
            .sheet(item: $selectedDistrict) { boundary in
                DistrictDetailSheet(
                    boundary: boundary,
                    color: fillColor(for: boundary),
                    representative: representative(for: boundary),
                    populationDirectory: populationDirectory,
                    industryDirectory: industryDirectory,
                    cityDirectory: cityDirectory,
                    universityDirectory: universityDirectory
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedState) { boundary in
                StateDetailSheet(
                    boundary: boundary,
                    senators: nationalSenateDirectory.senators(forState: boundary.state),
                    representatives: nationalHouseDirectory.representatives(forState: boundary.state),
                    populationDirectory: statePopulationDirectory,
                    industryDirectory: stateIndustryDirectory,
                    cityDirectory: stateCityDirectory,
                    universityDirectory: stateUniversityDirectory
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    /// The fill color for a district's sheet swatch: its representative's party
    /// color, or clear if no member matches it. Blue and red run slightly
    /// brighter in dark mode, where the stock system colors read too dark.
    private func fillColor(for boundary: MapBoundary) -> Color {
        guard let party = partyByDistrictCache[Self.districtKey(state: boundary.state, district: boundary.district)] else {
            return .clear
        }
        return DistrictMapPalette.color(for: party, dark: colorScheme == .dark)
    }

    /// The boundary matching a representative's state and district, if loaded.
    private func districtBoundary(for rep: Representative) -> MapBoundary? {
        let key = Self.districtKey(state: rep.state, district: rep.district)
        return districtBoundaries.first { Self.districtKey(state: $0.state, district: $0.district) == key }
    }

    /// The boundary of the user's own district, i.e. their House member's
    /// district — `mappable` only ever contains the user's own delegation.
    private var userDistrictBoundary: MapBoundary? {
        mappable.first.flatMap(districtBoundary(for:))
    }

    /// The region the recenter button (and initial auto-center) targets:
    /// framing the user's whole district, falling back to a metro-wide box.
    private var recenterRegion: MKCoordinateRegion? {
        if let boundary = userDistrictBoundary {
            return region(for: boundary)
        }
        if let userCoordinate {
            return wideRegion(centeredOn: userCoordinate)
        }
        return nil
    }

    /// A region tightly framing a district's full extent, with a little padding.
    private func region(for boundary: MapBoundary) -> MKCoordinateRegion {
        let points = boundary.rings.flatMap { $0 }
        guard let minLat = points.map(\.latitude).min(),
              let maxLat = points.map(\.latitude).max(),
              let minLon = points.map(\.longitude).min(),
              let maxLon = points.map(\.longitude).max()
        else {
            return MKCoordinateRegion(
                center: boundary.centroid,
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.3),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.3)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// A coarse, roughly metro-area-wide region around a coordinate.
    private func wideRegion(centeredOn coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
        )
    }

    /// Frames the user's district the first time both their representative and
    /// the district geometry are available, so the map settles on home. Only
    /// fires once — after that, the user's own panning takes over.
    private func centerOnUserDistrictIfNeeded() {
        guard !hasCenteredOnUserDistrict, userDistrictBoundary != nil else { return }
        hasCenteredOnUserDistrict = true
        isCenteredOnUserDistrict = true
        recenterTrigger += 1
    }

    /// Recenters on the user's district — framing the whole district rather than
    /// zooming to their exact position, since the district is what's relevant.
    private var recenterButton: some View {
        Button {
            isCenteredOnUserDistrict = true
            recenterTrigger += 1
        } label: {
            Image(systemName: isCenteredOnUserDistrict ? "location.fill" : "location")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 38, height: 38)
        }
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.2), value: isCenteredOnUserDistrict)
    }

    /// The House member who represents a given district, if any is on file.
    private func representative(for boundary: MapBoundary) -> Representative? {
        let key = Self.districtKey(state: boundary.state, district: boundary.district)
        return nationalHouseDirectory.members.first { Self.districtKey(state: $0.state, district: $0.district) == key }
    }
}

/// Party fill colors, shared between the map overlays and the detail sheets so
/// the swatch on a district's sheet matches its fill on the map.
enum DistrictMapPalette {
    static func color(for party: Party, dark: Bool) -> Color {
        guard dark else { return party.color }
        switch party {
        case .democrat: return Color(red: 0.40, green: 0.66, blue: 1.0)
        case .republican: return Color(red: 1.0, green: 0.40, blue: 0.38)
        case .independent: return party.color
        }
    }
}

#if canImport(UIKit)

// MARK: - MKMapView bridge

/// Wraps an `MKMapView` and feeds it the district/state geometry as overlays.
/// The heavy lifting (culling, tiling, redraw) is MapKit's; this type only
/// rebuilds overlays when the underlying data actually changes and nudges the
/// crossfade + camera in `updateUIView`.
struct DistrictMapRepresentable: UIViewRepresentable {
    let districtBoundaries: [MapBoundary]
    let stateBoundaries: [MapBoundary]
    let partyByDistrict: [String: Party]
    let mappable: [Representative]
    let colorSchemeIsDark: Bool
    let initialRegion: MKCoordinateRegion?
    let recenterRegion: MKCoordinateRegion?
    let recenterTrigger: Int
    @Binding var selectedDistrict: MapBoundary?
    @Binding var selectedState: MapBoundary?
    @Binding var isCentered: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        let config = MKStandardMapConfiguration(emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        mapView.preferredConfiguration = config

        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.setCameraBoundary(
            MKMapView.CameraBoundary(coordinateRegion: DistrictMapView.cameraBoundsRegion),
            animated: false
        )
        mapView.setCameraZoomRange(
            MKMapView.CameraZoomRange(maxCenterCoordinateDistance: DistrictMapView.maxCenterDistance),
            animated: false
        )

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.hostMapView = mapView

        // Rebuild the polygon overlays only when the geometry, party roster, or
        // color scheme changes — never on a camera move.
        let overlaySignature = "\(districtBoundaries.count)-\(stateBoundaries.count)-\(partyByDistrict.count)-\(colorSchemeIsDark)"
        if overlaySignature != coordinator.overlaySignature {
            coordinator.overlaySignature = overlaySignature
            coordinator.rebuildOverlays(on: mapView)
        }

        // Rebuild annotations only when the pinned members change.
        let annotationSignature = "\(mappable.count)-\(districtBoundaries.count)-\(stateBoundaries.count)"
        if annotationSignature != coordinator.annotationSignature {
            coordinator.annotationSignature = annotationSignature
            coordinator.rebuildAnnotations(on: mapView)
        }

        if let initialRegion, !coordinator.didApplyInitialRegion {
            coordinator.didApplyInitialRegion = true
            mapView.setRegion(initialRegion, animated: false)
        }

        if recenterTrigger != coordinator.lastRecenterTrigger {
            coordinator.lastRecenterTrigger = recenterTrigger
            if let recenterRegion {
                mapView.setRegion(recenterRegion, animated: true)
            }
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: DistrictMapRepresentable

        // Change-tracking so `updateUIView` only does real work when needed.
        var overlaySignature = ""
        var annotationSignature = ""
        var didApplyInitialRegion = false
        var lastRecenterTrigger = 0

        /// 0 at district-level zoom, 1 once fully zoomed out to state level.
        private var progress: Double = 0
        private static let stateLevelLowerSpan: Double = 20.0
        private static let stateLevelUpperSpan: Double = 22.0

        /// Roles keyed by overlay identity, so `rendererFor` knows how to style
        /// each overlay MapKit asks it to draw.
        private enum Role {
            case fill(Party)
            case stateOutline
        }
        private var overlayRoles: [ObjectIdentifier: Role] = [:]
        private var renderers: [ObjectIdentifier: MKOverlayRenderer] = [:]
        /// Renderers whose alpha tracks the district layer (fade out on zoom-out).
        private var districtFadeRenderers: [MKOverlayRenderer] = []
        /// Renderers whose alpha tracks the flag layer (fade *in* on zoom-out).
        private var flagFadeRenderers: [MKOverlayRenderer] = []
        /// Pre-clipped flag bitmaps keyed by state, kept so they survive an overlay
        /// rebuild (color-scheme change) without re-clipping.
        private var clippedFlags: [String: ClippedFlag] = [:]
        /// Each state's flag as a live map overlay, so it's projected by MapKit
        /// exactly like the district and state-border polygons — glued to the map,
        /// no wobble. Kept keyed by state so a color-scheme rebuild can re-add them.
        private var flagOverlays: [String: FlagOverlay] = [:]
        fileprivate weak var hostMapView: MKMapView?
        private var loadingFlagStates: Set<String> = []
        private var didPrefetchFlags = false

        /// Retained SwiftUI hosts for the portrait pins, keyed by annotation, so
        /// the hosting controllers outlive `viewFor` and aren't deallocated.
        private var hostingControllers: [ObjectIdentifier: UIViewController] = [:]

        init(_ parent: DistrictMapRepresentable) {
            self.parent = parent
        }

        // MARK: Overlays

        func rebuildOverlays(on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)
            overlayRoles.removeAll()
            renderers.removeAll()
            districtFadeRenderers.removeAll()
            flagFadeRenderers.removeAll()
            flagOverlays.removeAll()

            // District fills grouped by party — three multipolygons instead of
            // ~435 individual overlays.
            // District fills grouped by party. Each district's thin outline is drawn
            // by the fill renderer's stroke (below) rather than a separate 435-polygon
            // overlay — one fewer heavy per-tile draw pass, so tiles fill in faster
            // while panning.
            let tolerance = Self.overlaySimplifyTolerance
            var byParty: [Party: [MKPolygon]] = [:]
            for boundary in parent.districtBoundaries {
                guard let party = parent.partyByDistrict[
                    DistrictMapView.districtKey(state: boundary.state, district: boundary.district)
                ] else { continue }
                byParty[party, default: []].append(contentsOf: Self.polygons(for: boundary, simplifyTolerance: tolerance))
            }
            for (party, polygons) in byParty where !polygons.isEmpty {
                let overlay = MKMultiPolygon(polygons)
                overlayRoles[ObjectIdentifier(overlay)] = .fill(party)
                mapView.addOverlay(overlay, level: .aboveLabels)
            }

            // Re-add the flag overlays (below the state border, above the fills) so
            // they survive a color-scheme rebuild. Each is a `.aboveRoads` overlay
            // while everything else is `.aboveLabels`, so the state borders always
            // draw over the flags.
            for (state, flag) in clippedFlags {
                addFlagOverlay(flag, for: state, on: mapView)
            }

            // Heavier state outline, on top and always visible at both zooms — a
            // MapKit overlay, so it's projected with the map and never wobbles.
            let statePolygons = parent.stateBoundaries.flatMap {
                Self.polygons(for: $0, simplifyTolerance: tolerance)
            }
            if !statePolygons.isEmpty {
                let overlay = MKMultiPolygon(statePolygons)
                overlayRoles[ObjectIdentifier(overlay)] = .stateOutline
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
        }

        /// Tolerance (in degrees) for simplifying the boundary rings used for the
        /// map overlays — enough to strip the dense, near-collinear vertices in the
        /// Census data that make per-tile drawing slow, while staying crisp even at
        /// district-level zoom. Hit-testing and the detail-sheet thumbnails keep the
        /// full-resolution rings; only the drawn overlays are simplified.
        private static let overlaySimplifyTolerance: Double = 0.005

        /// Builds the MapKit polygons for a boundary, optionally simplifying each
        /// ring (Douglas–Peucker) to cut vertex count. Flags pass tolerance 0 so
        /// their one-time clip stays sharp; the districts/states simplify.
        nonisolated private static func polygons(for boundary: MapBoundary, simplifyTolerance: Double = 0) -> [MKPolygon] {
            boundary.rings.compactMap { ring in
                guard ring.count > 2 else { return nil }
                let points = simplifyTolerance > 0 ? simplify(ring, tolerance: simplifyTolerance) : ring
                guard points.count > 2 else { return nil }
                return MKPolygon(coordinates: points, count: points.count)
            }
        }

        /// Douglas–Peucker simplification of a coordinate ring. Longitude/latitude
        /// are treated as planar here — fine at these tolerances for thinning
        /// vertices. Endpoints are always kept.
        nonisolated private static func simplify(_ points: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
            guard points.count > 2 else { return points }
            let end = points.count - 1
            var dmax = 0.0
            var index = 0
            for i in 1..<end {
                let d = perpendicularDistance(points[i], lineStart: points[0], lineEnd: points[end])
                if d > dmax { index = i; dmax = d }
            }
            if dmax > tolerance {
                let left = simplify(Array(points[0...index]), tolerance: tolerance)
                let right = simplify(Array(points[index...end]), tolerance: tolerance)
                return left.dropLast() + right
            }
            return [points[0], points[end]]
        }

        nonisolated private static func perpendicularDistance(
            _ point: CLLocationCoordinate2D,
            lineStart: CLLocationCoordinate2D,
            lineEnd: CLLocationCoordinate2D
        ) -> Double {
            let dx = lineEnd.longitude - lineStart.longitude
            let dy = lineEnd.latitude - lineStart.latitude
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else {
                let px = point.longitude - lineStart.longitude
                let py = point.latitude - lineStart.latitude
                return (px * px + py * py).squareRoot()
            }
            let numerator = abs(
                dy * point.longitude - dx * point.latitude
                    + lineEnd.longitude * lineStart.latitude
                    - lineEnd.latitude * lineStart.longitude
            )
            return numerator / lengthSquared.squareRoot()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let oid = ObjectIdentifier(overlay)
            if let existing = renderers[oid] { return existing }

            // Flags are their own overlay type: a renderer that draws the state's
            // pre-clipped bitmap. Its alpha fades in as the map zooms out.
            if let flagOverlay = overlay as? FlagOverlay {
                let r = FlagOverlayRenderer(flagOverlay: flagOverlay)
                r.alpha = CGFloat(progress)
                renderers[oid] = r
                flagFadeRenderers.append(r)
                return r
            }

            guard let role = overlayRoles[oid] else { return MKOverlayRenderer(overlay: overlay) }

            let renderer: MKOverlayRenderer
            switch role {
            case .fill(let party):
                let r = MKMultiPolygonRenderer(multiPolygon: overlay as! MKMultiPolygon)
                r.fillColor = Self.partyUIColor(party, dark: parent.colorSchemeIsDark).withAlphaComponent(0.4)
                // The per-district outline is this renderer's stroke, so there's no
                // separate outline overlay to redraw per tile.
                r.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.5)
                r.lineWidth = 1
                r.alpha = CGFloat(1 - progress)
                districtFadeRenderers.append(r)
                renderer = r
            case .stateOutline:
                let r = MKMultiPolygonRenderer(multiPolygon: overlay as! MKMultiPolygon)
                r.fillColor = nil
                r.strokeColor = UIColor.label.withAlphaComponent(0.85)
                r.lineWidth = 2
                r.alpha = 1
                renderer = r
            }
            renderers[oid] = renderer
            return renderer
        }

        private static func partyUIColor(_ party: Party, dark: Bool) -> UIColor {
            UIColor(DistrictMapPalette.color(for: party, dark: dark))
        }

        // MARK: Flag loading

        /// Kicks off loading every state's flag at once. Called when the map
        /// first enters state-level zoom so all flags are fetched (and cached)
        /// concurrently up front, rather than each one waiting until its state
        /// scrolls into view and only then starting a fresh network fetch — the
        /// latter is what made flags lag in over several seconds while panning.
        private func prefetchFlags() {
            guard !didPrefetchFlags, !parent.stateBoundaries.isEmpty else { return }
            didPrefetchFlags = true
            for boundary in parent.stateBoundaries {
                loadFlagIfNeeded(for: boundary)
            }
        }

        /// Bitmap resolution for each state's pre-clipped flag, sized by the state's
        /// geographic extent so every flag has consistent on-screen sharpness rather
        /// than a fixed longest edge (which made large states upscale and look
        /// blocky while tiny states were over-sampled). Kept modest so each flag
        /// tile blits fast — large bitmaps are the main cost that leaves flags
        /// un-rendered when panning quickly.
        private static let flagPixelsPerMapPoint: CGFloat = 1.0e-4
        private static let flagMaxPixelDimension: CGFloat = 768

        private func loadFlagIfNeeded(for boundary: MapBoundary) {
            let state = boundary.state
            guard clippedFlags[state] == nil, !loadingFlagStates.contains(state) else { return }
            loadingFlagStates.insert(state)
            Task { @MainActor in
                defer { loadingFlagStates.remove(state) }
                guard let flag = await Self.loadClippedFlag(for: boundary) else { return }
                clippedFlags[state] = flag
                if let mapView = hostMapView {
                    addFlagOverlay(flag, for: state, on: mapView)
                }
            }
        }

        /// Loads a state's flag — bundled asset preferred, network the fallback —
        /// and rasterizes it clipped to the state's outline, entirely off the main
        /// thread. The single rasterization both downsamples and clips, so the flag
        /// layer's `contents` is a finished bitmap the GPU composites directly.
        private static func loadClippedFlag(for boundary: MapBoundary) async -> ClippedFlag? {
            let state = boundary.state
            let maxDimension = flagMaxPixelDimension
            // Bundled path: look up and clip entirely off the main thread.
            if let flag = await Task.detached(priority: .userInitiated, operation: {
                () -> ClippedFlag? in
                guard let image = StateFlagDirectory.bundledImage(forState: state) else { return nil }
                return Self.clippedFlag(for: boundary, flag: image, maxPixelDimension: maxDimension)
            }).value {
                return flag
            }
            // Network fallback for any state without a bundled flag.
            guard let url = StateFlagDirectory.flagURL(forState: state),
                  let image = await ImageCache.shared.image(for: url) else { return nil }
            return await Task.detached(priority: .userInitiated) {
                Self.clippedFlag(for: boundary, flag: image, maxPixelDimension: maxDimension)
            }.value
        }

        /// Rasterizes `flag` aspect-filled and clipped to `boundary`'s outline into
        /// a single premultiplied bitmap sized to the state's bounding box (longest
        /// edge `maxPixelDimension`). Runs once per state, off the main thread, so
        /// the layer's `contents` is a finished, upright bitmap. Returns it paired
        /// with its bounding `MKMapRect` for positioning on the map.
        nonisolated private static func clippedFlag(for boundary: MapBoundary, flag: PlatformImage, maxPixelDimension: CGFloat) -> ClippedFlag? {
            let polys = polygons(for: boundary)
            guard !polys.isEmpty else { return nil }

            // Bounding rect from the raw points. Alaska crosses the antimeridian —
            // its Aleutians sit near the east edge of MKMapPoint space while the
            // mainland is far west — so a naive union spans almost the whole globe.
            // Detect that (span > half the world) and re-map the wrapped points to
            // negative x so the state stays contiguous.
            let worldWidth = MKMapRect.world.size.width
            var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
            var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
            for polygon in polys {
                let r = polygon.boundingMapRect
                minX = min(minX, r.minX); maxX = max(maxX, r.maxX)
                minY = min(minY, r.minY); maxY = max(maxY, r.maxY)
            }
            let wraps = (maxX - minX) > worldWidth / 2
            if wraps {
                minX = .greatestFiniteMagnitude; maxX = -Double.greatestFiniteMagnitude
                for polygon in polys {
                    let pts = polygon.points()
                    for i in 0..<polygon.pointCount {
                        let x = pts[i].x > worldWidth / 2 ? pts[i].x - worldWidth : pts[i].x
                        minX = min(minX, x); maxX = max(maxX, x)
                    }
                }
            }
            let bounding = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            let mapW = bounding.size.width, mapH = bounding.size.height
            guard mapW > 0, mapH > 0 else { return nil }

            // Density-based, but never larger than the cap for a huge state.
            let scale = min(Self.flagPixelsPerMapPoint, maxPixelDimension / max(mapW, mapH))
            let pxW = max(1, CGFloat((mapW * scale).rounded()))
            let pxH = max(1, CGFloat((mapH * scale).rounded()))

            // Clip path in the bitmap's top-left-origin space. MKMapPoint y grows
            // southward — the same direction as the bitmap's y — so the flag comes
            // out upright.
            let path = CGMutablePath()
            for polygon in polys {
                let count = polygon.pointCount
                guard count > 2 else { continue }
                let mapPoints = polygon.points()
                var bitmapPoints = [CGPoint]()
                bitmapPoints.reserveCapacity(count)
                for i in 0..<count {
                    let mp = mapPoints[i]
                    let x = (wraps && mp.x > worldWidth / 2) ? mp.x - worldWidth : mp.x
                    bitmapPoints.append(CGPoint(
                        x: (x - bounding.minX) / mapW * Double(pxW),
                        y: (mp.y - bounding.minY) / mapH * Double(pxH)
                    ))
                }
                path.addLines(between: bitmapPoints)
                path.closeSubpath()
            }

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let bitmap = UIGraphicsImageRenderer(size: CGSize(width: pxW, height: pxH), format: format).image { ctx in
                let cg = ctx.cgContext
                cg.addPath(path)
                cg.clip()
                // Aspect-fill the flag into the bounding box.
                let iw = flag.size.width, ih = flag.size.height
                guard iw > 0, ih > 0 else { return }
                let fill = max(pxW / iw, pxH / ih)
                let drawSize = CGSize(width: iw * fill, height: ih * fill)
                flag.draw(in: CGRect(
                    x: (pxW - drawSize.width) / 2,
                    y: (pxH - drawSize.height) / 2,
                    width: drawSize.width,
                    height: drawSize.height
                ))
            }
            guard let cgImage = bitmap.cgImage else { return nil }
            return ClippedFlag(mapRect: bounding, image: cgImage)
        }

        // MARK: Flag overlays

        /// Adds (or replaces) a state's flag as a map overlay. It's placed at the
        /// `.aboveRoads` level while the fills, district outlines, and state border
        /// all sit at `.aboveLabels`, so the flag draws above the base map but below
        /// the black state border — the border reads as the seam between flags. The
        /// renderer's alpha (set in `updateProgress`) is the crossfade.
        private func addFlagOverlay(_ flag: ClippedFlag, for state: String, on mapView: MKMapView) {
            if let existing = flagOverlays[state] {
                renderers.removeValue(forKey: ObjectIdentifier(existing))
                mapView.removeOverlay(existing)
            }
            let overlay = FlagOverlay(flag: flag, state: state)
            flagOverlays[state] = overlay
            mapView.addOverlay(overlay, level: .aboveRoads)
        }

        // MARK: Annotations

        func rebuildAnnotations(on mapView: MKMapView) {
            let stale = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(stale)
            hostingControllers.removeAll()

            // The user's own House delegation, pinned at the district's middle.
            for rep in parent.mappable {
                guard let boundary = parent.districtBoundaries.first(where: {
                    DistrictMapView.districtKey(state: $0.state, district: $0.district)
                        == DistrictMapView.districtKey(state: rep.state, district: rep.district)
                }) else { continue }
                mapView.addAnnotation(RepresentativeAnnotation(representative: rep, coordinate: boundary.centroid))
            }

            // Governors, pinned at each state's middle (shown when zoomed out).
            for boundary in parent.stateBoundaries {
                if let governor = GovernorDirectory.governor(forState: boundary.state) {
                    mapView.addAnnotation(GovernorAnnotation(governor: governor, coordinate: boundary.centroid))
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let rep = annotation as? RepresentativeAnnotation {
                return portraitView(
                    for: annotation, on: mapView, alpha: CGFloat(1 - progress),
                    content: AnyView(RepresentativePortrait(representative: rep.representative, size: 40, style: .outline))
                )
            }
            if let gov = annotation as? GovernorAnnotation {
                return portraitView(
                    for: annotation, on: mapView, alpha: CGFloat(progress),
                    content: AnyView(GovernorPortrait(governor: gov.governor, size: 40, style: .outline))
                )
            }
            return nil
        }

        private func portraitView(for annotation: MKAnnotation, on mapView: MKMapView, alpha: CGFloat, content: AnyView) -> MKAnnotationView {
            let identifier = "portrait"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.subviews.forEach { $0.removeFromSuperview() }

            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
            view.frame = host.view.frame
            view.centerOffset = .zero
            view.addSubview(host.view)
            view.alpha = alpha
            hostingControllers[ObjectIdentifier(annotation)] = host
            return view
        }

        // MARK: Camera / crossfade

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateProgress(for: mapView.region, on: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateProgress(for: mapView.region, on: mapView)
            updateCenteredState(for: mapView.region)
        }

        /// Recomputes the district↔state crossfade from the visible latitude
        /// span and pushes the new alpha to the (cheap, scalar) renderer and
        /// annotation properties — no geometry is rebuilt.
        private func updateProgress(for region: MKCoordinateRegion, on mapView: MKMapView) {
            let span = region.span.latitudeDelta
            // NOTE: State-flag transition disabled for now — will reapproach in a
            // later update. Skipping the prefetch keeps flags from being fetched
            // and clipped while the fade-in below is commented out.
            // Start fetching every flag well before the crossfade begins, so
            // they're cached by the time they'd fade in.
            // if span > Self.stateLevelLowerSpan * 0.5 {
            //     prefetchFlags()
            // }
            let newProgress: Double
            if span <= Self.stateLevelLowerSpan {
                newProgress = 0
            } else if span >= Self.stateLevelUpperSpan {
                newProgress = 1
            } else {
                newProgress = (span - Self.stateLevelLowerSpan) / (Self.stateLevelUpperSpan - Self.stateLevelLowerSpan)
            }
            guard abs(newProgress - progress) > 0.001 else { return }
            progress = newProgress

            for renderer in districtFadeRenderers {
                renderer.alpha = CGFloat(1 - progress)
            }
            // NOTE: State-flag fade-in disabled for now — will reapproach in a
            // later update. Keeping the flag renderers at their default alpha means
            // no flags composite in as the district layer fades out.
            // Fade the flags in as the district layer fades out. Setting a
            // renderer's alpha composites its layer — no redraw, no re-clip — the
            // same cheap crossfade the district overlays use.
            // for renderer in flagFadeRenderers {
            //     renderer.alpha = CGFloat(progress)
            // }
            for annotation in mapView.annotations {
                guard let view = mapView.view(for: annotation) else { continue }
                if annotation is RepresentativeAnnotation {
                    view.alpha = CGFloat(1 - progress)
                } else if annotation is GovernorAnnotation {
                    view.alpha = CGFloat(progress)
                }
            }
        }

        /// Keeps the recenter button's icon in sync with whether the camera is
        /// still roughly framing the user's district.
        private func updateCenteredState(for region: MKCoordinateRegion) {
            guard let target = parent.recenterRegion else { return }
            let latTolerance = target.span.latitudeDelta * 0.25
            let lonTolerance = target.span.longitudeDelta * 0.25
            let centered = abs(region.center.latitude - target.center.latitude) < latTolerance
                && abs(region.center.longitude - target.center.longitude) < lonTolerance
            if centered != parent.isCentered {
                parent.isCentered = centered
            }
        }

        // MARK: Tap handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            // Past the midpoint of the crossfade, states read as the tappable
            // layer — so route the tap to whichever layer is legible now.
            if progress > 0.5 {
                parent.selectedState = parent.stateBoundaries.first { $0.contains(coordinate) }
            } else {
                parent.selectedDistrict = parent.districtBoundaries.first { $0.contains(coordinate) }
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// A pin for one of the user's House representatives.
final class RepresentativeAnnotation: NSObject, MKAnnotation {
    let representative: Representative
    let coordinate: CLLocationCoordinate2D
    var title: String? { representative.name }

    init(representative: Representative, coordinate: CLLocationCoordinate2D) {
        self.representative = representative
        self.coordinate = coordinate
    }
}

/// A pin for a state's governor, shown when zoomed out to state level.
final class GovernorAnnotation: NSObject, MKAnnotation {
    let governor: Governor
    let coordinate: CLLocationCoordinate2D
    var title: String? { governor.name }

    init(governor: Governor, coordinate: CLLocationCoordinate2D) {
        self.governor = governor
        self.coordinate = coordinate
    }
}

/// One state's flag, pre-clipped to its outline (see `Coordinator.clippedFlag`),
/// positioned by its bounding rect in map space. Drawn on the map by a
/// `FlagOverlayRenderer`.
struct ClippedFlag {
    let mapRect: MKMapRect
    let image: CGImage
}

/// A state's pre-clipped flag as a map overlay, so MapKit projects it exactly
/// like the district and border polygons — glued to the map with no wobble.
final class FlagOverlay: NSObject, MKOverlay {
    let state: String
    let image: CGImage
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(flag: ClippedFlag, state: String) {
        self.state = state
        self.image = flag.image
        self.boundingMapRect = flag.mapRect
        self.coordinate = MKMapPoint(x: flag.mapRect.midX, y: flag.mapRect.midY).coordinate
    }
}

/// Draws a `FlagOverlay`'s bitmap across its bounding rect. The bitmap is already
/// clipped to the state's outline and oriented in map space (y grows south), so
/// we only flip for Core Graphics' bottom-up context. Drawing the whole image at
/// its full rect in every tile keeps edges pixel-aligned, so there are no seams.
final class FlagOverlayRenderer: MKOverlayRenderer {
    private let image: CGImage

    init(flagOverlay: FlagOverlay) {
        self.image = flagOverlay.image
        super.init(overlay: flagOverlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let rect = self.rect(for: overlay.boundingMapRect)
        context.saveGState()
        // Default (not .high) interpolation: it's markedly cheaper per tile, so
        // flags render fast enough to keep up with quick panning. Drawing the whole
        // image at its full rect in every tile keeps edges pixel-identical across
        // tiles.
        context.interpolationQuality = .default
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }
}

#endif

/// The sheet shown when a district is tapped: its name beside a copy of its
/// outline, with the district's representative underneath.
private struct DistrictDetailSheet: View {
    let boundary: MapBoundary
    let color: Color
    let representative: Representative?
    let populationDirectory: DistrictPopulationDirectory
    let industryDirectory: DistrictIndustryDirectory
    let cityDirectory: DistrictCityDirectory
    let universityDirectory: DistrictUniversityDirectory

    private var population: Int? {
        populationDirectory.cachedPopulation(state: boundary.state, district: boundary.district ?? 0)
    }

    private var topIndustries: [String]? {
        industryDirectory.cachedTopIndustries(state: boundary.state, district: boundary.district ?? 0)
    }

    private var topCities: [String]? {
        cityDirectory.cachedTopCities(state: boundary.state, district: boundary.district ?? 0)
    }

    private var topUniversities: [String]? {
        universityDirectory.cachedTopUniversities(state: boundary.state, district: boundary.district ?? 0)
    }

    private static let populationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(boundary.displayName)
                            .font(.title2.bold())
                        if let population {
                            Text("Population: \(Self.populationFormatter.string(from: NSNumber(value: population)) ?? "\(population)")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    DistrictOutlineShape(rings: boundary.rings)
                        .fill(color.opacity(0.3))
                        .overlay(DistrictOutlineShape(rings: boundary.rings).stroke(color, lineWidth: 1.5))
                        .frame(width: 80, height: 80)
                }
                .task {
                    await populationDirectory.loadIfNeeded(state: boundary.state, district: boundary.district ?? 0)
                    await industryDirectory.loadIfNeeded(state: boundary.state, district: boundary.district ?? 0)
                    await cityDirectory.loadIfNeeded(boundary: boundary)
                    await universityDirectory.loadIfNeeded(boundary: boundary)
                }

                if let topIndustries, !topIndustries.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top Industries")
                            .font(.subheadline.bold())
                        ForEach(topIndustries, id: \.self) { industry in
                            Text(industry)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let topCities, !topCities.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top Cities")
                            .font(.subheadline.bold())
                        ForEach(topCities, id: \.self) { city in
                            Text(city)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let topUniversities, !topUniversities.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top Universities")
                            .font(.subheadline.bold())
                        ForEach(topUniversities, id: \.self) { university in
                            Text(university)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                if let representative {
                    NavigationLink(value: representative) {
                        RepresentativeRow(representative: representative)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("No representative currently on file for this district.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .padding(.top, 16)
            .navigationDestination(for: Representative.self) { rep in
                RepresentativeDetailView(representative: rep)
            }
        }
    }
}

/// The sheet shown when a state is tapped at state-level zoom: its name beside a
/// copy of its outline filled with its flag.
private struct StateDetailSheet: View {
    let boundary: MapBoundary
    let senators: [Representative]
    let representatives: [Representative]
    let populationDirectory: StatePopulationDirectory
    let industryDirectory: StateIndustryDirectory
    let cityDirectory: StateCityDirectory
    let universityDirectory: StateUniversityDirectory

    private var governor: Governor? {
        GovernorDirectory.governor(forState: boundary.state)
    }

    private var population: Int? {
        populationDirectory.cachedPopulation(state: boundary.state)
    }

    private var topIndustries: [String]? {
        industryDirectory.cachedTopIndustries(state: boundary.state)
    }

    private var topCities: [String]? {
        cityDirectory.cachedTopCities(state: boundary.state)
    }

    private var topUniversities: [String]? {
        universityDirectory.cachedTopUniversities(state: boundary.state)
    }

    private static let populationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(MapBoundary.stateName(for: boundary.state))
                                .font(.title2.bold())
                            if let population {
                                Text("Population: \(Self.populationFormatter.string(from: NSNumber(value: population)) ?? "\(population)")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        StateFlagImage(state: boundary.state)
                            .frame(width: 90, height: 90)
                            .clipShape(DistrictOutlineShape(rings: boundary.rings))
                            .overlay(
                                DistrictOutlineShape(rings: boundary.rings)
                                    .stroke(.primary.opacity(0.85), lineWidth: 1.5)
                            )
                    }
                    .task {
                        await populationDirectory.loadIfNeeded(state: boundary.state)
                        await industryDirectory.loadIfNeeded(state: boundary.state)
                        await cityDirectory.loadIfNeeded(state: boundary.state)
                        await universityDirectory.loadIfNeeded(state: boundary.state)
                    }

                    if let topIndustries, !topIndustries.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top Industries")
                                .font(.subheadline.bold())
                            ForEach(topIndustries, id: \.self) { industry in
                                Text(industry)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let topCities, !topCities.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top Cities")
                                .font(.subheadline.bold())
                            ForEach(topCities, id: \.self) { city in
                                Text(city)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let topUniversities, !topUniversities.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top Universities")
                                .font(.subheadline.bold())
                            ForEach(topUniversities, id: \.self) { university in
                                Text(university)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let governor {
                        Divider()

                        NavigationLink(value: governor) {
                            GovernorRow(governor: governor)
                        }
                        .buttonStyle(.plain)
                    }

                    if !senators.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(senators.indices, id: \.self) { index in
                                NavigationLink(value: senators[index]) {
                                    RepresentativeRow(representative: senators[index])
                                }
                                .buttonStyle(.plain)

                                if index < senators.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }

                    if !representatives.isEmpty {
                        Divider()

                        Text("House Delegation")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(representatives.indices, id: \.self) { index in
                                NavigationLink(value: representatives[index]) {
                                    RepresentativeRow(representative: representatives[index])
                                }
                                .buttonStyle(.plain)

                                if index < representatives.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding()
                .padding(.top, 16)
            }
            .navigationDestination(for: Governor.self) { governor in
                GovernorDetailView(governor: governor)
            }
            .navigationDestination(for: Representative.self) { rep in
                RepresentativeDetailView(representative: rep)
            }
        }
    }
}

/// Draws a district's boundary rings scaled to fit within the shape's rect,
/// preserving aspect ratio — a small "thumbnail" copy of the outline shown on
/// the map.
private struct DistrictOutlineShape: Shape {
    let rings: [[CLLocationCoordinate2D]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = rings.flatMap { $0 }
        guard let minLat = points.map(\.latitude).min(),
              let maxLat = points.map(\.latitude).max(),
              let rawMinLon = points.map(\.longitude).min(),
              let rawMaxLon = points.map(\.longitude).max()
        else { return path }

        // A boundary that crosses the antimeridian (e.g. Alaska, whose Aleutian
        // Islands run past 180° into positive longitude) has points on both
        // sides of the ±180 seam. Unwrap by shifting negative longitudes up by
        // 360° so the ring reads as one contiguous span.
        let crossesAntimeridian = rawMaxLon - rawMinLon > 180
        func unwrap(_ longitude: Double) -> Double {
            crossesAntimeridian && longitude < 0 ? longitude + 360 : longitude
        }
        let minLon = crossesAntimeridian ? points.map { unwrap($0.longitude) }.min()! : rawMinLon
        let maxLon = crossesAntimeridian ? points.map { unwrap($0.longitude) }.max()! : rawMaxLon

        // A degree of longitude spans less ground than a degree of latitude by a
        // factor of cos(latitude). Without this the outline is stretched
        // east-west and appears squashed vertically.
        let midLat = (minLat + maxLat) / 2
        let lonScale = max(cos(midLat * .pi / 180), .ulpOfOne)

        let latSpan = max(maxLat - minLat, .ulpOfOne)
        let lonSpan = max((maxLon - minLon) * lonScale, .ulpOfOne)
        let scale = min(rect.width / lonSpan, rect.height / latSpan)
        let originX = rect.minX + (rect.width - lonSpan * scale) / 2
        let originY = rect.minY + (rect.height - latSpan * scale) / 2

        func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: originX + (unwrap(coordinate.longitude) - minLon) * lonScale * scale,
                y: originY + (maxLat - coordinate.latitude) * scale
            )
        }

        // Soften only the corners: run straight along each edge until a short
        // distance from the vertex, then a small quad curve around it.
        let cornerCut: CGFloat = 1.5

        for ring in rings {
            let pts = ring.map(point)
            guard pts.count > 2 else {
                if let first = pts.first {
                    path.move(to: first)
                    for p in pts.dropFirst() { path.addLine(to: p) }
                    path.closeSubpath()
                }
                continue
            }

            // A point offset from `from` toward `to`, capped at half the segment
            // length so short edges never overshoot into artifacts.
            func offset(from a: CGPoint, toward b: CGPoint) -> CGPoint {
                let dx = b.x - a.x, dy = b.y - a.y
                let len = (dx * dx + dy * dy).squareRoot()
                guard len > 0 else { return a }
                let d = min(cornerCut, len / 2)
                return CGPoint(x: a.x + dx / len * d, y: a.y + dy / len * d)
            }

            let count = pts.count
            func entry(_ i: Int) -> CGPoint { offset(from: pts[i], toward: pts[(i + count - 1) % count]) }
            func exit(_ i: Int) -> CGPoint { offset(from: pts[i], toward: pts[(i + 1) % count]) }

            path.move(to: entry(0))
            for i in 0..<count {
                path.addQuadCurve(to: exit(i), control: pts[i])
                path.addLine(to: entry((i + 1) % count))
            }
            path.closeSubpath()
        }
        return path
    }
}

#Preview {
    DistrictMapView(representatives: SampleData.representatives, userCoordinate: nil)
}
