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
                Text(boundary.displayName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding()
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
}

#Preview {
    DistrictMapView(representatives: SampleData.representatives)
}
