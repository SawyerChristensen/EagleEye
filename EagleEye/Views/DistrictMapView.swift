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

    @State private var position: MapCameraPosition = .automatic
    @State private var stateBoundaries: [MapBoundary] = []
    @State private var districtBoundaries: [MapBoundary] = []
    @State private var selectedDistrict: MapBoundary?
    @State private var hasCenteredOnUserDistrict = false
    @State private var worldMask: MKPolygon?

    /// Members to show as pins. Senators are excluded for now — they represent
    /// a whole state rather than a single district, so they have no "middle of
    /// the district" point to pin at.
    private var mappable: [Representative] {
        representatives.filter { $0.office == .representative }
    }

    /// Each House member's party, keyed by state and district, used to tint
    /// their district's fill on the map.
    private var partyByDistrict: [String: Party] {
        Dictionary(
            mappable.map { (districtKey(state: $0.state, district: $0.district), $0.party) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    if let worldMask {
                        MapPolygon(worldMask)
                            .foregroundStyle(.gray.opacity(0.35))
                    }

                    ForEach(districtBoundaries) { boundary in
                        ForEach(Array(boundary.rings.enumerated()), id: \.offset) { _, ring in
                            MapPolygon(coordinates: closed(ring))
                                .foregroundStyle(fillColor(for: boundary).opacity(0.28))
                                .stroke(.secondary.opacity(0.5), lineWidth: 0.75)
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

                    UserAnnotation()
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                .mapControls {
                    recenterButton
                    MapCompass()
                }
                .onTapGesture { screenPoint in
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    selectedDistrict = districtBoundaries.first { $0.contains(coordinate) }
                }
            }
            .navigationTitle("District Map")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard districtBoundaries.isEmpty, stateBoundaries.isEmpty else { return }
                async let districts = Task.detached(priority: .userInitiated) { BoundaryLoader.loadDistricts() }.value
                async let states = Task.detached(priority: .userInitiated) { BoundaryLoader.loadStates() }.value
                districtBoundaries = await districts
                stateBoundaries = await states
                worldMask = Self.buildWorldMask(from: stateBoundaries)
                centerOnUserDistrictIfNeeded()
            }
            .onChange(of: representatives) { centerOnUserDistrictIfNeeded() }
            .sheet(item: $selectedDistrict) { boundary in
                DistrictDetailSheet(
                    boundary: boundary,
                    color: fillColor(for: boundary),
                    representative: representative(for: boundary)
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
        let world = [
            CLLocationCoordinate2D(latitude: 85, longitude: -180),
            CLLocationCoordinate2D(latitude: 85, longitude: 180),
            CLLocationCoordinate2D(latitude: -85, longitude: 180),
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
    /// delegate's district).
    private func fillColor(for boundary: MapBoundary) -> Color {
        partyByDistrict[districtKey(state: boundary.state, district: boundary.district)]?.color ?? .clear
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

    /// Frames the user's district edge-to-edge the first time both their
    /// representative and the district geometry are available, so the map
    /// opens already centered on home rather than on MapKit's generic
    /// default view. Only fires once — after that, the user's own panning
    /// and zooming takes over.
    private func centerOnUserDistrictIfNeeded() {
        guard !hasCenteredOnUserDistrict, let boundary = userDistrictBoundary else { return }
        hasCenteredOnUserDistrict = true
        position = .region(region(for: boundary))
    }

    /// Recenters on the user's district — framing the whole district rather
    /// than zooming to their exact position, since the district (not the
    /// neighborhood) is what's relevant here. Falls back to the stock
    /// "current location" behavior if the district geometry isn't loaded yet.
    private var recenterButton: some View {
        Button {
            withAnimation {
                if let boundary = userDistrictBoundary {
                    position = .region(region(for: boundary))
                } else {
                    position = .userLocation(fallback: .automatic)
                }
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .background(.regularMaterial, in: Circle())
    }

    /// The House member who represents a given district, if any is on file
    /// (e.g. a non-voting delegate's district may have no match).
    private func representative(for boundary: MapBoundary) -> Representative? {
        let key = districtKey(state: boundary.state, district: boundary.district)
        return mappable.first { districtKey(state: $0.state, district: $0.district) == key }
    }
}

/// The sheet shown when a district is tapped: its name beside a copy of its
/// outline, with the district's representative underneath.
private struct DistrictDetailSheet: View {
    let boundary: MapBoundary
    let color: Color
    let representative: Representative?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Text(boundary.displayName)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DistrictOutlineShape(rings: boundary.rings)
                        .fill(color.opacity(0.3))
                        .overlay(DistrictOutlineShape(rings: boundary.rings).stroke(color, lineWidth: 1.5))
                        .frame(width: 80, height: 80)
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
              let minLon = points.map(\.longitude).min(),
              let maxLon = points.map(\.longitude).max()
        else { return path }

        let latSpan = max(maxLat - minLat, .ulpOfOne)
        let lonSpan = max(maxLon - minLon, .ulpOfOne)
        let scale = min(rect.width / lonSpan, rect.height / latSpan)
        let originX = rect.minX + (rect.width - lonSpan * scale) / 2
        let originY = rect.minY + (rect.height - latSpan * scale) / 2

        func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: originX + (coordinate.longitude - minLon) * scale,
                y: originY + (maxLat - coordinate.latitude) * scale
            )
        }

        for ring in rings {
            guard let first = ring.first else { continue }
            path.move(to: point(first))
            for coordinate in ring.dropFirst() {
                path.addLine(to: point(coordinate))
            }
            path.closeSubpath()
        }
        return path
    }
}

#Preview {
    DistrictMapView(representatives: SampleData.representatives)
}
