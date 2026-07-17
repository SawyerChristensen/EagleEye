//
//  DistrictMapView.swift
//  EagleEye
//
//  The right "Map" tab: shows where the user's representatives' offices are.
//

import SwiftUI
import MapKit

struct DistrictMapView: View {
    let representatives: [Representative]
    /// The user's last resolved coordinate, if any — lets the map center on
    /// roughly the right place immediately, before the (much slower) district
    /// boundary parsing and lookup finish.
    let userCoordinate: CLLocationCoordinate2D?

    @State private var position: MapCameraPosition = .automatic
    @State private var stateBoundaries: [MapBoundary] = []
    @State private var districtBoundaries: [MapBoundary] = []
    @State private var selectedDistrict: MapBoundary?
    @State private var hasSetInitialRegion = false
    @State private var hasCenteredOnUserDistrict = false
    @State private var isCenteredOnUserDistrict = false
    @State private var worldMask: MKPolygon?
    @State private var nationalHouseDirectory = NationalHouseDirectory()
    @State private var populationDirectory = DistrictPopulationDirectory()
    @State private var industryDirectory = DistrictIndustryDirectory()
    @State private var cityDirectory = DistrictCityDirectory()
    @State private var universityDirectory = DistrictUniversityDirectory()

    /// Whether the camera is currently zoomed out far enough to treat this
    /// as a "state level" view: district fills/pins swap for flag-filled
    /// states with a governor pin apiece.
    @State private var isStateLevel = false
    @State private var stateFlagImages: [String: Image] = [:]
    @State private var stateFlagPixelSizes: [String: CGSize] = [:]
    @State private var loadingFlagStates: Set<String> = []
    /// The map view's own rendered size and the Mercator "map rect" it's
    /// currently showing — together these convert a boundary's extent into
    /// on-screen points, so a state's flag fill can be sized to actually
    /// cover its polygon. See `screenPointsPerMapUnit`.
    @State private var mapViewSize: CGSize = .zero
    @State private var visibleMapRect: MKMapRect = .world

    @Environment(\.colorScheme) private var colorScheme

    /// Once the visible region spans at least this many degrees of
    /// latitude, individual districts are too small to read — the map
    /// treats this as "state level" and swaps district fills/pins for
    /// flag-filled states with governor pins.
    private static let stateLevelSpanThreshold: Double = 6.0

    /// Members to show as pins. Senators are excluded for now — they represent
    /// a whole state rather than a single district, so they have no "middle of
    /// the district" point to pin at.
    private var mappable: [Representative] {
        representatives.filter { $0.office == .representative }
    }

