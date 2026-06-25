//
//  LocationPromptView.swift
//  EagleEye
//
//  The launch gate that asks the user for their location so the app can find
//  their congressional delegation.
//

import SwiftUI

/// Shown before the main tabs while the app resolves the user's location.
/// Displays a spinner while locating and a recovery path if access is denied.
struct LocationPromptView: View {
    /// Whether the user has declined location access (vs. still waiting).
    let isDenied: Bool
    /// Re-requests the user's location.
    let onRequestLocation: () async -> Void
    /// Continues into the app with sample data instead.
    let onUseSampleData: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "location.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Find Your Representatives")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Politica uses your location to find your two senators and your district's House representative.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                if isDenied {
                    Button {
                        Task { await onRequestLocation() }
                    } label: {
                        Label("Try Again", systemImage: "location")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: settingsURL) {
                            Text("Open Settings")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Continue with Sample Data", action: onUseSampleData)
                        .font(.subheadline)
                        .padding(.top, 4)
                } else {
                    ProgressView("Locating…")
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .task {
            // On first appearance, fire the system prompt automatically.
            if !isDenied {
                await onRequestLocation()
            }
        }
    }
}

#Preview("Locating") {
    LocationPromptView(isDenied: false, onRequestLocation: {}, onUseSampleData: {})
}

#Preview("Denied") {
    LocationPromptView(isDenied: true, onRequestLocation: {}, onUseSampleData: {})
}
