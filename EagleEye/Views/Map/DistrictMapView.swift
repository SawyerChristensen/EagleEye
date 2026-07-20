//
//  DistrictMapView.swift
//  EagleEye
//
//  The right "Map" tab: colored congressional-district outlines across the US,
//  fading to governor pins when zoomed out. State flags to be added in a future update
//
//
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
    @State private var showIcons = true
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
    @State private var demographicsDirectory = DistrictDemographicsDirectory()
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
                allRepresentatives: nationalHouseDirectory.members,
                colorSchemeIsDark: colorScheme == .dark,
                initialRegion: initialRegion,
                recenterRegion: recenterRegion,
                recenterTrigger: recenterTrigger,
                showIcons: showIcons,
                selectedDistrict: $selectedDistrict,
                selectedState: $selectedState,
                isCentered: $isCenteredOnUserDistrict
            )
            .ignoresSafeArea()
            // The recenter control lives outside the ignored safe area so it
            // stays clear of the home indicator and nav bar.
            .overlay(alignment: .topTrailing) {
                glassToolbar
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
                // Portraits load on demand: MapKit builds a pin's view only when
                // it scrolls on screen, and CachedAsyncImage fetches then. No bulk
                // prefetch — it just monopolized the shared URLSession's per-host
                // connections and starved the photo the user actually tapped.
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
                    demographicsDirectory: demographicsDirectory,
                    industryDirectory: industryDirectory,
                    cityDirectory: cityDirectory,
                    universityDirectory: universityDirectory
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(.systemBackground))
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

    /// A floating "liquid glass" toolbar for map controls.
    private var glassToolbar: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation { showIcons.toggle() }
            } label: {
                Image(systemName: showIcons ? "person" : "person.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .foregroundStyle(showIcons ? Color.primary : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            
            Divider()
                .frame(height: 16)
            
            Button {
                isCenteredOnUserDistrict = true
                recenterTrigger += 1
            } label: {
                Image(systemName: isCenteredOnUserDistrict ? "location.fill" : "location")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .foregroundStyle(Color.primary) //isCenteredOnUserDistrict ? Color.blue : Color.primary)
            .contentTransition(.symbolEffect(.replace))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial) // Liquid Glass effect
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
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
    let allRepresentatives: [Representative]
    let colorSchemeIsDark: Bool
    let initialRegion: MKCoordinateRegion?
    let recenterRegion: MKCoordinateRegion?
    let recenterTrigger: Int
    let showIcons: Bool
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
        let annotationSignature = "\(allRepresentatives.count)-\(districtBoundaries.count)-\(stateBoundaries.count)"
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
        
        if showIcons != coordinator.lastShowIcons {
            coordinator.lastShowIcons = showIcons
            coordinator.updateAnnotationVisibility(on: mapView)
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
        var lastShowIcons: Bool?
        
        var arePinsVisible: Bool?

        /// Roles keyed by overlay identity, so `rendererFor` knows how to style
        /// each overlay MapKit asks it to draw.
        private enum Role {
            case fill(Party)
            case stateOutline
        }
        private var overlayRoles: [ObjectIdentifier: Role] = [:]
        private var renderers: [ObjectIdentifier: MKOverlayRenderer] = [:]
        
        private var districtPolygonCache: [String: [MKPolygon]] = [:]
        private var statePolygonCache: [MKPolygon] = []
        
        /// Pre-clipped flag bitmaps keyed by state, kept so they survive an overlay
        /// rebuild (color-scheme change) without re-clipping.
        //private var clippedFlags: [String: ClippedFlag] = [:]
        /// Each state's flag as a live map overlay, so it's projected by MapKit
        /// exactly like the district and state-border polygons — glued to the map,
        /// no wobble. Kept keyed by state so a color-scheme rebuild can re-add them.
        //private var flagOverlays: [String: FlagOverlay] = [:]
        fileprivate weak var hostMapView: MKMapView?
        private var loadingFlagStates: Set<String> = []
        private var didPrefetchFlags = false

        init(_ parent: DistrictMapRepresentable) {
            self.parent = parent
        }

        // MARK: Overlays

        func rebuildOverlays(on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)
            overlayRoles.removeAll()
            renderers.removeAll()

            // Border smoothing (Douglas-Peucker simplification) disabled for now:
            // each district's rings are simplified independently, so shared borders
            // with neighbouring districts no longer line up and small districts look
            // off. Restore `Self.overlaySimplifyTolerance` to re-enable it later.
            let tolerance = 0.0 // Self.overlaySimplifyTolerance

            // 1. Cache Geometry if needed (only runs once)
            if districtPolygonCache.isEmpty {
                for boundary in parent.districtBoundaries {
                    let key = DistrictMapView.districtKey(state: boundary.state, district: boundary.district)
                    districtPolygonCache[key] = Self.polygons(for: boundary, simplifyTolerance: tolerance)
                }
                statePolygonCache = parent.stateBoundaries.flatMap {
                    Self.polygons(for: $0, simplifyTolerance: tolerance)
                }
            }

            // 2. Build the MultiPolygons per DISTRICT, not per party
            for boundary in parent.districtBoundaries {
                let key = DistrictMapView.districtKey(state: boundary.state, district: boundary.district)
                guard let party = parent.partyByDistrict[key],
                      let polygons = districtPolygonCache[key],
                      !polygons.isEmpty else { continue }
                
                // Create an overlay specifically for this district
                let overlay = MKMultiPolygon(polygons)
                
                // Track the role (fill color) using the exact same logic you already had
                overlayRoles[ObjectIdentifier(overlay)] = .fill(party)
                mapView.addOverlay(overlay, level: .aboveLabels)
            }

            // 3. Keep state outlines as they are (or separate them by state if you haven't already)
            // Note: It's better to add state borders individually too, rather than one massive country-wide array.
            for boundary in parent.stateBoundaries {
                let polygons = Self.polygons(for: boundary, simplifyTolerance: tolerance)
                guard !polygons.isEmpty else { continue }

                let overlay = MKMultiPolygon(polygons)
                overlayRoles[ObjectIdentifier(overlay)] = .stateOutline
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
        }

        private static let overlaySimplifyTolerance: Double = 0.01

        nonisolated private static func polygons(for boundary: MapBoundary, simplifyTolerance: Double = 0) -> [MKPolygon] {
            boundary.rings.compactMap { ring in
                guard ring.count > 2 else { return nil }
                let points = simplifyTolerance > 0 ? simplify(ring, tolerance: simplifyTolerance) : ring
                guard points.count > 2 else { return nil }
                return MKPolygon(coordinates: points, count: points.count)
            }
        }

        nonisolated private static func simplify(_ points: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
            guard points.count > 2 else { return points }
            let end = points.count - 1
            var dmaxSquared = 0.0
            var index = 0
            
            for i in 1..<end {
                let dSquared = perpendicularDistanceSquared(points[i], lineStart: points[0], lineEnd: points[end])
                if dSquared > dmaxSquared {
                    index = i
                    dmaxSquared = dSquared
                }
            }
            
            // Compare against tolerance squared!
            if dmaxSquared > (tolerance * tolerance) {
                let left = simplify(Array(points[0...index]), tolerance: tolerance)
                let right = simplify(Array(points[index...end]), tolerance: tolerance)
                return left.dropLast() + right
            }
            return [points[0], points[end]]
        }

        nonisolated private static func perpendicularDistanceSquared(
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
                return px * px + py * py
            }
            
            let crossProduct = dy * point.longitude - dx * point.latitude
                             + lineEnd.longitude * lineStart.latitude
                             - lineEnd.latitude * lineStart.longitude
                             
            return (crossProduct * crossProduct) / lengthSquared
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let oid = ObjectIdentifier(overlay)
            if let existing = renderers[oid] { return existing }

            /*if let flagOverlay = overlay as? FlagOverlay {
                let r = FlagOverlayRenderer(flagOverlay: flagOverlay)
                renderers[oid] = r
                return r
            }*/

            guard let role = overlayRoles[oid] else { return MKOverlayRenderer(overlay: overlay) }

            let renderer: MKOverlayRenderer
            switch role {
            case .fill(let party):
                let r = MKMultiPolygonRenderer(multiPolygon: overlay as! MKMultiPolygon)
                r.fillColor = Self.partyUIColor(party, dark: parent.colorSchemeIsDark).withAlphaComponent(0.4)
                r.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.5)
                r.lineWidth = 1
                r.alpha = 1.0 // Permanently fully opaque
                renderer = r
            case .stateOutline:
                let r = MKMultiPolygonRenderer(multiPolygon: overlay as! MKMultiPolygon)
                r.fillColor = nil
                r.strokeColor = UIColor.label.withAlphaComponent(0.85)
                r.lineWidth = 2
                r.alpha = 1.0
                renderer = r
            }
            renderers[oid] = renderer
            return renderer
        }

        private static func partyUIColor(_ party: Party, dark: Bool) -> UIColor {
            UIColor(DistrictMapPalette.color(for: party, dark: dark))
        }

        // MARK: Flag loading
        // (Omitted unchanged flag clipping logic for brevity: loadFlagIfNeeded, clippedFlag, prefetchFlags, loadClippedFlag)

        private static let flagPixelsPerMapPoint: CGFloat = 1.0e-4
        private static let flagMaxPixelDimension: CGFloat = 768
        
        /*private func addFlagOverlay(_ flag: ClippedFlag, for state: String, on mapView: MKMapView) {
            if let existing = flagOverlays[state] {
                renderers.removeValue(forKey: ObjectIdentifier(existing))
                mapView.removeOverlay(existing)
            }
            let overlay = FlagOverlay(flag: flag, state: state)
            flagOverlays[state] = overlay
            mapView.addOverlay(overlay, level: .aboveRoads)
        }*/

        // MARK: Annotations
        func updateAnnotationVisibility(on mapView: MKMapView) {
            let shouldShow = parent.showIcons //&& distance < 2_000_000

            // Only run the animation block if the visibility state actually needs to change
            guard shouldShow != arePinsVisible else { return }
            arePinsVisible = shouldShow

            UIView.animate(withDuration: 0.25) {
                for annotation in mapView.annotations {
                    if annotation is MKUserLocation { continue }
                    mapView.view(for: annotation)?.alpha = shouldShow ? 1.0 : 0.0
                }
            }

            // Now that the pins are visible, kick off the portrait fetches that
            // were deferred while zoomed out.
            if shouldShow {
                for annotation in mapView.annotations where !(annotation is MKUserLocation) {
                    (mapView.view(for: annotation) as? RepresentativePortraitAnnotationView)?.loadImageIfNeeded()
                }
            }
        }

        func rebuildAnnotations(on mapView: MKMapView) {
            let stale = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(stale)

            // The user's own House delegation, pinned at the district's middle.
            for rep in parent.allRepresentatives {
                guard let boundary = parent.districtBoundaries.first(where: {
                    DistrictMapView.districtKey(state: $0.state, district: $0.district)
                        == DistrictMapView.districtKey(state: rep.state, district: rep.district)
                }) else { continue }
                mapView.addAnnotation(RepresentativeAnnotation(representative: rep, coordinate: boundary.centroid))
            }
            // Note: Governors loop removed.
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let rep = annotation as? RepresentativeAnnotation else { return nil }

            let view = mapView.dequeueReusableAnnotationView(withIdentifier: RepresentativePortraitAnnotationView.reuseIdentifier)
                as? RepresentativePortraitAnnotationView
                ?? RepresentativePortraitAnnotationView(annotation: annotation, reuseIdentifier: RepresentativePortraitAnnotationView.reuseIdentifier)
            view.annotation = annotation
            view.configure(with: rep.representative)
            
            let shouldShow = parent.showIcons
            view.alpha = shouldShow ? 1.0 : 0.0
            if shouldShow { view.loadImageIfNeeded() }
            
            return view
            
            /*
            // Only fetch the portrait when the pin is actually visible. When
            // zoomed out the pins are hidden, so loading them just floods the
            // shared URL session with hundreds of requests for photos no one
            // can see — which is what starved every other image load.
            let isZoomedIn = mapView.camera.centerCoordinateDistance < 2_000_000
            view.alpha = isZoomedIn ? 1.0 : 0.0
            if isZoomedIn { view.loadImageIfNeeded() }
            return view*/
        }

        // MARK: Camera

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateCenteredState(for: mapView.region)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateAnnotationVisibility(on: mapView)
        }

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
            
            // Convert the GPS coordinate into a 2D map point for the MKMapRect check
            let tapMapPoint = MKMapPoint(coordinate)
            
            parent.selectedDistrict = parent.districtBoundaries.first { boundary in
                // FAST PATH: Does the tap fall inside the district's rough bounding box?
                // This takes nanoseconds and eliminates ~433 districts immediately.
                guard boundary.boundingBox.contains(tapMapPoint) else {
                    return false
                }
                
                // SLOW PATH: Run the heavy raycasting math only on the 1 or 2
                // districts whose bounding boxes actually encompass the tap.
                return boundary.contains(coordinate)
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

/// The annotation view for a representative pin: a circular portrait with a
/// party-colored ring, falling back to colored initials until (or unless) the
/// photo loads.
///
/// This deliberately renders the portrait with a plain `UIImageView` and loads
/// it directly through `ImageCache`, rather than hosting a SwiftUI
/// `RepresentativePortrait` in a `UIHostingController`. A per-pin hosting
/// controller that's only added as a subview (never parented as a child view
/// controller) has an unreliable SwiftUI lifecycle inside a recycled
/// `MKAnnotationView` — its `.task` may never fire — so the on-demand photo
/// fetch silently never started. Driving the load ourselves sidesteps that and
/// is far lighter across hundreds of pins.
@MainActor
final class RepresentativePortraitAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RepresentativePortrait"
    private static let diameter: CGFloat = 40

    private let placeholderView = UIView()
    private let initialsLabel = UILabel()
    private let imageView = UIImageView()

    /// The portrait to fetch when this pin becomes visible; set by `configure`,
    /// loaded lazily by `loadImageIfNeeded`.
    private var portraitURL: URL?
    /// The in-flight portrait load, cancelled when the view is reused for a
    /// different subject so a slow, stale fetch can't land on the wrong pin.
    private var loadTask: Task<Void, Never>?
    /// The URL a load is currently in flight for, so we don't start a second.
    private var loadingURL: URL?
    /// The URL the current image was loaded for, so a reuse for the same subject
    /// keeps the photo instead of flashing back to the placeholder.
    private var loadedURL: URL?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        frame = bounds
        backgroundColor = .clear
        centerOffset = .zero

        // Placeholder: a party-colored circle with white initials.
        placeholderView.frame = bounds
        placeholderView.layer.cornerRadius = Self.diameter / 2
        placeholderView.clipsToBounds = true
        placeholderView.layer.borderWidth = 3
        addSubview(placeholderView)

        initialsLabel.frame = bounds
        initialsLabel.textAlignment = .center
        initialsLabel.textColor = .white
        initialsLabel.font = .systemFont(ofSize: Self.diameter * 0.34, weight: .semibold)
        placeholderView.addSubview(initialsLabel)

        // Portrait, clipped to a circle with the same party-colored ring.
        imageView.frame = bounds
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Self.diameter / 2
        imageView.layer.borderWidth = 3
        imageView.isHidden = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Points the view at `representative`: applies its party color/initials and
    /// records the portrait to load. The photo itself is fetched lazily by
    /// `loadImageIfNeeded` once the pin is actually visible, so panning across a
    /// zoomed-out map (where hundreds of pins exist but are hidden) doesn't fire
    /// hundreds of simultaneous downloads and starve the shared URL session.
    /// Safe to call on a recycled view.
    func configure(with representative: Representative) {
        let ringColor = UIColor(representative.party.color).withAlphaComponent(0.6).cgColor
        placeholderView.backgroundColor = UIColor(representative.party.color)
        placeholderView.layer.borderColor = ringColor
        imageView.layer.borderColor = ringColor
        initialsLabel.text = Self.initials(for: representative.name)

        let url = representative.portraitURL
        // Reused for the same subject — keep whatever's loaded or in flight.
        if url == portraitURL { return }

        // Different subject: reset and wait for the next `loadImageIfNeeded`.
        loadTask?.cancel()
        loadTask = nil
        portraitURL = url
        loadingURL = nil
        loadedURL = nil
        imageView.image = nil
        showPlaceholder()
    }

    /// Starts the portrait fetch if the pin has a portrait it hasn't already
    /// loaded or begun loading. Called when the pin becomes visible.
    func loadImageIfNeeded() {
        guard let url = portraitURL, loadedURL != url, loadingURL != url else { return }
        loadingURL = url
        loadTask = Task { [weak self] in
            let image = await ImageCache.shared.image(for: url)
            guard let self, !Task.isCancelled, self.portraitURL == url else { return }
            if let image {
                self.imageView.image = image
                self.loadedURL = url
                self.showImage()
            }
            if self.loadingURL == url { self.loadingURL = nil }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        portraitURL = nil
        loadingURL = nil
        loadedURL = nil
        imageView.image = nil
        showPlaceholder()
    }

    private func showImage() {
        imageView.isHidden = false
        placeholderView.isHidden = true
    }

    private func showPlaceholder() {
        imageView.isHidden = true
        placeholderView.isHidden = false
    }

    /// The first letter of up to the first two words of `name`, e.g. "JD".
    private static func initials(for name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }
}
/*
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
}*/

#endif

/// The sheet shown when a district is tapped: its name beside a copy of its
/// Renders one `"Name — Value"` entry (the format the city and university
/// directories produce) with the name and value pushed to opposite edges via a
/// `Spacer`, matching the demographics and industries rows. Entries without a
/// value separator render as a plain leading label.
@ViewBuilder
private func spacedStatRow(_ entry: String) -> some View {
    let parts = entry.components(separatedBy: " — ")
    HStack {
        Text(parts[0])
        if parts.count > 1 {
            Spacer()
            Text(parts.dropFirst().joined(separator: " — "))
        }
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
}

/// outline, with the district's representative underneath.
private struct DistrictDetailSheet: View {
    let boundary: MapBoundary
    let color: Color
    let representative: Representative?
    let populationDirectory: DistrictPopulationDirectory
    let demographicsDirectory: DistrictDemographicsDirectory
    let industryDirectory: DistrictIndustryDirectory
    let cityDirectory: DistrictCityDirectory
    let universityDirectory: DistrictUniversityDirectory

    private var population: Int? {
        populationDirectory.cachedPopulation(state: boundary.state, district: boundary.district ?? 0)
    }

    private var demographics: DistrictDemographics? {
        demographicsDirectory.cachedDemographics(state: boundary.state, district: boundary.district ?? 0)
    }

    private var topIndustries: [IndustryShare]? {
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

    /// The outline's on-screen size: scaled to fill a 100pt box on its longer
    /// axis while keeping the district's true proportions, then trimmed to the
    /// outline's actual extent on the shorter axis. Sizing the frame to this (vs.
    /// a fixed 100×100) leaves no slack, so the outline sits flush in the corner
    /// and `FloatingCornerLayout`'s wrap zone matches its real height.
    private var outlineSize: CGSize {
        let maxDimension: CGFloat = 100
        let aspect = DistrictOutlineShape.aspectRatio(for: boundary.rings)
        guard aspect.isFinite, aspect > 0 else {
            return CGSize(width: maxDimension, height: maxDimension)
        }
        return aspect >= 1
            ? CGSize(width: maxDimension, height: maxDimension / aspect)
            : CGSize(width: maxDimension * aspect, height: maxDimension)
    }

    /// A labeled list of the district's headline Census demographics, with any
    /// figures the API couldn't compute omitted.
    @ViewBuilder
    private func demographicsSection(_ demographics: DistrictDemographics) -> some View {
        let rows: [(label: String, value: String)] = [
            demographics.medianHouseholdIncome.map {
                ("Median household income", $0.formatted(.currency(code: "USD").precision(.fractionLength(0))))
            },
            demographics.medianAge.map {
                ("Median age", "\($0.formatted(.number.precision(.fractionLength(1)))) years")
            },
            demographics.bachelorsOrHigherShare.map {
                ("Bachelor's degree or higher", $0.formatted(.percent.precision(.fractionLength(0))))
            },
            demographics.povertyShare.map {
                ("Poverty rate", $0.formatted(.percent.precision(.fractionLength(0))))
            },
            demographics.unemploymentShare.map {
                ("Unemployment rate", $0.formatted(.percent.precision(.fractionLength(0))))
            },
        ].compactMap { $0 }

        // Header and rows are wrapped in a tightly-spaced VStack so the section
        // reads as one group, with the surrounding stack providing the wider gap
        // that separates it from neighboring sections.
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Demographics")
                    .font(.subheadline.bold())
                ForEach(rows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.value)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    @State private var titleIsMultiLine = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                /*Text(boundary.displayName)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)

                Divider()*/

                FloatingCornerLayout(spacing: 16, floatSpacing: 16) {
                    // First subview is the floater, pinned to the top-right corner.
                    DistrictOutlineShape(rings: boundary.rings)
                        .fill(color.opacity(0.3))
                        .overlay(DistrictOutlineShape(rings: boundary.rings).stroke(color, lineWidth: 1.5))
                        .frame(width: outlineSize.width, height: outlineSize.height)

                    // 2. The main text content
                    Group {
                        if titleIsMultiLine {
                            Text(boundary.displayName)
                        } else {
                            Text(splitAfterFirstWord(boundary.displayName))
                        }
                    }
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background {
                        // 3. Measurement logic moved to the background.
                        // Backgrounds don't participate in the layout sequence,
                        // completely nullifying the unwanted 16 spacing.
                        ViewThatFits(in: .horizontal) {
                            Text(boundary.displayName) // Option A: Fits completely on one line
                                .font(.title2.bold())
                                .lineLimit(1)
                                .onAppear { titleIsMultiLine = false }
                            
                            Color.clear // Option B: Text wraps, fallback triggered
                                .onAppear { titleIsMultiLine = true }
                        }
                        .hidden() // Hides it visually, but still evaluates the sizing
                    }

                    Divider()

                    /*if let population {
                        Text("Population: \(Self.populationFormatter.string(from: NSNumber(value: population)) ?? "\(population)")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }*/

                    if let topCities, !topCities.isEmpty {
                        Text("Top Cities")
                            .font(.subheadline.bold())
                        ForEach(topCities, id: \.self) { city in
                            spacedStatRow(city)
                                .flowGap(4)
                        }
                    }

                    if let demographics {
                        demographicsSection(demographics)
                    }

                    if let topIndustries, !topIndustries.isEmpty {
                        Text("Top Industries")
                            .font(.subheadline.bold())
                        ForEach(topIndustries, id: \.name) { industry in
                            HStack {
                                Text(industry.name)
                                Spacer()
                                Text(industry.share, format: .percent.precision(.fractionLength(0)))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .flowGap(4)
                        }
                    }

                    if let topUniversities, !topUniversities.isEmpty {
                        Text("Top Universities")
                            .font(.subheadline.bold())
                        ForEach(topUniversities, id: \.self) { university in
                            spacedStatRow(university)
                                .flowGap(4)
                        }
                    }
                }
                //.frame(maxWidth: .infinity, alignment: .leading)
                /*

                // Title and top divider sit beside the district outline; all of the
                // district's information stacks below this header row.
                HStack(alignment: .top, spacing: 16) {
                    VStack {
                        Spacer()
                        
                        Text(boundary.displayName)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Spacer()

                        Divider()
                        
                        Spacer()
                        Spacer()
                    }

                    DistrictOutlineShape(rings: boundary.rings)
                        .fill(color.opacity(0.3))
                        .overlay(DistrictOutlineShape(rings: boundary.rings).stroke(color, lineWidth: 1.5))
                        .frame(width: outlineSize.width, height: outlineSize.height)
                }

                // Wider spacing between sections; each section groups its header
                // and rows tightly in its own VStack.
                VStack(alignment: .leading, spacing: 20) {
                    if let topCities, !topCities.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top Cities")
                                .font(.subheadline.bold())
                            ForEach(topCities, id: \.self) { city in
                                spacedStatRow(city)
                            }
                        }
                    }

                    if let demographics {
                        demographicsSection(demographics)
                    }

                    if let topIndustries, !topIndustries.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top Industries")
                                .font(.subheadline.bold())
                            ForEach(topIndustries, id: \.name) { industry in
                                HStack {
                                    Text(industry.name)
                                    Spacer()
                                    Text(industry.share, format: .percent.precision(.fractionLength(0)))
                                }
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
                                spacedStatRow(university)
                            }
                        }
                    }
                }*/
                .frame(maxWidth: .infinity, alignment: .leading)
                .task {
                    print("District outline height: \(outlineSize.height) — \(boundary.displayName)")
                    await populationDirectory.loadIfNeeded(state: boundary.state, district: boundary.district ?? 0)
                    await demographicsDirectory.loadIfNeeded(state: boundary.state, district: boundary.district ?? 0)
                    await industryDirectory.loadIfNeeded(state: boundary.state, district: boundary.district ?? 0)
                    await cityDirectory.loadIfNeeded(boundary: boundary)
                    await universityDirectory.loadIfNeeded(boundary: boundary)
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
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationDestination(for: Representative.self) { rep in
                RepresentativeDetailView(representative: rep)
            }
        }
    }
    
    func splitAfterFirstWord(_ text: String) -> String {
        // Find the first space in the string
        if let firstSpaceIndex = text.firstIndex(of: " ") {
            var modifiedText = text
            // Replace the space at that position with a newline character
            modifiedText.replaceSubrange(firstSpaceIndex...firstSpaceIndex, with: "\n")
            return modifiedText
        }
        // Return original text if it is only one word long
        return text
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
                                spacedStatRow(city)
                            }
                        }
                    }

                    if let topUniversities, !topUniversities.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top Universities")
                                .font(.subheadline.bold())
                            ForEach(topUniversities, id: \.self) { university in
                                spacedStatRow(university)
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

/// Flows a vertical stack of subviews around a floating element pinned to the
/// top-trailing corner. The *first* subview is the floater; the rest stack down
/// the leading edge, staying narrow (leaving room for the floater) while they sit
/// beside it and reclaiming the full width once they clear the floater's bottom.
/// This gives a "text wraps around the outline" effect that neither `HStack` nor
/// `VStack` can produce on their own.
///
/// Because it flows its *direct* subviews individually, a section's header and
/// each of its rows must be passed as separate subviews (not wrapped in a
/// `VStack`) for the rows themselves — not just the whole section — to reclaim
/// the full width once they clear the floater. Tighter within-section spacing is
/// expressed per-row with `.flowGap(_:)`, which overrides the default `spacing`.
private struct FloatingCornerLayout: Layout {
    /// Default vertical gap before a flowing subview, used when the subview does
    /// not specify its own `.flowGap(_:)`.
    var spacing: CGFloat = 4
    /// Horizontal gap kept between the flowing text and the floating element.
    var floatSpacing: CGFloat = 16

    private func floatSize(_ subviews: Subviews) -> CGSize {
        subviews.first?.sizeThatFits(.unspecified) ?? .zero
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let floater = floatSize(subviews)
        var y: CGFloat = 0
        for (index, sub) in subviews.dropFirst().enumerated() {
            if index > 0 { y += (sub[FlowGap.self] ?? spacing) }
            let inset = y < floater.height
            let availableWidth = inset ? max(0, width - floater.width - floatSpacing) : width
            y += sub.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil)).height
        }
        return CGSize(width: width, height: max(y, floater.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let floater = floatSize(subviews)
        if let float = subviews.first {
            float.place(
                at: CGPoint(x: bounds.maxX - floater.width, y: bounds.minY),
                proposal: ProposedViewSize(floater)
            )
        }
        var y: CGFloat = 0
        for (index, sub) in subviews.dropFirst().enumerated() {
            if index > 0 { y += (sub[FlowGap.self] ?? spacing) }
            let inset = y < floater.height
            let availableWidth = inset ? max(0, bounds.width - floater.width - floatSpacing) : bounds.width
            let size = sub.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil))
            sub.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + y),
                proposal: ProposedViewSize(width: availableWidth, height: size.height)
            )
            y += size.height
        }
    }
}

