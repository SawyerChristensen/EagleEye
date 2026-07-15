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

    /// Members to show as pins. Senators are excluded for now — their office
    /// coordinate placement isn't reliable yet — and any member whose office
    /// address failed to geocode is skipped rather than showing at (0, 0).
    private var mappable: [Representative] {
        representatives.filter { $0.office == .representative && $0.hasResolvedCoordinate }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(districtBoundaries) { boundary in
                    ForEach(Array(boundary.rings.enumerated()), id: \.offset) { _, ring in
                        MapPolyline(coordinates: closed(ring))
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
                    Annotation(rep.name, coordinate: rep.coordinate) {
                        RepresentativePortrait(representative: rep, size: 40, style: .outline)
                    }
                }

                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
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
        }
    }

    /// Closes a boundary ring so the outline draws back to its starting point.
    private func closed(_ ring: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard let first = ring.first else { return ring }
        return ring + [first]
    }
}

#Preview {
    DistrictMapView(representatives: SampleData.representatives)
}