    /// Every House member nationwide, keyed by state and district — used to
    /// tint every district's fill and to answer "who represents this
    /// district" for a tapped district, not just the user's own.
    private var partyByDistrict: [String: Party] {
        Dictionary(
            nationalHouseDirectory.members.map { (districtKey(state: $0.state, district: $0.district), $0.party) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    if let worldMask {
                        MapPolygon(worldMask)
                            .foregroundStyle(.black.opacity(0.2))
                            // MapKit has no API to hide physical-feature labels
                            // ("Rocky Mountains", etc.) on the standard basemap.
                            // Drawing the overlays *above* the label layer (they
                            // default to `.aboveRoads`, below labels) lets the
                            // fill wash paint over that text and suppress it.
                            .mapOverlayLevel(level: .aboveLabels)
                    }

                    if isStateLevel {
                        ForEach(stateBoundaries) { boundary in
                            ForEach(Array(boundary.rings.enumerated()), id: \.offset) { _, ring in
                                MapPolygon(coordinates: closed(ring))
                                    .foregroundStyle(stateFillStyle(for: boundary))
                                    .stroke(.primary.opacity(0.85), lineWidth: 2)
                                    .mapOverlayLevel(level: .aboveLabels)
                            }
                        }

                        ForEach(stateBoundaries) { boundary in
                            if let governor = GovernorDirectory.governor(forState: boundary.state) {
                                Annotation(governor.name, coordinate: boundary.centroid) {
                                    GovernorPortrait(governor: governor, size: 40, style: .outline)
                                }
                            }
                        }
                    } else {
                        ForEach(districtBoundaries) { boundary in
                            ForEach(Array(boundary.rings.enumerated()), id: \.offset) { _, ring in
                                MapPolygon(coordinates: closed(ring))
                                    .foregroundStyle(fillColor(for: boundary).opacity(0.4))
                                    .stroke(.secondary.opacity(0.5), lineWidth: 1)
                                    .mapOverlayLevel(level: .aboveLabels)
                            }
                        }

                        ForEach(stateBoundaries) { boundary in
                            ForEach(Array(boundary.rings.enumerated()), id: \.offset) { _, ring in
                                MapPolyline(coordinates: closed(ring))
                                    .stroke(.primary.opacity(0.85), lineWidth: 2)
                            }
                        }

                        ForEach(mappable) { rep in
                            if let coordinate = districtCenter(for: rep) {
                                Annotation(rep.name, coordinate: coordinate) {
                                    RepresentativePortrait(representative: rep, size: 40, style: .outline)
                                }
                            }
                        }
                    }

                    UserAnnotation()
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                .mapControls {
                    MapCompass()
                }
                .onTapGesture { screenPoint in
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    selectedDistrict = districtBoundaries.first { $0.contains(coordinate) }
                }
                .onGeometryChange(for: CGSize.self, of: \.size) { mapViewSize = $0 }
                .onMapCameraChange(frequency: .onEnd) { context in
                    isCenteredOnUserDistrict = isRegion(context.region, centeredOn: userDistrictBoundary)
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    isStateLevel = context.region.span.latitudeDelta > Self.stateLevelSpanThreshold
                    visibleMapRect = context.rect
                }
                .onChange(of: isStateLevel) { _, zoomedToStateLevel in
                    guard zoomedToStateLevel else { return }
                    for boundary in stateBoundaries {
                        loadFlagImageIfNeeded(for: boundary.state)
                    }
                }
                // `.mapControls` is built for MapKit's own control types (MapCompass,
                // MapUserLocationButton, etc.) — a plain custom Button placed inside it
                // is unreliable and can silently fail to render. An explicit overlay
                // guarantees this button actually shows up.
                .overlay(alignment: .bottomTrailing) {
                    recenterButton
                        .padding()
                }
            }
            .navigationTitle("District Map")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Get roughly in the right place right away, using the coordinate
                // we already have, rather than leaving MapKit's generic default
                // view up while the district boundaries load and get simplified.
                if !hasSetInitialRegion, let userCoordinate {
                    hasSetInitialRegion = true
                    position = .region(wideRegion(centeredOn: userCoordinate))
                }
                async let nationalLoad: Void = nationalHouseDirectory.loadIfNeeded()
                if districtBoundaries.isEmpty, stateBoundaries.isEmpty {
                    async let districts = Task.detached(priority: .userInitiated) { BoundaryLoader.loadDistricts() }.value
                    async let states = Task.detached(priority: .userInitiated) { BoundaryLoader.loadStates() }.value
                    districtBoundaries = await districts
                    stateBoundaries = await states
                    worldMask = Self.buildWorldMask(from: stateBoundaries)
                    centerOnUserDistrictIfNeeded()
                }
                await nationalLoad
            }
            .onChange(of: representatives) { centerOnUserDistrictIfNeeded() }
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
        }
    }

    /// A world-covering polygon with every state/territory boundary punched
    /// out as a hole, so filling it grey tints everything outside the US
    /// without touching the country's own territory.
    private static func buildWorldMask(from states: [MapBoundary]) -> MKPolygon? {
        guard !states.isEmpty else { return nil }
        // Longitude -180 and +180 are the same meridian, so a rectangle whose
        // edges run straight from one to the other collapses into a degenerate
        // sliver — MapKit then fills only the interior cut-outs (the US) instead
        // of everything around them. Breaking each horizontal edge into spans
        // shorter than 180° (midpoints at ±90 and 0) forces MapKit to render a
        // real, full-globe rectangle so the cut-outs behave as holes.
        let world = [
            CLLocationCoordinate2D(latitude: 85, longitude: -180),
            CLLocationCoordinate2D(latitude: 85, longitude: -90),
            CLLocationCoordinate2D(latitude: 85, longitude: 0),
            CLLocationCoordinate2D(latitude: 85, longitude: 90),
            CLLocationCoordinate2D(latitude: 85, longitude: 180),
            CLLocationCoordinate2D(latitude: -85, longitude: 180),
            CLLocationCoordinate2D(latitude: -85, longitude: 90),
            CLLocationCoordinate2D(latitude: -85, longitude: 0),
            CLLocationCoordinate2D(latitude: -85, longitude: -90),
            CLLocationCoordinate2D(latitude: -85, longitude: -180),
        ]
        let holes = states.flatMap { $0.rings }.map { ring in
            MKPolygon(coordinates: ring, count: ring.count)
        }
        return MKPolygon(coordinates: world, count: world.count, interiorPolygons: holes)
    }

    /// Closes a boundary ring so the outline draws back to its starting point.
    private func closed(_ ring: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard let first = ring.first else { return ring }
        return ring + [first]
    }

    /// A lookup key combining state and district number; at-large districts
    /// use `0`, matching the bundled Census boundary data. Congress.gov gives
    /// representatives' state as a full name (e.g. "California") while the
    /// bundled boundary data keys districts by postal code (e.g. "CA"), so
    /// both sides are normalized to the postal code before comparing.
    private func districtKey(state: String, district: Int?) -> String {
        let code = SenateService.stateCode(for: state) ?? state
        return "\(code)-\(district ?? 0)"
    }

    /// The fill color for a district's polygon: its representative's party
    /// color, or clear if no member currently matches it (e.g. a non-voting
    /// delegate's district). Blue and red run slightly brighter in dark mode,
    /// where the stock system colors read too dark against the near-black map.
    private func fillColor(for boundary: MapBoundary) -> Color {
        guard let party = partyByDistrict[districtKey(state: boundary.state, district: boundary.district)] else {
            return .clear
        }
        guard colorScheme == .dark else { return party.color }
        switch party {
        case .democrat: return Color(red: 0.40, green: 0.66, blue: 1.0)
        case .republican: return Color(red: 1.0, green: 0.40, blue: 0.38)
        case .independent: return party.color
        }
    }

    /// How many on-screen points one Mercator "map point" currently covers —
    /// derived from the map view's rendered size and the map rect it's
    /// showing, so a boundary's extent can be converted into the screen-space
    /// size its polygon actually occupies at the current zoom.
    private var screenPointsPerMapUnit: Double {
        guard visibleMapRect.size.width > 0 else { return 0 }
        return mapViewSize.width / visibleMapRect.size.width
    }

    /// A boundary's extent in Mercator "map point" units (width, height) —
    /// combined with `screenPointsPerMapUnit`, this gives the on-screen size
    /// of a state's polygon so its flag fill can be scaled to cover it.
    private func mapUnitSpan(for boundary: MapBoundary) -> (width: Double, height: Double) {
        let points = boundary.rings.flatMap { $0 }.map { MKMapPoint($0) }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return (0, 0) }
        return (maxX - minX, maxY - minY)
    }

    /// The fill style for a state's polygon at state-level zoom: its flag
    /// image, scaled to cover the polygon's on-screen bounding box (the same
    /// "fill the frame, crop the excess" look as `StateFlagImage`'s
    /// `.scaledToFill()`), or a neutral placeholder tint while the flag is
    /// still loading.
    private func stateFillStyle(for boundary: MapBoundary) -> AnyShapeStyle {
        guard let image = stateFlagImages[boundary.state],
              let pixelSize = stateFlagPixelSizes[boundary.state],
              pixelSize.width > 0, pixelSize.height > 0,
              screenPointsPerMapUnit > 0
        else {
            return AnyShapeStyle(Color.secondary.opacity(0.25))
        }
        let span = mapUnitSpan(for: boundary)
        let boxWidth = span.width * screenPointsPerMapUnit
        let boxHeight = span.height * screenPointsPerMapUnit
        guard boxWidth > 0, boxHeight > 0 else {
            return AnyShapeStyle(Color.secondary.opacity(0.25))
        }
        let scale = max(boxWidth / pixelSize.width, boxHeight / pixelSize.height)
        return AnyShapeStyle(ImagePaint(image: image, scale: CGFloat(scale)))
    }

    /// Loads and caches a state's flag the first time it's needed for the
    /// state-level fill, recording its pixel size so `stateFillStyle(for:)`
    /// can size the fill to cover the state's polygon.
    private func loadFlagImageIfNeeded(for state: String) {
        guard stateFlagImages[state] == nil, !loadingFlagStates.contains(state),
              let url = StateFlagDirectory.flagURL(forState: state)
        else { return }
        loadingFlagStates.insert(state)
        Task {
            defer { loadingFlagStates.remove(state) }
            guard let platformImage = await ImageCache.shared.image(for: url) else { return }
            #if canImport(UIKit)
            stateFlagImages[state] = Image(uiImage: platformImage)
            #elseif canImport(AppKit)
            stateFlagImages[state] = Image(nsImage: platformImage)
            #endif
            stateFlagPixelSizes[state] = platformImage.size
        }
    }

    /// The boundary matching a representative's state and district, if its
    /// geometry has loaded.
    private func districtBoundary(for rep: Representative) -> MapBoundary? {
        let key = districtKey(state: rep.state, district: rep.district)
        return districtBoundaries.first { districtKey(state: $0.state, district: $0.district) == key }
    }

    /// The point at which to pin a representative: the geometric middle of
    /// their district, so members are spread across the map rather than
    /// clustered at their Washington office.
    private func districtCenter(for rep: Representative) -> CLLocationCoordinate2D? {
        districtBoundary(for: rep)?.centroid
    }

    /// The boundary of the user's own district, i.e. their House member's
    /// district — `mappable` only ever contains the user's own delegation.
    private var userDistrictBoundary: MapBoundary? {
        mappable.first.flatMap(districtBoundary(for:))
    }

    /// A region tightly framing a district's full extent (with a little
    /// padding), rather than the tight "current position" zoom MapKit's
    /// stock location button defaults to.
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

    /// A coarse, roughly metro-area-wide region around a coordinate — used to
    /// get the map pointed at the right place immediately, before the precise
    /// district-fit region (see `region(for:)`) is ready.
    private func wideRegion(centeredOn coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
        )
    }

    /// Frames the user's district edge-to-edge the first time both their
    /// representative and the district geometry are available, so the map
    /// opens already centered on home rather than on MapKit's generic
    /// default view. Only fires once — after that, the user's own panning
    /// and zooming takes over.
    private func centerOnUserDistrictIfNeeded() {
        guard !hasCenteredOnUserDistrict, let boundary = userDistrictBoundary else { return }
        hasCenteredOnUserDistrict = true
        isCenteredOnUserDistrict = true
        position = .region(region(for: boundary))
    }

    /// Whether a camera region is still roughly framing the user's district,
    /// i.e. close enough to what `recenterButton` last set that panning or
    /// zooming hasn't meaningfully moved away from it yet.
    private func isRegion(_ region: MKCoordinateRegion, centeredOn boundary: MapBoundary?) -> Bool {
        guard let boundary else { return false }
        let target = self.region(for: boundary)
        let latTolerance = target.span.latitudeDelta * 0.25
        let lonTolerance = target.span.longitudeDelta * 0.25
        return abs(region.center.latitude - target.center.latitude) < latTolerance
            && abs(region.center.longitude - target.center.longitude) < lonTolerance
    }

    /// Recenters on the user's district — framing the whole district rather
    /// than zooming to their exact position, since the district (not the
    /// neighborhood) is what's relevant here. Falls back to the stock
    /// "current location" behavior if the district geometry isn't loaded yet.
    private var recenterButton: some View {
        Button {
            withAnimation {
                isCenteredOnUserDistrict = true
                if let boundary = userDistrictBoundary {
                    position = .region(region(for: boundary))
                } else {
                    position = .userLocation(fallback: .automatic)
                }
            }
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

    /// The House member who represents a given district, if any is on file
    /// (e.g. a non-voting delegate's district may have no match). Looked up
    /// nationwide so every district's sheet shows its own representative, not
    /// just the user's home district.
    private func representative(for boundary: MapBoundary) -> Representative? {
        let key = districtKey(state: boundary.state, district: boundary.district)
        return nationalHouseDirectory.members.first { districtKey(state: $0.state, district: $0.district) == key }
    }
}

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

/// Draws a district's boundary rings scaled to fit within the shape's rect,
/// preserving aspect ratio — a small "thumbnail" copy of the outline shown
/// on the map.
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

        // A boundary that crosses the antimeridian (e.g. Alaska, whose
        // Aleutian Islands run past 180° into positive longitude) has points
        // on both sides of the ±180 seam. Taking min/max of the raw
        // longitudes then spans nearly the whole globe, squashing the real
        // shape into a sliver on one side and a stray dot on the other.
        // Unwrap by shifting negative longitudes up by 360° so the ring reads
        // as one contiguous span instead of two far-apart clusters.
        let crossesAntimeridian = rawMaxLon - rawMinLon > 180
        func unwrap(_ longitude: Double) -> Double {
            crossesAntimeridian && longitude < 0 ? longitude + 360 : longitude
        }
        let minLon = crossesAntimeridian ? points.map { unwrap($0.longitude) }.min()! : rawMinLon
        let maxLon = crossesAntimeridian ? points.map { unwrap($0.longitude) }.max()! : rawMaxLon

        // A degree of longitude spans less ground than a degree of latitude by
        // a factor of cos(latitude). Without this correction the outline is
        // stretched east-west and appears squashed vertically.
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
        // distance from the vertex, then a small quad curve around it. Straight
        // edges stay on their true path; `cornerCut` controls how much of each
        // corner is rounded — small, so the effect is subtle.
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

            // A point offset from `from` toward `to`, capped at half the
            // segment length so short edges never overshoot into artifacts.
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
                // Round the corner at vertex i, then run straight to the next.
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