/// A per-subview override for the vertical gap `FloatingCornerLayout` leaves
/// before a flowing subview. `nil` means "use the layout's default `spacing`".
private struct FlowGap: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

private extension View {
    /// Overrides the gap `FloatingCornerLayout` leaves before this subview — used
    /// to hug a section's rows tightly under its header while sections stay
    /// separated by the layout's default spacing.
    func flowGap(_ gap: CGFloat) -> some View {
        layoutValue(key: FlowGap.self, value: gap)
    }
}

/// Draws a district's boundary rings scaled to fit within the shape's rect,
/// preserving aspect ratio — a small "thumbnail" copy of the outline shown on
/// the map.
private struct DistrictOutlineShape: Shape {
    let rings: [[CLLocationCoordinate2D]]

    /// The width-to-height ratio of the outline as it's drawn (longitude
    /// compressed by cos(latitude), antimeridian unwrapped) — lets a caller size
    /// the frame to the outline's true proportions so there's no slack around it.
    static func aspectRatio(for rings: [[CLLocationCoordinate2D]]) -> CGFloat {
        let points = rings.flatMap { $0 }
        guard let minLat = points.map(\.latitude).min(),
              let maxLat = points.map(\.latitude).max(),
              let rawMinLon = points.map(\.longitude).min(),
              let rawMaxLon = points.map(\.longitude).max()
        else { return 1 }

        let crossesAntimeridian = rawMaxLon - rawMinLon > 180
        func unwrap(_ longitude: Double) -> Double {
            crossesAntimeridian && longitude < 0 ? longitude + 360 : longitude
        }
        let minLon = crossesAntimeridian ? points.map { unwrap($0.longitude) }.min()! : rawMinLon
        let maxLon = crossesAntimeridian ? points.map { unwrap($0.longitude) }.max()! : rawMaxLon

        let midLat = (minLat + maxLat) / 2
        let lonScale = max(cos(midLat * .pi / 180), .ulpOfOne)
        let latSpan = max(maxLat - minLat, .ulpOfOne)
        let lonSpan = max((maxLon - minLon) * lonScale, .ulpOfOne)
        return CGFloat(lonSpan / latSpan)
    }

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
