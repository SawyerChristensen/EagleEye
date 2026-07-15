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

    /// Members to show as pins. Senators are excluded for now — their office
    /// coordinate placement isn't reliable yet — and any member whose office
    /// address failed to geocode is skipped rather than showing at (0, 0).
    private var mappable: [Representative] {
        representatives.filter { $0.office == .representative && $0.hasResolvedCoordinate }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
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
        }
    }
}

#Preview {
    DistrictMapView(representatives: SampleData.representatives)
}
