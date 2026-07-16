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
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .mapControls {
                    MapUserLocationButton()
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
            }
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

    /// The point at which to pin a representative: the geometric middle of
    /// their district, so members are spread across the map rather than
    /// clustered at their Washington office.
    private func districtCenter(for rep: Representative) -> CLLocationCoordinate2D? {
        let key = districtKey(state: rep.state, district: rep.district)
        return districtBoundaries.first { districtKey(state: $0.state, district: $0.district) == key }?.centroid
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
