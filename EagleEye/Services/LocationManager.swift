//
//  LocationManager.swift
//  EagleEye
//
//  Wraps CoreLocation to ask the user for their location once, using
//  async/await instead of the delegate callback style.
//

import Foundation
import CoreLocation

/// Requests the user's current location and surfaces the authorization status
/// to the UI. A one-shot location request is exposed as an `async` call so the
/// app can `await` a coordinate (or a thrown error) when it launches.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    /// Why a location request could not be fulfilled.
    enum LocationError: LocalizedError {
        /// The user declined the permission prompt, or access is restricted.
        case denied
        /// CoreLocation could not produce a fix (e.g. no signal, simulator).
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied:
                "Politica doesn't have permission to use your location."
            case .unavailable:
                "Your location couldn't be determined."
            }
        }
    }

    /// The current CoreLocation authorization status, observed by the UI.
    private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        authorizationStatus = .notDetermined
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    /// Prompts for permission if needed and waits for the user's choice.
    /// Throws `LocationError.denied` when access isn't (or wasn't) granted.
    /// Callers should await this before treating location as available, since
    /// the system permission dialog (when shown) must be answered first.
    func requestAuthorizationIfNeeded() async throws {
        switch authorizationStatus {
        case .notDetermined:
            let status = await requestAuthorization()
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                throw LocationError.denied
            }
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            throw LocationError.denied
        }
    }

    /// Resolves a single coordinate. Assumes authorization has already been
    /// granted, e.g. via `requestAuthorizationIfNeeded()`.
    func requestLocation() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    /// Shows the system permission prompt and waits for the user's choice.
    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorizationStatus = manager.authorizationStatus
            // Only resume once the user has actually answered the prompt.
            if manager.authorizationStatus != .notDetermined,
               let continuation = authorizationContinuation {
                authorizationContinuation = nil
                continuation.resume(returning: manager.authorizationStatus)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            if let coordinate = locations.last?.coordinate {
                continuation.resume(returning: coordinate)
            } else {
                continuation.resume(throwing: LocationError.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume(throwing: LocationError.unavailable)
        }
    }
}
