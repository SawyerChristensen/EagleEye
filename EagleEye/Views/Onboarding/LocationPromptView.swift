//
//  LocationPromptView.swift
//  EagleEye
//
//  The launch gate that asks the user for their location so the app can find
//  their congressional delegation. Offers a manual ZIP-code fallback for when
//  location is denied or too vague to resolve the right district.
//

import SwiftUI

/// Anchors the explanatory text to the screen's vertical center so the icon and
/// title float above it and the controls sit below, all relative to that line.
private extension VerticalAlignment {
    enum LocationDescription: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let locationDescription = VerticalAlignment(LocationDescription.self)
}

/// Shown before the main tabs while the app resolves the user's location.
/// Displays a spinner while locating and a recovery path if access is denied.
struct LocationPromptView: View {
    /// Whether the user has declined location access (vs. still waiting).
    let isDenied: Bool
    /// A user-facing note, e.g. a ZIP-lookup error, shown beneath the controls.
    let statusMessage: String?
    /// Re-requests the user's location.
    let onRequestLocation: () async -> Void
    /// Looks up the delegation for a manually entered ZIP code.
    let onSubmitZIP: (String) async -> Void

    @State private var zip = ""
    /// True while a tapped location request is in flight, so the choice buttons
    /// give way to a spinner until the request resolves (or drops us back here).
    @State private var isLocating = false

    private var isValidZIP: Bool {
        zip.count == 5 && zip.allSatisfy(\.isNumber)
    }

    var body: some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .locationDescription)) {
            // A full-screen anchor whose center defines the line the description
            // text is pinned to; the content below aligns to that same guide.
            Color.clear

            VStack(spacing: 24) {
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
                        // This line is what lands on the screen's vertical center.
                        .alignmentGuide(.locationDescription) { $0[VerticalAlignment.center] }
                }
                .padding(.horizontal)

                VStack(spacing: 12) {
                    if isLocating {
                        ProgressView("Locating…")
                            .padding(.bottom, 4)
                    } else {
                        // Sharing device location is opt-in: tapping this is the only
                        // thing that fires the iOS system prompt, so we never ask for
                        // location until the user chooses to share it.
                        Button {
                            Task {
                                isLocating = true
                                await onRequestLocation()
                                // Still on this screen means the request didn't carry
                                // us into the app (denied or no fix) — restore the
                                // choices so the user can retry or enter a ZIP.
                                isLocating = false
                            }
                        } label: {
                            Label(
                                isDenied ? "Try Again" : "Share My Location",
                                systemImage: "location.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if isDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            Link(destination: settingsURL) {
                                Text("Open Settings")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        zipEntry
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
            }
        }
    }

    /// A ZIP-code field and lookup button, offered as a manual alternative to
    /// device location. Location is often deliberately fuzzed for privacy and
    /// can resolve the wrong district, so this is always available.
    private var zipEntry: some View {
        VStack(spacing: 10) {
            HStack {
                Rectangle().fill(.quaternary).frame(height: 1)
                Text("or enter your ZIP code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle().fill(.quaternary).frame(height: 1)
            }

            HStack(spacing: 10) {
                TextField("ZIP code", text: $zip)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
                    .onChange(of: zip) { _, newValue in
                        // Keep only the first five digits as the user types.
                        let digits = String(newValue.filter(\.isNumber).prefix(5))
                        if digits != newValue { zip = digits }
                    }

                Button {
                    Task { await onSubmitZIP(zip) }
                } label: {
                    Text("Find")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidZIP)
            }
        }
        .padding(.top, 4)
    }
}

#Preview("Locating") {
    LocationPromptView(
        isDenied: false,
        statusMessage: nil,
        onRequestLocation: {},
        onSubmitZIP: { _ in }
    )
}

#Preview("Denied") {
    LocationPromptView(
        isDenied: true,
        statusMessage: "Couldn't find that ZIP code — please check it and try again.",
        onRequestLocation: {},
        onSubmitZIP: { _ in }
    )
}
