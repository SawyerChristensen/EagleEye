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
                    Marker(rep.name, systemImage: markerSymbol(for: rep), coordinate: rep.coordinate)
                        .tint(markerColor(for: rep))
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

    private func markerSymbol(for rep: Representative) -> String {
        rep.office == .senator ? "building.columns.fill" : "person.fill"
    }

    private func markerColor(for rep: Representative) -> Color {
        switch rep.party {
        case .democrat: .blue
        case .republican: .red
        case .independent: .purple
        }
    }
}

#Preview {
    DistrictMapView(representatives: SampleData.representatives)
}
