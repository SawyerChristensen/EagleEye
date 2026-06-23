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

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(representatives) { rep in
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
